package Sub::Uplevel;

use 5.006;
use strict;
our $VERSION = '0.22';
$VERSION = eval $VERSION;

# We must override *CORE::GLOBAL::caller if it hasn't already been 
# overridden or else Perl won't see our local override later.

if ( not defined *CORE::GLOBAL::caller{CODE} ) {
    *CORE::GLOBAL::caller = \&_normal_caller;
}

# modules to force reload if ":aggressive" is specified
my @reload_list = qw/Exporter Exporter::Heavy/;

sub import {
  no strict 'refs';
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
  
=head1 NAME

Sub::Uplevel - apparently run a function in a higher stack frame

=begin wikidoc

= VERSION

This documentation describes version %%VERSION%%

=end wikidoc

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

C<uplevel> will issue a warning if C<$num_frames> is more than the current call
stack depth.

=cut

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
    my($num_frames, $func, @args) = @_;
    
    # backwards compatible version of "no warnings 'redefine'"
    my $old_W = $^W;
    $^W = 0;

    # Update the caller proxy if the uplevel override isn't in effect
    local $Caller_Proxy = *CORE::GLOBAL::caller{CODE}
        if *CORE::GLOBAL::caller{CODE} != \&_uplevel_caller;
    local *CORE::GLOBAL::caller = \&_uplevel_caller;
    
    # restore old warnings state
    $^W = $old_W;

    if ( $num_frames >= _apparent_stack_height() ) {
      require Carp;
      Carp::carp("uplevel $num_frames is more than the caller stack");
    }

    local @Up_Frames = ($num_frames, @Up_Frames );
    
    return $func->(@args);
}

sub _normal_caller (;$) { ## no critic Prototypes
    my $height = $_[0];
    $height++;
    if ( CORE::caller() eq 'DB' ) {
        # passthrough the @DB::args trick
        package DB;
        if( wantarray and !@_ ) {
            return (CORE::caller($height))[0..2];
        }
        else {
            return CORE::caller($height);
        }
    }
    else {
        if( wantarray and !@_ ) {
            return (CORE::caller($height))[0..2];
        }
        else {
            return CORE::caller($height);
        }
    }
}

sub _uplevel_caller (;$) { ## no critic Prototypes
    my $height = $_[0] || 0;

    # shortcut if no uplevels have been called
    # always add +1 to CORE::caller (proxy caller function)
    # to skip this function's caller
    return $Caller_Proxy->( $height + 1 ) if ! @Up_Frames;

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
        
=cut

    my $saw_uplevel = 0;
    my $adjust = 0;

    # walk up the call stack to fight the right package level to return;
    # look one higher than requested for each call to uplevel found
    # and adjust by the amount found in the Up_Frames stack for that call.
    # We *must* use CORE::caller here since we need the real stack not what 
    # some other override says the stack looks like, just in case that other
    # override breaks things in some horrible way

    for ( my $up = 0; $up <= $height + $adjust; $up++ ) {
        my @caller = CORE::caller($up + 1); 
        if( defined $caller[0] && $caller[0] eq __PACKAGE__ ) {
            # add one for each uplevel call seen
            # and look into the uplevel stack for the offset
            $adjust += 1 + $Up_Frames[$saw_uplevel];
            $saw_uplevel++;
        }
    }

    # For returning values, we pass through the call to the proxy caller
    # function, just at a higher stack level
    my @caller;
    if ( CORE::caller() eq 'DB' ) {
        # passthrough the @DB::args trick
        package DB;
        @caller = $Sub::Uplevel::Caller_Proxy->($height + $adjust + 1);
    }
    else {
        @caller = $Caller_Proxy->($height + $adjust + 1);
    }

    if( wantarray ) {
        if( !@_ ) {
            @caller = @caller[0..2];
        }
        return @caller;
    }
    else {
        return $caller[0];
    }
}

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
unavoidably loaded prior to Sub::Uplevel is Exporter.  To forceably recompile
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

=head1 AUTHORS

David A Golden E<lt>dagolden@cpan.orgE<gt> (current maintainer)

Michael G Schwern E<lt>schwern@pobox.comE<gt> (original author)

=head1 LICENSE

Original code Copyright (c) 2001 to 2007 by Michael G Schwern.
Additional code Copyright (c) 2006 to 2008 by David A Golden.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=head1 SEE ALSO

PadWalker (for the similar idea with lexicals), Hook::LexWrap, 
Tcl's uplevel() at http://www.scriptics.com/man/tcl8.4/TclCmd/uplevel.htm

=cut

1;
