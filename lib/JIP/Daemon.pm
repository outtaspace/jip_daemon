package JIP::Daemon;

use 5.006;
use strict;
use warnings;
use POSIX ();
use Carp qw(carp croak);
use English qw(-no_match_vars);

our $VERSION = '0.01';

sub new {
    my ($class, %param) = @ARG;

    # Perform a trial run with no changes made (foreground if dry_run)
    my $dry_run = (exists $param{'dry_run'} and $param{'dry_run'}) ? 1 : 0;

    my $uid;
    if (exists $param{'uid'}) {
        $uid = $param{'uid'};

        croak qq{Bad argument "uid"\n}
            unless defined $uid and $uid =~ m{^\d+$}x;
    }

    my $gid;
    if (exists $param{'gid'}) {
        $gid = $param{'gid'};

        croak qq{Bad argument "gid"\n}
            unless defined $gid and $gid =~ m{^\d+$}x;
    }

    my $cwd;
    if (exists $param{'cwd'}) {
        $cwd = $param{'cwd'};

        croak qq{Bad argument "cwd"\n}
            unless defined $cwd and length $cwd;
    }

    my $umask;
    if (exists $param{'umask'}) {
        $umask = $param{'umask'};

        croak qq{Bad argument "umask"\n}
            unless defined $umask and length $umask;
    }

    return bless({}, $class)
        ->_set_dry_run($dry_run)
        ->_set_uid($uid)
        ->_set_gid($gid)
        ->_set_cwd($cwd)
        ->_set_umask($umask)
        ->_set_pid($PROCESS_ID)
        ->_set_detached(0);
}

sub daemonize {
    my $self = shift;

    return $self if $self->detached;

    # Fork and kill parent
    if (not $self->dry_run) {
        my $pid = fork; # returns child pid to the parent and 0 to the child

        if (defined $pid) {
            # fork returned 0, so this branch is the child
            if ($pid == 0) {
                POSIX::setsid()
                    or croak(sprintf qq{Can't start a new session: %s\n}, $OS_ERROR);

                $self->reopen_std;
            }

            # this branch is the parent
            else {
                exit; # parent exiting
            }
        }
        else {
            croak qq{Can't fork\n};
        }
    }

    $self->drop_privileges;

    return $self->_set_pid($PROCESS_ID)->_set_detached(1);
}

sub reopen_std {
    my $self = shift;

    open(STDIN,  '</dev/null')
        or croak(sprintf qq{Can't reopen STDIN: %s\n},   $OS_ERROR);
    open(STDOUT, '>/dev/null')
        or croak(sprintf qq{Can't reopen STDOUT: %s\n},  $OS_ERROR);
    open(STDERR, '>/dev/null')
        or croak(sprintf qq{Can't reopen STDERR: %s\n},  $OS_ERROR);

    return $self;
}

sub drop_privileges {
    my $self = shift;

    if (defined $self->uid) {
        POSIX::setuid($self->uid)
            or croak(sprintf qq{Can't set uid %s\n}, $self->uid);
    }

    if (defined $self->gid) {
        POSIX::setgid($self->gid)
            or croak(sprintf qq{Can't set gid %s\n}, $self->gid);
    }

    if (defined $self->umask) {
        umask $self->umask
            or croak(sprintf qq{Can't set umask %s: %s\n}, $self->umask, $OS_ERROR);
    }

    if (defined $self->cwd) {
        chdir $self->cwd
            or croak(sprintf qq{Can't chdir to %s: %s\n}, $self->cwd, $OS_ERROR);
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
        carp qq{No subprocess running\n};
        return;
    }
}

sub status {
    my $self = shift;
    my $pid  = $self->pid;

    return $pid, kill(0, $pid) ? 1 : 0, $self->detached;
}

# Accessors
sub pid {
    my $self = shift;
    return $self->{'pid'};
}

sub uid {
    my $self = shift;
    return $self->{'uid'};
}

sub gid {
    my $self = shift;
    return $self->{'gid'};
}

sub detached {
    my $self = shift;
    return $self->{'detached'};
}

sub dry_run {
    my $self = shift;
    return $self->{'dry_run'};
}

sub cwd {
    my $self = shift;
    return $self->{'cwd'};
}

sub umask {
    my $self = shift;
    return $self->{'umask'};
}

# private methods
sub _set_pid {
    my ($self, $pid) = @ARG;
    $self->{'pid'} = $pid;
    return $self;
}

sub _set_uid {
    my ($self, $uid) = @ARG;
    $self->{'uid'} = $uid;
    return $self;
}

sub _set_gid {
    my ($self, $gid) = @ARG;
    $self->{'gid'} = $gid;
    return $self;
}

sub _set_detached {
    my ($self, $detached) = @ARG;
    $self->{'detached'} = $detached;
    return $self;
}

sub _set_dry_run {
    my ($self, $dry_run) = @ARG;
    $self->{'dry_run'} = $dry_run;
    return $self;
}

sub _set_cwd {
    my ($self, $cwd) = @ARG;
    $self->{'cwd'} = $cwd;
    return $self;
}

sub _set_umask {
    my ($self, $umask) = @ARG;
    $self->{'umask'} = $umask;
    return $self;
}

1;

