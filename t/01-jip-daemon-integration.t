#!/usr/bin/env perl

use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;
use English qw(-no_match_vars);

plan tests => 2;

subtest 'Require some module' => sub {
    use_ok 'JIP::Daemon', '0.01';

    diag(
        sprintf 'Testing JIP::Daemon %s, Perl %s, %s',
            $JIP::Daemon::VERSION,
            $PERL_VERSION,
            $EXECUTABLE_NAME,
    );

    done_testing();
};

subtest 'try_kill()' => sub {
    plan tests => 2;

    is(JIP::Daemon->new->try_kill(0), 1);

    local $SIG{'USR1'} = sub { pass 'USR1 caught'; };

    JIP::Daemon->new->try_kill(10);
};

