##################################################
package Log::Log4perl::Config;
##################################################
use 5.006;
use strict;
use warnings;

use Log::Log4perl::Logger;
use Log::Log4perl::Level;
use Log::Log4perl::Config::PropertyConfigurator;
use Log::Log4perl::JavaMap;
use Log::Log4perl::Filter;
use Log::Log4perl::Filter::Boolean;
use Log::Log4perl::Config::Watch;

use constant _INTERNAL_DEBUG => 0;

our $CONFIG_FILE_READS       = 0;
our $CONFIG_INTEGRITY_CHECK  = 1;
our $CONFIG_INTEGRITY_ERROR  = undef;

our $WATCHER;
our $DEFAULT_WATCH_DELAY = 60; # seconds
our $OPTS = {};
our $OLD_CONFIG;
our $LOGGERS_DEFINED;
our $UTF8 = 0;

###########################################
sub init {
###########################################
    Log::Log4perl::Logger->reset();

    undef $WATCHER; # just in case there's a one left over (e.g. test cases)

    return _init(@_);
}

###########################################
sub utf8 {
###########################################
    my( $class, $flag ) = @_;

    $UTF8 = $flag if defined $flag;

    return $UTF8;
}

###########################################
sub watcher {
###########################################
    return $WATCHER;
}

###########################################
sub init_and_watch {
###########################################
    my ($class, $config, $delay, $opts) = @_;
        # delay can be a signal name - in this case we're gonna
        # set up a signal handler.

    if(defined $WATCHER) {
        $config = $WATCHER->file();
        if(defined $Log::Log4perl::Config::Watch::SIGNAL_CAUGHT) {
            $delay  = $WATCHER->signal();
        } else {
            $delay  = $WATCHER->check_interval();
        }
    }

    print "init_and_watch ($config-$delay). Resetting.\n" if _INTERNAL_DEBUG;

    Log::Log4perl::Logger->reset();

    defined ($delay) or $delay = $DEFAULT_WATCH_DELAY;  

    if (ref $config) {
        die "Log4perl can only watch a file, not a string of " .
            "configuration information";
    }elsif ($config =~ m!^(https?|ftp|wais|gopher|file):!){
        die "Log4perl can only watch a file, not a url like $config";
    }

    if($delay =~ /\D/) {
        $WATCHER = Log::Log4perl::Config::Watch->new(
                          file         => $config,
                          signal       => $delay,
                          l4p_internal => 1,
                   );
    } else {
        $WATCHER = Log::Log4perl::Config::Watch->new(
                          file           => $config,
                          check_interval => $delay,
                          l4p_internal   => 1,
                   );
    }

    if(defined $opts) {
        die "Parameter $opts needs to be a hash ref" if ref($opts) ne "HASH";
        $OPTS = $opts;
    }

    eval { _init($class, $config); };

    if($@) {
        die "$@" unless defined $OLD_CONFIG;
            # Call _init with a pre-parsed config to go back to old setting
        _init($class, undef, $OLD_CONFIG);
        warn "Loading new config failed, reverted to old one\n";
    }
}

