#!/usr/bin/perl

use warnings;
use strict;

use Test::More tests => 2;
BEGIN { use_ok('File::AtomicWrite') }
ok( defined $File::AtomicWrite::VERSION, '$VERSION defined' );
