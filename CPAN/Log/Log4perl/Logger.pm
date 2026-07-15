##################################################
package Log::Log4perl::Logger;
##################################################

use 5.006;
use strict;
use warnings;

use Log::Log4perl;
use Log::Log4perl::Level;
use Log::Log4perl::Layout;
use Log::Log4perl::Appender;
use Log::Log4perl::Appender::String;
use Log::Log4perl::Filter;
use Carp;

$Carp::Internal{"Log::Log4perl"}++;
$Carp::Internal{"Log::Log4perl::Logger"}++;

use constant _INTERNAL_DEBUG => 0;

    # Initialization
our $ROOT_LOGGER;
our $LOGGERS_BY_NAME = {};
our %APPENDER_BY_NAME = ();
our $INITIALIZED = 0;
our $NON_INIT_WARNED;
our $DIE_DEBUG = 0;
our $DIE_DEBUG_BUFFER = "";
    # Define the default appender that's used for formatting
    # warn/die/croak etc. messages.
our $STRING_APP_NAME = "_l4p_warn";
our $STRING_APP      = Log::Log4perl::Appender->new(
                          "Log::Log4perl::Appender::String",
                          name => $STRING_APP_NAME);
$STRING_APP->layout(Log::Log4perl::Layout::PatternLayout->new("%m"));
our $STRING_APP_CODEREF = generate_coderef([[$STRING_APP_NAME, $STRING_APP]]);

__PACKAGE__->reset();

###########################################
sub warning_render {
###########################################
    my($logger, @message) = @_;

    $STRING_APP->string("");
    $STRING_APP_CODEREF->($logger, 
                          @message, 
                          Log::Log4perl::Level::to_level($ALL));
    return $STRING_APP->string();
}

##################################################
sub cleanup {
##################################################
    # warn "Logger cleanup";

    # Nuke all convenience loggers to avoid them causing cleanup to 
    # be delayed until global destruction. Problem is that something like
    #     *{"DEBUG"} = sub { $logger->debug };
    # ties up a reference to $logger until global destruction, so we 
    # need to clean up all :easy shortcuts, hence freeing the last
    # logger references, to then rely on the garbage collector for cleaning
    # up the loggers.
    Log::Log4perl->easy_closure_global_cleanup();

    # Delete all loggers
    $LOGGERS_BY_NAME = {};

    # Delete the root logger
    undef $ROOT_LOGGER;

    # Delete all appenders
    %APPENDER_BY_NAME   = ();

    undef $INITIALIZED;
}

##################################################
sub DESTROY {
##################################################
    CORE::warn "Destroying logger $_[0] ($_[0]->{category})" 
            if $Log::Log4perl::CHATTY_DESTROY_METHODS;
}

##################################################
sub reset {
##################################################
    $ROOT_LOGGER        = __PACKAGE__->_new("", $OFF);
#    $LOGGERS_BY_NAME    = {};  #leave this alone, it's used by 
                                #reset_all_output_methods when 
                                #the config changes

    %APPENDER_BY_NAME   = ();
    undef $INITIALIZED;
    undef $NON_INIT_WARNED;
    Log::Log4perl::Appender::reset();

    #clear out all the existing appenders
    foreach my $logger (values %$LOGGERS_BY_NAME){
        $logger->{appender_names} = [];

	#this next bit deals with an init_and_watch case where a category
	#is deleted from the config file, we need to zero out the existing
	#loggers so ones not in the config file not continue with their old
	#behavior --kg
        next if $logger eq $ROOT_LOGGER;
        $logger->{level} = undef;
        $logger->level();  #set it from the hierarchy
    }

    # Clear all filters
    Log::Log4perl::Filter::reset();
}