##################################################
sub _init {
##################################################
    my($class, $config, $data) = @_;

    my %additivity = ();

    $LOGGERS_DEFINED = 0;

    print "Calling _init\n" if _INTERNAL_DEBUG;

    #keep track so we don't create the same one twice
    my %appenders_created = ();

    #some appenders need to run certain subroutines right at the
    #end of the configuration phase, when all settings are in place.
    my @post_config_subs  = ();

    # This logic is probably suited to win an obfuscated programming
    # contest. It desperately needs to be rewritten.
    # Basically, it works like this:
    # config_read() reads the entire config file into a hash of hashes:
    #     log4j.logger.foo.bar.baz: WARN, A1
    # gets transformed into
    #     $data->{log4j}->{logger}->{foo}->{bar}->{baz} = "WARN, A1";
    # The code below creates the necessary loggers, sets the appenders
    # and the layouts etc.
    # In order to transform parts of this tree back into identifiers
    # (like "foo.bar.baz"), we're using the leaf_paths functions below.
    # Pretty scary. But it allows the lines of the config file to be
    # in *arbitrary* order.

    $data = config_read($config) unless defined $data;
    
    if(_INTERNAL_DEBUG) {
        require Data::Dumper;
        Data::Dumper->import();
        print Data::Dumper::Dumper($data);
    }

    my @loggers      = ();
    my %filter_names = ();

    my $system_wide_threshold;

      # Autocorrect the rootlogger/rootLogger typo
    if(exists $data->{rootlogger} and 
       ! exists $data->{rootLogger}) {
         $data->{rootLogger} = $data->{rootlogger};
    }

        # Find all logger definitions in the conf file. Start
        # with root loggers.
    if(exists $data->{rootLogger}) {
        $LOGGERS_DEFINED++;
        push @loggers, ["", $data->{rootLogger}->{value}];
    }
        
        # Check if we've got a system-wide threshold setting
    if(exists $data->{threshold}) {
            # yes, we do.
        $system_wide_threshold = $data->{threshold}->{value};
    }

    if (exists $data->{oneMessagePerAppender}){
                    $Log::Log4perl::one_message_per_appender = 
                        $data->{oneMessagePerAppender}->{value};
    }

    if(exists $data->{utcDateTimes}) {
        require Log::Log4perl::DateFormat;
          # Need to split this up in two lines, or CVS will
          # mess it up.
        $Log::Log4perl::DateFormat::GMTIME = 
          !!$data->{utcDateTimes}->{value};
    }

        # Boolean filters 
    my %boolean_filters = ();

        # Continue with lower level loggers. Both 'logger' and 'category'
        # are valid keywords. Also 'additivity' is one, having a logger
        # attached. We'll differentiate between the two further down.
    for my $key (qw(logger category additivity PatternLayout filter)) {

        if(exists $data->{$key}) {

            for my $path (@{leaf_paths($data->{$key})}) {

                print "Path before: @$path\n" if _INTERNAL_DEBUG;

                my $value = boolean_to_perlish(pop @$path);

                pop @$path; # Drop the 'value' keyword part

                if($key eq "additivity") {
                    # This isn't a logger but an additivity setting.
                    # Save it in a hash under the logger's name for later.
                    $additivity{join('.', @$path)} = $value;

                    #a global user-defined conversion specifier (cspec)
                }elsif ($key eq "PatternLayout"){
                    &add_global_cspec(@$path[-1], $value);

                }elsif ($key eq "filter"){
                    print "Found entry @$path\n" if _INTERNAL_DEBUG;
                    $filter_names{@$path[0]}++;
                } else {

                    if (ref($value) eq "ARRAY") {
                      die "Multiple definitions of logger ".join('.',@$path)." in log4perl config";
                    }

                    # This is a regular logger
                    $LOGGERS_DEFINED++;
                    push @loggers, [join('.', @$path), $value];
                }
            }
        }
    }

        # Now go over all filters found by name
    for my $filter_name (sort keys %filter_names) {

        print "Checking filter $filter_name\n" if _INTERNAL_DEBUG;

            # The boolean filter needs all other filters already
            # initialized, defer its initialization
        if($data->{filter}->{$filter_name}->{value} eq
           "Log::Log4perl::Filter::Boolean") {
            print "Boolean filter ($filter_name)\n" if _INTERNAL_DEBUG;
            $boolean_filters{$filter_name}++;
            next;
        }

        my $type = $data->{filter}->{$filter_name}->{value};
        if(my $code = compile_if_perl($type)) {
            $type = $code;
        }
        
        print "Filter $filter_name is of type $type\n" if _INTERNAL_DEBUG;

        my $filter;

        if(ref($type) eq "CODE") {
                # Subroutine - map into generic Log::Log4perl::Filter class
            $filter = Log::Log4perl::Filter->new($filter_name, $type);
        } else {
                # Filter class
                die "Filter class '$type' doesn't exist" unless
                     Log::Log4perl::Util::module_available($type);
                eval "require $type" or die "Require of $type failed ($!)";

                # Invoke with all defined parameter
                # key/values (except the key 'value' which is the entry 
                # for the class)
            $filter = $type->new(name => $filter_name,
                map { $_ => $data->{filter}->{$filter_name}->{$_}->{value} } 
                grep { $_ ne "value" } 
                sort keys %{$data->{filter}->{$filter_name}});
        }
            # Register filter with the global filter registry
        $filter->register();
    }

        # Initialize boolean filters (they need the other filters to be
        # initialized to be able to compile their logic)
    for my $name (sort keys %boolean_filters) {
        my $logic = $data->{filter}->{$name}->{logic}->{value};
        die "No logic defined for boolean filter $name" unless defined $logic;
        my $filter = Log::Log4perl::Filter::Boolean->new(
                         name  => $name, 
                         logic => $logic);
        $filter->register();
    }

    for (@loggers) {
        my($name, $value) = @$_;

        my $logger = Log::Log4perl::Logger->get_logger($name);
        my ($level, @appnames) = split /\s*,\s*/, $value;

        $logger->level(
            Log::Log4perl::Level::to_priority($level),
            'dont_reset_all');

        if(exists $additivity{$name}) {
            $logger->additivity($additivity{$name}, 1);
        }

        for my $appname (@appnames) {

            my $appender = create_appender_instance(
                $data, $appname, \%appenders_created, \@post_config_subs,
                $system_wide_threshold);

            $logger->add_appender($appender, 'dont_reset_all');
            set_appender_by_name($appname, $appender, \%appenders_created);
        }
    }

    #run post_config subs
    for(@post_config_subs) {
        $_->();
    }

    #now we're done, set up all the output methods (e.g. ->debug('...'))
    Log::Log4perl::Logger::reset_all_output_methods();

    #Run a sanity test on the config not disabled
    if($Log::Log4perl::Config::CONFIG_INTEGRITY_CHECK and
       !config_is_sane()) {
        warn "Log::Log4perl configuration looks suspicious: ",
             "$CONFIG_INTEGRITY_ERROR";
    }

        # Successful init(), save config for later
    $OLD_CONFIG = $data;

    $Log::Log4perl::Logger::INITIALIZED = 1;
}

