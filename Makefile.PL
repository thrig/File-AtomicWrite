use inc::Module::Install;
name 'File-AtomicWrite';
all_from 'lib/File/AtomicWrite.pm';

perl_version '5.006';
requires 'Carp'            => 0;
requires 'File::Path'      => 0;
requires 'File::Temp'      => 0.18;
requires 'IO::Handle'      => 0;
recommends 'Digest::SHA1'  => 0;
test_requires 'Test::More' => 0;
test_requires 'File::Path' => 0;
test_requires 'File::Spec' => 0;

resources
  license    => 'http://dev.perl.org/licenses/artistic.html',
  repository => 'http://github.com/thrig/File-AtomicWrite',
  bugtracker =>
  'https://rt.cpan.org/Public/Dist/Display.html?Name=File-AtomicWrite';

WriteAll;
