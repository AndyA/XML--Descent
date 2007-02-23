use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    ( MM->can( 'signature_target' ) ? ( SIGN => 1 ) : () ),
    NAME          => 'XML::Descent',
    AUTHOR        => 'Andy Armstrong <andy@hexten.net>',
    LICENSE       => 'perl',
    VERSION_FROM  => 'lib/XML/Descent.pm',
    ABSTRACT_FROM => 'lib/XML/Descent.pm',
    PL_FILES      => {},
    PREREQ_PM     => {
        'Test::More'      => 0,
        'version'         => 0,
        'XML::TokeParser' => 0,
        'Class::Std'      => 0,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES    => 'XML-Descent-*' },
);
