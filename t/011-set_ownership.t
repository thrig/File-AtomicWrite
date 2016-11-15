#!perl
#
# Tests for standalone _set_ownership function.
#

use strict;
use warnings;
use Test::More;

my ($args, $data);

BEGIN {
    *CORE::GLOBAL::getpwnam = sub {
        $args->[0] = \@_;
        return defined($data->{getpwnam}) ? @{$data->{getpwnam}} : qw(user xyz 123 1234);
    };
    *CORE::GLOBAL::getgrnam = sub {
        $args->[1] = \@_;
        return defined($data->{getgrnam}) ? @{$data->{getgrnam}} : qw(group xyz 456);
    };
    *CORE::GLOBAL::chown = sub {
        $args->[2] = \@_;
        return defined($data->{chown}) ? $data->{chown} : 1;
    };
};

use File::AtomicWrite;

sub test_so {
    my ($owner, $expected, $diag) = @_;

    $args = [];

    my $fn = 'myfile';
    is(File::AtomicWrite::_set_ownership($fn, $owner), 1, "_set_ownership ok with owner $owner");

    is_deeply($args, $expected, "arguments as expected for owner $owner");

    if ($diag) {
        diag "args owner $owner ", explain $args;
    }
}

test_so("myuser:mygroup", [['myuser'], ['mygroup'], [123, 456, 'myfile']]);
test_so("myuser:789", [['myuser'], undef, [123, 789, 'myfile']]);
test_so("321:mygroup", [undef, ['mygroup'], [321, 456, 'myfile']]);
test_so("321:789", [undef, undef, [321, 789, 'myfile']]);
test_so("myuser", [['myuser'], undef, [123, -1, 'myfile']]);
test_so("myuser:", [['myuser'], undef, [123, -1, 'myfile']]);
test_so(":mygroup", [undef, ['mygroup'], [-1, 456, 'myfile']]);


done_testing;
