#!/usr/bin/env perl

use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Carp qw(croak);
use English qw(-no_match_vars);
use Mock::Quick qw(qtakeover qobj qmeth);
use Capture::Tiny qw(capture capture_stderr);

plan tests => 12;

subtest 'Require some module' => sub {
    plan tests => 2;

    use_ok 'JIP::Daemon', '0.01';
    require_ok 'JIP::Daemon';

    diag(
        sprintf 'Testing JIP::Daemon %s, Perl %s, %s',
            $JIP::Daemon::VERSION,
            $PERL_VERSION,
            $EXECUTABLE_NAME,
    );
};

subtest 'new()' => sub {
    eval { JIP::Daemon->new(uid => undef) } or do {
        like $EVAL_ERROR, qr{^Bad \s argument \s "uid"}x;
    };
    eval { JIP::Daemon->new(uid => q{}) } or do {
        like $EVAL_ERROR, qr{^Bad \s argument \s "uid"}x;
    };

    eval { JIP::Daemon->new(gid => undef) } or do {
        like $EVAL_ERROR, qr{^Bad \s argument \s "gid"}x;
    };
    eval { JIP::Daemon->new(gid => q{}) } or do {
        like $EVAL_ERROR, qr{^Bad \s argument \s "gid"}x;
    };

    eval { JIP::Daemon->new(cwd => undef) } or do {
        like $EVAL_ERROR, qr{^Bad \s argument \s "cwd"}x;
    };
    eval { JIP::Daemon->new(cwd => q{}) } or do {
        like $EVAL_ERROR, qr{^Bad \s argument \s "cwd"}x;
    };

    eval { JIP::Daemon->new(umask => undef) } or do {
        like $EVAL_ERROR, qr{^Bad \s argument \s "umask"}x;
    };
    eval { JIP::Daemon->new(umask => q{}) } or do {
        like $EVAL_ERROR, qr{^Bad \s argument \s "umask"}x;
    };

    eval { JIP::Daemon->new(logger => undef) } or do {
        like $EVAL_ERROR, qr{^Bad \s argument \s "logger"}x;
    };
    eval { JIP::Daemon->new(logger => qobj()) } or do {
        like $EVAL_ERROR, qr{^Bad \s argument \s "logger"}x;
    };

    eval { JIP::Daemon->new(log_callback => undef) } or do {
        like $EVAL_ERROR, qr{^Bad \s argument \s "log_callback"}x;
    };
    eval { JIP::Daemon->new(log_callback => q{}) } or do {
        like $EVAL_ERROR, qr{^Bad \s argument \s "log_callback"}x;
    };

    my $obj = JIP::Daemon->new;
    ok $obj, 'got instance if JIP::Daemon';

    isa_ok $obj, 'JIP::Daemon';

    can_ok $obj, qw(
        new
        daemonize
        reopen_std
        drop_privileges
        try_kill
        status
        pid
        uid
        gid
        cwd
        umask
        logger
        dry_run
        detached
        log_callback
    );

    is $obj->pid,      $PROCESS_ID;
    is $obj->dry_run,  0;
    is $obj->detached, 0;
    is $obj->uid,      undef;
    is $obj->gid,      undef;
    is $obj->cwd,      undef;
    is $obj->umask,    undef;
    is $obj->logger,   undef;
    is $obj->logger,   undef;

    is ref $obj->log_callback, 'CODE';

    done_testing();
};

subtest 'logging' => sub {
    plan tests => 2;

    my $logs = [];
    my $obj  = JIP::Daemon->new(logger => qobj(
        info => qmeth {
            my $self = shift;
            push @{ $logs }, @ARG;
        },
    ));

    is ref($obj->_log()), 'JIP::Daemon';
    $obj->_log('simple string');
    $obj->_log('format %s', 'value');

    # if logger is not defined
    $obj = JIP::Daemon->new;
    $obj->_log('another simple string');
    $obj->_log('another format %s', 'value');

    is_deeply $logs, ['simple string', 'format value'];
};

