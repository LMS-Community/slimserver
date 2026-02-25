package Devel::StackTrace::Frame;

use strict;
use warnings;

our $VERSION = '2.05';

# Create accessor routines
BEGIN {
    ## no critic (TestingAndDebugging::ProhibitNoStrict)
    no strict 'refs';

    my @attrs = qw(
        package
        filename
        line
        subroutine
        hasargs
        wantarray
        evaltext
        is_require
        hints
        bitmask
    );

    for my $attr (@attrs) {
        *{$attr} = sub { my $s = shift; return $s->{$attr} };
    }
}

{
    my @args = qw(
        package
        filename
        line
        subroutine
        hasargs
        wantarray
        evaltext
        is_require
        hints
        bitmask
    );

    sub new {
        my $proto = shift;
        my $class = ref $proto || $proto;

        my $self = bless {}, $class;

        @{$self}{@args} = @{ shift() };
        $self->{args}             = shift;
        $self->{respect_overload} = shift;
        $self->{max_arg_length}   = shift;
        $self->{message}          = shift;
        $self->{indent}           = shift;

        # fixup unix-style paths on win32
        $self->{filename} = File::Spec->canonpath( $self->{filename} );

        return $self;
    }
}

sub args {
    my $self = shift;

    return @{ $self->{args} };
}

sub as_string {
    my $self  = shift;
    my $first = shift;
    my $p     = shift;

    my $sub = $self->subroutine;

    # This code stolen straight from Carp.pm and then tweaked. All
    # errors are probably my fault  -dave
    if ($first) {
        $sub
            = defined $self->{message}
            ? $self->{message}
            : 'Trace begun';
    }
    else {

        # Build a string, $sub, which names the sub-routine called.
        # This may also be "require ...", "eval '...' or "eval {...}"
        if ( my $eval = $self->evaltext ) {
            if ( $self->is_require ) {
                $sub = "require $eval";
            }
            else {
                $eval =~ s/([\\\'])/\\$1/g;
                $sub = "eval '$eval'";
            }
        }
        elsif ( $sub eq '(eval)' ) {
            $sub = 'eval {...}';
        }

        # if there are any arguments in the sub-routine call, format
        # them according to the format variables defined earlier in
        # this file and join them onto the $sub sub-routine string
        #
        # We copy them because they're going to be modified.
        #
        if ( my @a = $self->args ) {
            for (@a) {

                # set args to the string "undef" if undefined
                unless ( defined $_ ) {
                    $_ = 'undef';
                    next;
                }

                # hack!
                ## no critic (Subroutines::ProtectPrivateSubs)
                $_ = $self->Devel::StackTrace::_ref_to_string($_)
                    if ref $_;
                ## use critic;

                ## no critic (Variables::RequireInitializationForLocalVars)
                local $SIG{__DIE__};
                local $@;
                ## use critic;

                ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                eval {
                    my $max_arg_length
                        = exists $p->{max_arg_length}
                        ? $p->{max_arg_length}
                        : $self->{max_arg_length};

                    if ( $max_arg_length
                        && length $_ > $max_arg_length ) {
                        ## no critic (BuiltinFunctions::ProhibitLvalueSubstr)
                        substr( $_, $max_arg_length ) = '...';
                    }

                    s/'/\\'/g;

                    # 'quote' arg unless it looks like a number
                    $_ = "'$_'" unless /^-?[\d.]+$/;

                    # print control/high ASCII chars as 'M-<char>' or '^<char>'
                    s/([\200-\377])/sprintf("M-%c",ord($1)&0177)/eg;
                    s/([\0-\37\177])/sprintf("^%c",ord($1)^64)/eg;
                };
                ## use critic

                if ( my $e = $@ ) {
                    $_ = $e =~ /malformed utf-8/i ? '(bad utf-8)' : '?';
                }
            }

            # append ('all', 'the', 'arguments') to the $sub string
            $sub .= '(' . join( ', ', @a ) . ')';
            $sub .= ' called';
        }
    }

    # If the user opted into indentation (a la Carp::confess), pre-add a tab
    my $tab = $self->{indent} && !$first ? "\t" : q{};

    return "${tab}$sub at " . $self->filename . ' line ' . $self->line;
}

1;

# ABSTRACT: A single frame in a stack trace

__END__

=pod

=encoding UTF-8

=head1 NAME

Devel::StackTrace::Frame - A single frame in a stack trace

=head1 VERSION

version 2.05

=head1 DESCRIPTION

See L<Devel::StackTrace> for details.

=for Pod::Coverage new

=head1 METHODS

See Perl's C<caller> documentation for more information on what these methods
return.

=head2 $frame->package

The package which created this frame.

=head2 $frame->filename

The filename which created this frame.

=head2 $frame->line

The line where the frame was created.

=head2 $frame->subroutine

The subroutine which created this frame.

=head2 $frame->hasargs

This will be true if a new C<@_> was created for this this frame.

=head2 $frame->wantarray

This indicates the context for the call for this frame. This will be true if
called in array context, false in scalar context, and C<undef> in void context.

=head2 $frame->evaltext

Returns undef if the frame was not part of an eval.

=head2 $frame->is_require

Returns undef if the frame was not part of a require.

=head2 $frame->args

Returns the arguments passed to the frame. Note that any arguments that are
references are returned as references, not copies.

=head2 $frame->hints

Returns the value of C<$^H> for this frame.

=head2 $frame->bitmask

Returns the value of C<$bitmask> for this frame.

=head2 $frame->as_string

Returns a string containing a description of the frame.

=head1 SUPPORT

Bugs may be submitted at L<https://github.com/houseabsolute/Devel-StackTrace/issues>.

=head1 SOURCE

The source code repository for Devel-StackTrace can be found at L<https://github.com/houseabsolute/Devel-StackTrace>.

=head1 AUTHOR

Dave Rolsky <autarch@urth.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2000 - 2024 by David Rolsky.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

The full text of the license can be found in the
F<LICENSE> file included with this distribution.

=cut
