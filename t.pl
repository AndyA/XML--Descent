#!/usr/bin/perl -w
#
#  t
#
#  Created by Andy Armstrong on 2006-11-22.
#  Copyright (c) 2006 Hexten. All rights reserved.

use strict;
use lib 'lib';
use Carp;
use XML::Descent;
use Data::Dumper;

$| = 1;

my $xml = <<EOX;
<?xml version="1.0" encoding="utf-8"?>
<config>
    <favourites>
        <folder name="Me">
            <url name="Hexten">http://hexten.net/</url>
        </folder>
        <folder name="Programming">
            <url name="Source code search">http://www.koders.com/</url>
            <folder name="Perl">
                <url name="CPAN Search">http://search.cpan.org/</url>
                <url name="Perl Documentation">http://perldoc.perl.org/</url>
            </folder>
            <folder name="Ruby">
                <url name="Ruby Home">http://www.ruby-lang.org/</url>
            </folder>
        </folder>
    </favourites>
    <meta>
        <title>Frog fleening</title>
        <body>The body text is just <a href="http://www.w3.org/MarkUp/">HTML</a>.</body>
        <url>http://cpan.hexten.net/</url>
        <ignored>This text is ignored</ignored>
        <handled>This has a handler which doesn't recursively parse the contents</handled>
        <tokenised>This is <i>tokenised</i>.</tokenised>
    </meta>
</config>
EOX

my $p = XML::Descent->new({
    Input   => \$xml
});

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

$p->on(meta => sub {
    my ($title, $body, $link);
    $p->on(title => sub {
        $title = $p->text();
    });
    $p->on(body => sub {
        $body = $p->xml();
    });
    $p->on(url => sub {
        $link = $p->text();
    });
    $p->on(handled => sub {
        print "<handled> found, automatically parsed\n";
    });
    $p->on(tokenised => sub {
        while (my $tok = $p->get_token()) {
            print join(', ', @{$tok}), "\n";
        }
    });
    $p->walk();
    print "title: ", $title, "\n";
    print "body:  ", $body,  "\n";
    print "link:  ", $link,  "\n";
});

my $res = $p->walk();
print Dumper($res);

# Would be nice to be able to write the above as
# my $root = $p->walk($xml);

# At any point
#
# $p->text()        Gets the text (no tags) contained within the current node
# $p->dom()         Gets the DOM of the contained nodes
# $p->walk()        Gets the result of applying the currently active parsing
#                   rules to the contained nodes
# $p->xml()         Get the contained XML
# $p->next()        Gets the next token from the contained nodes

