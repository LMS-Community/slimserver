package Devel::StackTrace;

use 5.006;

use strict;
use warnings;

our $VERSION = '2.05';

use Devel::StackTrace::Frame;
use File::Spec;
use Scalar::Util qw( blessed );

use overload
    '""'     => \&as_string,
    bool     => sub {1},
    fallback => 1;

sub new {
    my $class = shift;
    my %p     = @_;

    $p{unsafe_ref_capture} = !delete $p{no_refs}
        if exists $p{no_refs};

    my $self = bless {
        index  => undef,
        frames => [],
        raw    => [],
        %p,
    }, $class;

    $self->_record_caller_data;

    return $self;
}

sub _record_caller_data {
    my $self = shift;

    my $filter = $self->{filter_frames_early} && $self->_make_frame_filter;

    # We exclude this method by starting at least one frame back.
    my $x = 1 + ( $self->{skip_frames} || 0 );

    while (
        my @c
        = $self->{no_args}
        ? caller( $x++ )
        : do {
            ## no critic (Modules::ProhibitMultiplePackages, Variables::ProhibitPackageVars)
            package    # the newline keeps dzil from adding a version here
                DB;
            @DB::args = ();
            caller( $x++ );
        }
    ) {

        my @args;

        ## no critic (Variables::ProhibitPackageVars, BuiltinFunctions::ProhibitComplexMappings)
        unless ( $self->{no_args} ) {

            # This is the same workaroud as was applied to Carp.pm a little
            # while back
            # (https://rt.perl.org/Public/Bug/Display.html?id=131046):
            #
            #   Guard our serialization of the stack from stack refcounting
            #   bugs NOTE this is NOT a complete solution, we cannot 100%
            #   guard against these bugs. However in many cases Perl *is*
            #   capable of detecting them and throws an error when it
            #   does. Unfortunately serializing the arguments on the stack is
            #   a perfect way of finding these bugs, even when they would not
            #   affect normal program flow that did not poke around inside the
            #   stack. Inside of Carp.pm it makes little sense reporting these
            #   bugs, as Carp's job is to report the callers errors, not the
            #   ones it might happen to tickle while doing so.  See:
            #   https://rt.perl.org/Public/Bug/Display.html?id=131046 and:
            #   https://rt.perl.org/Public/Bug/Display.html?id=52610 for more
            #   details and discussion. - Yves
            @args = map {
                my $arg;
                local $@ = $@;
                eval {
                    $arg = $_;
                    1;
                } or do {
                    $arg = '** argument not available anymore **';
                };
                $arg;
            } @DB::args;
        }
        ## use critic

        my $raw = {
            caller => \@c,
            args   => \@args,
        };

        next if $filter && !$filter->($raw);

        unless ( $self->{unsafe_ref_capture} ) {
            $raw->{args} = [ map { ref $_ ? $self->_ref_to_string($_) : $_ }
                    @{ $raw->{args} } ];
        }

        push @{ $self->{raw} }, $raw;
    }
}

sub _ref_to_string {
    my $self = shift;
    my $ref  = shift;

    return overload::AddrRef($ref)
        if blessed $ref && $ref->isa('Exception::Class::Base');

    return overload::AddrRef($ref) unless $self->{respect_overload};

    ## no critic (Variables::RequireInitializationForLocalVars)
    local $@;
    local $SIG{__DIE__};
    ## use critic

    my $str = eval { $ref . q{} };

    return $@ ? overload::AddrRef($ref) : $str;
}

sub _make_frames {
    my $self = shift;

    my $filter = !$self->{filter_frames_early} && $self->_make_frame_filter;

    my $raw = delete $self->{raw};
    for my $r ( @{$raw} ) {
        next if $filter && !$filter->($r);

        $self->_add_frame( $r->{caller}, $r->{args} );
    }
}

my $default_filter = sub {1};

