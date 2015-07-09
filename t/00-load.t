#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;

my $mod;
BEGIN {
    $mod = 'Log::Minimal';
    use_ok( $mod );
}

diag( "Testing Log::Minimal $Log::Minimal::VERSION, Perl $], $^X" );

my $l = $mod->new();
isa_ok($l, $mod );


done_testing();
