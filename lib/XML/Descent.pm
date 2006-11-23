package XML::Descent;

use warnings;
use strict;
use Carp;
use XML::TokeParser;
use Class::Std;
use Data::Dumper;

use version; our $VERSION = qv('0.0.1');

# TODO:
#    Extend path selector syntax for on()
#    Move path recording into get_token()
#    Add dom() parser

my %context : ATTR;         # Context for walk()
my %parser  : ATTR;         # The XML::TokeParser
my %token   : ATTR;         # Last token fetched
my %path    : ATTR;         # Tag path elements

sub BUILD {
    my ($self, $id, $args) = @_;

    my $input = $args->{Input} || croak("No Input arg");
    delete $args->{Input};

    $parser{$id}  = XML::TokeParser->new($input, %{$args});
    $context{$id} = {
        parent      => undef,
        rules       => { },
        store       => { }
    };
    $token{$id}   = undef;
    $path{$id}    = [ ];
}

# Not a method
# sub _get_context_attr {
#     my ($tos, $name) = @_;
#     # Walk up the context stack
#     for (;;) {
#         return $tos->{$name} if exists $tos->{$name};
#         return unless defined $tos->{parent};
#         $tos = $tos->{parent};
#     }
# }

# Not a method
sub _get_rule_handler {
    my ($tos, $tok) = @_;
    my $elem = $tok->[1];
    for (;;) {
        if (defined($tos->{rules}->{$elem})) {
            return $tos->{rules}->{$elem};
        } elsif (defined($tos->{rules}->{'*'})) {
            return $tos->{rules}->{'*'};
        }
        return unless defined $tos->{parent};
        $tos = $tos->{parent};
    }
}

sub _depth {
    my $self = shift;
    my $id   = ident($self);
    
    return scalar(@{$path{$id}});
}

sub get_token() {
    my $self = shift;
    my $id   = ident($self);
    my $p    = $parser{$id};

    my $tok = $token{$id} = $p->get_token();
    
    if (defined($tok)) {
        if ($tok->[0] eq 'S') {
            push @{$path{$id}}, $tok->[1];
        } elsif ($tok->[0] eq 'E') {
            my $tos = pop @{$path{$id}};
            die "$tos <> $tok->[1]"
                unless $tos eq $tok->[1];
        }
    }

    my $stopat = $context{$id}->{stopat};
    return if defined($stopat) && $self->_depth() < $stopat;
    return $tok;
}

sub text {
    my $self = shift;
    my $id   = ident($self);
    my @txt  = ( );
    
    TOKEN: while (my $tok = $self->get_token()) {
        if ($tok->[0] eq 'S') {
            push @txt, $self->text();
        } elsif ($tok->[0] eq 'E') {
            last TOKEN;
        } elsif ($tok->[0] eq 'T') {
            push @txt, $tok->[1];
        }
    }

    return join('', @txt);
}

sub xml {
    my $self = shift;
    my $id   = ident($self);

    my @xml  = ( );

    TOKEN: while (my $tok = $self->get_token()) {
        if ($tok->[0] eq 'S') {
            push @xml, $tok->[4];
            push @xml, $self->xml();
            push @xml, $token{$id}->[2];
        } elsif ($tok->[0] eq 'E') {
            last TOKEN;
        } elsif ($tok->[0] eq 'T' || $tok->[0] eq 'C') {
            push @xml, $tok->[1];
        } elsif ($tok->[0] eq 'PI') {
            push @xml, $tok->[3];
        } else {
            die "Unhandled token type: $tok->[0]";
        }
    }

    return join('', @xml);
}

sub stash {
    my $self = shift;
    my $id   = ident($self);
    my ($name, $value) = @_;
    
    my $parent = $context{$id}->{parent};
    push @{$parent->{store}->{$name}}, $value;
}

sub get_path {
    my $self = shift;
    my $id   = ident($self);

    return '/' . join('/', @{$path{$id}});
}