sub _make_frame_filter {
    my $self = shift;

    my ( @i_pack_re, %i_class );
    if ( $self->{ignore_package} ) {
        ## no critic (Variables::RequireInitializationForLocalVars)
        local $@;
        local $SIG{__DIE__};
        ## use critic

        $self->{ignore_package} = [ $self->{ignore_package} ]
            unless eval { @{ $self->{ignore_package} } };

        @i_pack_re
            = map { ref $_ ? $_ : qr/^\Q$_\E$/ } @{ $self->{ignore_package} };
    }

    my $p = __PACKAGE__;
    push @i_pack_re, qr/^\Q$p\E$/;

    if ( $self->{ignore_class} ) {
        $self->{ignore_class} = [ $self->{ignore_class} ]
            unless ref $self->{ignore_class};
        %i_class = map { $_ => 1 } @{ $self->{ignore_class} };
    }

    my $user_filter = $self->{frame_filter};

    return sub {
        return 0 if grep { $_[0]{caller}[0] =~ /$_/ } @i_pack_re;
        return 0 if grep { $_[0]{caller}[0]->isa($_) } keys %i_class;

        if ($user_filter) {
            return $user_filter->( $_[0] );
        }

        return 1;
    };
}

sub _add_frame {
    my $self = shift;
    my $c    = shift;
    my $p    = shift;

    # eval and is_require are only returned when applicable under 5.00503.
    push @$c, ( undef, undef ) if scalar @$c == 6;

    push @{ $self->{frames} },
        Devel::StackTrace::Frame->new(
        $c,
        $p,
        $self->{respect_overload},
        $self->{max_arg_length},
        $self->{message},
        $self->{indent}
        );
}

sub next_frame {
    my $self = shift;

    # reset to top if necessary.
    $self->{index} = -1 unless defined $self->{index};

    my @f = $self->frames;
    if ( defined $f[ $self->{index} + 1 ] ) {
        return $f[ ++$self->{index} ];
    }
    else {
        $self->{index} = undef;
        ## no critic (Subroutines::ProhibitExplicitReturnUndef)
        return undef;
    }
}

sub prev_frame {
    my $self = shift;

    my @f = $self->frames;

    # reset to top if necessary.
    $self->{index} = scalar @f unless defined $self->{index};

    if ( defined $f[ $self->{index} - 1 ] && $self->{index} >= 1 ) {
        return $f[ --$self->{index} ];
    }
    else {
        ## no critic (Subroutines::ProhibitExplicitReturnUndef)
        $self->{index} = undef;
        return undef;
    }
}

sub reset_pointer {
    my $self = shift;

    $self->{index} = undef;

    return;
}

sub frames {
    my $self = shift;

    if (@_) {
        die
            "Devel::StackTrace->frames can only take Devel::StackTrace::Frame args\n"
            if grep { !$_->isa('Devel::StackTrace::Frame') } @_;

        $self->{frames} = \@_;
        delete $self->{raw};
    }
    else {
        $self->_make_frames if $self->{raw};
    }

    return @{ $self->{frames} };
}

sub frame {
    my $self = shift;
    my $i    = shift;

    return unless defined $i;

    return ( $self->frames )[$i];
}

sub frame_count {
    my $self = shift;

    return scalar( $self->frames );
}

sub message { $_[0]->{message} }

sub as_string {
    my $self = shift;
    my $p    = shift;

    my @frames = $self->frames;
    if (@frames) {
        my $st    = q{};
        my $first = 1;
        for my $f (@frames) {
            $st .= $f->as_string( $first, $p ) . "\n";
            $first = 0;
        }

        return $st;
    }

    my $msg = $self->message;
    return $msg if defined $msg;

    return 'Trace begun';
}

{
    ## no critic (Modules::ProhibitMultiplePackages, ClassHierarchies::ProhibitExplicitISA)
    package    # hide from PAUSE
        Devel::StackTraceFrame;

    our @ISA = 'Devel::StackTrace::Frame';
}

1;

# ABSTRACT: An object representing a stack trace

__END__

=pod

=encoding UTF-8

=head1 NAME

Devel::StackTrace - An object representing a stack trace

=head1 VERSION

version 2.05

=head1 SYNOPSIS

  use Devel::StackTrace;

  my $trace = Devel::StackTrace->new;

  print $trace->as_string; # like carp

  # from top (most recent) of stack to bottom.
  while ( my $frame = $trace->next_frame ) {
      print "Has args\n" if $frame->hasargs;
  }

  # from bottom (least recent) of stack to top.
  while ( my $frame = $trace->prev_frame ) {
      print "Sub: ", $frame->subroutine, "\n";
  }

