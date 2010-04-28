use inc::Module::Install;

# Define metadata
name 'File-AtomicWrite';
all_from 'lib/File/AtomicWrite.pm';

# Specific dependencies
requires 'File::Path'        => '1.06';
requires 'File::Temp'        => '0.18';
recommends 'Digest::SHA1'    => '2.10';
test_requires 'Digest::SHA1' => '2.10';
test_requires 'File::Path'   => '1.06';
test_requires 'File::Spec'   => '3.26';
test_requires 'Test::More'   => '0.72';

WriteAll;