subtest 'try_kill()' => sub {
    plan tests => 6;

    my $control = qtakeover 'POSIX' => (
        kill => sub {
            my ($pid, $signal) = @ARG;
            is_deeply [$pid, $signal], [$PROCESS_ID, q{9}];
            return 1;
        },
    );
    is(JIP::Daemon->new->try_kill(q{9}), 1);
    $control->restore('kill');

    $control->override(kill => sub {
        my ($pid, $signal) = @ARG;
        is_deeply [$pid, $signal], [$PROCESS_ID, q{0}];
        return 1;
    });
    is(JIP::Daemon->new->try_kill, 1);
    $control->restore('kill');

    my $std_err = capture_stderr {
        my $control_daemon = qtakeover 'JIP::Daemon' => (pid => sub { undef });

        is(JIP::Daemon->new->try_kill(q{0}), undef);
    };
    like $std_err, qr{^No \s subprocess \s running}x;
};

subtest 'status()' => sub {
    plan tests => 2;

    my $control = qtakeover 'POSIX' => (
        kill => sub {
            my ($pid, $signal) = @ARG;
            is_deeply [$pid, $signal], [$PROCESS_ID, 0];
            return 1;
        },
    );

    is_deeply [JIP::Daemon->new->status], [$PROCESS_ID, 1, 0];
};

subtest 'drop_privileges()' => sub {
    plan tests => 9;

    my $logs       = [];
    my $empty_logs = sub { $logs = []; };

    my $cb = sub {
        my $self = shift;
        push @{ $logs }, @ARG;
    };

    {
        my $uid = '65534';

        my $control = qtakeover 'POSIX' => (setuid => sub {
            is $ARG[0], $uid;
            return 1;
        });

        is(
            ref JIP::Daemon->new(uid => $uid, log_callback => $cb)->drop_privileges,
            'JIP::Daemon',
        );
        is_deeply $logs, ['Set uid=%d', $uid];

        $empty_logs->();
    }
    {
        my $gid = '65534';

        my $control = qtakeover 'POSIX' => (setgid => sub {
            is $ARG[0], $gid;
            return 1;
        });

        JIP::Daemon->new(gid => $gid, log_callback => $cb)->drop_privileges;
        is_deeply $logs, ['Set gid=%d', $gid];

        $empty_logs->();
    }
    {
        my $umask = 0;

        my $control = qtakeover 'POSIX' => (umask => sub {
            is $ARG[0], $umask;
            return 1;
        });

        JIP::Daemon->new(umask => $umask, log_callback => $cb)->drop_privileges;
        is_deeply $logs, ['Set umask=%s', $umask];

        $empty_logs->();
    }
    {
        my $cwd = q{/};

        my $control = qtakeover 'POSIX' => (chdir => sub {
            is $ARG[0], $cwd;
            return 1;
        });

        JIP::Daemon->new(cwd => $cwd, log_callback => $cb)->drop_privileges;
        is_deeply $logs, ['Set cwd=%s', $cwd];

        $empty_logs->();
    }
};