##################################################
sub config_is_sane {
##################################################
    if(! $LOGGERS_DEFINED) {
        $CONFIG_INTEGRITY_ERROR = "No loggers defined";
        return 0;
    }    

    if(scalar keys %Log::Log4perl::Logger::APPENDER_BY_NAME == 0) {
        $CONFIG_INTEGRITY_ERROR = "No appenders defined";
        return 0;
    }

    return 1;
}

##################################################
sub create_appender_instance {
##################################################
    my($data, $appname, $appenders_created, $post_config_subs,
       $system_wide_threshold) = @_;

    my $appenderclass = get_appender_by_name(
            $data, $appname, $appenders_created);

    print "appenderclass=$appenderclass\n" if _INTERNAL_DEBUG;

    my $appender;

    if (ref $appenderclass) {
        $appender = $appenderclass;
    } else {
        die "ERROR: you didn't tell me how to " .
            "implement your appender '$appname'"
                unless $appenderclass;

        if (Log::Log4perl::JavaMap::translate($appenderclass)){
            # It's Java. Try to map
            print "Trying to map Java $appname\n" if _INTERNAL_DEBUG;
            $appender = Log::Log4perl::JavaMap::get($appname, 
                                        $data->{appender}->{$appname});

        }else{
            # It's Perl
            my @params = grep { $_ ne "layout" and
                                $_ ne "value"
                              } sort keys %{$data->{appender}->{$appname}};
    
            my %param = ();
            foreach my $pname (@params){
                #this could be simple value like 
                #{appender}{myAppender}{file}{value} => 'log.txt'
                #or a structure like
                #{appender}{myAppender}{login} => 
                #                         { name => {value => 'bob'},
                #                           pwd  => {value => 'xxx'},
                #                         }
                #in the latter case we send a hashref to the appender
                if (exists $data->{appender}{$appname}
                                  {$pname}{value}      ) {
                    $param{$pname} = $data->{appender}{$appname}
                                            {$pname}{value};
                }else{
                    $param{$pname} = {map {$_ => $data->{appender}
                                                        {$appname}
                                                        {$pname}
                                                        {$_}
                                                        {value}} 
                                     sort keys %{$data->{appender}
                                                   {$appname}
                                                   {$pname}}
                                     };
                }
    
            }

            my $depends_on = [];
    
            $appender = Log::Log4perl::Appender->new(
                $appenderclass, 
                name                 => $appname,
                l4p_post_config_subs => $post_config_subs,
                l4p_depends_on       => $depends_on,
                %param,
            ); 
    
            for my $dependency (@$depends_on) {
                # If this appender indicates that it needs other appenders
                # to exist (e.g. because it's a composite appender that
                # relays messages on to its appender-refs) then we're 
                # creating their instances here. Reason for this is that 
                # these appenders are not attached to any logger and are
                # therefore missed by the config parser which goes through
                # the defined loggers and just creates *their* attached
                # appenders.
                $appender->composite(1);
                next if exists $appenders_created->{$appname};
                my $app = create_appender_instance($data, $dependency, 
                             $appenders_created,
                             $post_config_subs);
                # If the appender appended a subroutine to $post_config_subs
                # (a reference to an array of subroutines)
                # here, the configuration parser will later execute this
                # method. This is used by a composite appender which needs
                # to make sure all of its appender-refs are available when
                # all configuration settings are done.

                # Smuggle this sub-appender into the hash of known appenders 
                # without attaching it to any logger directly.
                $
                Log::Log4perl::Logger::APPENDER_BY_NAME{$dependency} = $app;
            }
        }
    }

    add_layout_by_name($data, $appender, $appname) unless
        $appender->composite();

       # Check for appender thresholds
    my $threshold = 
       $data->{appender}->{$appname}->{Threshold}->{value};

    if(defined $system_wide_threshold and
       !defined $threshold) {
        $threshold = $system_wide_threshold;
    }

    if(defined $threshold) {
            # Need to split into two lines because of CVS
        $appender->threshold($
            Log::Log4perl::Level::PRIORITY{$threshold});
    }

        # Check for custom filters attached to the appender
    my $filtername = 
       $data->{appender}->{$appname}->{Filter}->{value};
    if(defined $filtername) {
            # Need to split into two lines because of CVS
        my $filter = Log::Log4perl::Filter::by_name($filtername);
        die "Filter $filtername doesn't exist" unless defined $filter;
        $appender->filter($filter);
    }

    if(defined $system_wide_threshold and
       defined $threshold and
       $
        Log::Log4perl::Level::PRIORITY{$system_wide_threshold} > 
       $
         Log::Log4perl::Level::PRIORITY{$threshold}
      ) {
        $appender->threshold($
            Log::Log4perl::Level::PRIORITY{$system_wide_threshold});
    }

    if(exists $data->{appender}->{$appname}->{threshold}) {
        die "invalid keyword 'threshold' - perhaps you meant 'Threshold'?";
    }

    return $appender;
}

