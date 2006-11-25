package XML::Descent;

use warnings;
use strict;
use Carp;
use XML::TokeParser;
use Class::Std;

use version; our $VERSION = qv('0.0.1');

# TODO:
#    Implement on_match($re, $sub)
#    Implement on_path($xpath, $sub)
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
        obj         => undef
    };
    $token{$id}   = undef;
    $path{$id}    = [ ];
}

# Not a method
sub _get_rule_handler {
    my ($tos, $tok) = @_;
    my $elem = $tok->[1];
    while (defined($tos)) {
        if (defined($tos->{rules}->{$elem})) {
            return $tos->{rules}->{$elem};
        } elsif (defined($tos->{rules}->{'*'})) {
            return $tos->{rules}->{'*'};
        }
        $tos = $tos->{parent};
    }
    
    return;
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
                    stopat  => $stopat,
                    obj     => $tos->{obj}
                };
                
                # Call handler
                $handler->($tok->[1], $tok->[2], $tos->{obj});
                
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
}

sub on {
    my $self = shift;
    my $id   = ident($self);
    my ($path, $cb) = @_;

    if (ref($path) eq 'ARRAY') {
        for my $p (@{$path}) {
            $context{$id}->{rules}->{$p} = $cb;
        }
    } else {
        $context{$id}->{rules}->{$path} = $cb;
    }
}

sub inherit {
    my $self = shift;
    my $id   = ident($self);
    my ($path) = @_;

    if (ref($path) eq 'ARRAY') {
        $self->inherit($_) for @{$path};
    } else {
        $self->on($path, _get_rule_handler($context{$id}->{parent}, $path));
    }
}

sub context {
    my $self = shift;
    my $id   = ident($self);
    
    if (@_) {
        return $context{$id}->{obj} = $_[0];
    } else {
        return $context{$id}->{obj};
    }
}

1;

__END__

=head1 NAME

XML::Descent - Recursive descent XML parsing

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

A handler provides a convenient lexical scope that lasts until the
closing tag of the element that triggered the handler is reached.

When called at the top level the parsing methods walk(), text() and
xml() parse the whole XML document. When called recursively within a
handler they parse the portion of the document nested inside node that
triggered the handler.

New handlers may be defined within a handler and their scope will be
limited to the XML inside the node that triggered the handler.

=head1 INTERFACE 

=over

=item C<new( { options } )>

Create a new XML::Descent. Options are supplied has a hash reference.
The only option recognised directly by XML::Descent is C<Input> which
should be reference to the object that provides the XML source. Any
value that can be passed as the first argument to C<XML::TokeParser-
>new> is allowed.

The remaining options are passed directly to C<XML::TokeParser>; consult
that module's documentation for more details.

=item C<walk>

Parse part of the XML document tree triggering any handlers that correspond
with elements it contains. When called recursively within a handler C<walk>
visits all the elements below the element that triggered the handler and
then returns.

=item C<on( [ element names ], handler )>

Register a handler to be called when the named element is encountered.
Multiple element names may be supplied as an array reference. Calling
C<on> within a handler defines a nested local handler who's scope is
limited to the containing element. Handlers are called with three
arguments: the name of the element that triggered the handler, a hash of
the element's attributes and a user defined context value - see
C<context> for more about that.

For example:

    $p = XML::Descent->new( { Input => \$some_xml } );

    # Global handler - trigger anywhere an <options> tag is found
    $p->on(options => sub {
        my ($elem, $attr, $ctx) = @_;
        
        # Define a nested handler for <name> elements that only
        # applies within the <options> handler.
        $p->on(name => sub {
            my ($elem, $attr, $ctx) = @_;
            # Get the inner text of the name element
            my $name = $p->text();
            print "Name: $name\n";
        });
        
        # Recursively walk elements inside <options> triggering
        # any handlers
        $p->walk();
    });

    # Start parsing
    $p->walk();

A handler should call one of the parsing methods (C<walk>, C<text>, C<xml>
or C<get_token>) before returning to consume any nested XML. If none of
the parsing methods are called nested XML is automatically discarded so
that the parser can properly move past the current element.

Nested handlers temporarily override another handler with the same name.
A handler named '*' will trigger for all elements for which there is no
explicit handler. A nested '*' handler hides all handlers defined in
containing scopes.

=item C<inherit( [ element names ] )>

