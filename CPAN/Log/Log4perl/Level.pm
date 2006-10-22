###############r###################################
package Log::Log4perl::Level;
##################################################

use 5.006;
use strict;
use warnings;
use Carp;

# log4j, for whatever reason, puts 0 as all and MAXINT as OFF.
# this seems less optimal, as more logging would imply a higher
# level. But oh well. Probably some brokenness that has persisted. :)
use constant ALL_INT   => 0;
use constant DEBUG_INT => 10000;
use constant INFO_INT  => 20000;
use constant WARN_INT  => 30000;
use constant ERROR_INT => 40000;
use constant FATAL_INT => 50000;
use constant OFF_INT   => (2 ** 31) - 1;

no strict qw(refs);
use vars qw(%PRIORITY %LEVELS %SYSLOG %L4P_TO_LD);

%PRIORITY = (); # unless (%PRIORITY);
%LEVELS = () unless (%LEVELS);
%SYSLOG = () unless (%SYSLOG);
%L4P_TO_LD = () unless (%L4P_TO_LD);

sub add_priority {
  my ($prio, $intval, $syslog, $log_dispatch_level) = @_;
  $prio = uc($prio); # just in case;

  $PRIORITY{$prio}    = $intval;
  $LEVELS{$intval}    = $prio;

  # Set up the mapping between Log4perl integer levels and 
  # Log::Dispatch levels
  # Note: Log::Dispatch uses the following levels:
  # 0 debug
  # 1 info
  # 2 notice
  # 3 warning
  # 4 error
  # 5 critical
  # 6 alert
  # 7 emergency

      # The equivalent Log::Dispatch level is optional, set it to 
      # the highest value (7=emerg) if it's not provided.
  $log_dispatch_level = 7 unless defined $log_dispatch_level;
  
  $L4P_TO_LD{$prio}  = $log_dispatch_level;

  $SYSLOG{$prio}      = $syslog if defined($syslog);
}

# create the basic priorities
add_priority("OFF",   OFF_INT,   -1, 7);
add_priority("FATAL", FATAL_INT,  0, 7);
add_priority("ERROR", ERROR_INT,  3, 4);
add_priority("WARN",  WARN_INT,   4, 3);
add_priority("INFO",  INFO_INT,   6, 1);
add_priority("DEBUG", DEBUG_INT,  7, 0);
add_priority("ALL",   ALL_INT,    7, 0);

# we often sort numerically, so a helper func for readability
sub numerically {$a <=> $b}

###########################################
sub import {
###########################################
    my($class, $namespace) = @_;
           
    if(defined $namespace) {
        # Export $OFF, $FATAL, $ERROR etc. to
        # the given namespace
        $namespace .= "::" unless $namespace =~ /::$/;
    } else {
        # Export $OFF, $FATAL, $ERROR etc. to
        # the caller's namespace
        $namespace = caller(0) . "::";
    }

    for my $key (keys %PRIORITY) {
        my $name  = "$namespace$key";
        my $value = $PRIORITY{$key};
        *{"$name"} = \$value;
	my $nameint = "$namespace${key}_INT";
	my $func = uc($key) . "_INT";
	*{"$nameint"} = \&$func;
    }
}

##################################################
sub new { 
##################################################
    # We don't need any of this class nonsense
    # in Perl, because we won't allow subclassing
    # from this. We're optimizing for raw speed.
}

##################################################
sub to_priority {
# changes a level name string to a priority numeric
##################################################
    my($string) = @_;

    if(exists $PRIORITY{$string}) {
        return $PRIORITY{$string};
    }else{
        croak "level '$string' is not a valid error level (".join ('|', keys %PRIORITY),')';
    }
}

##################################################
sub to_level {
# changes a priority numeric constant to a level name string 
##################################################
    my ($priority) = @_;
    if (exists $LEVELS{$priority}) {
        return $LEVELS{$priority}
    }else {
      croak("priority '$priority' is not a valid error level number (",
	  join("|", sort numerically keys %LEVELS), "
          )");
    }

}

##################################################
sub to_LogDispatch_string {
# translates into strings that Log::Dispatch recognizes
##################################################
    my($priority) = @_;

    confess "do what? no priority?" unless defined $priority;

    my $string;

    if(exists $LEVELS{$priority}) {
        $string = $LEVELS{$priority};
    }

        # Log::Dispatch idiosyncrasies
    if($priority == $PRIORITY{WARN}) {
        $string = "WARNING";
    }
         
    if($priority == $PRIORITY{FATAL}) {
        $string = "EMERGENCY";
    }
         
    return $string;
}

###################################################
sub is_valid {
###################################################
    my $q = shift;

    if ($q =~ /[A-Z]/) {
        return exists $PRIORITY{$q};
    }else{
        return $LEVELS{$q};
    }
    
}

sub get_higher_level {
    my ($old_priority, $delta) = @_;

    $delta ||= 1;

    my $new_priority = 0;

    foreach (1..$delta){
        #so the list is DEBUG, INFO, WARN, ERROR, FATAL
      # but remember, the numbers go in reverse order!
        foreach my $p (sort numerically keys %LEVELS){
            if ($p > $old_priority) {
                $new_priority = $p;
                last;
            }
        }
        $old_priority = $new_priority;
    }
    return $new_priority;
}

sub get_lower_level {
    my ($old_priority, $delta) = @_;

    $delta ||= 1;

    my $new_priority = 0;

    foreach (1..$delta){
        #so the list is FATAL, ERROR, WARN, INFO, DEBUG
      # but remember, the numbers go in reverse order!
        foreach my $p (reverse sort numerically keys %LEVELS){
            if ($p < $old_priority) {
                $new_priority = $p;
                last;
            }
        }
        $old_priority = $new_priority;
    }
    return $new_priority;
}

sub isGreaterOrEqual {
  my $lval = shift;
  my $rval = shift;
  
  # in theory, we should check if the above really ARE valid levels.
  # but we just use numeric comparison, since they aren't really classes.

  # oh, yeah, and 'cuz level ints go from 0 .. N with 0 being highest,
  # these are reversed.
  return $lval <= $rval;
}

######################################################################
# 
# since the integer representation of levels is reversed from what
# we normally want, we don't want to use < and >... instead, we
# want to use this comparison function


1;

__END__

=head1 NAME

Log::Log4perl::Level - Predefined log levels

=head1 SYNOPSIS

  use Log::Log4perl::Level;
  print $ERROR, "\n";

  # -- or --

  use Log::Log4perl qw(:levels);
  print $ERROR, "\n";

=head1 DESCRIPTION

C<Log::Log4perl::Level> simply exports a predefined set of I<Log4perl> log
levels into the caller's name space. It is used internally by 
C<Log::Log4perl>. The following scalars are defined:

    $OFF
    $FATAL
    $ERROR
    $WARN
    $INFO
    $DEBUG
    $ALL

C<Log::Log4perl> also exports these constants into the caller's namespace
if you pull it in providing the C<:levels> tag:

    use Log::Log4perl qw(:levels);

This is the preferred way, there's usually no need to call 
C<Log::Log4perl::Level> explicitely.

The numerical values assigned to these constants are purely virtual,
only used by Log::Log4perl internally and can change at any time,
so please don't make any assumptions.

If the caller wants to import these constants into a different namespace,
it can be provided with the C<use> command:

    use Log::Log4perl::Level qw(MyNameSpace);

After this C<$MyNameSpace::ERROR>, C<$MyNameSpace::INFO> etc. 
will be defined accordingly.

=head1 SEE ALSO

=head1 AUTHOR

Mike Schilli, E<lt>m@perlmeister.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2002 by Mike Schilli

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
