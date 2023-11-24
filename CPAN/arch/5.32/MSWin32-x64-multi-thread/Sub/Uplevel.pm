package Sub::Uplevel;
use 5.006;
use strict;
# ABSTRACT: apparently run a function in a higher stack frame

our $VERSION = '0.2800';

# Frame check global constant
our $CHECK_FRAMES;
BEGIN {
  $CHECK_FRAMES = !! $CHECK_FRAMES;
}
use constant CHECK_FRAMES => $CHECK_FRAMES;

# We must override *CORE::GLOBAL::caller if it hasn't already been 
# overridden or else Perl won't see our local override later.

if ( not defined *CORE::GLOBAL::caller{CODE} ) {
  *CORE::GLOBAL::caller = \&_normal_caller;
}

# modules to force reload if ":aggressive" is specified
my @reload_list = qw/Exporter Exporter::Heavy/;

sub import {
  no strict 'refs'; ## no critic
  my ($class, @args) = @_;
  for my $tag ( @args, 'uplevel' ) {
    if ( $tag eq 'uplevel' ) {
      my $caller = caller(0);
      *{"$caller\::uplevel"} = \&uplevel;
    }
    elsif( $tag eq ':aggressive' ) {
      _force_reload( @reload_list );
    }
    else {
      die qq{"$tag" is not exported by the $class module\n}
    }
  }
  return;
}

sub _force_reload {
  no warnings 'redefine';
  local $^W = 0;
  for my $m ( @_ ) {
    $m =~ s{::}{/}g;
    $m .= ".pm";
    require $m if delete $INC{$m};
  }
}

#pod =head1 SYNOPSIS
#pod
#pod   use Sub::Uplevel;
#pod
#pod   sub foo {
#pod       print join " - ", caller;
#pod   }
#pod
#pod   sub bar {
#pod       uplevel 1, \&foo;
#pod   }
#pod
#pod   #line 11
#pod   bar();    # main - foo.plx - 11
#pod
#pod =head1 DESCRIPTION
#pod
#pod Like Tcl's uplevel() function, but not quite so dangerous.  The idea
#pod is just to fool caller().  All the really naughty bits of Tcl's
#pod uplevel() are avoided.
#pod
#pod B<THIS IS NOT THE SORT OF THING YOU WANT TO DO EVERYDAY>
#pod
#pod =over 4
#pod
#pod =item B<uplevel>
#pod
#pod   uplevel $num_frames, \&func, @args;
#pod
#pod Makes the given function think it's being executed $num_frames higher
#pod than the current stack level.  So when they use caller($frames) it
#pod will actually give caller($frames + $num_frames) for them.
#pod
#pod C<uplevel(1, \&some_func, @_)> is effectively C<goto &some_func> but
#pod you don't immediately exit the current subroutine.  So while you can't
#pod do this:
#pod
#pod     sub wrapper {
#pod         print "Before\n";
#pod         goto &some_func;
#pod         print "After\n";
#pod     }
#pod
#pod you can do this:
#pod
#pod     sub wrapper {
#pod         print "Before\n";
#pod         my @out = uplevel 1, &some_func;
#pod         print "After\n";
#pod         return @out;
#pod     }
#pod
#pod C<uplevel> has the ability to issue a warning if C<$num_frames> is more than
#pod the current call stack depth, although this warning is disabled and compiled
#pod out by default as the check is relatively expensive.
#pod
#pod To enable the check for debugging or testing, you should set the global
#pod C<$Sub::Uplevel::CHECK_FRAMES> to true before loading Sub::Uplevel for the
#pod first time as follows:
#pod
#pod     #!/usr/bin/perl
#pod     
#pod     BEGIN {
#pod         $Sub::Uplevel::CHECK_FRAMES = 1;
#pod     }
#pod     use Sub::Uplevel;
#pod
#pod Setting or changing the global after the module has been loaded will have
#pod no effect.
#pod
#pod =cut

# @Up_Frames -- uplevel stack
# $Caller_Proxy -- whatever caller() override was in effect before uplevel
our (@Up_Frames, $Caller_Proxy);

sub _apparent_stack_height {
    my $height = 1; # start above this function 
    while ( 1 ) {
        last if ! defined scalar $Caller_Proxy->($height);
        $height++;
    }
    return $height - 1; # subtract 1 for this function
}

sub uplevel {
    # Backwards compatible version of "no warnings 'redefine'"
    my $old_W = $^W;
    $^W = 0;

    # Update the caller proxy if the uplevel override isn't in effect
    local $Caller_Proxy = *CORE::GLOBAL::caller{CODE}
        if *CORE::GLOBAL::caller{CODE} != \&_uplevel_caller;
    local *CORE::GLOBAL::caller = \&_uplevel_caller;

    # Restore old warnings state
    $^W = $old_W;

    if ( CHECK_FRAMES and $_[0] >= _apparent_stack_height() ) {
      require Carp;
      Carp::carp("uplevel $_[0] is more than the caller stack");
    }

    local @Up_Frames = (shift, @Up_Frames );

    my $function = shift;
    return $function->(@_);
}