##################################################
sub _new {
##################################################
    my($class, $category, $level) = @_;

    print("_new: $class/$category/", defined $level ? $level : "undef",
          "\n") if _INTERNAL_DEBUG;

    die "usage: __PACKAGE__->_new(category)" unless
        defined $category;
    
    $category  =~ s/::/./g;

       # Have we created it previously?
    if(exists $LOGGERS_BY_NAME->{$category}) {
        print "_new: exists already\n" if _INTERNAL_DEBUG;
        return $LOGGERS_BY_NAME->{$category};
    }

    my $self  = {
        category  => $category,
        num_appenders => 0,
        additivity    => 1,
        level         => $level,
        layout        => undef,
                };

   bless $self, $class;

   $level ||= $self->level();

        # Save it in global structure
   $LOGGERS_BY_NAME->{$category} = $self;

   $self->set_output_methods;

   print("Created logger $self ($category)\n") if _INTERNAL_DEBUG;

   return $self;
}

##################################################
sub category {
##################################################
   my ($self) = @_;

   return $self->{ category };
}

##################################################
sub reset_all_output_methods {
##################################################
    print "reset_all_output_methods: \n" if _INTERNAL_DEBUG;

    foreach my $loggername ( keys %$LOGGERS_BY_NAME){
        $LOGGERS_BY_NAME->{$loggername}->set_output_methods;
    }
    $ROOT_LOGGER->set_output_methods;
}

##################################################
sub set_output_methods {
# Here's a big performance increase.  Instead of having the logger
# calculate whether to log and whom to log to every time log() is called,
# we calculate it once when the logger is created, and recalculate
# it if the config information ever changes.
#
##################################################
   my ($self) = @_;
    
   my (@appenders, %seen);

   my ($level) = $self->level();

   print "set_output_methods: $self->{category}/$level\n" if _INTERNAL_DEBUG;

   #collect the appenders in effect for this category    

   for(my $logger = $self; $logger; $logger = parent_logger($logger)) {

        foreach my $appender_name (@{$logger->{appender_names}}){

                #only one message per appender, (configurable)
            next if $seen{$appender_name} ++ && 
                    $Log::Log4perl::one_message_per_appender;

            push (@appenders,     
                   [$appender_name,
                    $APPENDER_BY_NAME{$appender_name},
                   ]
            );
        }
        last unless $logger->{additivity};
    }

        #make a no-op coderef for inactive levels
    my $noop = generate_noop_coderef();

       #make a coderef
    my $coderef = (! @appenders ? $noop : &generate_coderef(\@appenders)); 

    my %priority = %Log::Log4perl::Level::PRIORITY; #convenience and cvs

   # changed to >= from <= as level ints were reversed
    foreach my $levelname (keys %priority){
        if (Log::Log4perl::Level::isGreaterOrEqual($level,
						   $priority{$levelname}
						   )) {
            print "  ($priority{$levelname} <= $level)\n"
                  if _INTERNAL_DEBUG;
            $self->{$levelname}      = $coderef;
            $self->{"is_$levelname"} = generate_is_xxx_coderef("1");
            print "Setting is_$levelname to 1\n" if _INTERNAL_DEBUG;
        }else{
            print "  ($priority{$levelname} > $level)\n" if _INTERNAL_DEBUG;
            $self->{$levelname}      = $noop;
            $self->{"is_$levelname"} = generate_is_xxx_coderef("0");
            print "Setting is_$levelname to 0\n" if _INTERNAL_DEBUG;
        }

        print("  Setting [$self] $self->{category}.$levelname to ",
              ($self->{$levelname} == $noop ? "NOOP" : 
              ("Coderef [$coderef]: " . scalar @appenders . " appenders")), 
              "\n") if _INTERNAL_DEBUG;
    }
}

