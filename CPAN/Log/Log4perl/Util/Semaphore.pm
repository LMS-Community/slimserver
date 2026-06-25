#//////////////////////////////////////////
package Log::Log4perl::Util::Semaphore;
#//////////////////////////////////////////
use IPC::SysV qw(IPC_RMID IPC_CREAT IPC_EXCL SEM_UNDO IPC_NOWAIT 
                 IPC_SET IPC_STAT SETVAL);
use IPC::Semaphore;
use POSIX qw(EEXIST);
use strict;
use warnings;
use constant INTERNAL_DEBUG => 0;

###########################################
sub new {
###########################################
    my($class, %options) = @_;

    my $self = {
        key           => undef,
        mode          => undef,
        uid           => undef,
        gid           => undef,
        destroy       => undef,
        semop_wait    => .1,
        semop_retries => 1,
	creator       => $$,
        %options,
    };

    $self->{ikey} = unpack("i", pack("A4", $self->{key}));

      # Accept usernames in the uid field as well
    if(defined $self->{uid} and 
       $self->{uid} =~ /\D/) {
        $self->{uid} = (getpwnam $self->{uid})[2];
    }

    bless $self, $class;
    $self->init();

    my @values = ();
    for my $param (qw(mode uid gid)) {
        push @values, $param, $self->{$param} if defined $self->{$param};
    }
    $self->semset(@values) if @values;

    return $self;
}

###########################################
sub init {
###########################################
    my($self) = @_;

    print "Semaphore init '$self->{key}'/'$self->{ikey}'\n" if INTERNAL_DEBUG;

    $self->{id} = semget( $self->{ikey}, 
                          1, 
                          &IPC_EXCL|&IPC_CREAT|($self->{mode}||0777),
                  );

   if(! defined $self->{id} and
      $! == EEXIST) {
       print "Semaphore '$self->{key}' already exists\n" if INTERNAL_DEBUG;
       defined( $self->{id} = semget( $self->{ikey}, 1, 0 ) )
           or die "semget($self->{ikey}) failed: $!";
   } elsif($!) {
       die "Cannot create semaphore $self->{key}/$self->{ikey} ($!)";
   }

   print "Semaphore has id $self->{id}\n" if INTERNAL_DEBUG;
}

###########################################
sub status_as_string {
###########################################
    my($self, @values) = @_;

    my $sem = IPC::Semaphore->new($self->{ikey}, 1, 0);

    my $values  = join('/', $sem->getall());
    my $ncnt    = $sem->getncnt(0);
    my $pidlast = $sem->getpid(0);
    my $zcnt    = $sem->getzcnt(0);
    my $id      = $sem->id();

    return <<EOT;
Semaphore Status
Key ...................................... $self->{key}
iKey ..................................... $self->{ikey}
Id ....................................... $id
Values ................................... $values
Processes waiting for counter increase ... $ncnt
Processes waiting for counter to hit 0 ... $zcnt
Last process to perform an operation ..... $pidlast
EOT
}

###########################################
sub semsetval {
###########################################
    my($self, %keyvalues) = @_;

    my $sem = IPC::Semaphore->new($self->{ikey}, 1, 0);
    $sem->setval(%keyvalues);
}

###########################################
sub semset {
###########################################
    my($self, @values) = @_;

    print "Setting values for semaphore $self->{key}/$self->{ikey}\n" if
        INTERNAL_DEBUG;

    my $sem = IPC::Semaphore->new($self->{ikey}, 1, 0);
    $sem->set(@values);
}

###########################################
sub semlock {
###########################################
    my($self) = @_;

    my $operation = pack("s!*", 
                          # wait until it's 0
                         0, 0, 0,
                          # increment by 1
                         0, 1, SEM_UNDO
                        );

    print "Locking semaphore '$self->{key}'\n" if INTERNAL_DEBUG;
    $self->semop($self->{id}, $operation);
}

###########################################
sub semunlock {
###########################################
    my($self) = @_;

#    my $operation = pack("s!*", 
#                          # decrement by 1
#                         0, -1, SEM_UNDO
#                        );
#
    print "Unlocking semaphore '$self->{key}'\n" if INTERNAL_DEBUG;

#      # ignore errors, as they might result from trying to unlock an
#      # already unlocked semaphore.
#    semop($self->{id}, $operation);

    semctl $self->{id}, 0, SETVAL, 0;
}

###########################################
sub remove {
###########################################
    my($self) = @_;

    print "Removing semaphore '$self->{key}/$self->{id}'\n" if INTERNAL_DEBUG;

    semctl ($self->{id}, 0, &IPC_RMID, 0) or 
        die "Removing semaphore $self->{key} failed: $!";
}

###########################################
sub DESTROY {
###########################################
    my($self) = @_;

    if($self->{destroy} && $$==$self->{creator}) {
        $self->remove();
    }
}

###########################################
sub semop {
###########################################
    my($self, @args) = @_;

    my $retries     = $self->{semop_retries};

    my $rc;

    {
        $rc = semop($args[0], $args[1]);

        if(!$rc and 
           $! =~ /temporarily unavailable/ and
           $retries-- > 0) {
            $rc = 'undef' unless defined $rc;
            print "semop failed (rc=$rc), retrying\n", 
                  $self->status_as_string if INTERNAL_DEBUG;
            select undef, undef, undef, $self->{semop_wait};
            redo;
        }
    }

    $rc or die "semop(@args) failed: $! ";
    $rc;
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Util::Semaphore - Easy to use semaphores

=head1 SYNOPSIS

    use Log::Log4perl::Util::Semaphore;
    my $sem = Log::Log4perl::Util::Semaphore->new( key => "abc" );

    $sem->semlock();
      # ... critical section 
    $sem->semunlock();

    $sem->semset( uid  => (getpwnam("hugo"))[2], 
                  gid  => 102,
                  mode => 0644
                );

=head1 DESCRIPTION

Log::Log4perl::Util::Semaphore provides the synchronisation mechanism
for the Synchronized.pm appender in Log4perl, but can be used independently
of Log4perl.

As a convenience, the C<uid> field accepts user names as well, which it 
translates into the corresponding uid by running C<getpwnam>.

=head1 LICENSE

Copyright 2002-2013 by Mike Schilli E<lt>m@perlmeister.comE<gt> 
and Kevin Goess E<lt>cpan@goess.orgE<gt>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=head1 AUTHOR

Please contribute patches to the project on Github:

    http://github.com/mschilli/log4perl

Send bug reports or requests for enhancements to the authors via our

MAILING LIST (questions, bug reports, suggestions/patches): 
log4perl-devel@lists.sourceforge.net

Authors (please contact them via the list above, not directly):
Mike Schilli <m@perlmeister.com>,
Kevin Goess <cpan@goess.org>

Contributors (in alphabetical order):
Ateeq Altaf, Cory Bennett, Jens Berthold, Jeremy Bopp, Hutton
Davidson, Chris R. Donnelly, Matisse Enzer, Hugh Esco, Anthony
Foiani, James FitzGibbon, Carl Franks, Dennis Gregorovic, Andy
Grundman, Paul Harrington, Alexander Hartmaier  David Hull, 
Robert Jacobson, Jason Kohles, Jeff Macdonald, Markus Peter, 
Brett Rann, Peter Rabbitson, Erik Selberg, Aaron Straup Cope, 
Lars Thegler, David Viner, Mac Yang.