Inherit handlers from the containing scope. Typically used to import
handlers that would otherwise be masked by a catch all '*' handler.

    $p->on('a' => sub {
        my ($elem, $attr, $ctx) = @_;
        my $link = $attr->{href} || '';
        my $text = $p->text();
        print "Link: $text ($link)\n";
    });
    
    $p->on('special' => sub {
        my ($elem, $attr, $ctx) = @_;

        # Within <special> we want to handle all
        # tags apart from <a> by printing them out
        $p->on('*' => sub {
            my ($elem, $attr, $ctx) = @_;
            print "Found: $elem\n";
        });
        
        # Get the handler for <a> from our containing
        # scope.
        $p->inherit('a');
        $p->walk();
    });

The inherited handler is the handler that would have applied in the containing
scope for an element with the given name. For example:

    $p->on('*' => sub { print "Whatever\n"; $p->walk(); });
    $p->on('interesting' => sub {
        # Inherits the default 'Whatever' handler because that's the handler
        # that would have been called for <frob> in the containing scope
        $p->inherit('frob');
        # Handle everything else ourselves
        #p->on('*', sub { $p->walk(); });
    });

=item C<context>

Every time a handler is called a new scope is created for it. This allows
nested handlers to be defined. The current scope contains a user context
variable which can be used, for example, to keep track of an object that
is being filled with values parsed from the XML. The context value is
inherited from the parent scope but may be overridden locally.

For example:

    my $root = { };

    # Set the outermost context
    $p->context($root);

    # Handle HTML <a href...> links /anywhere/
    $p->on('a' => sub {
        my ($elem, $attr, $ctx) = @_;
        my $link = {
            href => $attr->{href},
            text => $p->text()
        };
        push @{$ctx->{links}}, $link;
    });
    
    # Links in the body are stored in a nested
    # object.
    $p->on('body' => sub {
        my ($elem, $attr, $ctx) = @_;
        my $body = { };
        # Set the context
        $p->context($body);
        $p->walk();
        $ctx->{body} = $body;
    });
    
    $p->walk();
    
Note that the handler for <a href...> tags stores its results in the
current context object - whatever that happens to be. That means that
outside of any <body> tag links will be stored in C<$root> but within a
<body> they will be stored in a nested object (C<$root->{body}>). The
<a> handler itself need know nothing of this.

With no parameter C<context> returns the current context. The current
context is also passed as the third argument to handlers.

=item C<text>

Return any text contained within the current element. XML markup is
discarded.

=item C<xml>

Return the unparsed inner XML of the current element. For example:

    $p->on('item' => sub {
        my ($elem, $attr, $ctx) = @_;
        my $item_source = $p->xml();
        print "Item: $item_source\n";
    });

If <item> contains XHTML (for example) the above handler would correctly
capture it without recursively parsing any elements it contains. Parsing

    <feed>
        <item>This is the <i>first story</i>.</item>
        <item>This is <b>another story</b>.</item>
    </feed>
    
would print

    Item: This is the <i>first story</i>.
    Item: This is <b>another story</b>.

=item C<get_path>

Called within a handler returns the path that leads to the current
element. For example:

    $p->on('here' => sub {
        my ($elem, $attr, $ctx) = @_;
        print "I am here: ", $p->get_path(), "\n";
        $p->walk();
    });

would, if applied to this XML

    <outer>
        <inner>
            <here />
        </inner>
        <here />
    </outer>
    
print

    I am here: /outer/inner/here
    I am here: /outer/here

=item C<get_token>

XML::Descent is built on C<XML::TokeParser> which splits an XML document
into a stream of tokens representing start tags, end tags, literal text,
comment and processing instructions. Within an element C<get_token> returns
the same stream of tokens that C<XML::TokeParser> would produce. Returns
C<undef> once all the tokens contained within the current element have
been read (i.e. it's impossible to read past the end of the enclosed XML).

=back

=head1 DIAGNOSTICS

Please consult the documentation for C<XML::TokeParser> for a list of
diagnostics it can generate.

=over

=item C<< No Input arg >>

The constructor must be passed an arg named 'Input' which is then passed
as the first argument to the C<XML::TokeParser> constructor.

=back

=head1 DEPENDENCIES

XML::TokeParser, Class::Std

=head1 INCOMPATIBILITIES

None reported.

=head1 SEE ALSO

L<http://en.wikipedia.org/wiki/Recursive_descent_parser>,
L<XML::Descent::Tutorial>, 
L<XML::TokeParser>,
L<XML::Twig>.

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