sub _normal_caller (;$) { ## no critic Prototypes
    my ($height) = @_;
    $height++;
    my @caller = CORE::caller($height);
    if ( CORE::caller() eq 'DB' ) {
        # Oops, redo picking up @DB::args
        package DB;
        @caller = CORE::caller($height);
    }

    return if ! @caller;                  # empty
    return $caller[0] if ! wantarray;     # scalar context
    return @_ ? @caller : @caller[0..2];  # extra info or regular
}

sub _uplevel_caller (;$) { ## no critic Prototypes
    my $height = $_[0] || 0;

    # shortcut if no uplevels have been called
    # always add +1 to CORE::caller (proxy caller function)
    # to skip this function's caller
    return $Caller_Proxy->( $height + 1 ) if ! @Up_Frames;

#pod =begin _private
#pod
#pod So it has to work like this:
#pod
#pod     Call stack               Actual     uplevel 1
#pod CORE::GLOBAL::caller
#pod Carp::short_error_loc           0
#pod Carp::shortmess_heavy           1           0
#pod Carp::croak                     2           1
#pod try_croak                       3           2
#pod uplevel                         4            
#pod function_that_called_uplevel    5            
#pod caller_we_want_to_see           6           3
#pod its_caller                      7           4
#pod
#pod So when caller(X) winds up below uplevel(), it only has to use  
#pod CORE::caller(X+1) (to skip CORE::GLOBAL::caller).  But when caller(X)
#pod winds up no or above uplevel(), it's CORE::caller(X+1+uplevel+1).
#pod
#pod Which means I'm probably going to have to do something nasty like walk
#pod up the call stack on each caller() to see if I'm going to wind up   
#pod before or after Sub::Uplevel::uplevel().
#pod
#pod =end _private
#pod
#pod =begin _dagolden
#pod
#pod I found the description above a bit confusing.  Instead, this is the logic
#pod that I found clearer when CORE::GLOBAL::caller is invoked and we have to
#pod walk up the call stack:
#pod
#pod * if searching up to the requested height in the real call stack doesn't find
#pod a call to uplevel, then we can return the result at that height in the
#pod call stack
#pod
#pod * if we find a call to uplevel, we need to keep searching upwards beyond the
#pod requested height at least by the amount of upleveling requested for that
#pod call to uplevel (from the Up_Frames stack set during the uplevel call)
#pod
#pod * additionally, we need to hide the uplevel subroutine call, too, so we search
#pod upwards one more level for each call to uplevel
#pod
#pod * when we've reached the top of the search, we want to return that frame
#pod in the call stack, i.e. the requested height plus any uplevel adjustments
#pod found during the search
#pod
#pod =end _dagolden
#pod
#pod =cut

    my $saw_uplevel = 0;
    my $adjust = 0;

    # walk up the call stack to fight the right package level to return;
    # look one higher than requested for each call to uplevel found
    # and adjust by the amount found in the Up_Frames stack for that call.
    # We *must* use CORE::caller here since we need the real stack not what 
    # some other override says the stack looks like, just in case that other
    # override breaks things in some horrible way
    my $test_caller;
    for ( my $up = 0; $up <= $height + $adjust; $up++ ) {
        $test_caller = scalar CORE::caller($up + 1);
        if( $test_caller && $test_caller eq __PACKAGE__ ) {
            # add one for each uplevel call seen
            # and look into the uplevel stack for the offset
            $adjust += 1 + $Up_Frames[$saw_uplevel];
            $saw_uplevel++;
        }
    }

    # For returning values, we pass through the call to the proxy caller
    # function, just at a higher stack level
    my @caller = $Caller_Proxy->($height + $adjust + 1);
    if ( CORE::caller() eq 'DB' ) {
        # Oops, redo picking up @DB::args
        package DB;
        @caller = $Sub::Uplevel::Caller_Proxy->($height + $adjust + 1);
    }

    return if ! @caller;                  # empty
    return $caller[0] if ! wantarray;     # scalar context
    return @_ ? @caller : @caller[0..2];  # extra info or regular
}