###########################################
sub add_layout_by_name {
###########################################
    my($data, $appender, $appender_name) = @_;

    my $layout_class = $data->{appender}->{$appender_name}->{layout}->{value};

    die "Layout not specified for appender $appender_name" unless $layout_class;

    $layout_class =~ s/org.apache.log4j./Log::Log4perl::Layout::/;

        # Check if we have this layout class
    if(!Log::Log4perl::Util::module_available($layout_class)) {
        if(Log::Log4perl::Util::module_available(
           "Log::Log4perl::Layout::$layout_class")) {
            # Someone used the layout shortcut, use the fully qualified
            # module name instead.
            $layout_class = "Log::Log4perl::Layout::$layout_class";
        } else {
            die "ERROR: trying to set layout for $appender_name to " .
                "'$layout_class' failed ($@)";
        }
    }
    Log::Log4perl::Util::module_available($layout_class) or
        die "Require to $layout_class failed ($@)";

    $appender->layout($layout_class->new(
        $data->{appender}->{$appender_name}->{layout},
        ));
}

###########################################
sub get_appender_by_name {
###########################################
    my($data, $name, $appenders_created) = @_;

    if (exists $appenders_created->{$name}) {
        return $appenders_created->{$name};
    } else {
        return $data->{appender}->{$name}->{value};
    }
}

###########################################
sub set_appender_by_name {
###########################################
# keep track of appenders we've already created
###########################################
    my($appname, $appender, $appenders_created) = @_;

    $appenders_created->{$appname} ||= $appender;
}

##################################################
sub add_global_cspec {
##################################################
# the config file said
# log4j.PatternLayout.cspec.Z=sub {return $$*2}
##################################################
    my ($letter, $perlcode) = @_;

    die "error: only single letters allowed in log4j.PatternLayout.cspec.$letter"
        unless ($letter =~ /^[a-zA-Z]$/);

    Log::Log4perl::Layout::PatternLayout::add_global_cspec($letter, $perlcode);
}

my $LWP_USER_AGENT;
sub set_LWP_UserAgent
{
    $LWP_USER_AGENT = shift;
}