##################################################
sub generate_coderef {
##################################################
    my $appenders = shift;
                    
    print "generate_coderef: ", scalar @$appenders, 
          " appenders\n" if _INTERNAL_DEBUG;

    my $watch_check_code = generate_watch_code("logger", 1);

    return sub {
      my $logger = shift;
      my $level  = pop;

      my $message;
      my $appenders_fired = 0;
      
      # Evaluate all parameters that need to be evaluated. Two kinds:
      #
      # (1) It's a hash like { filter => "filtername",
      #                        value  => "value" }
      #     => filtername(value)
      #
      # (2) It's a code ref
      #     => coderef()
      #

      $message   = [map { ref $_ eq "HASH" && 
                           exists $_->{filter} && 
                           ref $_->{filter} eq 'CODE' ?
                               $_->{filter}->($_->{value}) :
                           ref $_ eq "CODE" ?
                               $_->() : $_ 
                          } @_];                  

      print("coderef: $logger->{category}\n") if _INTERNAL_DEBUG;

      if(defined $Log::Log4perl::Config::WATCHER) {
          return unless $watch_check_code->($logger, @_, $level);
      }

      foreach my $a (@$appenders) {   #note the closure here
          my ($appender_name, $appender) = @$a;

          print("  Sending message '<$message->[0]>' ($level) " .
                "to $appender_name\n") if _INTERNAL_DEBUG;
                
          $appender->log(
              #these get passed through to Log::Dispatch
              { name    => $appender_name,
                level   => $Log::Log4perl::Level::L4P_TO_LD{
                               $level},   
                message => $message,
              },
              #these we need
              $logger->{category},
              $level,
          ) and $appenders_fired++;
              # Only counting it if it returns a true value. Otherwise
              # the appender threshold might have suppressed it after all.
    
      } #end foreach appenders
    
      return $appenders_fired;

    }; #end coderef
}

##################################################
sub generate_noop_coderef {
##################################################
    my $watch_delay_code;

    # This might seem crazy at first, but even in a Log4perl noop, we
    # need to check if the configuration changed in a init_and_watch 
    # situation. Why? Say, an application is running in a loop that
    # constantly tries to issue debug() messages, but they're suppressed by
    # the current Log4perl configuration. If debug() (which is a noop
    # here) wasn't watching the configuration for changes, it would never
    # catch the case where someone bumps up the log level and expects
    # the application to pick it up and start logging debug() statements.

    my $watch_check_code = generate_watch_code("logger", 1);

    my $coderef;

    if(defined $Log::Log4perl::Config::WATCHER) {
        $coderef = $watch_check_code;
    } else {
        $coderef = sub { undef };
    }

    return $coderef;
}

##################################################
sub generate_is_xxx_coderef {
##################################################
    my($return_token) = @_;

    return generate_watch_code("checker", $return_token);
}

##################################################
sub generate_watch_code {
##################################################
    my($type, $return_token) = @_;

    print "generate_watch_code:\n" if _INTERNAL_DEBUG;

      # No watcher configured, return a no-op as watch code.
    if(! defined $Log::Log4perl::Config::WATCHER) {
        return sub { $return_token };
    }

    my $cond = generate_watch_conditional();

    return sub {
        print "exe_watch_code:\n" if _INTERNAL_DEBUG;

       if(_INTERNAL_DEBUG) {
           print "Next check: ",
             "$Log::Log4perl::Config::Watch::NEXT_CHECK_TIME ",
             " Now: ", time(), " Mod: ",
             (stat($Log::Log4perl::Config::WATCHER->file()))[9],
             "\n";
       }

       if( $cond->() ) {
           my $init_permitted = 1;

           if(exists $Log::Log4perl::Config::OPTS->{ preinit_callback } ) {
               print "Calling preinit_callback\n" if _INTERNAL_DEBUG;
               $init_permitted = 
               $Log::Log4perl::Config::OPTS->{ preinit_callback }->( 
                   Log::Log4perl::Config->watcher()->file() );
               print "Callback returned $init_permitted\n" if _INTERNAL_DEBUG;
           }

           if( $init_permitted ) {
               Log::Log4perl->init_and_watch();
           } else {
               # It was time to reinit, but init wasn't permitted.
               # Return true, so that the logger continues as if
               # it wasn't time to reinit.
               return 1;
           }

           my $logger = shift;
           my $level  = pop;

           # Forward call to new configuration
           if($type eq "checker") {
               return $logger->$level();

           } elsif( $type eq "logger") {
               my $methodname = lc($level);

               # Bump up the caller level by three, since
               # we've artificially introduced additional levels.
               local $Log::Log4perl::caller_depth =
                     $Log::Log4perl::caller_depth + 3;

               # Get a new logger for the same category (the old
               # logger might be obsolete because of the re-init)
               $logger = Log::Log4perl::get_logger( $logger->{category} );

               $logger->$methodname(@_); # send the message
               # to the new configuration
               return undef;     # Return false, so the logger finishes
               # prematurely and doesn't log the same 
               # message again.
           } else {
               die "internal error: unknown type";
           }
       } else {
           if(_INTERNAL_DEBUG) {
               print "Conditional returned false\n";
           }
           return $return_token;
       }
   };
}

