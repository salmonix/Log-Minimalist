use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'Log::Minimal',
    AUTHOR           => q{Laszlo Forro <getforum@gmail.com>},
    VERSION_FROM     => 'lib/Log/Minimal.pm',
    ABSTRACT_FROM    => 'lib/Log/Minimal.pm',
    LICENSE          => 'artistic_2',
    PL_FILES         => {},
    MIN_PERL_VERSION => 5.006,
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    BUILD_REQUIRES => {
        'Test::More' => 0,
    },
    PREREQ_PM => {
        'Method::Signatures' => 20141021,
        'Memoize' => 1.03,
        'IO::Interactive' => 0.0.6,
        'Term::ANSIColor' => 4.03,
        'Scalar::Util' => 1.41,
        'Carp' => 1.3301,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'Log-Minimal-*' },
);