###########################################
sub config_read {
###########################################
# Read the lib4j configuration and store the
# values into a nested hash structure.
###########################################
    my($config) = @_;

    die "Configuration not defined" unless defined $config;

    my @text;
    my $parser;

    $CONFIG_FILE_READS++;  # Count for statistical purposes

    my $base_configurator = Log::Log4perl::Config::BaseConfigurator->new(
        utf8 => $UTF8,
    );

    my $data = {};

    if (ref($config) eq 'HASH') {   # convert the hashref into a list 
                                    # of name/value pairs
        print "Reading config from hash\n" if _INTERNAL_DEBUG;
        @text = ();
        for my $key ( sort keys %$config ) {
            if( ref( $config->{$key} ) eq "CODE" ) {
                $config->{$key} = $config->{$key}->();
            }
            push @text, $key . '=' . $config->{$key} . "\n";
        }
    } elsif (ref $config eq 'SCALAR') {
        print "Reading config from scalar\n" if _INTERNAL_DEBUG;
        @text = split(/\n/,$$config);

    } elsif (ref $config eq 'GLOB' or 
             ref $config eq 'IO::File') {
            # If we have a file handle, just call the reader
        print "Reading config from file handle\n" if _INTERNAL_DEBUG;
        @text = @{ $base_configurator->file_h_read( $config ) };

    } elsif (ref $config) {
            # Caller provided a config parser object, which already
            # knows which file (or DB or whatever) to parse.
        print "Reading config from parser object\n" if _INTERNAL_DEBUG;
        $data = $config->parse();
        return $data;

    } elsif ($config =~ m|^ldap://|){
       if(! Log::Log4perl::Util::module_available("Net::LDAP")) {
           die "Log4perl: missing Net::LDAP needed to parse LDAP urls\n$@\n";
       }

       require Net::LDAP;
       require Log::Log4perl::Config::LDAPConfigurator;

       return Log::Log4perl::Config::LDAPConfigurator->new->parse($config);

    } else {

        if ($config =~ /^(https?|ftp|wais|gopher|file):/){
            my ($result, $ua);
    
            die "LWP::UserAgent not available" unless
                Log::Log4perl::Util::module_available("LWP::UserAgent");

            require LWP::UserAgent;
            unless (defined $LWP_USER_AGENT) {
                $LWP_USER_AGENT = LWP::UserAgent->new;
    
                # Load proxy settings from environment variables, i.e.:
                # http_proxy, ftp_proxy, no_proxy etc (see LWP::UserAgent)
                # You need these to go thru firewalls.
                $LWP_USER_AGENT->env_proxy;
            }
            $ua = $LWP_USER_AGENT;

            my $req = new HTTP::Request GET => $config;
            my $res = $ua->request($req);

            if ($res->is_success) {
                @text = split(/\n/, $res->content);
            } else {
                die "Log4perl couln't get $config, ".
                     $res->message." ";
            }
        } else {
            print "Reading config from file '$config'\n" if _INTERNAL_DEBUG;
            print "Reading ", -s $config, " bytes.\n" if _INTERNAL_DEBUG;
              # Use the BaseConfigurator's file reader to avoid duplicating
              # utf8 handling here.
            $base_configurator->file( $config );
            @text = @{ $base_configurator->text() };
        }
    }
    
    print "Reading $config: [@text]\n" if _INTERNAL_DEBUG;

    if(! grep /\S/, @text) {
        return $data;
    }

    if ($text[0] =~ /^<\?xml /) {

        die "XML::DOM not available" unless
                Log::Log4perl::Util::module_available("XML::DOM");

        require XML::DOM; 
        require Log::Log4perl::Config::DOMConfigurator;

        XML::DOM->VERSION($Log::Log4perl::DOM_VERSION_REQUIRED);
        $parser = Log::Log4perl::Config::DOMConfigurator->new();
        $data = $parser->parse(\@text);
    } else {
        $parser = Log::Log4perl::Config::PropertyConfigurator->new();
        $data = $parser->parse(\@text);
    }

    $data = $parser->parse_post_process( $data, leaf_paths($data) );

    return $data;
}

###########################################
sub unlog4j {
###########################################
    my ($string) = @_;

    $string =~ s#^org\.apache\.##;
    $string =~ s#^log4j\.##;
    $string =~ s#^l4p\.##;
    $string =~ s#^log4perl\.##i;

    $string =~ s#\.#::#g;

    return $string;
}

############################################################
sub leaf_paths {
############################################################
# Takes a reference to a hash of hashes structure of 
# arbitrary depth, walks the tree and returns a reference
# to an array of all possible leaf paths (each path is an 
# array again).
# Example: { a => { b => { c => d }, e => f } } would generate
#          [ [a, b, c, d], [a, e, f] ]
############################################################
    my ($root) = @_;

    my @stack  = ();
    my @result = ();

    push @stack, [$root, []];  
    
    while(@stack) {
        my $item = pop @stack;

        my($node, $path) = @$item;

        if(ref($node) eq "HASH") { 
            for(sort keys %$node) {
                push @stack, [$node->{$_}, [@$path, $_]];
            }
        } else {
            push @result, [@$path, $node];
        }
    }
    return \@result;
}

