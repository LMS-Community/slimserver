package Carp::Assert;

require 5.004;

use strict qw(subs vars);
use Exporter;

use vars qw(@ISA $VERSION %EXPORT_TAGS);

BEGIN {
    $VERSION = '0.18';

    @ISA = qw(Exporter);

    %EXPORT_TAGS = (
                    NDEBUG => [qw(assert affirm should shouldnt DEBUG)],
                   );
    $EXPORT_TAGS{DEBUG} = $EXPORT_TAGS{NDEBUG};
    Exporter::export_tags(qw(NDEBUG DEBUG));
}

# constant.pm, alas, adds too much load time (yes, I benchmarked it)
sub REAL_DEBUG  ()  { 1 }       # CONSTANT
sub NDEBUG      ()  { 0 }       # CONSTANT

# Export the proper DEBUG flag according to if :NDEBUG is set.
# Also export noop versions of our routines if NDEBUG
sub noop { undef }
sub noop_affirm (&;$) { undef };

sub import {
    my $env_ndebug = exists $ENV{PERL_NDEBUG} ? $ENV{PERL_NDEBUG}
                                              : $ENV{'NDEBUG'};
    if( grep(/^:NDEBUG$/, @_) or $env_ndebug ) {
        my $caller = caller;
        foreach my $func (grep !/^DEBUG$/, @{$EXPORT_TAGS{'NDEBUG'}}) {
            if( $func eq 'affirm' ) {
                *{$caller.'::'.$func} = \&noop_affirm;
            } else {
                *{$caller.'::'.$func} = \&noop;
            }
        }
        *{$caller.'::DEBUG'} = \&NDEBUG;
    }
    else {
        *DEBUG = *REAL_DEBUG;
        Carp::Assert->_export_to_level(1, @_);
    }
}


# 5.004's Exporter doesn't have export_to_level.
sub _export_to_level
{
      my $pkg = shift;
      my $level = shift;
      (undef) = shift;                  # XXX redundant arg
      my $callpkg = caller($level);
      $pkg->export($callpkg, @_);
}


sub unimport {
    *DEBUG = *NDEBUG;
    push @_, ':NDEBUG';
    goto &import;
}


# Can't call confess() here or the stack trace will be wrong.
sub _fail_msg {
    my($name) = shift;
    my $msg = 'Assertion';
    $msg   .= " ($name)" if defined $name;
    $msg   .= " failed!\n";
    return $msg;
}


=head1 NAME

Carp::Assert - executable comments

=head1 SYNOPSIS

    # Assertions are on.
    use Carp::Assert;

    $next_sunrise_time = sunrise();

    # Assert that the sun must rise in the next 24 hours.
    assert(($next_sunrise_time - time) < 24*60*60) if DEBUG;

    # Assert that your customer's primary credit card is active
    affirm {
        my @cards = @{$customer->credit_cards};
        $cards[0]->is_active;
    };


    # Assertions are off.
    no Carp::Assert;

    $next_pres = divine_next_president();

    # Assert that if you predict Dan Quayle will be the next president
    # your crystal ball might need some polishing.  However, since
    # assertions are off, IT COULD HAPPEN!
    shouldnt($next_pres, 'Dan Quayle') if DEBUG;


=head1 DESCRIPTION

=for testing
use Carp::Assert;


    "We are ready for any unforseen event that may or may not 
    occur."
        - Dan Quayle

Carp::Assert is intended for a purpose like the ANSI C library
assert.h.  If you're already familiar with assert.h, then you can
probably skip this and go straight to the FUNCTIONS section.

Assertions are the explict expressions of your assumptions about the
reality your program is expected to deal with, and a declaration of
those which it is not.  They are used to prevent your program from
blissfully processing garbage inputs (garbage in, garbage out becomes
garbage in, error out) and to tell you when you've produced garbage
output.  (If I was going to be a cynic about Perl and the user nature,
I'd say there are no user inputs but garbage, and Perl produces
nothing but...)

An assertion is used to prevent the impossible from being asked of
your code, or at least tell you when it does.  For example:

=for example begin

    # Take the square root of a number.
    sub my_sqrt {
        my($num) = shift;

        # the square root of a negative number is imaginary.
        assert($num >= 0);

        return sqrt $num;
    }

=for example end

=for example_testing
is( my_sqrt(4),  2,            'my_sqrt example with good input' );
ok( !eval{ my_sqrt(-1); 1 },   '  and pukes on bad' );

The assertion will warn you if a negative number was handed to your
subroutine, a reality the routine has no intention of dealing with.

An assertion should also be used as something of a reality check, to
make sure what your code just did really did happen:

    open(FILE, $filename) || die $!;
    @stuff = <FILE>;
    @stuff = do_something(@stuff);

    # I should have some stuff.
    assert(@stuff > 0);

The assertion makes sure you have some @stuff at the end.  Maybe the
file was empty, maybe do_something() returned an empty list... either
way, the assert() will give you a clue as to where the problem lies,
rather than 50 lines down at when you wonder why your program isn't
printing anything.