##################################################
sub generate_watch_conditional {
##################################################

    if(defined $Log::Log4perl::Config::Watch::SIGNAL_CAUGHT) {
        # In this mode, we just check for the variable indicating
        # that the signal has been caught
        return sub {
            return $Log::Log4perl::Config::Watch::SIGNAL_CAUGHT;
        };
    }

    return sub {
        return 
            ( time() > $Log::Log4perl::Config::Watch::NEXT_CHECK_TIME and 
              $Log::Log4perl::Config::WATCHER->change_detected() );
    };
}

##################################################
sub parent_string {
##################################################
    my($string) = @_;

    if($string eq "") {
        return undef; # root doesn't have a parent.
    }

    my @components = split /\./, $string;
    
    if(@components == 1) {
        return "";
    }

    pop @components;

    return join('.', @components);
}

##################################################
sub level {
##################################################
    my($self, $level, $dont_reset_all) = @_;

        # 'Set' function
    if(defined $level) {
        croak "invalid level '$level'" 
                unless Log::Log4perl::Level::is_valid($level);
        if ($level =~ /\D/){
            $level = Log::Log4perl::Level::to_priority($level);
        }
        $self->{level} = $level;   

        &reset_all_output_methods
            unless $dont_reset_all;  #keep us from getting overworked 
                                     #if it's the config file calling us 

        return $level;
    }

        # 'Get' function
    if(defined $self->{level}) {
        return $self->{level};
    }

    for(my $logger = $self; $logger; $logger = parent_logger($logger)) {

        # Does the current logger have the level defined?

        if($logger->{category} eq "") {
            # It's the root logger
            return $ROOT_LOGGER->{level};
        }
            
        if(defined $LOGGERS_BY_NAME->{$logger->{category}}->{level}) {
            return $LOGGERS_BY_NAME->{$logger->{category}}->{level};
        }
    }

    # We should never get here because at least the root logger should
    # have a level defined
    die "We should never get here.";
}

##################################################
sub parent_logger {
# Get the parent of the current logger or undef
##################################################
    my($logger) = @_;

        # Is it the root logger?
    if($logger->{category} eq "") {
        # Root has no parent
        return undef;
    }

        # Go to the next defined (!) parent
    my $parent_class = parent_string($logger->{category});

    while($parent_class ne "" and
          ! exists $LOGGERS_BY_NAME->{$parent_class}) {
        $parent_class = parent_string($parent_class);
        $logger =  $LOGGERS_BY_NAME->{$parent_class};
    }

    if($parent_class eq "") {
        $logger = $ROOT_LOGGER;
    } else {
        $logger = $LOGGERS_BY_NAME->{$parent_class};
    }

    return $logger;
}

##################################################
sub get_root_logger {
##################################################
    my($class) = @_;
    return $ROOT_LOGGER;    
}

##################################################
sub additivity {
##################################################
    my($self, $onoff, $no_reinit) = @_;

    if(defined $onoff) {
        $self->{additivity} = $onoff;
    }

    if( ! $no_reinit ) {
        $self->set_output_methods();
    }

    return $self->{additivity};
}

##################################################
sub get_logger {
##################################################
    my($class, $category) = @_;

    unless(defined $ROOT_LOGGER) {
        Carp::confess "Internal error: Root Logger not initialized.";
    }

    return $ROOT_LOGGER if $category eq "";

    my $logger = $class->_new($category);
    return $logger;
}

