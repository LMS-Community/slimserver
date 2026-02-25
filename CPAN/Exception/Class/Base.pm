package Exception::Class::Base;

use strict;
use warnings;

our $VERSION = '1.45';

use Class::Data::Inheritable 0.02;
use Devel::StackTrace 2.00;
use Scalar::Util qw( blessed );

use base qw(Class::Data::Inheritable);

BEGIN {
    __PACKAGE__->mk_classdata('Trace');
    __PACKAGE__->mk_classdata('UnsafeRefCapture');

    __PACKAGE__->mk_classdata('NoContextInfo');
    __PACKAGE__->NoContextInfo(0);

    __PACKAGE__->mk_classdata('RespectOverload');
    __PACKAGE__->RespectOverload(0);

    __PACKAGE__->mk_classdata('MaxArgLength');
    __PACKAGE__->MaxArgLength(0);

    sub NoRefs {
        my $self = shift;
        if (@_) {
            my $val = shift;
            return $self->UnsafeRefCapture( !$val );
        }
        else {
            return $self->UnsafeRefCapture;
        }
    }

    sub Fields { () }
}

use overload

    # an exception is always true
    bool => sub {1}, '""' => 'as_string', fallback => 1;

# Create accessor routines
BEGIN {
    my @fields = qw( message pid uid euid gid egid time trace );

    foreach my $f (@fields) {
        my $sub = sub { my $s = shift; return $s->{$f}; };

        ## no critic (TestingAndDebugging::ProhibitNoStrict)
        no strict 'refs';
        *{$f} = $sub;
    }
    *error = \&message;

    my %trace_fields = (
        package => 'package',
        file    => 'filename',
        line    => 'line',
    );

    while ( my ( $f, $m ) = each %trace_fields ) {
        my $sub = sub {
            my $s = shift;
            return $s->{$f} if exists $s->{$f};

            my $frame = $s->trace->frame(0);

            return $s->{$f} = $frame ? $frame->$m : undef;
        };

        ## no critic (TestingAndDebugging::ProhibitNoStrict)
        no strict 'refs';
        *{$f} = $sub;
    }
}

sub Classes { Exception::Class::Classes() }

sub throw {
    my $proto = shift;

    $proto->rethrow if ref $proto;

    die $proto->new(@_);
}

sub rethrow {
    my $self = shift;

    die $self;
}

sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;

    my $self = bless {}, $class;

    $self->_initialize(@_);

    return $self;
}

sub _initialize {
    my $self = shift;
    my %p    = @_ == 1 ? ( error => $_[0] ) : @_;

    $self->{message} = $p{message} || $p{error} || q{};

    $self->{show_trace} = $p{show_trace} if exists $p{show_trace};

    if ( $self->NoContextInfo ) {
        $self->{show_trace} = 0;
        $self->{package}    = $self->{file} = $self->{line} = undef;
    }
    else {
        # CORE::time is important to fix an error with some versions of
        # Perl
        $self->{time} = CORE::time();
        $self->{pid}  = $$;
        $self->{uid}  = $<;
        $self->{euid} = $>;
        $self->{gid}  = $(;
        $self->{egid} = $);

        my @ignore_class   = (__PACKAGE__);
        my @ignore_package = 'Exception::Class';

        if ( my $i = delete $p{ignore_class} ) {
            push @ignore_class, ( ref($i) eq 'ARRAY' ? @$i : $i );
        }

        if ( my $i = delete $p{ignore_package} ) {
            push @ignore_package, ( ref($i) eq 'ARRAY' ? @$i : $i );
        }

        $self->{trace} = Devel::StackTrace->new(
            ignore_class       => \@ignore_class,
            ignore_package     => \@ignore_package,
            unsafe_ref_capture => $self->UnsafeRefCapture,
            respect_overload   => $self->RespectOverload,
            max_arg_length     => $self->MaxArgLength,
            map { $p{$_} ? ( $_ => delete $p{$_} ) : () } qw(
                frame_filter
                filter_frames_early
                skip_frames
            ),
        );
    }

    my %fields = map { $_ => 1 } $self->Fields;
    while ( my ( $key, $value ) = each %p ) {
        next if $key =~ /^(?:error|message|show_trace)$/;

        if ( $fields{$key} ) {
            $self->{$key} = $value;
        }
        else {
            Exception::Class::Base->throw(
                error => "unknown field $key passed to constructor for class "
                    . ref $self );
        }
    }
}

sub context_hash {
    my $self = shift;

    return {
        time => $self->{time},
        pid  => $self->{pid},
        uid  => $self->{uid},
        euid => $self->{euid},
        gid  => $self->{gid},
        egid => $self->{egid},
    };
}

sub field_hash {
    my $self = shift;

    my $hash = {};

    for my $field ( $self->Fields ) {
        $hash->{$field} = $self->$field;
    }

    return $hash;
}

sub description {
    return 'Generic exception';
}

sub show_trace {
    my $self = shift;

    return 0 unless $self->{trace};

    if (@_) {
        $self->{show_trace} = shift;
    }

    return exists $self->{show_trace} ? $self->{show_trace} : $self->Trace;
}