###########################################
sub leaf_path_to_hash {
###########################################
    my($leaf_path, $data) = @_;

    my $ref = \$data;

    for my $part ( @$leaf_path[0..$#$leaf_path-1] ) {
        $ref = \$$ref->{ $part };
    }

    return $ref;
}

###########################################
sub eval_if_perl {
###########################################
    my($value) = @_;

    if(my $cref = compile_if_perl($value)) {
        return $cref->();
    }

    return $value;
}

###########################################
sub compile_if_perl {
###########################################
    my($value) = @_;

    if($value =~ /^\s*sub\s*{/ ) {
        my $mask;
        unless( Log::Log4perl::Config->allow_code() ) {
            die "\$Log::Log4perl::Config->allow_code() setting " .
                "prohibits Perl code in config file";
        }
        if( defined( $mask = Log::Log4perl::Config->allowed_code_ops() ) ) {
            return compile_in_safe_cpt($value, $mask );
        }
        elsif( $mask = Log::Log4perl::Config->allowed_code_ops_convenience_map(
                             Log::Log4perl::Config->allow_code()
                          ) ) {
            return compile_in_safe_cpt($value, $mask );
        }
        elsif( Log::Log4perl::Config->allow_code() == 1 ) {

            # eval without restriction
            my $cref = eval "package main; $value" or 
                die "Can't evaluate '$value' ($@)";
            return $cref;
        }
        else {
            die "Invalid value for \$Log::Log4perl::Config->allow_code(): '".
                Log::Log4perl::Config->allow_code() . "'";
        }
    }

    return undef;
}

###########################################
sub compile_in_safe_cpt {
###########################################
    my($value, $allowed_ops) = @_;

    # set up a Safe compartment
    require Safe;
    my $safe = Safe->new();
    $safe->permit_only( @{ $allowed_ops } );
 
    # share things with the compartment
    for( sort keys %{ Log::Log4perl::Config->vars_shared_with_safe_compartment() } ) {
        my $toshare = Log::Log4perl::Config->vars_shared_with_safe_compartment($_);
        $safe->share_from( $_, $toshare )
            or die "Can't share @{ $toshare } with Safe compartment";
    }
    
    # evaluate with restrictions
    my $cref = $safe->reval("package main; $value") or
        die "Can't evaluate '$value' in Safe compartment ($@)";
    return $cref;
    
}

###########################################
sub boolean_to_perlish {
###########################################
    my($value) = @_;

        # Translate boolean to perlish
    $value = 1 if $value =~ /^true$/i;
    $value = 0 if $value =~ /^false$/i;

    return $value;
}

###########################################
sub vars_shared_with_safe_compartment {
###########################################
    my($class, @args) = @_;

        # Allow both for ...::Config::foo() and ...::Config->foo()
    if(defined $class and $class ne __PACKAGE__) {
        unshift @args, $class;
    }
   
    # handle different invocation styles
    if(@args == 1 && ref $args[0] eq 'HASH' ) {
        # replace entire hash of vars
        %Log::Log4perl::VARS_SHARED_WITH_SAFE_COMPARTMENT = %{$args[0]};
    }
    elsif( @args == 1 ) {
        # return vars for given package
        return $Log::Log4perl::VARS_SHARED_WITH_SAFE_COMPARTMENT{
               $args[0]};
    }
    elsif( @args == 2 ) {
        # add/replace package/var pair
        $Log::Log4perl::VARS_SHARED_WITH_SAFE_COMPARTMENT{
           $args[0]} = $args[1];
    }

    return wantarray ? %Log::Log4perl::VARS_SHARED_WITH_SAFE_COMPARTMENT
                     : \%Log::Log4perl::VARS_SHARED_WITH_SAFE_COMPARTMENT;
    
}

###########################################
sub allowed_code_ops {
###########################################
    my($class, @args) = @_;

        # Allow both for ...::Config::foo() and ...::Config->foo()
    if(defined $class and $class ne __PACKAGE__) {
        unshift @args, $class;
    }
   
    if(@args) {
        @Log::Log4perl::ALLOWED_CODE_OPS_IN_CONFIG_FILE = @args;
    }
    else {
        # give back 'undef' instead of an empty arrayref
        unless( @Log::Log4perl::ALLOWED_CODE_OPS_IN_CONFIG_FILE ) {
            return;
        }
    }

    return wantarray ? @Log::Log4perl::ALLOWED_CODE_OPS_IN_CONFIG_FILE
                     : \@Log::Log4perl::ALLOWED_CODE_OPS_IN_CONFIG_FILE;
}

###########################################
sub allowed_code_ops_convenience_map {
###########################################
    my($class, @args) = @_;

        # Allow both for ...::Config::foo() and ...::Config->foo()
    if(defined $class and $class ne __PACKAGE__) {
        unshift @args, $class;
    }

    # handle different invocation styles
    if( @args == 1 && ref $args[0] eq 'HASH' ) {
        # replace entire map
        %Log::Log4perl::ALLOWED_CODE_OPS = %{$args[0]};
    }
    elsif( @args == 1 ) {
        # return single opcode mask
        return $Log::Log4perl::ALLOWED_CODE_OPS{
                   $args[0]};
    }
    elsif( @args == 2 ) {
        # make sure the mask is an array ref
        if( ref $args[1] ne 'ARRAY' ) {
            die "invalid mask (not an array ref) for convenience name '$args[0]'";
        }
        # add name/mask pair
        $Log::Log4perl::ALLOWED_CODE_OPS{
            $args[0]} = $args[1];
    }

    return wantarray ? %Log::Log4perl::ALLOWED_CODE_OPS
                     : \%Log::Log4perl::ALLOWED_CODE_OPS
}

###########################################
sub allow_code {
###########################################
    my($class, @args) = @_;

        # Allow both for ...::Config::foo() and ...::Config->foo()
    if(defined $class and $class ne __PACKAGE__) {
        unshift @args, $class;
    }
   
    if(@args) {
        $Log::Log4perl::ALLOW_CODE_IN_CONFIG_FILE = 
            $args[0];
    }

    return $Log::Log4perl::ALLOW_CODE_IN_CONFIG_FILE;
}

################################################
sub var_subst {
################################################
    my($varname, $subst_hash) = @_;

        # Throw out blanks
    $varname =~ s/\s+//g;

    if(exists $subst_hash->{$varname}) {
        print "Replacing variable: '$varname' => '$subst_hash->{$varname}'\n" 
            if _INTERNAL_DEBUG;
        return $subst_hash->{$varname};

    } elsif(exists $ENV{$varname}) {
        print "Replacing ENV variable: '$varname' => '$ENV{$varname}'\n" 
            if _INTERNAL_DEBUG;
        return $ENV{$varname};

    }

    die "Undefined Variable '$varname'";
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Config - Log4perl configuration file syntax

=head1 DESCRIPTION

In C<Log::Log4perl>, configuration files are used to describe how the
system's loggers ought to behave. 

The format is the same as the one as used for C<log4j>, just with
a few perl-specific extensions, like enabling the C<Bar::Twix>
syntax instead of insisting on the Java-specific C<Bar.Twix>.

Comment lines and blank lines (all whitespace or empty) are ignored.

Comment lines may start with arbitrary whitespace followed by one of:

=over 4

=item # - Common comment delimiter

=item ! - Java .properties file comment delimiter accepted by log4j

=item ; - Common .ini file comment delimiter

=back

Comments at the end of a line are not supported. So if you write

    log4perl.appender.A1.filename=error.log #in current dir

you will find your messages in a file called C<error.log #in current dir>.

Also, blanks between syntactical entities are ignored, it doesn't 
matter if you write

    log4perl.logger.Bar.Twix=WARN,Screen

or 

    log4perl.logger.Bar.Twix = WARN, Screen

C<Log::Log4perl> will strip the blanks while parsing your input.

Assignments need to be on a single line. However, you can break the
line if you want to by using a continuation character at the end of the
line. Instead of writing

    log4perl.appender.A1.layout=Log::Log4perl::Layout::SimpleLayout

you can break the line at any point by putting a backslash at the very (!)
end of the line to be continued:

    log4perl.appender.A1.layout=\
        Log::Log4perl::Layout::SimpleLayout

Watch out for trailing blanks after the backslash, which would prevent
the line from being properly concatenated.

=head2 Loggers

Loggers are addressed by category:

    log4perl.logger.Bar.Twix      = WARN, Screen

This sets all loggers under the C<Bar::Twix> hierarchy on priority
C<WARN> and attaches a later-to-be-defined C<Screen> appender to them.
Settings for the root appender (which doesn't have a name) can be
accomplished by simply omitting the name:

    log4perl.logger = FATAL, Database, Mailer 

This sets the root appender's level to C<FATAL> and also attaches the 
later-to-be-defined appenders C<Database> and C<Mailer> to it. Alternatively,
the root logger can be addressed as C<rootLogger>:

    log4perl.rootLogger = FATAL, Database, Mailer

The additivity flag of a logger is set or cleared via the 
C<additivity> keyword:

    log4perl.additivity.Bar.Twix = 0|1

(Note the reversed order of keyword and logger name, resulting
from the dilemma that a logger name could end in C<.additivity>
according to the log4j documentation).

=head2 Appenders and Layouts

Appender names used in Log4perl configuration file
lines need to be resolved later on, in order to
define the appender's properties and its layout. To specify properties
of an appender, just use the C<appender> keyword after the
C<log4perl> intro and the appender's name:

        # The Bar::Twix logger and its appender
    log4perl.logger.Bar.Twix = DEBUG, A1
    log4perl.appender.A1=Log::Log4perl::Appender::File
    log4perl.appender.A1.filename=test.log
    log4perl.appender.A1.mode=append
    log4perl.appender.A1.layout=Log::Log4perl::Layout::SimpleLayout

This sets a priority of C<DEBUG> for loggers in the C<Bar::Twix>
hierarchy and assigns the C<A1> appender to it, which is later on
resolved to be an appender of type C<Log::Log4perl::Appender::File>, simply
appending to a log file. According to the C<Log::Log4perl::Appender::File>
manpage, the C<filename> parameter specifies the name of the log file
and the C<mode> parameter can be set to C<append> or C<write> (the
former will append to the logfile if one with the specified name
already exists while the latter would clobber and overwrite it).

The order of the entries in the configuration file is not important,
C<Log::Log4perl> will read in the entire file first and try to make
sense of the lines after it knows the entire context.

You can very well define all loggers first and then their appenders
(you could even define your appenders first and then your loggers,
but let's not go there):

    log4perl.logger.Bar.Twix = DEBUG, A1
    log4perl.logger.Bar.Snickers = FATAL, A2

    log4perl.appender.A1=Log::Log4perl::Appender::File
    log4perl.appender.A1.filename=test.log
    log4perl.appender.A1.mode=append
    log4perl.appender.A1.layout=Log::Log4perl::Layout::SimpleLayout

    log4perl.appender.A2=Log::Log4perl::Appender::Screen
    log4perl.appender.A2.stderr=0
    log4perl.appender.A2.layout=Log::Log4perl::Layout::PatternLayout
    log4perl.appender.A2.layout.ConversionPattern = %d %m %n

Note that you have to specify the full path to the layout class
and that C<ConversionPattern> is the keyword to specify the printf-style
formatting instructions.

=head1 Configuration File Cookbook

Here's some examples of often-used Log4perl configuration files:

=head2 Append to STDERR

    log4perl.category.Bar.Twix      = WARN, Screen
    log4perl.appender.Screen        = Log::Log4perl::Appender::Screen
    log4perl.appender.Screen.layout = \
        Log::Log4perl::Layout::PatternLayout
    log4perl.appender.Screen.layout.ConversionPattern = %d %m %n

=head2 Append to STDOUT

    log4perl.category.Bar.Twix      = WARN, Screen
    log4perl.appender.Screen        = Log::Log4perl::Appender::Screen
    log4perl.appender.Screen.stderr = 0
    log4perl.appender.Screen.layout = \
        Log::Log4perl::Layout::PatternLayout
    log4perl.appender.Screen.layout.ConversionPattern = %d %m %n

=head2 Append to a log file

    log4perl.logger.Bar.Twix = DEBUG, A1
    log4perl.appender.A1=Log::Log4perl::Appender::File
    log4perl.appender.A1.filename=test.log
    log4perl.appender.A1.mode=append
    log4perl.appender.A1.layout = \
        Log::Log4perl::Layout::PatternLayout
    log4perl.appender.A1.layout.ConversionPattern = %d %m %n

Note that you could even leave out 

    log4perl.appender.A1.mode=append

and still have the logger append to the logfile by default, although
the C<Log::Log4perl::Appender::File> module does exactly the opposite.
This is due to some nasty trickery C<Log::Log4perl> performs behind 
the scenes to make sure that beginner's CGI applications don't clobber 
the log file every time they're called.

=head2 Write a log file from scratch

If you loathe the Log::Log4perl's append-by-default strategy, you can
certainly override it:

    log4perl.logger.Bar.Twix = DEBUG, A1
    log4perl.appender.A1=Log::Log4perl::Appender::File
    log4perl.appender.A1.filename=test.log
    log4perl.appender.A1.mode=write
    log4perl.appender.A1.layout=Log::Log4perl::Layout::SimpleLayout

C<write> is the C<mode> that has C<Log::Log4perl::Appender::File>
explicitly clobber the log file if it exists.

=head2 Configuration files encoded in utf-8

If your configuration file is encoded in utf-8 (which matters if you 
e.g. specify utf8-encoded appender filenames in it), then you need to 
tell Log4perl before running init():

    use Log::Log4perl::Config;
    Log::Log4perl::Config->utf( 1 );

    Log::Log4perl->init( ... );

This makes sure Log4perl interprets utf8-encoded config files correctly.
This setting might become the default at some point.

=head1 SEE ALSO

Log::Log4perl::Config::PropertyConfigurator

Log::Log4perl::Config::DOMConfigurator

Log::Log4perl::Config::LDAPConfigurator (coming soon!)

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