Since assertions are designed for debugging and will remove themelves
from production code, your assertions should be carefully crafted so
as to not have any side-effects, change any variables, or otherwise
have any effect on your program.  Here is an example of a bad
assertation:

    assert($error = 1 if $king ne 'Henry');  # Bad!

It sets an error flag which may then be used somewhere else in your
program. When you shut off your assertions with the $DEBUG flag,
$error will no longer be set.

Here's another example of B<bad> use:

    assert($next_pres ne 'Dan Quayle' or goto Canada);  # Bad!

This assertion has the side effect of moving to Canada should it fail.
This is a very bad assertion since error handling should not be
placed in an assertion, nor should it have side-effects.

In short, an assertion is an executable comment.  For instance, instead
of writing this

    # $life ends with a '!'
    $life = begin_life();

you'd replace the comment with an assertion which B<enforces> the comment.

    $life = begin_life();
    assert( $life =~ /!$/ );

=for testing
my $life = 'Whimper!';
ok( eval { assert( $life =~ /!$/ ); 1 },   'life ends with a bang' );


=head1 FUNCTIONS

=over 4

=item B<assert>

    assert(EXPR) if DEBUG;
    assert(EXPR, $name) if DEBUG;

assert's functionality is effected by compile time value of the DEBUG
constant, controlled by saying C<use Carp::Assert> or C<no
Carp::Assert>.  In the former case, assert will function as below.
Otherwise, the assert function will compile itself out of the program.
See L<Debugging vs Production> for details.

=for testing
{
  package Some::Other;
  no Carp::Assert;
  ::ok( eval { assert(0) if DEBUG; 1 } );
}

Give assert an expression, assert will Carp::confess() if that
expression is false, otherwise it does nothing.  (DO NOT use the
return value of assert for anything, I mean it... really!).

=for testing
ok( eval { assert(1); 1 } );
ok( !eval { assert(0); 1 } );

The error from assert will look something like this:

    Assertion failed!
            Carp::Assert::assert(0) called at prog line 23
            main::foo called at prog line 50

=for testing
eval { assert(0) };
like( $@, '/^Assertion failed!/',       'error format' );
like( $@, '/Carp::Assert::assert\(0\) called at/',      '  with stack trace' );

Indicating that in the file "prog" an assert failed inside the
function main::foo() on line 23 and that foo() was in turn called from
line 50 in the same file.

If given a $name, assert() will incorporate this into your error message,
giving users something of a better idea what's going on.

    assert( Dogs->isa('People'), 'Dogs are people, too!' ) if DEBUG;
    # Result - "Assertion (Dogs are people, too!) failed!"

=for testing
eval { assert( Dogs->isa('People'), 'Dogs are people, too!' ); };
like( $@, '/^Assertion \(Dogs are people, too!\) failed!/', 'names' );

=cut

sub assert ($;$) {
    unless($_[0]) {
        require Carp;
        Carp::confess( _fail_msg($_[1]) );
    }
    return undef;
}


=item B<affirm>

    affirm BLOCK if DEBUG;
    affirm BLOCK $name if DEBUG;

Very similar to assert(), but instead of taking just a simple
expression it takes an entire block of code and evaluates it to make
sure its true.  This can allow more complicated assertions than
assert() can without letting the debugging code leak out into
production and without having to smash together several
statements into one.

=for example begin

    affirm {
        my $customer = Customer->new($customerid);
        my @cards = $customer->credit_cards;
        grep { $_->is_active } @cards;
    } "Our customer has an active credit card";

=for example end

=for testing
my $foo = 1;  my $bar = 2;
eval { affirm { $foo == $bar } };
like( $@, '/\$foo == \$bar/' );


affirm() also has the nice side effect that if you forgot the C<if DEBUG>
suffix its arguments will not be evaluated at all.  This can be nice
if you stick affirm()s with expensive checks into hot loops and other
time-sensitive parts of your program.

If the $name is left off and your Perl version is 5.6 or higher the
affirm() diagnostics will include the code begin affirmed.

=cut

sub affirm (&;$) {
    unless( eval { &{$_[0]}; } ) {
        my $name = $_[1];

        if( !defined $name ) {
            eval {
                require B::Deparse;
                $name = B::Deparse->new->coderef2text($_[0]);
            };
            $name = 
              'code display non-functional on this version of Perl, sorry'
                if $@;
        }

        require Carp;
        Carp::confess( _fail_msg($name) );
    }
    return undef;
}

=item B<should>

=item B<shouldnt>

    should  ($this, $shouldbe)   if DEBUG;
    shouldnt($this, $shouldntbe) if DEBUG;

Similar to assert(), it is specially for simple "this should be that"
or "this should be anything but that" style of assertions.

Due to Perl's lack of a good macro system, assert() can only report
where something failed, but it can't report I<what> failed or I<how>.
should() and shouldnt() can produce more informative error messages:

    Assertion ('this' should be 'that'!) failed!
            Carp::Assert::should('this', 'that') called at moof line 29
            main::foo() called at moof line 58

