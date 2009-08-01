package Log::Dispatch::Output;

use strict;
use warnings;

use Log::Dispatch;

use base qw( Log::Dispatch::Base );

use Carp ();

our $VERSION = '1.26';

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    die "The new method must be overridden in the $class subclass";
}

sub log
{
    my $self = shift;

    my %p = @_;

    return unless $self->_should_log($p{level});

    $p{message} = $self->_apply_callbacks(%p)
        if $self->{callbacks};

    $self->log_message(%p);
}

sub _basic_init
{
    my $self = shift;

    my %p = @_;

    # Map the names to numbers so they can be compared.
    $self->{level_names} = [ qw( debug info notice warning error critical alert emergency ) ];

    my $x = 0;
    $self->{level_numbers} = { ( map { $_ => $x++ } @{ $self->{level_names} } ),
                               err   => 4,
                               crit  => 5,
                               emerg => 7 };

    $self->{name} = $p{name};

    $self->{min_level} = $self->_level_as_number($p{min_level});
    die "Invalid level specified for min_level" unless defined $self->{min_level};

    # Either use the parameter supplies or just the highest possible
    # level.
    $self->{max_level} =
        ( exists $p{max_level} ?
          $self->_level_as_number($p{max_level}) :
          $#{ $self->{level_names} }
        );

    die "Invalid level specified for max_level" unless defined $self->{max_level};

    my @cb = $self->_get_callbacks(%p);
    $self->{callbacks} = \@cb if @cb;
}

sub name
{
    my $self = shift;

    return $self->{name};
}

sub min_level
{
    my $self = shift;

    return $self->{level_names}[ $self->{min_level} ];
}

sub max_level
{
    my $self = shift;

    return $self->{level_names}[ $self->{max_level} ];
}

sub accepted_levels
{
    my $self = shift;

    return @{ $self->{level_names} }[ $self->{min_level} .. $self->{max_level} ] ;
}

sub _should_log
{
    my $self = shift;

    my $msg_level = $self->_level_as_number(shift);
    return ( ( $msg_level >= $self->{min_level} ) &&
             ( $msg_level <= $self->{max_level} ) );
}

sub _level_as_number
{
    my $self = shift;
    my $level = shift;

    unless ( defined $level )
    {
        Carp::croak "undefined value provided for log level";
    }

    return $level if $level =~ /^\d$/;

    unless ( Log::Dispatch->level_is_valid($level) )
    {
        Carp::croak "$level is not a valid Log::Dispatch log level";
    }

    return $self->{level_numbers}{$level};
}

sub _level_as_name
{
    my $self = shift;
    my $level = shift;

    unless ( defined $level )
    {
        Carp::croak "undefined value provided for log level";
    }

    return $level unless $level =~ /^\d$/;

    return $self->{level_names}[$level];
}


1;

__END__

=head1 NAME

Log::Dispatch::Output - Base class for all Log::Dispatch::* object

=head1 SYNOPSIS

  package Log::Dispatch::MySubclass;

  use Log::Dispatch::Output;
  use base qw( Log::Dispatch::Output );

  sub new
  {
      my $proto = shift;
      my $class = ref $proto || $proto;

      my %p = @_;

      my $self = bless {}, $class

      $self->_basic_init(%p);

      # Do more if you like
  }

  sub log_message
  {
      my $self = shift;
      my %p = @_;

      # Do something with message in $p{message}
  }

=head1 DESCRIPTION

This module is the base class from which all Log::Dispatch::* objects
should be derived.

=head1 METHODS

=over 4

=item * new(%p)

This must be overridden in a subclass.  Takes the following
parameters:

=over 4

=item * name ($)

The name of the object (not the filename!).  Required.

=item * min_level ($)

The minimum logging level this object will accept.  See the
Log::Dispatch documentation on L<Log Levels|Log::Dispatch/"Log Levels"> for more information.  Required.

=item * max_level ($)

The maximum logging level this obejct will accept.  See the
Log::Dispatch documentation on L<Log Levels|Log::Dispatch/"Log Levels"> for more information.  This is not
required.  By default the maximum is the highest possible level (which
means functionally that the object has no maximum).

=item * callbacks( \& or [ \&, \&, ... ] )

This parameter may be a single subroutine reference or an array
reference of subroutine references.  These callbacks will be called in
the order they are given and passed a hash containing the following keys:

 ( message => $log_message, level => $log_level )

The callbacks are expected to modify the message and then return a
single scalar containing that modified message.  These callbacks will
be called when either the C<log> or C<log_to> methods are called and
will only be applied to a given message once.  If they do not return
the message then you will get no output.  Make sure to return the
message!

=back

=item * _basic_init(%p)

This should be called from a subclass's constructor.  Make sure to
pass the arguments in @_ to it.  It sets the object's name and minimum
level.  It also sets up two other attributes which are used by other
Log::Dispatch::Output methods, level_names and level_numbers.

=item * name

Returns the object's name.

=item * min_level

Returns the object's minimum log level.

=item * max_level

Returns the object's maximum log level.

=item * accepted_levels

Returns a list of the object's accepted levels (by name) from minimum
to maximum.

=item * log( level => $, message => $ )

Sends a message if the level is greater than or equal to the object's
minimum level.  This method applies any message formatting callbacks
that the object may have.

=item * _should_log ($)

This method is called from the C<log()> method with the log level of
the message to be logged as an argument.  It returns a boolean value
indicating whether or not the message should be logged by this
particular object.  The C<log()> method will not process the message
if the return value is false.

=item * _level_as_number ($)

This method will take a log level as a string (or a number) and return
the number of that log level.  If not given an argument, it returns
the calling object's log level instead.  If it cannot determine the
level then it will issue a warning and return undef.

=back

=head2 Subclassing

This class should be used as the base class for all logging objects
you create that you would like to work under the Log::Dispatch
architecture.  Subclassing is fairly trivial.  For most subclasses, if
you simply copy the code in the SYNOPSIS and then put some
functionality into the C<log_message> method then you should be all
set.  Please make sure to use the C<_basic_init> method as directed.

The actual logging implementation should be done in a C<log_message>
method that you write. B<Do not override C<log>!>.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