sub as_string {
    my $self = shift;

    my $str = $self->full_message;
    unless ( defined $str && length $str ) {
        my $desc = $self->description;
        $str = defined $desc
            && length $desc ? "[$desc]" : '[Generic exception]';
    }

    $str .= "\n\n" . $self->trace->as_string
        if $self->show_trace;

    return $str;
}

sub full_message { $_[0]->message }

#
# The %seen bit protects against circular inheritance.
#
## no critic (BuiltinFunctions::ProhibitStringyEval, ErrorHandling::RequireCheckingReturnValueOfEval)
eval <<'EOF' if $] == 5.006;
sub isa {
    my ( $inheritor, $base ) = @_;
    $inheritor = ref($inheritor) if ref($inheritor);

    my %seen;

    no strict 'refs';
    my @parents = ( $inheritor, @{"$inheritor\::ISA"} );
    while ( my $class = shift @parents ) {
        return 1 if $class eq $base;

        push @parents, grep { !$seen{$_}++ } @{"$class\::ISA"};
    }
    return 0;
}
EOF

sub caught {
    my $class = shift;

    my $e = $@;

    return unless defined $e && blessed($e) && $e->isa($class);
    return $e;
}

1;

# ABSTRACT: A base class for exception objects

__END__

=pod

=encoding UTF-8

=head1 NAME

Exception::Class::Base - A base class for exception objects

=head1 VERSION

version 1.45

=head1 SYNOPSIS

  use Exception::Class 'MyException';

  eval { MyException->throw( error => 'I feel funny.' ) };

  print $@->error;

=head1 DESCRIPTION

This class is the base class for all exceptions created by L<Exception::Class>.
It provides a number of methods for getting information about the exception.

=for Pod::Coverage     Classes
    caught
    NoRefs

=head1 METHODS

=head2 MyException->Trace($boolean)

Each C<Exception::Class::Base> subclass can be set individually to include a
stacktrace when the C<as_string> method is called. The default is to not
include a stacktrace. Calling this method with a value changes this behavior.
It always returns the current value (after any change is applied).

This value is inherited by any subclasses. However, if this value is set for a
subclass, it will thereafter be independent of the value in
C<Exception::Class::Base>.

Do not call this on the C<Exception::Class::Base> class directly or you'll
change it for all exception classes that use L<Exception::Class>, including
ones created in modules you don't control.

This is a class method, not an object method.

=head2 MyException->UnsafeRefCapture($boolean)

When a C<Devel::StackTrace> object is created, it walks through the stack and
stores the arguments which were passed to each subroutine on the stack. If any
of these arguments are references, then that means that the
C<Devel::StackTrace> ends up increasing the ref count of these references,
delaying their destruction.

Since C<Exception::Class::Base> uses C<Devel::StackTrace> internally, this
method provides a way to tell C<Devel::StackTrace> not to store these
references. Instead, C<Devel::StackTrace> replaces references with their
stringified representation.

This method defaults to false. As with C<Trace>, it is inherited by subclasses
but setting it in a subclass makes it independent thereafter.

Do not call this on the C<Exception::Class::Base> class directly or you'll
change it for all exception classes that use L<Exception::Class>, including
ones created in modules you don't control.

=head2 MyException->RespectOverload($boolean)

When a C<Devel::StackTrace> object stringifies, by default it ignores
stringification overloading on any objects being dealt with.

Since C<Exception::Class::Base> uses C<Devel::StackTrace> internally, this
method provides a way to tell C<Devel::StackTrace> to respect overloading.

This method defaults to false. As with C<Trace>, it is inherited by subclasses
but setting it in a subclass makes it independent thereafter.

Do not call this on the C<Exception::Class::Base> class directly or you'll
change it for all exception classes that use L<Exception::Class>, including
ones created in modules you don't control.

=head2 MyException->MaxArgLength($boolean)

When a C<Devel::StackTrace> object stringifies, by default it displays the full
argument for each function. This parameter can be used to limit the maximum
length of each argument.

Since C<Exception::Class::Base> uses C<Devel::StackTrace> internally, this
method provides a way to tell C<Devel::StackTrace> to limit the length of
arguments.

This method defaults to 0. As with C<Trace>, it is inherited by subclasses but
setting it in a subclass makes it independent thereafter.

Do not call this on the C<Exception::Class::Base> class directly or you'll
change it for all exception classes that use L<Exception::Class>, including
ones created in modules you don't control.

=head2 MyException->Fields

This method returns the extra fields defined for the given class, as a list.

Do not call this on the C<Exception::Class::Base> class directly or you'll
change it for all exception classes that use L<Exception::Class>, including
ones created in modules you don't control.

=head2 MyException->throw( $message )

=head2 MyException->throw( message => $message )

=head2 MyException->throw( error => $error )

This method creates a new object with the given error message. If no error
message is given, this will be an empty string. It then dies with this object
as its argument.