##################################################
sub add_appender {
##################################################
    my($self, $appender, $dont_reset_all) = @_;

        # We take this as an indicator that we're initialized.
    $INITIALIZED = 1;

    my $appender_name = $appender->name();

    $self->{num_appenders}++;  #should this be inside the unless?

      # Add newly created appender to the end of the appender array
    unless (grep{$_ eq $appender_name} @{$self->{appender_names}}){
        $self->{appender_names} = [sort @{$self->{appender_names}}, 
                                        $appender_name];
    }

    $APPENDER_BY_NAME{$appender_name} = $appender;

    reset_all_output_methods
                unless $dont_reset_all;  # keep us from getting overworked
                                         # if it's  the config file calling us

        # For chaining calls ...
    return $appender;
}

##################################################
sub remove_appender {
##################################################
    my($self, $appender_name, $dont_reset_all, $sloppy) = @_;

    my %appender_names = map { $_ => 1 } @{$self->{appender_names}};
    
    if(!exists $appender_names{$appender_name}) {
        die "No such appender: $appender_name" unless $sloppy;
        return undef;
    }

    delete $appender_names{$appender_name};
    $self->{num_appenders}--;
    $self->{appender_names} = [sort keys %appender_names];

    &reset_all_output_methods
                unless $dont_reset_all; 
}

##################################################
sub eradicate_appender {
##################################################
        # If someone calls Logger->... and not Logger::...
    shift if $_[0] eq __PACKAGE__;

    my($appender_name, $dont_reset_all) = @_;

    return 0 unless exists 
        $APPENDER_BY_NAME{$appender_name};

        # Remove the given appender from all loggers
        # and delete all references to it, causing
        # its DESTROY method to be called.
    foreach my $logger (values %$LOGGERS_BY_NAME){
        $logger->remove_appender($appender_name, 0, 1);
    }
        # Also remove it from the root logger
    $ROOT_LOGGER->remove_appender($appender_name, 0, 1);
    
    delete $APPENDER_BY_NAME{$appender_name};

    &reset_all_output_methods
                unless $dont_reset_all; 

    return 1;
}

##################################################
sub has_appenders {
##################################################
    my($self) = @_;

    return $self->{num_appenders};
}

##################################################
sub log {
# external api
##################################################
    my ($self, $priority, @messages) = @_;

    confess("log: No priority given!") unless defined($priority);

       # Just in case of 'init_and_watch' -- see Changes 0.21
    $_[0] = $LOGGERS_BY_NAME->{$_[0]->{category}} if 
        defined $Log::Log4perl::Config::WATCHER;

    init_warn() unless $INITIALIZED or $NON_INIT_WARNED;

    croak "priority $priority isn't numeric" if ($priority =~ /\D/);

    my $which = Log::Log4perl::Level::to_level($priority);

    $self->{$which}->($self, @messages, 
                    Log::Log4perl::Level::to_level($priority));
}

