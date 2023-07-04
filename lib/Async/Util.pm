package Async::Util;
BEGIN {
    $Async::Util::VERSION = '0.01';
}
# ABSTRACT: utilities for doing common async operations
use strict;
use warnings;
use v5.10;
no warnings 'recursion';
use Carp;
use Exporter;
use Scalar::Util qw(weaken);

our @ISA               = qw(Exporter);
our @EXPORT_OK         = qw(amap azipmap achain);
my  $DEFAULT_AT_A_TIME = 100;

sub amap {
    my (%args) = @_;

    return _amap_ignore(%args) if exists $args{output} && !$args{output};
    return _amap(%args);
}

sub _amap {
    my (%args) = @_;

    my $action    = $args{action};
    my $inputs    = $args{inputs};
    my $cb        = $args{cb};
    my $at_a_time = $args{at_a_time} || $DEFAULT_AT_A_TIME;

    croak q/Argument 'inputs' is required/ if !defined $inputs;
    croak q/Argument 'action' is required/ if !defined $action;
    croak q/Argument 'cb' is required/     if !defined $cb;

    croak q/Argument 'inputs' must be an ArrayRef/ if ref $inputs ne 'ARRAY';
    croak q/Argument 'action' must be a CodeRef/   if ref $action ne 'CODE';
    croak q/Argument 'cb'     must be a CodeRef/   if ref $cb ne 'CODE';

    my $inflight    = 0;
    my $cb_count    = 0;
    my $input_index = 0;
    my $outputs     = [];
    my $any_err     = 0;
    my $after_work;

    my $run = sub {

        while ($inflight < $at_a_time && $input_index <= $#{ $inputs }) {

            $inflight++;

            my $index = $input_index;
            my $input = $inputs->[ $index ];
            $input_index++;

            my $after_work_wrapper = sub {
                my ($res, $err) = @_;
                my $i = $index;
                $after_work->($res, $err, $i);
            };

            $action->($input, $after_work_wrapper);

            weaken $after_work_wrapper;
        }

    };

    $after_work = sub {
        my ($output, $err, $index) = @_;

        $cb_count++;
        $inflight--;

        return if $any_err;

        if ($err) {
            $any_err = 1;
            return $cb->(undef, $err);
        }

        # store the output
        $outputs->[$index] = $output;

        return $cb->($outputs) if $cb_count == @{ $inputs };

        $run->();
    };

    $run->();
    # weaken $run;

    return;
}

sub _amap_ignore {
    my (%args) = @_;

    my $action    = $args{action};
    my $inputs    = $args{inputs};
    my $cb        = $args{cb};
    my $at_a_time = $args{at_a_time} || $DEFAULT_AT_A_TIME;

    croak q/Argument 'inputs' is required/ if !defined $inputs;
    croak q/Argument 'action' is required/ if !defined $action;
    croak q/Argument 'cb' is required/     if !defined $cb;

    croak q/Argument 'inputs' must be an ArrayRef/ if ref $inputs ne 'ARRAY';
    croak q/Argument 'action' must be a CodeRef/   if ref $action ne 'CODE';
    croak q/Argument 'cb'     must be a CodeRef/   if ref $cb ne 'CODE';

    my $inflight    = 0;
    my $cb_count    = 0;
    my $input_index = 0;
    my $any_err     = 0;
    my $after_work;

    my $run = sub {

        while ($inflight < $at_a_time && $input_index <= $#{ $inputs }) {

            $inflight++;

            my $index = $input_index;
            my $input = $inputs->[ $index ];
            $input_index++;

            $action->($input, $after_work);
        }
    };

    $after_work = sub {
        my (undef, $err) = @_;

        $cb_count++;
        $inflight--;

        return if $any_err;

        if ($err) {
            $any_err = 1;
            return $cb->(undef, $err);
        }

        return $cb->() if $cb_count == @{ $inputs };

        $run->();
    };

    $run->();

    weaken $after_work;

    return;
}

sub azipmap {
    my (%args) = @_;

    my $actions   = $args{actions};
    my $inputs    = $args{inputs};
    my $cb        = $args{cb};
    my $at_a_time = $args{at_a_time} || $DEFAULT_AT_A_TIME;

    croak q/Argument 'inputs' is required/  if !defined $inputs;
    croak q/Argument 'actions' is required/ if !defined $actions;
    croak q/Argument 'cb' is required/      if !defined $cb;

    croak q/Argument 'actions' must be an ArrayRef/ if ref $actions ne 'ARRAY';
    croak q/Argument 'cb' must be a CodeRef/        if ref $cb ne 'CODE';

    $inputs //= map { undef } 1..@{ $actions };

    my $inflight = 0;
    my $cb_count = 0;
    my $work_idx = 0;
    my $outputs  = [];
    my $any_err  = 0;
    my $after_work;

    my $run = sub {

        while ($inflight < $at_a_time && $work_idx <= $#{ $actions }) {

            $inflight++;

            my $index  = $work_idx;
            my $action = $actions->[ $index ];
            my $input  = $inputs->[ $index ];
            $work_idx++;

            my $after_work_wrapper = sub {
                my $i = $index;
                $after_work->($_[0], $_[1], $i);
            };

            $action->($input, $after_work_wrapper);

            weaken $after_work_wrapper;
        }
    };

    $after_work = sub {
        my ($output, $err, $index) = @_;

        $cb_count++;
        $inflight--;

        return if $any_err;

        if ($err) {
            $any_err = 1;
            $cb->(undef, $err);
        }

        $outputs->[$index] = $output;

        return $cb->($outputs) if $cb_count == @{ $actions };

        $run->();
    };

    $run->();
    weaken $run;

    return;
}