#pod =back
#pod
#pod =head1 EXAMPLE
#pod
#pod The main reason I wrote this module is so I could write wrappers
#pod around functions and they wouldn't be aware they've been wrapped.
#pod
#pod     use Sub::Uplevel;
#pod
#pod     my $original_foo = \&foo;
#pod
#pod     *foo = sub {
#pod         my @output = uplevel 1, $original_foo;
#pod         print "foo() returned:  @output";
#pod         return @output;
#pod     };
#pod
#pod If this code frightens you B<you should not use this module.>
#pod
#pod
#pod =head1 BUGS and CAVEATS
#pod
#pod Well, the bad news is uplevel() is about 5 times slower than a normal
#pod function call.  XS implementation anyone?  It also slows down every invocation
#pod of caller(), regardless of whether uplevel() is in effect.
#pod
#pod Sub::Uplevel overrides CORE::GLOBAL::caller temporarily for the scope of
#pod each uplevel call.  It does its best to work with any previously existing
#pod CORE::GLOBAL::caller (both when Sub::Uplevel is first loaded and within 
#pod each uplevel call) such as from Contextual::Return or Hook::LexWrap.  
#pod
#pod However, if you are routinely using multiple modules that override 
#pod CORE::GLOBAL::caller, you are probably asking for trouble.
#pod
#pod You B<should> load Sub::Uplevel as early as possible within your program.  As
#pod with all CORE::GLOBAL overloading, the overload will not affect modules that
#pod have already been compiled prior to the overload.  One module that often is
#pod unavoidably loaded prior to Sub::Uplevel is Exporter.  To forcibly recompile
#pod Exporter (and Exporter::Heavy) after loading Sub::Uplevel, use it with the
#pod ":aggressive" tag:
#pod
#pod     use Sub::Uplevel qw/:aggressive/;
#pod
#pod The private function C<Sub::Uplevel::_force_reload()> may be passed a list of
#pod additional modules to reload if ":aggressive" is not aggressive enough.  
#pod Reloading modules may break things, so only use this as a last resort.
#pod
#pod As of version 0.20, Sub::Uplevel requires Perl 5.6 or greater.
#pod
#pod =head1 HISTORY
#pod
#pod Those who do not learn from HISTORY are doomed to repeat it.
#pod
#pod The lesson here is simple:  Don't sit next to a Tcl programmer at the
#pod dinner table.
#pod
#pod =head1 THANKS
#pod
#pod Thanks to Brent Welch, Damian Conway and Robin Houston.
#pod
#pod See http://www.perl.com/perl/misc/Artistic.html
#pod
#pod =head1 SEE ALSO
#pod
#pod PadWalker (for the similar idea with lexicals), Hook::LexWrap, 
#pod Tcl's uplevel() at http://www.scriptics.com/man/tcl8.4/TclCmd/uplevel.htm
#pod
#pod =cut

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Sub::Uplevel - apparently run a function in a higher stack frame

=head1 VERSION

version 0.2800

=head1 SYNOPSIS

  use Sub::Uplevel;

  sub foo {
      print join " - ", caller;
  }

  sub bar {
      uplevel 1, \&foo;
  }

  #line 11
  bar();    # main - foo.plx - 11

=head1 DESCRIPTION

Like Tcl's uplevel() function, but not quite so dangerous.  The idea
is just to fool caller().  All the really naughty bits of Tcl's
uplevel() are avoided.

B<THIS IS NOT THE SORT OF THING YOU WANT TO DO EVERYDAY>

=over 4

=item B<uplevel>

  uplevel $num_frames, \&func, @args;

Makes the given function think it's being executed $num_frames higher
than the current stack level.  So when they use caller($frames) it
will actually give caller($frames + $num_frames) for them.

C<uplevel(1, \&some_func, @_)> is effectively C<goto &some_func> but
you don't immediately exit the current subroutine.  So while you can't
do this:

    sub wrapper {
        print "Before\n";
        goto &some_func;
        print "After\n";
    }

you can do this:

    sub wrapper {
        print "Before\n";
        my @out = uplevel 1, &some_func;
        print "After\n";
        return @out;
    }

C<uplevel> has the ability to issue a warning if C<$num_frames> is more than
the current call stack depth, although this warning is disabled and compiled
out by default as the check is relatively expensive.

To enable the check for debugging or testing, you should set the global
C<$Sub::Uplevel::CHECK_FRAMES> to true before loading Sub::Uplevel for the
first time as follows:

    #!/usr/bin/perl
    
    BEGIN {
        $Sub::Uplevel::CHECK_FRAMES = 1;
    }
    use Sub::Uplevel;

Setting or changing the global after the module has been loaded will have
no effect.

=begin _private

So it has to work like this:

    Call stack               Actual     uplevel 1
CORE::GLOBAL::caller
Carp::short_error_loc           0
Carp::shortmess_heavy           1           0
Carp::croak                     2           1
try_croak                       3           2
uplevel                         4            
function_that_called_uplevel    5            
caller_we_want_to_see           6           3
its_caller                      7           4

