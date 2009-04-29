use warnings;
use strict;

use Test::More 'no_plan';
BEGIN { use_ok('File::AtomicWrite') }

can_ok( 'File::AtomicWrite', qw{write_file} );

# See if File::Spec still makes sense...
BEGIN { use_ok('File::Spec') }
can_ok( 'File::Spec', qw{catfile tmpdir} );

my $tmp_dir = File::Spec->tmpdir();
ok( defined $tmp_dir, 'check that tmp_dir defined' );

# These should fail
{
  eval { File::AtomicWrite->write_file(); };
  like( $@, qr/missing or empty required option/, 'empty invocation' );

  eval { File::AtomicWrite->write_file( { file => 'somefile' } ); };
  like( $@, qr/missing or empty required option/, 'incomplete invocation' );
}

# TODO really need a File::Temp filename to test with, or write files
# out under the t directory, as otherwise have a security problem.
exit 0;

REQ_TMP_DIR: {
  skip "no temp directory", 0 unless defined $tmp_dir;

  my $test_file = File::Spec->catfile( $tmp_dir, "atomicwrite-test1" );
  File::AtomicWrite->write_file( { file => $test_file, input => \"hi" } );
}
