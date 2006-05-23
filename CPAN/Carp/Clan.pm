
##
## Based on Carp.pm from Perl 5.005_03.
## Last modified 12-Jun-2001 by Steffen Beyer.
## Should be reasonably backwards compatible.
##
## This module is free software and can
## be used, modified and redistributed
## under the same terms as Perl itself.
##

@DB::args = (); # Avoid warning "used only once" in Perl 5.003

package Carp::Clan;

use strict;
use vars qw( $MaxEvalLen $MaxArgLen $MaxArgNums $Verbose $VERSION );

# Original comments by Andy Wardley <abw@kfs.org> 09-Apr-1998.

# The $Max(EvalLen|(Arg(Len|Nums)) variables are used to specify how
# the eval text and function arguments should be formatted when printed.

$MaxEvalLen =  0;   # How much eval '...text...' to show. 0 = all.
$MaxArgLen  = 64;   # How much of each argument to print. 0 = all.
$MaxArgNums =  8;   # How many arguments to print.        0 = all.

$Verbose = 0;       # If true then make _shortmsg call _longmsg instead.

$VERSION = '5.3';

# _longmsg() crawls all the way up the stack reporting on all the function
# calls made. The error string, $error, is originally constructed from the
# arguments passed into _longmsg() via confess(), cluck() or _shortmsg().
# This gets appended with the stack trace messages which are generated for
# each function call on the stack.

