#!/usr/bin/env perl

use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;
use English qw(-no_match_vars);

plan tests => 3;

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
    plan tests => 3;

    is(JIP::Daemon->new->try_kill,    1);
    is(JIP::Daemon->new->try_kill(0), 1);

    local $SIG{'USR1'} = sub { pass 'USR1 caught'; };
    JIP::Daemon->new->try_kill(10);
};

subtest 'status()' => sub {
    plan tests => 1;

    is_deeply [JIP::Daemon->new->status], [$PROCESS_ID, 1, 0];
};