So this:

    should($this, $that) if DEBUG;

is similar to this:

    assert($this eq $that) if DEBUG;

except for the better error message.

Currently, should() and shouldnt() can only do simple eq and ne tests
(respectively).  Future versions may allow regexes.

=cut

sub should ($$) {
    unless($_[0] eq $_[1]) {
        require Carp;
        &Carp::confess( _fail_msg("'$_[0]' should be '$_[1]'!") );
    }
    return undef;
}

sub shouldnt ($$) {
    unless($_[0] ne $_[1]) {
        require Carp;
        &Carp::confess( _fail_msg("'$_[0]' shouldn't be that!") );
    }
    return undef;
}

# Sorry, I couldn't resist.
sub shouldn't ($$) {     # emacs cperl-mode madness #' sub {
    my $env_ndebug = exists $ENV{PERL_NDEBUG} ? $ENV{PERL_NDEBUG}
                                              : $ENV{'NDEBUG'};
    if( $env_ndebug ) {
        return undef;
    }
    else {
        shouldnt($_[0], $_[1]);
    }
}

=back

=head1 Debugging vs Production

Because assertions are extra code and because it is sometimes necessary to
place them in 'hot' portions of your code where speed is paramount,
Carp::Assert provides the option to remove its assert() calls from your
program.

So, we provide a way to force Perl to inline the switched off assert()
routine, thereby removing almost all performance impact on your production
code.

    no Carp::Assert;  # assertions are off.
    assert(1==1) if DEBUG;

DEBUG is a constant set to 0.  Adding the 'if DEBUG' condition on your
assert() call gives perl the cue to go ahead and remove assert() call from
your program entirely, since the if conditional will always be false.

    # With C<no Carp::Assert> the assert() has no impact.
    for (1..100) {
        assert( do_some_really_time_consuming_check ) if DEBUG;
    }

If C<if DEBUG> gets too annoying, you can always use affirm().

    # Once again, affirm() has (almost) no impact with C<no Carp::Assert>
    for (1..100) {
        affirm { do_some_really_time_consuming_check };
    }

Another way to switch off all asserts, system wide, is to define the
NDEBUG or the PERL_NDEBUG environment variable.

You can safely leave out the "if DEBUG" part, but then your assert()
function will always execute (and its arguments evaluated and time
spent).  To get around this, use affirm().  You still have the
overhead of calling a function but at least its arguments will not be
evaluated.


=head1 Differences from ANSI C

assert() is intended to act like the function from ANSI C fame. 
Unfortunately, due to Perl's lack of macros or strong inlining, it's not
nearly as unobtrusive.

Well, the obvious one is the "if DEBUG" part.  This is cleanest way I could
think of to cause each assert() call and its arguments to be removed from
the program at compile-time, like the ANSI C macro does.

Also, this version of assert does not report the statement which
failed, just the line number and call frame via Carp::confess.  You
can't do C<assert('$a == $b')> because $a and $b will probably be
lexical, and thus unavailable to assert().  But with Perl, unlike C,
you always have the source to look through, so the need isn't as
great.


=head1 EFFICIENCY

With C<no Carp::Assert> (or NDEBUG) and using the C<if DEBUG> suffixes
on all your assertions, Carp::Assert has almost no impact on your
production code.  I say almost because it does still add some load-time
to your code (I've tried to reduce this as much as possible).

If you forget the C<if DEBUG> on an C<assert()>, C<should()> or
C<shouldnt()>, its arguments are still evaluated and thus will impact
your code.  You'll also have the extra overhead of calling a
subroutine (even if that subroutine does nothing).

Forgetting the C<if DEBUG> on an C<affirm()> is not so bad.  While you
still have the overhead of calling a subroutine (one that does
nothing) it will B<not> evaluate its code block and that can save
alot.

Try to remember the B<if DEBUG>.


=head1 ENVIRONMENT

=over 4

=item NDEBUG

Defining NDEBUG switches off all assertions.  It has the same effect
as changing "use Carp::Assert" to "no Carp::Assert" but it effects all
code.

=item PERL_NDEBUG

Same as NDEBUG and will override it.  Its provided to give you
something which won't conflict with any C programs you might be
working on at the same time.

=back


=head1 BUGS, CAVETS and other MUSINGS

Someday, Perl will have an inline pragma, and the C<if DEBUG>
bletcherousness will go away.

affirm() mucks with the expression's caller and it is run in an eval
so anything that checks $^S will be wrong.

Yes, there is a C<shouldn't> routine.  It mostly works, but you B<must>
put the C<if DEBUG> after it.

It would be nice if we could warn about missing C<if DEBUG>.


=head1 COPYRIGHT

Copyright 2002 by Michael G Schwern E<lt>schwern@pobox.comE<gt>.

This program is free software; you can redistribute it and/or 
modify it under the same terms as Perl itself.

See F<http://www.perl.com/perl/misc/Artistic.html>


=head1 AUTHOR

Michael G Schwern <schwern@pobox.com>

=cut

return q|You don't just EAT the largest turnip in the world!|;