######################################################################
#
# create_custom_level 
# creates a custom level
# in theory, could be used to create the default ones
######################################################################
sub create_custom_level {
######################################################################
  my $level = shift || die("create_custom_level: " .
                           "forgot to pass in a level string!");
  my $after = shift || die("create_custom_level: " .
                           "forgot to pass in a level after which to " .
                           "place the new level!");
  my $syslog_equiv = shift; # can be undef
  my $log_dispatch_level = shift; # optional

  ## only let users create custom levels before initialization

  die("create_custom_level must be called before init or " .
      "first get_logger() call") if ($INITIALIZED);

  my %PRIORITY = %Log::Log4perl::Level::PRIORITY; #convenience

  die("create_custom_level: no such level \"$after\"! Use one of: ", 
     join(", ", sort keys %PRIORITY)) unless $PRIORITY{$after};

  # figure out new int value by AFTER + (AFTER+ 1) / 2

  my $next_prio = Log::Log4perl::Level::get_lower_level($PRIORITY{$after}, 1);
  my $cust_prio = int(($PRIORITY{$after} + $next_prio) / 2);

  die(qq{create_custom_level: Calculated level of $cust_prio already exists!
      This should only happen if you've made some insane number of custom
      levels (like 15 one after another)
      You can usually fix this by re-arranging your code from:
      create_custom_level("cust1", X);
      create_custom_level("cust2", X);
      create_custom_level("cust3", X);
      create_custom_level("cust4", X);
      create_custom_level("cust5", X);
      into:
      create_custom_level("cust3", X);
      create_custom_level("cust5", X);
      create_custom_level("cust4", 4);
      create_custom_level("cust2", cust3);
      create_custom_level("cust1", cust2);
   }) if (${Log::Log4perl::Level::LEVELS{$cust_prio}});

  Log::Log4perl::Level::add_priority($level, $cust_prio, $syslog_equiv,
                                     $log_dispatch_level);

  print("Adding prio $level at $cust_prio\n") if _INTERNAL_DEBUG;

  # get $LEVEL into namespace of Log::Log4perl::Logger to 
  # create $logger->foo nd $logger->is_foo
  my $name = "Log::Log4perl::Logger::";
  my $key = $level;

  no strict qw(refs);
  # be sure to use ${Log...} as CVS adds log entries for Log
  *{"$name$key"} = \${Log::Log4perl::Level::PRIORITY{$level}};

  # now, stick it in the caller's namespace
  $name = caller(0) . "::";
  *{"$name$key"} = \${Log::Log4perl::Level::PRIORITY{$level}};
  use strict qw(refs);

  create_log_level_methods($level);

  return 0;

}

########################################
#
# if we were hackin' lisp (or scheme), we'd be returning some lambda
# expressions. But we aren't. :) So we'll just create some strings and
# eval them.
########################################
sub create_log_level_methods {
########################################
  my $level = shift || die("create_log_level_methods: " .
                           "forgot to pass in a level string!");
  my $lclevel = lc($level);
  my $levelint = uc($level) . "_INT";
  my $initial_cap = ucfirst($lclevel);

  no strict qw(refs);

  # This is a bit better way to create code on the fly than eval'ing strings.
  # -erik

  *{__PACKAGE__ . "::$lclevel"} = sub {
        if(_INTERNAL_DEBUG) {
            my $level_disp = (defined $_[0]->{level} ? $_[0]->{level} 
                                                     : "[undef]");
            print "$lclevel: ($_[0]->{category}/$level_disp) [@_]\n";
        }
        init_warn() unless $INITIALIZED or $NON_INIT_WARNED;
        $_[0]->{$level}->(@_, $level) if defined $_[0]->{$level};
     };

  # Added these to have is_xxx functions as fast as xxx functions
  # -ms
  
  my $islevel   = "is_" . $level;
  my $islclevel = "is_" . $lclevel;

  *{__PACKAGE__ . "::is_$lclevel"} = sub {
      $_[0]->{$islevel}->($_[0], $islclevel);
  };
  
  # Add the isXxxEnabled() methods as identical to the is_xxx
  # functions. - dviner
  
  *{__PACKAGE__ . "::is".$initial_cap."Enabled"} = 
                           \&{__PACKAGE__ . "::is_$lclevel"};
  
  use strict qw(refs);

  return 0;
}

#now lets autogenerate the logger subs based on the defined priorities
foreach my $level (keys %Log::Log4perl::Level::PRIORITY){
  create_log_level_methods($level);
}

##################################################
sub init_warn {
##################################################
    CORE::warn "Log4perl: Seems like no initialization happened. " .
               "Forgot to call init()?\n";
    # Only tell this once;
    $NON_INIT_WARNED = 1;
}

#######################################################
# call me from a sub-func to spew the sub-func's caller
#######################################################
sub callerline {
  my $message = join ('', @_);

  my $caller_offset = 
    Log::Log4perl::caller_depth_offset( 
        $Log::Log4perl::caller_depth + 1 );

  my ($pack, $file, $line) = caller($caller_offset);

  if (not chomp $message) {     # no newline
    $message .= " at $file line $line";

    # Someday, we'll use Threads. Really.
    if (defined &Thread::tid) {
      my $tid = Thread->self->tid;
      $message .= " thread $tid" if $tid;
    }
  }

  return ($message, "\n");
}