subtest 'exceptions in drop_privileges()' => sub {
    plan tests => 4;

    my $control = qtakeover 'POSIX' => (
        setuid => sub { 0 },
        setgid => sub { 0 },
        umask  => sub { 0 },
        chdir  => sub { 0 },
    );

    eval { JIP::Daemon->new(uid => 1)->drop_privileges } or do {
        like $EVAL_ERROR, qr{^Can't \s set \s uid \s "1":}x;
    };
    eval { JIP::Daemon->new(gid => 2)->drop_privileges } or do {
        like $EVAL_ERROR, qr{^Can't \s set \s gid \s "2":}x;
    };
    eval { JIP::Daemon->new(umask => 3)->drop_privileges } or do {
        like $EVAL_ERROR, qr{^Can't \s set \s umask \s "3":}x;
    };
    eval { JIP::Daemon->new(cwd => q{/})->drop_privileges } or do {
        like $EVAL_ERROR, qr{^Can't \s chdir \s to \s "/":}x;
    };
};

subtest 'reopen_std()' => sub {
    plan tests => 2;

    my $obj;

    my ($std_out, $std_err) = capture {
        print {*STDOUT} q{first std_out msg}
            or croak(sprintf q{Can't print to STDOUT: %s}, $OS_ERROR);
        print {*STDERR} q{first std_err msg}
            or croak(sprintf q{Can't print to STDERR: %s}, $OS_ERROR);

        $obj = JIP::Daemon->new->reopen_std;
        print {*STDOUT} q{second std_out msg}
            or croak(sprintf q{Can't print to STDOUT: %s}, $OS_ERROR);
        print {*STDERR} q{second std_err msg}
            or croak(sprintf q{Can't print to STDERR: %s}, $OS_ERROR);
    };

    is ref($obj), 'JIP::Daemon';
    is_deeply[$std_out, $std_err], [q{first std_out msg}, q{first std_err msg}];
};

subtest 'daemonize. dry_run' => sub {
    plan tests => 3;

    my $control_daemon = qtakeover 'JIP::Daemon' => (
        drop_privileges => sub {
            pass 'drop_privileges() method is invoked';
        },
    );

    my $obj = JIP::Daemon->new(dry_run => 1)->daemonize;
    is_deeply [$obj->detached, $obj->pid], [1, $PROCESS_ID];

    # daemonize on detached process changes nothing
    $obj->daemonize;
    is_deeply [$obj->detached, $obj->pid], [1, $PROCESS_ID];
};

subtest 'daemonize. parent' => sub {
    plan tests => 7;

    my $pid  = '500';
    my $logs = [];

    my $control_posix = qtakeover 'POSIX' => (
        fork => sub {
            pass 'fork() method is invoked';
            return $pid;
        },
        exit => sub {
            pass 'fork() method is invoked';
            my $exit_status = shift;
            is $exit_status, 0;
        },
    );
    my $control_daemon = qtakeover 'JIP::Daemon' => (
        logger => qobj(info => qmeth {
            my ($self, $msg) = @ARG;
            push @{ $logs }, $msg;
        }),
        drop_privileges => sub {
            pass 'drop_privileges() method is invoked';
        },
    );

    my $obj = JIP::Daemon->new->daemonize;
    is_deeply [$obj->detached, $obj->pid], [1, $pid];

    # daemonize on detached process changes nothing
    $obj->daemonize;
    is_deeply [$obj->detached, $obj->pid], [1, $pid];
    is_deeply $logs, [
        'Daemonizing the process',
        'Spawned process pid=500. Parent exiting',
    ];
};

subtest 'daemonize. child' => sub {
    plan tests => 8;

    my $pid  = '500';
    my $logs = [];

    my $control_posix = qtakeover 'POSIX' => (
        fork => sub {
            pass 'fork() method is invoked';
            return 0;
        },
        setsid => sub {
            pass 'setsid() method is invoked';
            return 1;
        },
        getpid => sub {
            pass 'getpid() method is invoked';
            return $pid;
        },
    );
    my $control_daemon = qtakeover 'JIP::Daemon' => (
        logger => qobj(info => qmeth {
            my ($self, $msg) = @ARG;
            push @{ $logs }, $msg;
        }),
        reopen_std => sub {
            pass 'reopen_std() method is invoked';
        },
        drop_privileges => sub {
            pass 'drop_privileges() method is invoked';
        },
    );

    my $obj = JIP::Daemon->new->daemonize;
    is_deeply [$obj->detached, $obj->pid], [1, $pid];

    # daemonize on detached process changes nothing
    $obj->daemonize;
    is_deeply [$obj->detached, $obj->pid], [1, $pid];
    is_deeply $logs, ['Daemonizing the process'];
};

subtest 'daemonize. exceptions' => sub {
    plan tests => 6;

    my $logs = [];

    my $control_daemon = qtakeover 'JIP::Daemon' => (
        logger => qobj(info => qmeth {
            my ($self, $msg) = @ARG;
            push @{ $logs }, $msg;
        }),
    );
    my $control_posix = qtakeover 'POSIX' => (
        fork => sub {
            pass 'fork() method is invoked';
            return;
        },
    );
    eval { JIP::Daemon->new->daemonize } or do {
        like $EVAL_ERROR, qr{^Can't \s fork}x;
    };
    $control_posix->restore('fork');

    $control_posix->override(
        fork => sub {
            pass 'fork() method is invoked';
            return 0;
        },
        setsid => sub {
            pass 'setsid() method is invoked';
            return;
        },
    );
    eval { JIP::Daemon->new->daemonize } or do {
        like $EVAL_ERROR, qr{^Can't \s start \s a \s new \s session:}x;
    };
    is_deeply $logs, ['Daemonizing the process', 'Daemonizing the process'];
};

