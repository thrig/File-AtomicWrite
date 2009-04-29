# Like IO::AtomicWrite, except uses File::Temp to create the temporary
# file, and offers various degrees of more paranoid write handling, and
# means to set Unix file permissions and ownerships on the resulting
# file. Run perldoc(1) on this module for more information.
#
# Copyright 2009 by Jeremy Mates.
#
# This module is free software; you can redistribute it and/or modify it
# under the Artistic license.

use strict;
use warnings;

require 5.006;

use Carp qw(croak);
use File::Basename qw(dirname);
use File::Path qw(mkpath);
use File::Temp qw(tempfile);

our $VERSION = '0.01';

# Default options, override via hashref passed to write_file().
my %default_params = ( template => ".tmp.XXXXXXXX", MKPATH => 0 );

# Single method that accepts output filename, perhaps optional tmp file
# template, and a filehandle or scalar ref, and handles all the details
# in a single shot.
sub write_file {
  my $class = shift;
  my $user_params = shift || croak("not enough parameters passed\n");

  my $params_ref = { %default_params, %$user_params };

  for my $req_param (qw{file input}) {
    if ( !exists $params_ref->{$req_param}
      or !defined $params_ref->{$req_param} ) {
      croak("missing or empty required option: $req_param\n");
    }
  }

  $params_ref->{_dir} = dirname( $params_ref->{file} );

  # TODO support tmpdir option, so the temporary directory can be
  # different from the actual file directory. (With suitable warnings
  # about partition boundaries and so forth. Required for certain
  # directories where some other program might accidentally read even
  # the transitory tempfile this module creates, such as /etc/cron.d or
  # /etc/logrotate.d on certain platforms.)

  if ( !-d $params_ref->{_dir} ) {
    _mkpath( $params_ref->{MKPATH}, $params_ref->{_dir} );
  }

  my ( $tmp_fh, $tmp_filename ) = tempfile(
    $params_ref->{template},
    DIR    => $params_ref->{_dir},
    UNLINK => 0
  );
  if ( !defined $tmp_fh ) {
    die "unable to obtain temporary filehandle\n";
  }

  my $input = $params_ref->{input};
  if ( ref $input eq '' ) {
    unless ( print $tmp_fh $$input ) {
      my $save_errstr = $!;

      # recommended by perlport(1) prior to unlink/rename calls
      close $tmp_fh;
      unlink $tmp_filename;

      croak("error printing to temporary file: $save_errstr\n");
    }
  } else {
    while ( my $line = <$input> ) {
      unless ( print $tmp_fh $line ) {
        my $save_errstr = $!;

        # recommended by perlport(1) prior to unlink/rename calls
        close $tmp_fh;
        unlink $tmp_filename;

        croak("error printing to temporary file: $save_errstr\n");
      }
    }
  }

  if ( exists $params_ref->{min_size} ) {
    my $written = tell($tmp_fh);
    if ( $written == -1 ) {
      # recommended by perlport(1) prior to unlink/rename calls
      close $tmp_fh;
      unlink $tmp_filename;

      die("unable to tell() on temporary filehandle\n");

    } elsif ( $written < $params_ref->{min_size} ) {
      # recommended by perlport(1) prior to unlink/rename calls
      close $tmp_fh;
      unlink $tmp_filename;

      croak("bytes written failed to exceed min_size required\n");
    }
  }

  # TODO checksum option on the written data as a very paranoid check?

  # recommended by perlport(1) prior to unlink/rename calls
  close($tmp_fh);

  eval {
    if ( exists $params_ref->{mode} ) {
      _set_mode( $params_ref->{mode}, $tmp_filename );
    }

    if ( exists $params_ref->{owner} ) {
      _set_ownership( $params_ref->{owner}, $tmp_filename );
    }
  };
  if ($@) {
    unlink $tmp_filename;
    die $@;
  }

  unless ( rename( $tmp_filename, $params_ref->{file} ) ) {
    my $save_errstr = $!;
    unlink $tmp_filename;
    croak "unable to rename file: $save_errstr\n";
  }
}

sub _mkpath {
  my $mkpath    = shift;
  my $directory = shift;

  if ($mkpath) {
    mkpath($directory);
    if ( !-d $directory ) {
      croak("could not create parent directory\n");
    }
  } else {
    croak("parent directory does not exist\n");
  }

  return 1;
}

# Accepts file permission (mode), filename. croak()s on problems.
sub _set_mode {
  my $mode     = shift;
  my $filename = shift;

  croak("invalid mode data\n") if !defined $mode or $mode !~ m/^\d+$/;

  my $count = chmod( oct($mode), $filename );
  if ( $count != 1 ) {
    die "unable to chmod temporary file\n";
  }

  return 1;
}

