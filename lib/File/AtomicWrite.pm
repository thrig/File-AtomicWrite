# Like IO::AtomicWrite, except uses File::Temp to create the temporary
# file, and offers various degrees of more paranoid write handling, and
# means to set Unix file permissions and ownerships on the resulting
# file. Run perldoc(1) on this module for more information.
#
# Copyright 2009 by Jeremy Mates.
#
# This module is free software; you can redistribute it and/or modify it
# under the Artistic license.

package File::AtomicWrite;

use strict;
use warnings;

require 5.006;

use Carp qw(croak);
use File::Basename qw(dirname);
use File::Path qw(mkpath);
use File::Temp qw(tempfile);

our $VERSION = '0.91';

# Default options
my %default_params = ( template => ".tmp.XXXXXXXX", MKPATH => 0 );

# Class method that accepts output filename, perhaps optional tmp file
# template, and a filehandle or scalar ref, and handles all the details
# in a single shot.
sub write_file {
  my $class = shift;
  my $user_params = shift || {};

  if ( !exists $user_params->{input} ) {
    croak("missing 'input' option");
  }

  my ( $params_ref, $digest, $tmp_fh, $tmp_filename ) = _init($user_params);

  # Attempt cleanup if things go awry
  local $SIG{TERM} = sub {
    # recommended by perlport(1) prior to unlink/rename calls
    close($tmp_fh) if defined $tmp_fh;
    unlink($tmp_filename) if defined $tmp_filename;
  };

  my $input_ref = ref $params_ref->{input};
  unless ( $input_ref eq 'SCALAR' or $input_ref eq 'GLOB' ) {
    croak("invalid type for input option: $input_ref\n");
  }

  my $input = $params_ref->{input};
  if ( $input_ref eq 'SCALAR' ) {
    unless ( print $tmp_fh $$input ) {
      my $save_errstr = $!;

      # recommended by perlport(1) prior to unlink/rename calls
      close($tmp_fh) if defined $tmp_fh;
      unlink($tmp_filename) if defined $tmp_filename;

      croak("error printing to temporary file: $save_errstr\n");
    }
    if ( exists $params_ref->{CHECKSUM}
      and !exists $params_ref->{checksum} ) {
      $digest->add($$input);
    }

  } elsif ( $input_ref eq 'GLOB' ) {
    while ( my $line = <$input> ) {
      unless ( print $tmp_fh $line ) {
        my $save_errstr = $!;

        # recommended by perlport(1) prior to unlink/rename calls
        close($tmp_fh) if defined $tmp_fh;
        unlink($tmp_filename) if defined $tmp_filename;

        croak("error printing to temporary file: $save_errstr\n");
      }

      if ( exists $params_ref->{CHECKSUM}
        and !exists $params_ref->{checksum} ) {
        $digest->add($$input);
      }
    }
  }

  _resolve( $params_ref, $digest, $tmp_fh, $tmp_filename );
}

sub new {
  my $class      = shift;
  my $self       = {};
  my $user_param = shift || {};

  croak("option 'input' only for write_file class method")
    if exists $user_param->{input};

  @{$self}{qw(_params _digest _tmp_fh _tmp_filename)} = _init($user_param);

  bless $self, $class;
  return $self;
}

sub fh {
  return shift->{_tmp_fh};
}

sub filename {
  return shift->{_tmp_filename};
}

sub checksum {
  my $self = shift;
  $self->{_params}->{checksum} = shift;

  if ( !$self->{_digest} ) {
    $self->{_params}->{CHECKSUM} = 1;
    $self->{_digest} = _init_checksum( $self->{_params} );
  }

  return $self;
}

sub commit {
  my $self = shift;
  _resolve( @{$self}{qw(_params _digest _tmp_fh _tmp_filename)} );
}

sub DESTROY {
  my $self = shift;

  # recommended by perlport(1) prior to unlink/rename calls
  close $self->{_tmp_fh} if defined $self->{_tmp_fh};
  unlink $self->{_tmp_filename} if defined $self->{_tmp_filename};
}

sub _init {
  my $user_params = shift || {};
  my $params_ref = { %default_params, %$user_params };

  if ( !exists $params_ref->{file}
    or !defined $params_ref->{file} ) {
    croak("missing 'file' option");
  }

  my $digest = _init_checksum($params_ref);

  $params_ref->{_dir} = dirname( $params_ref->{file} );
  if ( !-d $params_ref->{_dir} ) {
    _mkpath( $params_ref->{MKPATH}, $params_ref->{_dir} );
  }

  if ( exists $params_ref->{tmpdir} ) {
    if ( !-d $params_ref->{tmpdir}
      and $params_ref->{tmpdir} ne $params_ref->{_dir} ) {
      _mkpath( $params_ref->{MKPATH}, $params_ref->{tmpdir} );

      # partition sanity check
      my @dev_ids = map { ( stat $params_ref->{$_} )[0] } qw{_dir tmpdir};
      if ( $dev_ids[0] != $dev_ids[1] ) {
        croak("tmpdir and file directory on different partitions\n");
      }
    }
  } else {
    $params_ref->{tmpdir} = $params_ref->{_dir};
  }

  my ( $tmp_fh, $tmp_filename ) = tempfile(
    $params_ref->{template},
    DIR    => $params_ref->{tmpdir},
    UNLINK => 0
  );
  if ( !defined $tmp_fh ) {
    die "unable to obtain temporary filehandle\n";
  }

  if ( exists $params_ref->{BINMODE} and $params_ref->{BINMODE} ) {
    binmode($tmp_fh);
  }

  return $params_ref, $digest, $tmp_fh, $tmp_filename;
}

