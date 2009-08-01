package Log::Dispatch;

use 5.006;

use strict;
use warnings;

use base qw( Log::Dispatch::Base );

use Carp ();

our $VERSION = '2.22';
our %LEVELS;


BEGIN
{
    foreach my $l ( qw( debug info notice warning err error crit critical alert emerg emergency ) )
    {
        my $sub = sub { my $self = shift;
                        $self->log( level => $l, message => "@_" ); };

        $LEVELS{$l} = 1;

        no strict 'refs';
        *{$l} = $sub
    }
}

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;
    my %p = @_;

    my $self = bless {}, $class;

    my @cb = $self->_get_callbacks(%p);
    $self->{callbacks} = \@cb if @cb;

    return $self;
}

sub add
{
    my $self = shift;
    my $object = shift;

    # Once 5.6 is more established start using the warnings module.
    if (exists $self->{outputs}{$object->name} && $^W)
    {
        Carp::carp("Log::Dispatch::* object ", $object->name, " already exists.");
    }

    $self->{outputs}{$object->name} = $object;
}

sub remove
{
    my $self = shift;
    my $name = shift;

    return delete $self->{outputs}{$name};
}

sub log
{
    my $self = shift;
    my %p = @_;

    return unless $self->would_log( $p{level} );

    $self->_log_to_outputs( $self->_prepare_message(%p) );
}

sub _prepare_message
{
    my $self = shift;
    my %p = @_;

    $p{message} = $p{message}->()
        if ref $p{message} eq 'CODE';

    $p{message} = $self->_apply_callbacks(%p)
        if $self->{callbacks};

    return %p;
}

sub _log_to_outputs
{
    my $self = shift;
    my %p = @_;

    foreach (keys %{ $self->{outputs} })
    {
        $p{name} = $_;
        $self->_log_to(%p);
    }
}

sub log_and_die
{
    my $self = shift;

    my %p = $self->_prepare_message(@_);

    $self->_log_to_outputs(%p) if $self->would_log($p{level});

    $self->_die_with_message(%p);
}

sub log_and_croak
{
    my $self = shift;

    $self->log_and_die( @_, carp_level => 3 );
}

sub _die_with_message
{
    my $self = shift;
    my %p = @_;

    my $msg = $p{message};

    local $Carp::CarpLevel = ($Carp::CarpLevel || 0) + $p{carp_level}
	if exists $p{carp_level};

    Carp::croak($msg);
}

sub log_to
{
    my $self = shift;
    my %p = @_;

    $p{message} = $self->_apply_callbacks(%p)
        if $self->{callbacks};

    $self->_log_to(%p);
}

sub _log_to
{
    my $self = shift;
    my %p = @_;
    my $name = $p{name};

    if (exists $self->{outputs}{$name})
    {
        $self->{outputs}{$name}->log(@_);
    }
    elsif ($^W)
    {
        Carp::carp("Log::Dispatch::* object named '$name' not in dispatcher\n");
    }
}

sub output
{
    my $self = shift;
    my $name = shift;

    return unless exists $self->{outputs}{$name};

    return $self->{outputs}{$name};
}

sub level_is_valid
{
    shift;
    return $LEVELS{ shift() };
}

sub would_log
{
    my $self = shift;
    my $level = shift;

    return 0 unless $self->level_is_valid($level);

    foreach ( values %{ $self->{outputs} } )
    {
        return 1 if $_->_should_log($level);
    }

    return 0;
}


1;

__END__

=head1 NAME

Log::Dispatch - Dispatches messages to one or more outputs

=head1 SYNOPSIS

  use Log::Dispatch;

  my $dispatcher = Log::Dispatch->new;

  $dispatcher->add( Log::Dispatch::File->new( name => 'file1',
                                              min_level => 'debug',
                                              filename => 'logfile' ) );

  $dispatcher->log( level => 'info',
                    message => 'Blah, blah' );

  my $sub = sub { my %p = @_;  return reverse $p{message}; };
  my $reversing_dispatcher = Log::Dispatch->new( callbacks => $sub );

=head1 DESCRIPTION

This module manages a set of Log::Dispatch::* objects, allowing you to
add and remove output objects as desired.

=head1 METHODS

=over 4

=item * new

Returns a new Log::Dispatch object.  This method takes one optional
parameter:

=over 8

=item * callbacks( \& or [ \&, \&, ... ] )

This parameter may be a single subroutine reference or an array
reference of subroutine references.  These callbacks will be called in
the order they are given and passed a hash containing the following keys:

 ( message => $log_message, level => $log_level )

In addition, any key/value pairs passed to a logging method will be
passed onto your callback.

The callbacks are expected to modify the message and then return a
single scalar containing that modified message.  These callbacks will
be called when either the C<log> or C<log_to> methods are called and
will only be applied to a given message once.  If they do not return
the message then you will get no output.  Make sure to return the
message!

=back

=item * add( Log::Dispatch::* OBJECT )

Adds a new a Log::Dispatch::* object to the dispatcher.  If an object
of the same name already exists, then that object is replaced.  A
warning will be issued if the C<$^W> is true.

NOTE: This method can really take any object that has methods called
'name' and 'log'.

=item * remove($)

Removes the object that matches the name given to the remove method.
The return value is the object being removed or undef if no object
matched this.

=item * log( level => $, message => $ or \& )

Sends the message (at the appropriate level) to all the
Log::Dispatch::* objects that the dispatcher contains (by calling the
C<log_to> method repeatedly).

This method also accepts a subroutine reference as the message
argument. This reference will be called only if there is an output
that will accept a message of the specified level.

B<WARNING>: This logging method does something intelligent with a
subroutine reference as the message but other methods, like
C<log_to()> or the C<log()> method of an output object, will just
stringify the reference.

=item * log_and_die( level => $, message => $ or \& )

Has the same behavior as calling C<log()> but calls
C<_die_with_message()> at the end.

=item * log_and_croak( level => $, message => $ or \& )

This method adjusts the C<$Carp::CarpLevel> scalar so that the croak
comes from the context in which it is called.

=item * _die_with_message( message => $, carp_level => $ )

This method is used by C<log_and_die> and will either die() or croak()
depending on the value of C<message>: if it's a reference or it ends
with a new line then a plain die will be used, otherwise it will
croak.

You can throw exception objects by subclassing this method.

If the C<carp_level> parameter is present its value will be added to
the current value of C<$Carp::CarpLevel>.

=item * log_to( name => $, level => $, message => $ )

Sends the message only to the named object.

=item * level_is_valid( $string )

Returns true or false to indicate whether or not the given string is a
valid log level.  Can be called as either a class or object method.

=item * would_log( $string )

Given a log level, returns true or false to indicate whether or not
anything would be logged for that log level.

=item * output( $name )

Returns an output of the given name.  Returns undef or an empty list,
depending on context, if the given output does not exist.

=back

=head1 CONVENIENCE METHODS

Version 1.6 of Log::Dispatch adds a number of convenience methods for
logging.  You may now call any valid log level (including valid
abbreviations) as a method on the Log::Dispatch object with a single
argument that is the message to be logged.  This is converted into a
call to the C<log> method with the appropriate level.

For example:

 $dispatcher->alert('Strange data in incoming request');

translates to:

 $dispatcher->log( level => 'alert', message => 'Strange data in incoming request' );