=head1 DESCRIPTION

The C<Devel::StackTrace> module contains two classes, C<Devel::StackTrace> and
L<Devel::StackTrace::Frame>. These objects encapsulate the information that can
retrieved via Perl's C<caller> function, as well as providing a simple
interface to this data.

The C<Devel::StackTrace> object contains a set of C<Devel::StackTrace::Frame>
objects, one for each level of the stack. The frames contain all the data
available from C<caller>.

This code was created to support my L<Exception::Class::Base> class (part of
L<Exception::Class>) but may be useful in other contexts.

=head1 'TOP' AND 'BOTTOM' OF THE STACK

When describing the methods of the trace object, I use the words 'top' and
'bottom'. In this context, the 'top' frame on the stack is the most recent
frame and the 'bottom' is the least recent.

Here's an example:

  foo();  # bottom frame is here

  sub foo {
     bar();
  }

  sub bar {
     Devel::StackTrace->new;  # top frame is here.
  }

=head1 METHODS

This class provide the following methods:

=head2 Devel::StackTrace->new(%named_params)

Returns a new Devel::StackTrace object.

Takes the following parameters:

=over 4

=item * frame_filter => $sub

By default, Devel::StackTrace will include all stack frames before the call to
its constructor.

However, you may want to filter out some frames with more granularity than
'ignore_package' or 'ignore_class' allow.

You can provide a subroutine which is called with the raw frame data for each
frame. This is a hash reference with two keys, "caller", and "args", both of
which are array references. The "caller" key is the raw data as returned by
Perl's C<caller> function, and the "args" key are the subroutine arguments
found in C<@DB::args>.

The filter should return true if the frame should be included, or false if it
should be skipped.

=item * filter_frames_early => $boolean

If this parameter is true, C<frame_filter> will be called as soon as the
stacktrace is created, and before refs are stringified (if
C<unsafe_ref_capture> is not set), rather than being filtered lazily when
L<Devel::StackTrace::Frame> objects are first needed.

This is useful if you want to filter based on the frame's arguments and want to
be able to examine object properties, for example.

=item * ignore_package => $package_name OR \@package_names

Any frames where the package is one of these packages will not be on the stack.

=item * ignore_class => $package_name OR \@package_names

Any frames where the package is a subclass of one of these packages (or is the
same package) will not be on the stack.

Devel::StackTrace internally adds itself to the 'ignore_package' parameter,
meaning that the Devel::StackTrace package is B<ALWAYS> ignored. However, if
you create a subclass of Devel::StackTrace it will not be ignored.

=item * skip_frames => $integer

This will cause this number of stack frames to be excluded from top of the
stack trace. This prevents the frames from being captured at all, and applies
before the C<frame_filter>, C<ignore_package>, or C<ignore_class> options, even
with C<filter_frames_early>.

=item * unsafe_ref_capture => $boolean

If this parameter is true, then Devel::StackTrace will store references
internally when generating stacktrace frames.

B<This option is very dangerous, and should never be used with exception
objects>. Using this option will keep any objects or references alive past
their normal lifetime, until the stack trace object goes out of scope. It can
keep objects alive even after their C<DESTROY> sub is called, resulting it it
being called multiple times on the same object.

If not set, Devel::StackTrace replaces any references with their stringified
representation.

=item * no_args => $boolean

If this parameter is true, then Devel::StackTrace will not store caller
arguments in stack trace frames at all.

=item * respect_overload => $boolean

By default, Devel::StackTrace will call C<overload::AddrRef> to get the
underlying string representation of an object, instead of respecting the
object's stringification overloading. If you would prefer to see the overloaded
representation of objects in stack traces, then set this parameter to true.

=item * max_arg_length => $integer

By default, Devel::StackTrace will display the entire argument for each
subroutine call. Setting this parameter causes truncates each subroutine
argument's string representation if it is longer than this number of
characters.

=item * message => $string