#######################################################
sub and_warn {
#######################################################
  my $self = shift;
  CORE::warn(callerline($self->warning_render(@_)));
}

#######################################################
sub and_die {
#######################################################
  my $self = shift;
  my $arg  = $_[0];

  my($msg) = callerline($self->warning_render(@_));

  if($DIE_DEBUG) {
      $DIE_DEBUG_BUFFER = "DIE_DEBUG: $msg";
  } else {
      if( $Log::Log4perl::STRINGIFY_DIE_MESSAGE ) {
          die("$msg\n");
      }
      die $arg;
  }
}

##################################################
sub logwarn {
##################################################
  my $self = shift;

  local $Log::Log4perl::caller_depth = 
        $Log::Log4perl::caller_depth + 1;

  if ($self->is_warn()) {
        # Since we're one caller level off now, compensate for that.
    my @chomped = @_;
    chomp($chomped[-1]);
    $self->warn(@chomped);
  }

  $self->and_warn(@_);
}

##################################################
sub logdie {
##################################################
  my $self = shift;

  local $Log::Log4perl::caller_depth = 
        $Log::Log4perl::caller_depth + 1;

  if ($self->is_fatal()) {
        # Since we're one caller level off now, compensate for that.
    my @chomped = @_;
    chomp($chomped[-1]);
    $self->fatal(@chomped);
  }

  $Log::Log4perl::LOGDIE_MESSAGE_ON_STDERR ? 
      $self->and_die(@_) : 
        exit($Log::Log4perl::LOGEXIT_CODE);
}

##################################################
sub logexit {
##################################################
  my $self = shift;

  local $Log::Log4perl::caller_depth = 
        $Log::Log4perl::caller_depth + 1;

  if ($self->is_fatal()) {
        # Since we're one caller level off now, compensate for that.
    my @chomped = @_;
    chomp($chomped[-1]);
    $self->fatal(@chomped);
  }

  exit $Log::Log4perl::LOGEXIT_CODE;
}

##################################################
# clucks and carps are WARN level
sub logcluck {
##################################################
  my $self = shift;

  local $Log::Log4perl::caller_depth = 
        $Log::Log4perl::caller_depth + 1;

  local $Carp::CarpLevel = 
        $Carp::CarpLevel + 1;

  my $msg = $self->warning_render(@_);

  if ($self->is_warn()) {
    my $message = Carp::longmess($msg);
    foreach (split(/\n/, $message)) {
      $self->warn("$_\n");
    }
  }

  Carp::cluck($msg);
}

##################################################
sub logcarp {
##################################################
  my $self = shift;

  local $Carp::CarpLevel = $Carp::CarpLevel + 1;

  local $Log::Log4perl::caller_depth = 
        $Log::Log4perl::caller_depth + 1;

  my $msg = $self->warning_render(@_);

  if ($self->is_warn()) {
    my $message = Carp::shortmess($msg);
    foreach (split(/\n/, $message)) {
      $self->warn("$_\n");
    }
  }

  Carp::carp($msg);
}

##################################################
# croaks and confess are FATAL level
##################################################
sub logcroak {
##################################################
  my $self = shift;
  my $arg  = $_[0];

  my $msg = $self->warning_render(@_);

  local $Carp::CarpLevel = 
        $Carp::CarpLevel + 1;

  local $Log::Log4perl::caller_depth = 
        $Log::Log4perl::caller_depth + 1;

  if ($self->is_fatal()) {
    my $message = Carp::shortmess($msg);
    foreach (split(/\n/, $message)) {
      $self->fatal("$_\n");
    }
  }

  my $croak_msg = $arg;

  if( $Log::Log4perl::STRINGIFY_DIE_MESSAGE ) {
      $croak_msg = $msg;
  }

  $Log::Log4perl::LOGDIE_MESSAGE_ON_STDERR ? 
      Carp::croak($croak_msg) : 
        exit($Log::Log4perl::LOGEXIT_CODE);
}

