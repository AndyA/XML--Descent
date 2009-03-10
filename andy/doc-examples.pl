#!/usr/bin/perl -w
#
#  doc-examples
#
#  Created by Andy Armstrong on 2006-11-23.
#  Copyright (c) 2006 Hexten. All rights reserved.

use strict;
use lib 'lib';
use Carp;
use XML::Descent;

$| = 1;

# Example 1
{
  my $xml = <<EOX;
<links>
    <link url="http://google.com/" />
    <link url="http://hexten.net/" />
</links>
EOX

  my $p = XML::Descent->new( { Input => \$xml } );
  $p->on(
    link => sub {
      my ( $elem, $attr ) = @_;
      print "Found link: ", $attr->{url}, "\n";
      $p->walk();    # recurse
    }
  );
  $p->walk();        # parse
}