sub _init_checksum {
  my $params_ref = shift;
  my $digest     = 0;

  if ( exists $params_ref->{CHECKSUM} and $params_ref->{CHECKSUM} ) {
    eval { require Digest::SHA1; };
    if ($@) {
      croak("cannot checksum as lack Digest::SHA1\n");
    }
    $digest = Digest::SHA1->new;
  } else {
    # so can rely on 'exists' test elsewhere hereafter
    delete $params_ref->{CHECKSUM};
  }

  return $digest;
}

sub _resolve {
  my $params_ref   = shift;
  my $digest       = shift;
  my $tmp_fh       = shift;
  my $tmp_filename = shift;

  if ( exists $params_ref->{CHECKSUM}
    and !exists $params_ref->{checksum} ) {
    $params_ref->{checksum} = $digest->hexdigest;
  }

  eval {
    if ( exists $params_ref->{min_size} ) {
      _check_min_size( $tmp_fh, $params_ref->{min_size} );
    }
    if ( exists $params_ref->{CHECKSUM} ) {
      _check_checksum( $tmp_fh, $params_ref->{checksum} );
    }
  };
  if ($@) {
    # recommended by perlport(1) prior to unlink/rename calls
    close($tmp_fh) if defined $tmp_fh;
    unlink($tmp_filename) if defined $tmp_filename;
    die $@;
  }

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

  return 1;
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

sub _check_checksum {
  my $tmp_fh   = shift;
  my $checksum = shift;

  seek( $tmp_fh, 0, 0 )
    or die("tmp fh seek() error: $!\n");

  my $digest = Digest::SHA1->new;
  $digest->addfile($tmp_fh);

  my $on_disk_checksum = $digest->hexdigest;

  if ( $on_disk_checksum ne $checksum ) {
    croak("temporary file SHA1 hexdigest does not match supplied checksum\n");
  }

  return 1;
}

sub _check_min_size {
  my $tmp_fh   = shift;
  my $min_size = shift;

  # Must seek, as OO method allows the fh or filename to be passed off
  # and used by who knows what first.
  seek( $tmp_fh, 0, 2 )
    or die("tmp fh seek() error: $!\n");

  my $written = tell($tmp_fh);
  if ( $written == -1 ) {
    die("tmp fh tell() error: $!\n");
  } elsif ( $written < $min_size ) {
    croak("bytes written failed to exceed min_size required\n");
  }

  return 1;
}

# Accepts file permission (mode), filename. croak()s on problems.
sub _set_mode {
  my $mode     = shift;
  my $filename = shift;

  croak("invalid mode data\n") if !defined $mode or $mode !~ m/^\d+$/;

  my $count = chmod( $mode, $filename );
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

  # Only customize group if have something from caller
  if ( defined $group_name ) {
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

  # standalone method: requires filename and
  # input data (filehandle or scalar ref)
  File::AtomicWrite->write_file(
    { file  => 'data.dat',
      input => $filehandle
    }
  );

  # how paranoid are you?
  File::AtomicWrite->write_file(
    { file     => '/etc/passwd',
      input    => \$scalarref,
      CHECKSUM => 1,
      min_size => 100
    }
  );

  # OO interface
  my $aw = File::AtomicWrite->new({ file => 'name' });

  my $tmp_fh   = $aw->fh;
  my $tmp_file = $aw->filename;

  print $tmp_fh ...

  $aw->checksum($sha1_hexdigest);
  $aw->commit;

=head1 DESCRIPTION

This module writes files out atomically by first creating a temporary
filehandle, then using the rename() function to overwrite the target
file. The module optionally supports size tests on the output file
(to help avoid a zero byte C<passwd> file and the resulting
headaches, for example).

Should anything go awry, the module will C<die> or C<croak> as
appropriate. All error messages created by the module will end with a
newline, though those from submodules (L<File::Temp|File::Temp>,
L<File::Path>) may not. Therefore, all calls should be wrapped in
eval blocks:

  eval {
    File::AtomicWrite->write_file(...);
  };
  if ($@) {
    die "uh oh: $@";
  }

=head1 METHODS

=over 4

=item C<write_file>

Class method. Requires a hash reference that contains the B<input> and
B<file> options. Performs the various required steps in a single method
call. Only if all checks pass will the B<input> data be moved to the
B<file> file via C<rename()>. If not, the module will throw an error,
and attempt to cleanup any temporary files created.

See L<"OPTIONS"> for details on the various required and optional
values that can be passed to C<write_file> in a hash reference.

=item C<new>

Takes same options as C<write_file> (excepting the C<input> option),
returns an object.

In the event a rollback is required, C<undef> the File::AtomicWrite
object. The object destructor should then unlink the temporary file.
However, should the process receive a TERM or some other catchable
signal that causes it to exit, the cleanup will not be run. This edge
case will need to be handled by the caller. See perlipc(1) for more
information on signal handling.

  my $aw = File::AtomicWrite->new({file => 'somefile'});

  $SIG{TERM} = { undef $aw };
  ...

=item C<fh>

Instance method, returns a filehandle for the temporary file.

=item C<filename>

Instance method, returns the file name of the temporary file.

=item C<checksum>

Instance method. Takes a single argument that should contain the
L<Digest::SHA1|Digest::SHA1> C<hexdigest> of the data written to the
temporary file. Enables the C<CHECKSUM> option.

=item C<commit>

Instance method. Call once finished with the temporary file. A number of
sanity checks (if enabled via the appropriate option) will be performed.
If these pass, the temporary file will be renamed to the real filename.

=back

=head1 OPTIONS

The C<write_file> method accepts a number of options, supplied via a
hash reference:

=over 4

=item B<file>

Mandatory. A filename in the current working directory, or a path to the
file that will be eventually created. By default, the temporary file
will be written into the parent directory of the B<file> path. This
default can be changed by using the B<tmpdir> option.

If the B<MKPATH> option is true, the module will attempt to create any
missing directories, instead of issuing an error.

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

Specify a minimum size (in bytes) that the data written must exceed. If
not, the module throws an error.

=item B<mode>

Accepts a Unix mode for C<chmod> to be applied to the file. Usual
throwing of error. NOTE: depending on the source of the mode, C<oct()>
may be first required to convert it into an octal number:

  my $orig_mode = (stat $source_file)[2] & 07777;
  ...->write_file({ ..., mode => $orig_mode });

  my $mode = '0644';
  ...->write_file({ ..., mode => oct($mode) });

The module does not change C<umask()>, nor is there a means to specify
the permissions on directories created if B<MKPATH> is set.

=item B<owner>

Accepts similar arguments to chown(1) to be applied via C<chown>
to the file. Usual throwing of error.

  ...->write_file({ ..., owner => '0'   });
  ...->write_file({ ..., owner => '0:0' });
  ...->write_file({ ..., owner => 'user:somegroup' });

=item B<tmpdir>

If set to a directory, the temporary file will be written to this
directory instead of by default to the parent directory of the target
B<file>. If the B<tmpdir> is on a different partition than the parent
directory for B<file>, or if anything else goes awry, the module will
throw an error.

This option is advisable when writing files to include directories such
as C</etc/logrotate.d>, as the programs that read include files from
these directories may read even a temporary dot file while it is being
written. To avoid this (slight but non-zero) risk, use the B<tmpdir>
option to write the configuration out in full under a different
directory on the same partition.

=item B<checksum>

If this option exists, and B<CHECKSUM> is true, the module will not
create a L<Digest::SHA1|Digest::SHA1> C<hexdigest> of the data being
written out to disk, but instead will rely on the value passed by
the caller.

=item B<CHECKSUM>

If true, L<Digest::SHA1|Digest::SHA1> will be used to checksum the data
read back from the disk against the checksum derived from the data
written out to the temporary file. See also the B<checksum> option.

=item B<BINMODE>

If true, C<binmode()> is set on the temporary filehandle prior to
writing the B<input> data to it.

=item B<MKPATH>

If true (default is false), attempt to create the parent directory of
B<file> should that directory not exist. If false, and the parent
directory does not exist, the module throws an error. If the directory
cannot be created, the module throws an error.

If true, this option will also attempt to create the B<tmpdir>
directory, if set.

=back

=head1 BUGS

No known bugs.
  
=head2 Reporting Bugs
  
Newer versions of this module may be available from CPAN.
  
If the bug is in the latest version, send a report to the author.
Patches that fix problems or add new features are welcome.

http://github.com/thrig/File-AtomicWrite/tree/master

=head2 Known Issues

See perlport(1) for various portability problems possible with the
C<rename()> call.

=head1 SEE ALSO

Supporting modules:

L<File::Temp|File::Temp>, L<File::Path|File::Path>, L<File::Basename|File::Basename>, L<Digest::SHA1|Digest::SHA1>

Alternatives, depending on the need, include:

L<IO::Atomic|IO::Atomic>, L<File::Transaction|File::Transaction>, L<File::Transaction::Atomic|File::Transaction::Atomic>

=head1 AUTHOR

Jeremy Mates, E<lt>jmates@sial.orgE<gt>

=head1 COPYRIGHT

Copyright 2009 by Jeremy Mates.

This program is free software; you can redistribute it and/or modify it
under the Artistic license.

=cut