This method also takes a C<show_trace> parameter which indicates whether or not
the particular exception object being created should show a stacktrace when its
C<as_string> method is called. This overrides the value of C<Trace> for this
class if it is given.

The frames included in the trace can be controlled by the C<ignore_class> and
C<ignore_package> parameters. These are passed directly to Devel::Stacktrace's
constructor. See C<Devel::Stacktrace> for more details. This class B<always>
passes C<__PACKAGE__> for C<ignore_class> and C<'Exception::Class'> for
C<ignore_package>, in addition to any arguments you provide.

If only a single value is given to the constructor it is assumed to be the
message parameter.

Additional keys corresponding to the fields defined for the particular
exception subclass will also be accepted.

=head2 MyException->new(...)

This method takes the same parameters as C<throw>, but instead of dying simply
returns a new exception object.

This method is always called when constructing a new exception object via the
C<throw> method.

=head2 MyException->description

Returns the description for the given C<Exception::Class::Base> subclass. The
C<Exception::Class::Base> class's description is "Generic exception" (this may
change in the future). This is also an object method.

=head2 $exception->rethrow

Simply dies with the object as its sole argument. It's just syntactic sugar.
This does not change any of the object's attribute values.  However, it will
cause C<caller> to report the die as coming from within the
C<Exception::Class::Base> class rather than where rethrow was called.

Of course, you always have access to the original stacktrace for the exception
object.

=head2 $exception->message

=head2 $exception->error

Returns the error/message associated with the exception.

=head2 $exception->pid

Returns the pid at the time the exception was thrown.

=head2 $exception->uid

Returns the real user id at the time the exception was thrown.

=head2 $exception->gid

Returns the real group id at the time the exception was thrown.

=head2 $exception->euid

Returns the effective user id at the time the exception was thrown.

=head2 $exception->egid

Returns the effective group id at the time the exception was thrown.

=head2 $exception->time

Returns the time in seconds since the epoch at the time the exception was
thrown.

=head2 $exception->package

Returns the package from which the exception was thrown.

=head2 $exception->file

Returns the file within which the exception was thrown.

=head2 $exception->line

Returns the line where the exception was thrown.

=head2 $exception->context_hash

Returns a hash reference with the following keys:

=over 4

=item * time

=item * pid

=item * uid

=item * euid

=item * gid

=item * egid

=back

=head2 $exception->field_hash

Returns a hash reference where the keys are any fields defined for the
exception class and the values are the values associated with the field in the
given object.

=head2 $exception->trace

Returns the trace object associated with the object.

=head2 $exception->show_trace($boolean)

This method can be used to set whether or not a stack trace is included when
the as_string method is called or the object is stringified.

=head2 $exception->as_string

Returns a string form of the error message (something like what you'd expect
from die). If the class or object is set to show traces then then the full
trace is also included. The result looks like C<Carp::confess>.

=head2 $exception->full_message

Called by the C<as_string> method to get the message. By default, this is the
same as calling the C<message> method, but may be overridden by a subclass. See
below for details.

=head1 LIGHTWEIGHT EXCEPTIONS

A lightweight exception is one which records no information about its context
when it is created. This can be achieved by setting C<< $class->NoContextInfo
>> to a true value.

You can make this the default for a class of exceptions by setting it after
creating the class:

  use Exception::Class (
      'LightWeight',
      'HeavyWeight',
  );

  LightWeight->NoContextInfo(1);

A lightweight exception does have a stack trace object, nor does it record the
time, pid, uid, euid, gid, or egid. It only has a message.

=head1 OVERLOADING

C<Exception::Class::Base> objects are overloaded so that stringification
produces a normal error message. This just calls the C<< $exception->as_string
>> method described above. This means that you can just C<print $@> after an
C<eval> and not worry about whether or not its an actual object. It also means
an application or module could do this:

  $SIG{__DIE__} = sub { Exception::Class::Base->throw( error => join '', @_ ); };

and this would probably not break anything (unless someone was expecting a
different type of exception object from C<die>).

=head1 OVERRIDING THE as_string METHOD

By default, the C<as_string> method simply returns the value C<message> or
C<error> param plus a stack trace, if the class's C<Trace> method returns a
true value or C<show_trace> was set when creating the exception.

However, once you add new fields to a subclass, you may want to include those
fields in the stringified error.

Inside the C<as_string> method, the message (non-stack trace) portion of the
error is generated by calling the C<full_message> method. This can be easily
overridden. For example:

  sub full_message {
      my $self = shift;

      my $msg = $self->message;

      $msg .= " and foo was " . $self->foo;

      return $msg;
  }

=head1 SUPPORT

Bugs may be submitted at L<https://github.com/houseabsolute/Exception-Class/issues>.

I am also usually active on IRC as 'autarch' on C<irc://irc.perl.org>.

=head1 SOURCE

The source code repository for Exception-Class can be found at L<https://github.com/houseabsolute/Exception-Class>.

=head1 AUTHOR

Dave Rolsky <autarch@urth.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2021 by Dave Rolsky.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

The full text of the license can be found in the
F<LICENSE> file included with this distribution.

=cut