##################################################
sub logconfess {
##################################################
  my $self = shift;
  my $arg  = $_[0];

  local $Carp::CarpLevel = 
        $Carp::CarpLevel + 1;

  local $Log::Log4perl::caller_depth = 
        $Log::Log4perl::caller_depth + 1;

  my $msg = $self->warning_render(@_);

  if ($self->is_fatal()) {
    my $message = Carp::longmess($msg);
    foreach (split(/\n/, $message)) {
      $self->fatal("$_\n");
    }
  }

  my $confess_msg = $arg;

  if( $Log::Log4perl::STRINGIFY_DIE_MESSAGE ) {
      $confess_msg = $msg;
  }

  $Log::Log4perl::LOGDIE_MESSAGE_ON_STDERR ? 
      confess($confess_msg) :
        exit($Log::Log4perl::LOGEXIT_CODE);
}

##################################################
# in case people prefer to use error for warning
##################################################
sub error_warn {
##################################################
  my $self = shift;

  local $Log::Log4perl::caller_depth = 
        $Log::Log4perl::caller_depth + 1;

  if ($self->is_error()) {
    $self->error(@_);
  }

  $self->and_warn(@_);
}

##################################################
sub error_die {
##################################################
  my $self = shift;

  local $Log::Log4perl::caller_depth = 
        $Log::Log4perl::caller_depth + 1;

  my $msg = $self->warning_render(@_);

  if ($self->is_error()) {
    $self->error($msg);
  }

  $Log::Log4perl::LOGDIE_MESSAGE_ON_STDERR ? 
      $self->and_die($msg) :
        exit($Log::Log4perl::LOGEXIT_CODE);
}

##################################################
sub more_logging {
##################################################
  my ($self) = shift;
  return $self->dec_level(@_);
}

##################################################
sub inc_level {
##################################################
    my ($self, $delta) = @_;

    $delta ||= 1;

    $self->level(Log::Log4perl::Level::get_higher_level($self->level(), 
                                                        $delta));

    $self->set_output_methods;
}

##################################################
sub less_logging {
##################################################
  my ($self) = shift;
  return $self->inc_level(@_);
}

##################################################
sub dec_level {
##################################################
    my ($self, $delta) = @_;

    $delta ||= 1;

    $self->level(Log::Log4perl::Level::get_lower_level($self->level(), $delta));

    $self->set_output_methods;
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Logger - Main Logger Class

=head1 SYNOPSIS

    # It's not here

=head1 DESCRIPTION

While everything that makes Log4perl tick is implemented here,
please refer to L<Log::Log4perl> for documentation.

=head1 LICENSE

Copyright 2002-2013 by Mike Schilli E<lt>m@perlmeister.comE<gt> 
and Kevin Goess E<lt>cpan@goess.orgE<gt>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=head1 AUTHOR

Please contribute patches to the project on Github:

    http://github.com/mschilli/log4perl

Send bug reports or requests for enhancements to the authors via our

MAILING LIST (questions, bug reports, suggestions/patches): 
log4perl-devel@lists.sourceforge.net

Authors (please contact them via the list above, not directly):
Mike Schilli <m@perlmeister.com>,
Kevin Goess <cpan@goess.org>

Contributors (in alphabetical order):
Ateeq Altaf, Cory Bennett, Jens Berthold, Jeremy Bopp, Hutton
Davidson, Chris R. Donnelly, Matisse Enzer, Hugh Esco, Anthony
Foiani, James FitzGibbon, Carl Franks, Dennis Gregorovic, Andy
Grundman, Paul Harrington, Alexander Hartmaier  David Hull, 
Robert Jacobson, Jason Kohles, Jeff Macdonald, Markus Peter, 
Brett Rann, Peter Rabbitson, Erik Selberg, Aaron Straup Cope, 
Lars Thegler, David Viner, Mac Yang.