sub achain {
    my (%args) = @_;

    my $input  = $args{input};
    my $cb     = $args{cb};
    my $steps  = $args{steps};

    croak q/Argument 'cb' is required/    if !defined $cb;
    croak q/Argument 'steps' is required/ if !defined $steps;

    croak q/Argument 'cb' must be a CodeRef/      if ref $cb ne 'CODE';
    croak q/Argument 'steps' must be an ArrayRef/ if ref $steps ne 'ARRAY';

    my $run; $run = sub {
        my ($result, $err) = @_;

        return $cb->(undef, $err) if $err;

        my $next_cb = shift @{ $steps };

        return $cb->($result) if !defined $next_cb;

        $next_cb->($result, $run);
    };

    $run->($input);
    weaken $run;

    return;
}

1;

__END__

=pod

=head1 NAME

Async::Util - Utilities for common asynchronous programming tasks

=head1 SYNOPSIS

    use Async::Util qw(amap azipmap achain);

    # async map
    amap(
        inputs => [ 'foo', 'bar' ],
        action => \&something_asynchronous,
        cb     => \&do_this_at_the_end,
    );

    # invoke action on the corresponding input
    azipmap(
        inputs  => [ 1, 1, 1 ],
        actions => [
            ... # asynchronous subs
        ],
        cb     => \&do_this_at_the_end,
    );

    # execute steps in order
    achain(
        input => 2,
        steps => [
            ... # asynchronous subs
        ],
        cb    => \&do_this_at_the_end,
    );

Examples using AnyEvent:

    use AnyEvent;
    use Async::Util qw(amap);

    my @timers;
    my $delayed_double = sub {
        my ($input, $cb) = @_;

        push @timers, AnyEvent->timer(after => 2, cb => sub {
            $cb->($input*2);
        });
    };

    my $cv = AE::cv;

    amap(
        inputs    => [ 1 .. 20 ],
        action    => $delayed_double,
        cb        => sub { $cv->send(@_) },
        at_a_time => 5,
    );

    my ($res, $err) = $cv->recv;

    # achain
    my $cv = AE::cv;

    achain(
        input => 2,
        steps => [
            sub {
                my ($input, $cb) = @_;
                push @timers, AnyEvent->timer(
                    after => 0,
                    cb    => sub { $cb->($input+1) },
                );
            },
            sub {
                my ($input, $cb) = @_;
                push @timers, AnyEvent->timer(
                    after => 0,
                    cb    => sub { $cb->($input * 2) },
                );
            },
        ],
        cb => sub { $cv->send(@_) },
    );

    my ($res, $err) = $cv->recv; # $res is 6

=head1 DESCRIPTION

C<Async::Util> provides functionality for common tasks that come up when doing
asynchronous programming. This module's functions often take code refs. These
code refs are invoked with two arguments: the input and a callback to be
invoked on completion. When the provided callback is invoked it should be
passed an output argument and an optional error.

=head1 FUNCTIONS

=head2 amap

C<amap> is an asynchronous version of map:

    amap(
        inputs    => <ARRAY_REF>,
        action    => <CODE_REF>,
        cb        => <CODE_REF>,
        at_a_time => <INTEGER>, # defaults to 100
        output    => <BOOL>,    # defaults to true
    );

The action coderef is executed for every provided input. The first argument to
the action coderef is an input from the list and the second is a callback.
When the action is done it should invoke the callback passing the result as
the first argument and optionally an error message as the second.

If the action will produce no output then it can pass C<undef> as the first
argument to the callback and an optional error as the second argument in the
usual way. In this case, the C<amap> argument C<output> can be set to 0,
allowing certain performance optimizations to occur.

The C<at_a_time> argument sets the maximum number of inputs that will be
processed simultaneously. This defaults to 100.

When the action has been applied to each input then the C<cb> coderef is
invoked and passed an arrayref containing one result for every input. If
action ever passes an error to its callback then the cb coderef is immediately
invoked and passed the error. No more inputs are processed.

=head2 azipmap

C<azipmap> executes a list of callbacks on a list of corresponding inputs.
Every provided action is executed and passed the input found in the same
position in the list of provided inputs. In other words, the list of actions
and the list of inputs are zipped in to action/input pairs, then each action
is executed on its input.

    azipmap(
        inputs    => <ARRAY_REF>,
        actions   => <CODE_REF>,
        cb        => <CODE_REF>,
        at_a_time => <INTEGER>, # defaults to 100
        output    => <BOOL>,    # defaults to true
    );

Just as with C<amap>, actions should pass a result to the passed in callback
as well as an optional error. Also, as with C<amap>, the C<cb> coderef is
invoked once all the inputs have been processed or immediately if any action
passes an error to its callback.

=head2 achain

C<achain> executes the provided steps in order. Each step's coderef is passed
an input and a callback. When the step is complete is should invoke the
coderef and pass a result and an optional error. The result from each step
becomes the input to the next step. The first step's input is the value passed
to C<achain> as the C<input> argument. When all steps are complete the C<cb>
coderef is executed and passed the result from the last step. If any step
returns an error then the C<cb> coderef is immediately invoked and passed the
error.

    achain(
        input => <SCALAR>,
        steps => <ARRAY_REF>,
        cb    => <CODE_REF>,
    );

=head1 REPOSITORY

L<http://github.com/wjackson/async-util>

=head1 AUTHORS

Whitney Jackson
