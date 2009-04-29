use warnings;
use strict;

use Test::More 'no_plan';
BEGIN { use_ok('File::AtomicWrite') }

ok( defined $File::AtomicWrite::VERSION, '$VERSION defined' );