# Accepts "0" or "user:group" type ownership details and a filename,
# attempts to set ownership rights on that filename. croak()s if
# anything goes awry.
sub _set_ownership {
  my $owner    = shift;
  my $filename = shift;

  croak("invalid owner data\n") if !defined $owner or length $owner < 1;

  # defaults if nothing comes of the subsequent parsing
  my ( $uid, $gid ) = ( -1, -1 );

  my ( $user_name, $group_name ) = split /[:.]/, $owner, 2;

  my ( $login, $pass, $user_uid, $user_gid );
  if ( $user_name =~ m/^(\d+)$/ ) {
    $uid = $1;
  } else {
    ( $login, $pass, $user_uid, $user_gid ) = getpwnam($user_name)
      or croak("user not in password database\n");
    $uid = $user_uid;
  }

  if ( !defined $group_name ) {
    $gid = $user_gid;
  } else {
    if ( $group_name =~ m/^(\d+)$/ ) {
      $gid = $group_name;
    } else {
      my ( $group_name, $pass, $group_gid ) = getgrnam($group_name)
        or croak("group not in group database\n");
      $gid = $group_gid;
    }
  }

  my $count = chown( $uid, $gid, $filename );
  if ( $count != 1 ) {
    die "unable to chown temporary file\n";
  }

  return 1;
}

1;

=head1 NAME

File::AtomicWrite - writes files atomically via rename()

=head1 SYNOPSIS

  use File::AtomicWrite ();

  eval {

    File::AtomicWrite->write_file(
      file  => 'data.dat',
      input => $filehandle
    );

    # how paranoid are you?
    File::AtomicWrite->write_file(
      file     => '/etc/passwd',
      input    => $$scalarref,
      min_size => 100
    );

  };
  if ($@) {
    die "uh oh: $@";
  }

=head1 DESCRIPTION

This module writes files out atomically by first creating a temporary
filehandle, then using the rename() function to overwrite the target
file. The module optionally supports size tests on the output file
(to help avoid a zero byte C<passwd> file and the resulting
headaches, for example).

Should anything go awry, the module will C<die> or C<croak> as
appropriate. All error messages created by the module will end with a
newline, though those from submodules (L<File::Temp|File::Temp>,
L<File::Path>) may not.

=head1 METHODS

=over 4

=item C<write_file>

Class method. Performs the various required steps in a single method
call. Requires that the complete file data be passed via the
C<input> option.

See L<"OPTIONS"> for details on the various required and optional
options that can be passed as a hash reference to C<write_file>.

=back

=head1 OPTIONS

The C<write_file> method accepts a number of options, supplied via a
hash reference:

=over 4

item B<file>

Mandatory. Filename in the current working directory, or a path to the
file that will be eventually created.

=item B<input>

Mandatory. Scalar reference, or otherwise some filehandle reference
that can be looped over via C<E<lt>E<gt>>. Supplies the data to be
written to B<file>.

=item B<template>

Template to supply to L<File::Temp|File::Temp>. Defaults to a hopefully
reasonable value if unset. NOTE: if customized, the template must
contain a sufficient number of C<X> that terminate the template string,
as otherwise L<File::Temp|File::Temp> will throw an error.

=item B<min_size>

Specify a minimum size (in bytes) that the data written to the file must
exceede. If not, the module throws an error.

=item B<mode>

Accepts a Unix mode for C<chmod> to be applied to the file. C<oct()> is
run on this value. Usual throwing of error.

=item B<owner>

Accepts similar arguments to chown(1) to be applied via C<chown>
to the file. Usual throwing of error.

=item B<MKPATH>

If true (default is false), attempt to create the parent directory of
B<file> should that directory not exist. If false, and the parent
directory does not exist, the module throws an error. If the directory
cannot be created, the module throws an error.

=back

=head1 BUGS

No known bugs.
  
=head2 Reporting Bugs
  
Newer versions of this module may be available from CPAN.
  
If the bug is in the latest version, send a report to the author.
Patches that fix problems or add new features are welcome.

=head2 Known Issues

See perlport(1) for various portability problems possible with the
C<rename()> call.

=head1 SEE ALSO

L<File::Temp|File::Temp>

Alternatives, depending on the need, include:

L<IO::Atomic|IO::Atomic>, L<File::Transaction|File::Transaction>, L<File::Transaction::Atomic|File::Transaction::Atomic>

=head1 AUTHOR

Jeremy Mates, E<lt>jmates@sial.orgE<gt>

=head1 COPYRIGHT

Copyright 2009 by Jeremy Mates.

This program is free software; you can redistribute it and/or modify it
under the Artistic license.

=cut