These methods act like Perl's C<print> built-in when given a list of
arguments.  Thus, the following calls are equivalent:

 my @array = ('Something', 'bad', 'is', here');
 $dispatcher->alert(@array);

 my $scalar = "@array";
 $dispatcher->alert($scalar);

One important caveat about these methods is that its not that forwards
compatible.  If I were to add more parameters to the C<log> call, it
is unlikely that these could be integrated into these methods without
breaking existing uses.  This probably means that any future
parameters to the C<log> method will never be integrated into these
convenience methods.  OTOH, I don't see any immediate need to expand
the parameters given to the C<log> method.

=head2 Log Levels

The log levels that Log::Dispatch uses are taken directly from the
syslog man pages (except that I expanded them to full words).  Valid
levels are:

=over 4

=item debug

=item info

=item notice

=item warning

=item error

=item critical

=item alert

=item emergency

=back

Alternately, the numbers 0 through 7 may be used (debug is 0 and
emergency is 7).  The syslog standard of 'err', 'crit', and 'emerg'
is also acceptable.

=head1 USAGE

This module is designed to be used as a one-stop logging system.  In
particular, it was designed to be easy to subclass so that if you want
to handle messaging in a way not implemented in this package, you
should be able to add this with minimal effort.

The basic idea behind Log::Dispatch is that you create a Log::Dispatch
object and then add various logging objects to it (such as a file
logger or screen logger).  Then you call the C<log> method of the
dispatch object, which passes the message to each of the objects,
which in turn decide whether or not to accept the message and what to
do with it.

This makes it possible to call single method and send a message to a
log file, via email, to the screen, and anywhere else, all with very
little code needed on your part, once the dispatching object has been
created.

The logging levels that Log::Dispatch uses are borrowed from the
standard UNIX syslog levels, except that where syslog uses partial
words ("err") Log::Dispatch also allows the use of the full word as
well ("error").

=head2 Making your own logging objects

Making your own logging object is generally as simple as subclassing
Log::Dispatch::Output and overriding the C<new> and C<log> methods.
See the L<Log::Dispatch::Output> docs for more details.

If you would like to create your own subclass for sending email then
it is even simpler.  Simply subclass L<Log::Dispatch::Email> and
override the C<send_email> method.  See the L<Log::Dispatch::Email>
docs for more details.

=head2 Why doesn't Log::Dispatch add a newline to the message?

A few people have written email to me asking me to add something that
would tack a newline onto the end of all messages that don't have one.
This will never happen.  There are several reasons for this.  First of
all, Log::Dispatch was designed as a simple system to broadcast a
message to multiple outputs.  It does not attempt to understand the
message in any way at all.  Adding a newline implies an attempt to
understand something about the message and I don't want to go there.
Secondly, this is not very cross-platform and I don't want to go down
the road of testing Config values to figure out what to tack onto
messages based on OS.

I think people's desire to do this is because they are too focused on
just the logging to files aspect of this module.  In this case
newlines make sense.  However, imagine someone is using this module to
log to a remote server and the interactions between the client and
server use newlines as part of the control flow.  Casually adding a
newline could cause serious problems.

However, the 1.2 release adds the callbacks parameter for the
Log::Dispatch object which you can easily use to add newlines to
messages if you so desire.

=head1 RELATED MODULES

=head2 Log::Dispatch::DBI

Written by Tatsuhiko Miyagawa.  Log output to a database table.

=head2 Log::Dispatch::FileRotate

Written by Mark Pfeiffer.  Rotates log files periodically as part of
its usage.

=head2 Log::Dispatch::File::Stamped

Written by Eric Cholet.  Stamps log files with date and time
information.

=head2 Log::Dispatch::Jabber

Written by Aaron Straup Cope.  Logs messages via Jabber.

=head2 Log::Dispatch::Tk

Written by Dominique Dumont.  Logs messages to a Tk window.

=head2 Log::Dispatch::Win32EventLog

Written by Arthur Bergman.  Logs messages to the Windows event log.

=head2 Log::Log4perl

An implementation of Java's log4j API in Perl, using Log::Dispatch to
do the actual logging.  Created by Mike Schilli and Kevin Goess.

=head2 Log::Dispatch::Config

Written by Tatsuhiko Miyagawa.  Allows configuration of logging via a
text file similar (or so I'm told) to how it is done with log4j.
Simpler than Log::Log4perl.

=head2 Log::Agent

A very different API for doing many of the same things that
Log::Dispatch does.  Originally written by Raphael Manfredi.

=head1 SUPPORT

Please submit bugs and patches to the CPAN RT system at
http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Log%3A%3ADispatch
or via email at bug-log-dispatch@rt.cpan.org.

Support questions can be sent to me at my email address, shown below.

The code repository is at https://svn.urth.org/svn/Log-Dispatch/

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=head1 COPYRIGHT

Copyright (c) 1999-2006 David Rolsky.  All rights reserved.  This
program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included
with this module.

=head1 SEE ALSO

Log::Dispatch::ApacheLog, Log::Dispatch::Email,
Log::Dispatch::Email::MailSend, Log::Dispatch::Email::MailSender,
Log::Dispatch::Email::MailSendmail, Log::Dispatch::Email::MIMELite,
Log::Dispatch::File, Log::Dispatch::File::Locked,
Log::Dispatch::Handle, Log::Dispatch::Output, Log::Dispatch::Screen,
Log::Dispatch::Syslog

=cut