So when caller(X) winds up below uplevel(), it only has to use  
CORE::caller(X+1) (to skip CORE::GLOBAL::caller).  But when caller(X)
winds up no or above uplevel(), it's CORE::caller(X+1+uplevel+1).

Which means I'm probably going to have to do something nasty like walk
up the call stack on each caller() to see if I'm going to wind up   
before or after Sub::Uplevel::uplevel().

=end _private

=begin _dagolden

I found the description above a bit confusing.  Instead, this is the logic
that I found clearer when CORE::GLOBAL::caller is invoked and we have to
walk up the call stack:

* if searching up to the requested height in the real call stack doesn't find
a call to uplevel, then we can return the result at that height in the
call stack

* if we find a call to uplevel, we need to keep searching upwards beyond the
requested height at least by the amount of upleveling requested for that
call to uplevel (from the Up_Frames stack set during the uplevel call)

* additionally, we need to hide the uplevel subroutine call, too, so we search
upwards one more level for each call to uplevel

* when we've reached the top of the search, we want to return that frame
in the call stack, i.e. the requested height plus any uplevel adjustments
found during the search

=end _dagolden

=back

=head1 EXAMPLE

The main reason I wrote this module is so I could write wrappers
around functions and they wouldn't be aware they've been wrapped.

    use Sub::Uplevel;

    my $original_foo = \&foo;

    *foo = sub {
        my @output = uplevel 1, $original_foo;
        print "foo() returned:  @output";
        return @output;
    };

If this code frightens you B<you should not use this module.>

=head1 BUGS and CAVEATS

Well, the bad news is uplevel() is about 5 times slower than a normal
function call.  XS implementation anyone?  It also slows down every invocation
of caller(), regardless of whether uplevel() is in effect.

Sub::Uplevel overrides CORE::GLOBAL::caller temporarily for the scope of
each uplevel call.  It does its best to work with any previously existing
CORE::GLOBAL::caller (both when Sub::Uplevel is first loaded and within 
each uplevel call) such as from Contextual::Return or Hook::LexWrap.  

However, if you are routinely using multiple modules that override 
CORE::GLOBAL::caller, you are probably asking for trouble.

You B<should> load Sub::Uplevel as early as possible within your program.  As
with all CORE::GLOBAL overloading, the overload will not affect modules that
have already been compiled prior to the overload.  One module that often is
unavoidably loaded prior to Sub::Uplevel is Exporter.  To forcibly recompile
Exporter (and Exporter::Heavy) after loading Sub::Uplevel, use it with the
":aggressive" tag:

    use Sub::Uplevel qw/:aggressive/;

The private function C<Sub::Uplevel::_force_reload()> may be passed a list of
additional modules to reload if ":aggressive" is not aggressive enough.  
Reloading modules may break things, so only use this as a last resort.

As of version 0.20, Sub::Uplevel requires Perl 5.6 or greater.

=head1 HISTORY

Those who do not learn from HISTORY are doomed to repeat it.

The lesson here is simple:  Don't sit next to a Tcl programmer at the
dinner table.

=head1 THANKS

Thanks to Brent Welch, Damian Conway and Robin Houston.

See http://www.perl.com/perl/misc/Artistic.html

=head1 SEE ALSO

PadWalker (for the similar idea with lexicals), Hook::LexWrap, 
Tcl's uplevel() at http://www.scriptics.com/man/tcl8.4/TclCmd/uplevel.htm

=for :stopwords cpan testmatrix url annocpan anno bugtracker rt cpants kwalitee diff irc mailto metadata placeholders metacpan

=head1 SUPPORT

=head2 Bugs / Feature Requests

Please report any bugs or feature requests through the issue tracker
at L<https://github.com/Perl-Toolchain-Gang/Sub-Uplevel/issues>.
You will be notified automatically of any progress on your issue.

=head2 Source Code

This is open source software.  The code repository is available for
public review and contribution under the terms of the license.

L<https://github.com/Perl-Toolchain-Gang/Sub-Uplevel>

  git clone https://github.com/Perl-Toolchain-Gang/Sub-Uplevel.git

=head1 AUTHORS

=over 4

=item *

Michael Schwern <mschwern@cpan.org>

=item *

David Golden <dagolden@cpan.org>

=back

=head1 CONTRIBUTORS

=for stopwords Adam Kennedy Alexandr Ciornii David Golden Graham Ollis J. Nick Koston Michael Gray

=over 4

=item *

Adam Kennedy <adamk@cpan.org>

=item *

Alexandr Ciornii <alexchorny@gmail.com>

=item *

David Golden <xdg@xdg.me>

=item *

Graham Ollis <plicease@cpan.org>

=item *

J. Nick Koston <nick@cpanel.net>

=item *

Michael Gray <mg13@sanger.ac.uk>

=back

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2017 by Michael Schwern and David Golden.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