sub walk {
    my $self = shift;
    my $id   = ident($self);

    TOKEN: while (my $tok = $self->get_token()) {
        if ($tok->[0] eq 'S') {
            my $tos = $context{$id};
            my $handler = _get_rule_handler($tos, $tok);
            if (defined($handler)) {
                my $stopat = $self->_depth();
                
                # Push context
                $context{$id} = {
                    parent  => $tos,
                    rules   => { },
                    store   => { },
                    stopat  => $stopat
                };
                
                # Call handler
                $handler->($tok->[1], $tok->[2]);
                
                # If handler didn't recursively parse the content of
                # this node we need to discard it.
                while ($self->_depth() >= $stopat &&
                       ($tok = $self->get_token())) {
                    # do nothing
                }
                
                # Pop context
                $context{$id} = $tos;
            } else {
                $self->walk();
            }
        } elsif ($tok->[0] eq 'E') {
            last TOKEN;
        }
    }

    return $context{$id}->{store};
}

sub on {
    my $self = shift;
    my $id   = ident($self);
    my ($path, $cb) = @_;

    $context{$id}->{rules}->{$path} = $cb;
}

1;

__END__

=head1 NAME

XML::Descent - Simple recursive descent XML parsing

=head1 VERSION

This document describes XML::Descent version 0.0.1

=head1 SYNOPSIS

    use XML::Descent;

    # Create parser
    my $p = XML::Descent->new({
        Input   => \$xml
    });

    # Setup handlers
    $p->on(folder => sub {
        my ($elem, $attr) = @_;

        $p->on(url => sub {
            my ($elem, $attr) = @_;
            my $link = {
                name    => $attr->{name},
                url     => $p->text()
            };
            $p->stash(link => $link);
        });

        my $folder = $p->walk();
        $folder->{name} = $attr->{name};

        $p->stash(folder => $folder);
    });

    # Parse
    my $res = $p->walk();
  
=head1 DESCRIPTION

The conventional models for parsing XML are either DOM (a data structure
representing the entire document tree is created) or SAX (callbacks are
issued for each element in the XML).

XML grammar is recursive - so it's nice to be able to write recursive
parsers for it. XML::Descent allows such parsers to be created.

Typically a new XML::Descent is created and handlers are defined for
elements we're interested in

    my $p = XML::Descent->new({ Input => \$xml });
    $p->on(link => sub {
        my ($elem, $attr) = @_;
        print "Found link: ", $attr->{url}, "\n";
        $p->walk(); # recurse
    });
    $p->walk(); # parse

When called at the top level the parsing methods walk(), text() and
xml() parse the whole XML document. When called recursively within a
handler they parse the portion of the document nested inside node that
triggered the handler.

New handlers may be defined within a handler and their scope will be
limited to the XML inside the node that triggered the handler.

=head1 INTERFACE 

=over

=item C<new>

=item C<walk>

=item C<on>

=item C<stash>

=item C<text>

=item C<xml>

=item C<get_path>

=item C<get_token>

=back

=head1 DIAGNOSTICS

=for author to fill in:
    List every single error and warning message that the module can
    generate (even the ones that will "never happen"), with a full
    explanation of each problem, one or more likely causes, and any
    suggested remedies.

=over

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=item C<< Another error message here >>

[Description of error here]

[Et cetera, et cetera]

=back

=head1 CONFIGURATION AND ENVIRONMENT

=for author to fill in:
    A full explanation of any configuration system(s) used by the
    module, including the names and locations of any configuration
    files, and the meaning of any environment variables or properties
    that can be set. These descriptions must also include details of any
    configuration language used.
  
XML::Descent requires no configuration files or environment variables.

=head1 DEPENDENCIES

=for author to fill in:
    A list of all the other modules that this module relies upon,
    including any restrictions on versions, and an indication whether
    the module is part of the standard Perl distribution, part of the
    module's distribution, or must be installed separately. ]

None.


=head1 INCOMPATIBILITIES

None reported.

=head1 SEE ALSO

L<http://en.wikipedia.org/wiki/Recursive_descent_parser>

=head1 BUGS AND LIMITATIONS

XML::Descent uses C<XML::TokeParser> to do the actual parsing.
XML::TokeParser can only return start tags, end tags, raw text and
processing instructions. As a result C<xml()> called at the root of
an XML document will exclude any <?xml?> declaration.

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-xml-descent@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.

=head1 AUTHOR

Andy Armstrong  C<< <andy@hexten.net> >>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2006, Andy Armstrong C<< <andy@hexten.net> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
