#!perl
# vim:ts=2:sw=2:et:ft=perl

use strict;
use warnings;

use XML::Descent;
use Data::Dumper;
use Test::More tests => 2;

my $td = test_data(
  do { local $/; <DATA> }
);

{
  ok my $p = XML::Descent->new( Input => \$td->{t1} );
  my @got = ();
  $p->on(
    link => sub {
      my ( $elem, $attr, $ctx ) = @_;
      push @got, [ $p->get_path, $attr ];
    },
    name => sub {
      my ( $elem, $attr, $ctx ) = @_;
      push @got, [ $p->get_path, $attr ];
    },
    nested => sub {
      my ( $elem, $attr, $ctx ) = @_;
      $p->on(
        '*' => sub {
          my ( $elem, $attr, $ctx ) = @_;
          push @got, [ '*', $p->get_path, $attr ];
        }
      )->inherit( 'name' )->walk;
    },
  )->walk;

  my @expect = (
    [ '/root/link', { 'href' => 'http://hexten.net/' } ],
    [ '/root/name', {} ],
    [ '*', '/root/nested/link', { 'href' => 'http://perl.org/' } ],
    [ '/root/nested/name', {} ]
  );

  is_deeply \@got, \@expect, 'inherit';
}

sub test_data {
  my $xml = shift;
  my $td  = {};
  my $p   = XML::Descent->new( Input => \$xml );
  $p->on(
    test => sub {
      my ( $elem, $attr, $ctx ) = @_;
      $td->{ $attr->{id} } = $p->xml;
    }
  )->walk;
  return $td;
}

__DATA__
<test id="t1">
  <root>
    <link href="http://hexten.net/">Hexten</link>
    <name>Horse Fingers</name>
    <nested>
      <link href="http://perl.org/">Perl</link>
      <name>Providence</name>
    </nested>
  </root>
</test>