sub _longmsg
{
    return(@_) if (ref $_[0]);
    local $^W = 0; # For cases when overloaded stringify returns undef
    local $_;      # Protect surrounding program - just in case...
    my($pack,$file,$line,$sub,$hargs,$eval,$require,@parms,$push);
    my $error = join('', @_);
    my $msg = '';
    my $i = 0;
    while ( do { { package DB; ($pack,$file,$line,$sub,$hargs,undef,$eval,$require) = caller($i++) } } )
    {
        next if ($pack eq 'Carp::Clan');
        if ($error eq '')
        {
            if (defined $eval)
            {
                $eval =~ s/([\\\'])/\\$1/g unless ($require); # Escape \ and '
                $eval =~ s/([\x00-\x1F\x7F-\xFF])/sprintf("\\x%02X",ord($1))/eg;
                substr($eval,$MaxEvalLen) = '...' if ($MaxEvalLen && length($eval) > $MaxEvalLen);
                if ($require)        { $sub = "require $eval"; }
                else                 { $sub = "eval '$eval'";  }
            }
            elsif ($sub eq '(eval)') { $sub = 'eval {...}';    }
            else
            {
                @parms = ();
                if ($hargs)
                {
                    $push = 0;
                    @parms = @DB::args; # We may trash some of the args so we take a copy
                    if ($MaxArgNums and @parms > $MaxArgNums)
                    {
                        $#parms = $MaxArgNums;
                        pop(@parms);
                        $push = 1;
                    }
                    for (@parms)
                    {
                        if (defined $_)
                        {
                            if (ref $_)
                            {
                                $_ = "$_"; # Beware of overloaded objects!
                            }
                            else
                            {
                                unless (/^-?\d+(?:\.\d+(?:[eE][+-]\d+)?)?$/) # Looks numeric
                                {
                                    s/([\\\'])/\\$1/g; # Escape \ and '
                                    s/([\x00-\x1F\x7F-\xFF])/sprintf("\\x%02X",ord($1))/eg;
                                    substr($_,$MaxArgLen) = '...' if ($MaxArgLen and length($_) > $MaxArgLen);
                                    $_ = "'$_'";
                                }
                            }
                        }
                        else { $_ = 'undef'; }
                    }
                    push(@parms, '...') if ($push);
                }
                $sub .= '(' . join(', ', @parms) . ')';
            }
            if ($msg eq '') { $msg = "$sub called"; }
            else            { $msg .= "\t$sub called"; }
        }
        else
        {
            if ($sub =~ /::/) { $msg = "$sub(): $error"; }
            else              { $msg = "$sub: $error";   }
        }
        $msg .= " at $file line $line\n" unless ($error =~ /\n$/);
        $error = '';
    }
    $msg ||= $error;
    $msg =~ tr/\0//d; # Circumvent die's incorrect handling of NUL characters
    $msg;
}

# _shortmsg() is called by carp() and croak() to skip all the way up to
# the top-level caller's package and report the error from there. confess()
# and cluck() generate a full stack trace so they call _longmsg() to
# generate that. In verbose mode _shortmsg() calls _longmsg() so you
# always get a stack trace.

sub _shortmsg
{
    my $pattern = shift;
    my $verbose = shift;
    return(@_) if (ref $_[0]);
    goto &_longmsg if ($Verbose or $verbose);
    my($pack,$file,$line,$sub);
    my $error = join('', @_);
    my $msg = '';
    my $i = 0;
    while (($pack,$file,$line,$sub) = caller($i++))
    {
        next if ($pack eq 'Carp::Clan' or $pack =~ /$pattern/);
        if    ($error eq '') { $msg = "$sub() called";  }
        elsif ($sub =~ /::/) { $msg = "$sub(): $error"; }
        else                 { $msg = "$sub: $error";   }
        $msg .= " at $file line $line\n" unless ($error =~ /\n$/);
        $msg =~ tr/\0//d; # Circumvent die's incorrect handling of NUL characters
        return $msg;
    }
    goto &_longmsg;
}

# The following four functions call _longmsg() or _shortmsg() depending on
# whether they should generate a full stack trace (confess() and cluck())
# or simply report the caller's package (croak() and carp()), respectively.
# confess() and croak() die, carp() and cluck() warn.

# Following code kept for calls with fully qualified subroutine names:
# (For backward compatibility with the original Carp.pm)

sub croak
{
    my $callpkg = caller(0);
    my $pattern = ($callpkg eq 'main') ? '^:::' : "^$callpkg\$";
    die _shortmsg($pattern, 0, @_);
}
sub confess { die _longmsg(@_); }
sub carp
{
    my $callpkg = caller(0);
    my $pattern = ($callpkg eq 'main') ? '^:::' : "^$callpkg\$";
    warn _shortmsg($pattern, 0, @_);
}
sub cluck { warn _longmsg(@_); }

# The following method imports a different closure for every caller.
# I.e., different modules can use this module at the same time
# and in parallel and still use different patterns.

sub import
{
    my $pkg     = shift;
    my $callpkg = caller(0);
    my $pattern = ($callpkg eq 'main') ? '^:::' : "^$callpkg\$";
    my $verbose = 0;
    my $item;
    my $file;

    for $item (@_)
    {
        if ($item =~ /^\d/)
        {
            if ($VERSION < $item)
            {
                $file = "$pkg.pm";
                $file =~ s!::!/!g;
                $file = $INC{$file};
                die _shortmsg('^:::', 0, "$pkg $item required--this is only version $VERSION ($file)");
            }
        }
        elsif ($item =~ /^verbose$/i) { $verbose = 1;     }
        else                          { $pattern = $item; }
    }
    # Speed up pattern matching in Perl versions >= 5.005:
    # (Uses "eval ''" because qr// is a syntax error in previous Perl versions)
    if ($] >= 5.005)
    {
        eval '$pattern = qr/$pattern/;';
    }
    else
    {
        eval { $pkg =~ /$pattern/; };
    }
    if ($@)
    {
        $@ =~ s/\s+$//;
        $@ =~ s/\s+at\s.+$//;
        die _shortmsg('^:::', 0, $@);
    }
    {
        local($^W) = 0;
        no strict "refs";
        *{"${callpkg}::croak"}   = sub { die  _shortmsg($pattern, $verbose, @_); };
        *{"${callpkg}::confess"} = sub { die  _longmsg (                    @_); };
        *{"${callpkg}::carp"}    = sub { warn _shortmsg($pattern, $verbose, @_); };
        *{"${callpkg}::cluck"}   = sub { warn _longmsg (                    @_); };
    }
}

1;