By default, Devel::StackTrace will use 'Trace begun' as the message for the
first stack frame when you call C<as_string>. You can supply an alternative
message using this option.

=item * indent => $boolean

If this parameter is true, each stack frame after the first will start with a
tab character, just like C<Carp::confess>.

=back

=head2 $trace->next_frame

Returns the next L<Devel::StackTrace::Frame> object on the stack, going down.
If this method hasn't been called before it returns the first frame. It returns
C<undef> when it reaches the bottom of the stack and then resets its pointer so
the next call to C<< $trace->next_frame >> or C<< $trace->prev_frame >> will
work properly.

=head2 $trace->prev_frame

Returns the next L<Devel::StackTrace::Frame> object on the stack, going up. If
this method hasn't been called before it returns the last frame. It returns
undef when it reaches the top of the stack and then resets its pointer so the
next call to C<< $trace->next_frame >> or C<< $trace->prev_frame >> will work
properly.

=head2 $trace->reset_pointer

Resets the pointer so that the next call to C<< $trace->next_frame >> or C<<
$trace->prev_frame >> will start at the top or bottom of the stack, as
appropriate.

=head2 $trace->frames

When this method is called with no arguments, it returns a list of
L<Devel::StackTrace::Frame> objects. They are returned in order from top (most
recent) to bottom.

This method can also be used to set the object's frames if you pass it a list
of L<Devel::StackTrace::Frame> objects.

This is useful if you want to filter the list of frames in ways that are more
complex than can be handled by the C<< $trace->filter_frames >> method:

  $stacktrace->frames( my_filter( $stacktrace->frames ) );

=head2 $trace->frame($index)

Given an index, this method returns the relevant frame, or undef if there is no
frame at that index. The index is exactly like a Perl array. The first frame is
0 and negative indexes are allowed.

=head2 $trace->frame_count

Returns the number of frames in the trace object.

=head2 $trace->as_string(\%p)

Calls C<< $frame->as_string >> on each frame from top to bottom, producing
output quite similar to the Carp module's cluck/confess methods.

The optional C<\%p> parameter only has one option. The C<max_arg_length>
parameter truncates each subroutine argument's string representation if it is
longer than this number of characters.

If all the frames in a trace are skipped then this just returns the C<message>
passed to the constructor or the string C<"Trace begun">.

=head2 $trace->message

Returns the message passed to the constructor. If this wasn't passed then this
method returns C<undef>.

=head1 SUPPORT

Bugs may be submitted at L<https://github.com/houseabsolute/Devel-StackTrace/issues>.

=head1 SOURCE

The source code repository for Devel-StackTrace can be found at L<https://github.com/houseabsolute/Devel-StackTrace>.

=head1 DONATIONS

If you'd like to thank me for the work I've done on this module, please
consider making a "donation" to me via PayPal. I spend a lot of free time
creating free software, and would appreciate any support you'd care to offer.

Please note that B<I am not suggesting that you must do this> in order for me
to continue working on this particular software. I will continue to do so,
inasmuch as I have in the past, for as long as it interests me.

Similarly, a donation made in this way will probably not make me work on this
software much more, unless I get so many donations that I can consider working
on free software full time (let's all have a chuckle at that together).

To donate, log into PayPal and send money to autarch@urth.org, or use the
button at L<https://houseabsolute.com/foss-donations/>.

=head1 AUTHOR

Dave Rolsky <autarch@urth.org>

=head1 CONTRIBUTORS

=for stopwords Dagfinn Ilmari Mannsåker David Cantrell Graham Knop Ivan Bessarabov Mark Fowler Pali Ricardo Signes

=over 4

=item *

Dagfinn Ilmari Mannsåker <ilmari@ilmari.org>

=item *

David Cantrell <david@cantrell.org.uk>

=item *

Graham Knop <haarg@haarg.org>

=item *

Ivan Bessarabov <ivan@bessarabov.ru>

=item *

Mark Fowler <mark@twoshortplanks.com>

=item *

Pali <pali@cpan.org>

=item *

Ricardo Signes <rjbs@cpan.org>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2000 - 2024 by David Rolsky.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

The full text of the license can be found in the
F<LICENSE> file included with this distribution.

=cut
