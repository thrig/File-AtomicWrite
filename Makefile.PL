use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
  NAME         => 'File::AtomicWrite',
  VERSION_FROM => 'lib/File/AtomicWrite.pm',
  PREREQ_PM    => {
    Carp         => 0,
    File::Path   => 0,
    File::Temp   => 0.18,
    IO::Handle   => 0,
    Digest::SHA1 => 0,
    Test::More   => 0,
    File::Spec   => 0
  },
  ( $] >= 5.005
    ?    ## Add these new keywords supported since 5.005
      (
      ABSTRACT_FROM =>
        'lib/File/AtomicWrite.pm',    # retrieve abstract from module
      AUTHOR => 'Jeremy Mates <jmates@cpan.org>'
      )
    : ()
  ),
);
