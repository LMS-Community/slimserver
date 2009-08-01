package Log::Dispatch::Syslog;

use strict;
use warnings;

use Log::Dispatch::Output;

use base qw( Log::Dispatch::Output );

use Sys::Syslog 0.16 ();

our $VERSION = '1.18';

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    my %p = @_;

    my $self = bless {}, $class;

    $self->_basic_init(%p);
    $self->_init(%p);

    return $self;
}

sub _init
{
    my $self = shift;

    my %p = @_;

    $self->{ident}    = $p{ident};
    $self->{logopt}   = $p{logopt};
    $self->{facility} = $p{facility};
    $self->{socket}   = $p{socket};

    $self->{priorities} = [ 'DEBUG',
                            'INFO',
                            'NOTICE',
                            'WARNING',
                            'ERR',
                            'CRIT',
                            'ALERT',
                            'EMERG' ];

    Sys::Syslog::setlogsock( $self->{socket} )
        if defined $self->{socket};
}

sub log_message
{
    my $self = shift;
    my %p = @_;

    my $pri = $self->_level_as_number($p{level});

    eval
    {
        Sys::Syslog::openlog($self->{ident}, $self->{logopt}, $self->{facility});
        Sys::Syslog::syslog($self->{priorities}[$pri], $p{message});
        Sys::Syslog::closelog;
    };

    warn $@ if $@ and $^W;
}


1;

__END__

=head1 NAME

Log::Dispatch::Syslog - Object for logging to system log.

=head1 SYNOPSIS

  use Log::Dispatch::Syslog;

  my $file = Log::Dispatch::Syslog->new( name      => 'file1',
                                         min_level => 'info',
                                         ident     => 'Yadda yadda' );

  $file->log( level => 'emerg', message => "Time to die." );

=head1 DESCRIPTION

This module provides a simple object for sending messages to the
system log (via UNIX syslog calls).

Note that logging may fail if you try to pass UTF-8 characters in the
log message. If logging fails and warnings are enabled, the error
message will be output using Perl's C<warn>.

=head1 METHODS

=over 4

=item * new(%p)

This method takes a hash of parameters.  The following options are
valid:

=over 8

=item * name ($)

The name of the object.  Required.

=item * min_level ($)

The minimum logging level this object will accept.  See the
Log::Dispatch documentation on L<Log Levels|Log::Dispatch/"Log Levels"> for more information.  Required.

=item * max_level ($)

The maximum logging level this obejct will accept.  See the
Log::Dispatch documentation on L<Log Levels|Log::Dispatch/"Log Levels"> for more information.  This is not
required.  By default the maximum is the highest possible level (which
means functionally that the object has no maximum).

=item * ident ($)

This string will be prepended to all messages in the system log.
Defaults to $0.

=item * logopt ($)

A string containing the log options (separated by any separator you
like).  See the openlog(3) and Sys::Syslog docs for more details.
Defaults to ''.

=item * facility ($)

Specifies what type of program is doing the logging to the system log.
Valid options are 'auth', 'authpriv', 'cron', 'daemon', 'kern',
'local0' through 'local7', 'mail, 'news', 'syslog', 'user',
'uucp'.  Defaults to 'user'

=item * socket ($)

Tells what type of socket to use for sending syslog messages.  Valid
options are listed in C<Sys::Syslog>.

If you don't provide this, then we let C<Sys::Syslog> simply pick one
that works, which is the preferred option, as it makes your code more
portable.

=item * callbacks( \& or [ \&, \&, ... ] )

This parameter may be a single subroutine reference or an array
reference of subroutine references.  These callbacks will be called in
the order they are given and passed a hash containing the following keys:

 ( message => $log_message, level => $log_level )

The callbacks are expected to modify the message and then return a
single scalar containing that modified message.  These callbacks will
be called when either the C<log> or C<log_to> methods are called and
will only be applied to a given message once.

=back

=item * log_message( message => $ )

Sends a message to the appropriate output.  Generally this shouldn't
be called directly but should be called through the C<log()> method
(in Log::Dispatch::Output).

=back

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
