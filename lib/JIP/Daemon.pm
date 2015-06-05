package JIP::Daemon;

use 5.006;
use strict;
use warnings;
use JIP::ClassField;
use POSIX ();
use Carp qw(carp croak);
use English qw(-no_match_vars);

our $VERSION = '0.01';

my $default_log_callback = sub {
    my ($self, @params) = @ARG;

    my $logger = $self->logger;

    if (defined $logger) {
        my $msg;

        if (@params == 1) {
            $msg = shift @params;
        }
        elsif (@params) {
            my $format = shift @params;
            $msg = sprintf $format, @params;
        }

        $logger->info($msg) if defined $msg;
    }
};

map { has $_ => (get => '+', set => '-') } qw(
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

sub new {
    my ($class, %param) = @ARG;

    # Perform a trial run with no changes made (foreground if dry_run)
    my $dry_run = (exists $param{'dry_run'} and $param{'dry_run'}) ? 1 : 0;

    my $uid;
    if (exists $param{'uid'}) {
        $uid = $param{'uid'};

        croak q{Bad argument "uid"}
            unless defined $uid and $uid =~ m{^\d+$}x;
    }

    my $gid;
    if (exists $param{'gid'}) {
        $gid = $param{'gid'};

        croak q{Bad argument "gid"}
            unless defined $gid and $gid =~ m{^\d+$}x;
    }

    my $cwd;
    if (exists $param{'cwd'}) {
        $cwd = $param{'cwd'};

        croak q{Bad argument "cwd"}
            unless defined $cwd and length $cwd;
    }

    my $umask;
    if (exists $param{'umask'}) {
        $umask = $param{'umask'};

        croak q{Bad argument "umask"}
            unless defined $umask and length $umask;
    }

    my $logger;
    if (exists $param{'logger'}) {
        $logger = $param{'logger'};

        croak q{Bad argument "logger"}
            unless defined $logger and $logger->can('info');
    }

    my $log_callback;
    if (exists $param{'log_callback'}) {
        $log_callback = $param{'log_callback'};

        croak q{Bad argument "log_callback"}
            unless defined $log_callback and ref($log_callback) eq 'CODE';
    }
    else {
        $log_callback = $default_log_callback;
    }

    return bless({}, $class)
        ->_set_dry_run($dry_run)
        ->_set_uid($uid)
        ->_set_gid($gid)
        ->_set_cwd($cwd)
        ->_set_umask($umask)
        ->_set_logger($logger)
        ->_set_log_callback($log_callback)
        ->_set_pid($PROCESS_ID)
        ->_set_detached(0);
}

sub daemonize {
    my $self = shift;

    return $self if $self->detached;

    # Fork and kill parent
    if (not $self->dry_run) {
        $self->_log('Daemonizing the process');

        my $pid = fork; # returns child pid to the parent and 0 to the child

        croak q{Can't fork} if not defined $pid;

        # fork returned 0, so this branch is the child
        if ($pid == 0) {
            POSIX::setsid()
                or croak(sprintf q{Can't start a new session: %s}, $OS_ERROR);

            $self->reopen_std;
        }

        # this branch is the parent
        else {
            $self->_log('Spawned process pid=%d. Parent exiting', $pid);
            exit;
        }
    }

    $self->drop_privileges;

    return $self->_set_pid($PROCESS_ID)->_set_detached(1);
}

sub reopen_std {
    my $self = shift;

    open(STDIN,  '</dev/null')
        or croak(sprintf q{Can't reopen STDIN: %s},   $OS_ERROR);
    open(STDOUT, '>/dev/null')
        or croak(sprintf q{Can't reopen STDOUT: %s},  $OS_ERROR);
    open(STDERR, '>/dev/null')
        or croak(sprintf q{Can't reopen STDERR: %s},  $OS_ERROR);

    return $self;
}

sub drop_privileges {
    my $self = shift;

    if (defined $self->uid) {
        my $uid = $self->uid;
        $self->_log('Set uid=%d', $uid);
        POSIX::setuid($self->uid)
            or croak(sprintf q{Can't set uid %s}, $self->uid);
    }

    if (defined $self->gid) {
        my $gid = $self->gid;
        $self->_log('Set gid=%d', $gid);
        POSIX::setgid($gid)
            or croak(sprintf q{Can't set gid %s}, $gid);
    }

    if (defined $self->umask) {
        my $umask = $self->umask;
        $self->_log('Set umask=%s', $umask);
        umask $umask
            or croak(sprintf q{Can't set umask %s: %s}, $umask, $OS_ERROR);
    }

    if (defined $self->cwd) {
        my $cwd = $self->cwd;
        $self->_log('Set cwd=%s', $cwd);
        chdir $cwd
            or croak(sprintf q{Can't chdir to %s: %s}, $cwd, $OS_ERROR);
    }

    return $self;
}

sub try_kill {
    my ($self, $signal) = @ARG;

    my $pid = $self->pid;

    if (defined $pid) {
        return kill $signal // 'KILL', $pid;
    }
    else {
        carp q{No subprocess running};
        return;
    }
}

sub status {
    my $self = shift;
    my $pid  = $self->pid;

    return $pid, kill(0, $pid) ? 1 : 0, $self->detached;
}

# private methods
sub _log {
    my $self = shift;

    $self->log_callback->($self, @ARG);

    return $self;
}

1;

