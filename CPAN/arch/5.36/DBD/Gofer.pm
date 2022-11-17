{
    package DBD::Gofer;

    use strict;

    require DBI;
    require DBI::Gofer::Request;
    require DBI::Gofer::Response;
    require Carp;

    our $VERSION = "0.015327";

#   $Id: Gofer.pm 15326 2012-06-06 16:32:38Z Tim $
#
#   Copyright (c) 2007, Tim Bunce, Ireland
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.



    # attributes we'll allow local STORE
    our %xxh_local_store_attrib = map { $_=>1 } qw(
        Active
        CachedKids
        Callbacks
        DbTypeSubclass
        ErrCount Executed
        FetchHashKeyName
        HandleError HandleSetErr
        InactiveDestroy
        AutoInactiveDestroy
        PrintError PrintWarn
        Profile
        RaiseError
        RootClass
        ShowErrorStatement
        Taint TaintIn TaintOut
        TraceLevel
        Warn
        dbi_quote_identifier_cache
        dbi_connect_closure
        dbi_go_execute_unique
    );
    our %xxh_local_store_attrib_if_same_value = map { $_=>1 } qw(
        Username
        dbi_connect_method
    );

    our $drh = undef;    # holds driver handle once initialized
    our $methods_already_installed;

    sub driver{
        return $drh if $drh;

        DBI->setup_driver('DBD::Gofer');

        unless ($methods_already_installed++) {
            my $opts = { O=> 0x0004 }; # IMA_KEEP_ERR
            DBD::Gofer::db->install_method('go_dbh_method', $opts);
            DBD::Gofer::st->install_method('go_sth_method', $opts);
            DBD::Gofer::st->install_method('go_clone_sth',  $opts);
            DBD::Gofer::db->install_method('go_cache',      $opts);
            DBD::Gofer::st->install_method('go_cache',      $opts);
        }

        my($class, $attr) = @_;
        $class .= "::dr";
        ($drh) = DBI::_new_drh($class, {
            'Name' => 'Gofer',
            'Version' => $VERSION,
            'Attribution' => 'DBD Gofer by Tim Bunce',
        });

        $drh;
    }


    sub CLONE {
        undef $drh;
    }


    sub go_cache {
        my $h = shift;
        $h->{go_cache} = shift if @_;
        # return handle's override go_cache, if it has one
        return $h->{go_cache} if defined $h->{go_cache};
        # or else the transports default go_cache
        return $h->{go_transport}->{go_cache};
    }


    sub set_err_from_response { # set error/warn/info and propagate warnings
        my $h = shift;
        my $response = shift;
        if (my $warnings = $response->warnings) {
            warn $_ for @$warnings;
        }
        my ($err, $errstr, $state) = $response->err_errstr_state;
        # Only set_err() if there's an error else leave the current values
        # (The current values will normally be set undef by the DBI dispatcher
        # except for methods marked KEEPERR such as ping.)
        $h->set_err($err, $errstr, $state) if defined $err;
        return undef;
    }


    sub install_methods_proxy {
        my ($installed_methods) = @_;
        while ( my ($full_method, $attr) = each %$installed_methods ) {
            # need to install both a DBI dispatch stub and a proxy stub
            # (the dispatch stub may be already here due to local driver use)

            DBI->_install_method($full_method, "", $attr||{})
                unless defined &{$full_method};

            # now install proxy stubs on the driver side
            $full_method =~ m/^DBI::(\w\w)::(\w+)$/
                or die "Invalid method name '$full_method' for install_method";
            my ($type, $method) = ($1, $2);
            my $driver_method = "DBD::Gofer::${type}::${method}";
            next if defined &{$driver_method};
            my $sub;
            if ($type eq 'db') {
                $sub = sub { return shift->go_dbh_method(undef, $method, @_) };
            }
            else {
                $sub = sub { shift->set_err($DBI::stderr, "Can't call \$${type}h->$method when using DBD::Gofer"); return; };
            }
            no strict 'refs';
            *$driver_method = $sub;
        }
    }
}


{   package DBD::Gofer::dr; # ====== DRIVER ======

    $imp_data_size = 0;
    use strict;

    sub connect_cached {
        my ($drh, $dsn, $user, $auth, $attr)= @_;
        $attr ||= {};
        return $drh->SUPER::connect_cached($dsn, $user, $auth, {
            (%$attr),
            go_connect_method => $attr->{go_connect_method} || 'connect_cached',
        });
    }


    sub connect {
        my($drh, $dsn, $user, $auth, $attr)= @_;
        my $orig_dsn = $dsn;

        # first remove dsn= and everything after it
        my $remote_dsn = ($dsn =~ s/;?\bdsn=(.*)$// && $1)
            or return $drh->set_err($DBI::stderr, "No dsn= argument in '$orig_dsn'");

        if ($attr->{go_bypass}) { # don't use DBD::Gofer for this connection
            # useful for testing with DBI_AUTOPROXY, e.g., t/03handle.t
            return DBI->connect($remote_dsn, $user, $auth, $attr);
        }

        my %go_attr;
        # extract any go_ attributes from the connect() attr arg
        for my $k (grep { /^go_/ } keys %$attr) {
            $go_attr{$k} = delete $attr->{$k};
        }
        # then override those with any attributes embedded in our dsn (not remote_dsn)
        for my $kv (grep /=/, split /;/, $dsn, -1) {
            my ($k, $v) = split /=/, $kv, 2;
            $go_attr{ "go_$k" } = $v;
        }

        if (not ref $go_attr{go_policy}) { # if not a policy object already
            my $policy_class = $go_attr{go_policy} || 'classic';
            $policy_class = "DBD::Gofer::Policy::$policy_class"
                unless $policy_class =~ /::/;
            _load_class($policy_class)
                or return $drh->set_err($DBI::stderr, "Can't load $policy_class: $@");
            # replace policy name in %go_attr with policy object
            $go_attr{go_policy} = eval { $policy_class->new(\%go_attr) }
                or return $drh->set_err($DBI::stderr, "Can't instanciate $policy_class: $@");
        }
        # policy object is left in $go_attr{go_policy} so transport can see it
        my $go_policy = $go_attr{go_policy};

        if ($go_attr{go_cache} and not ref $go_attr{go_cache}) { # if not a cache object already
            my $cache_class = $go_attr{go_cache};
            $cache_class = "DBI::Util::CacheMemory" if $cache_class eq '1';
            _load_class($cache_class)
                or return $drh->set_err($DBI::stderr, "Can't load $cache_class $@");
            $go_attr{go_cache} = eval { $cache_class->new() }
                or $drh->set_err(0, "Can't instanciate $cache_class: $@"); # warning
        }

        # delete any other attributes that don't apply to transport
        my $go_connect_method = delete $go_attr{go_connect_method};

        my $transport_class = delete $go_attr{go_transport}
            or return $drh->set_err($DBI::stderr, "No transport= argument in '$orig_dsn'");
        $transport_class = "DBD::Gofer::Transport::$transport_class"
            unless $transport_class =~ /::/;
        _load_class($transport_class)
            or return $drh->set_err($DBI::stderr, "Can't load $transport_class: $@");
        my $go_transport = eval { $transport_class->new(\%go_attr) }
            or return $drh->set_err($DBI::stderr, "Can't instanciate $transport_class: $@");

        my $request_class = "DBI::Gofer::Request";
        my $go_request = eval {
            my $go_attr = { %$attr };
            # XXX user/pass of fwd server vs db server ? also impact of autoproxy
            if ($user) {
                $go_attr->{Username} = $user;
                $go_attr->{Password} = $auth;
            }
            # delete any attributes we can't serialize (or don't want to)
            delete @{$go_attr}{qw(Profile HandleError HandleSetErr Callbacks)};
            # delete any attributes that should only apply to the client-side
            delete @{$go_attr}{qw(RootClass DbTypeSubclass)};

            $go_connect_method ||= $go_policy->connect_method($remote_dsn, $go_attr) || 'connect';
            $request_class->new({
                dbh_connect_call => [ $go_connect_method, $remote_dsn, $user, $auth, $go_attr ],
            })
        } or return $drh->set_err($DBI::stderr, "Can't instanciate $request_class: $@");

        my ($dbh, $dbh_inner) = DBI::_new_dbh($drh, {
            'Name' => $dsn,
            'USER' => $user,
            go_transport => $go_transport,
            go_request => $go_request,
            go_policy => $go_policy,
        });

        # mark as inactive temporarily for STORE. Active not set until connected() called.
        $dbh->STORE(Active => 0);

        # should we ping to check the connection
        # and fetch dbh attributes
        my $skip_connect_check = $go_policy->skip_connect_check($attr, $dbh);
        if (not $skip_connect_check) {
            if (not $dbh->go_dbh_method(undef, 'ping')) {
                return undef if $dbh->err; # error already recorded, typically
                return $dbh->set_err($DBI::stderr, "ping failed");
            }
        }

        return $dbh;
    }

    sub _load_class { # return true or false+$@
        my $class = shift;
        (my $pm = $class) =~ s{::}{/}g;
        $pm .= ".pm";
        return 1 if eval { require $pm };
        delete $INC{$pm}; # shouldn't be needed (perl bug?) and assigning undef isn't enough
        undef; # error in $@
    }

}


{   package DBD::Gofer::db; # ====== DATABASE ======
    $imp_data_size = 0;
    use strict;
    use Carp qw(carp croak);

    my %dbh_local_store_attrib = %DBD::Gofer::xxh_local_store_attrib;

    sub connected {
        shift->STORE(Active => 1);
    }

    sub go_dbh_method {
        my $dbh = shift;
        my $meta = shift;
        # @_ now contains ($method_name, @args)

        my $request = $dbh->{go_request};
        $request->init_request([ wantarray, @_ ], $dbh);
        ++$dbh->{go_request_count};

        my $go_policy = $dbh->{go_policy};
        my $dbh_attribute_update = $go_policy->dbh_attribute_update();
        $request->dbh_attributes( $go_policy->dbh_attribute_list() )
            if $dbh_attribute_update eq 'every'
            or $dbh->{go_request_count}==1;

        $request->dbh_last_insert_id_args($meta->{go_last_insert_id_args})
            if $meta->{go_last_insert_id_args};

        my $transport = $dbh->{go_transport}
            or return $dbh->set_err($DBI::stderr, "Not connected (no transport)");

        local $transport->{go_cache} = $dbh->{go_cache}
            if defined $dbh->{go_cache};

        my ($response, $retransmit_sub) = $transport->transmit_request($request);
        $response ||= $transport->receive_response($request, $retransmit_sub);
        $dbh->{go_response} = $response
            or die "No response object returned by $transport";

        die "response '$response' returned by $transport is not a response object"
            unless UNIVERSAL::isa($response,"DBI::Gofer::Response");

        if (my $dbh_attributes = $response->dbh_attributes) {

            # XXX installed_methods piggybacks on dbh_attributes for now
            if (my $installed_methods = delete $dbh_attributes->{dbi_installed_methods}) {
                DBD::Gofer::install_methods_proxy($installed_methods)
                    if $dbh->{go_request_count}==1;
            }

            # XXX we don't STORE here, we just stuff the value into the attribute cache
            $dbh->{$_} = $dbh_attributes->{$_}
                for keys %$dbh_attributes;
        }

        my $rv = $response->rv;
        if (my $resultset_list = $response->sth_resultsets) {
            # dbh method call returned one or more resultsets
            # (was probably a metadata method like table_info)
            #
            # setup an sth but don't execute/forward it
            my $sth = $dbh->prepare(undef, { go_skip_prepare_check => 1 });
            # set the sth response to our dbh response
            (tied %$sth)->{go_response} = $response;
            # setup the sth with the results in our response
            $sth->more_results;
            # and return that new sth as if it came from original request
            $rv = [ $sth ];
        }
        elsif (!$rv) { # should only occur for major transport-level error
            #carp("no rv in response { @{[ %$response ]} }");
            $rv = [ ];
        }

        DBD::Gofer::set_err_from_response($dbh, $response);

        return (wantarray) ? @$rv : $rv->[0];
    }


    # Methods that should be forwarded but can be cached
    for my $method (qw(
        tables table_info column_info primary_key_info foreign_key_info statistics_info
        data_sources type_info_all get_info
        parse_trace_flags parse_trace_flag
        func
    )) {
        my $policy_name = "cache_$method";
        my $super_name  = "SUPER::$method";
        my $sub = sub {
            my $dbh = shift;
            my $rv;

            # if we know the remote side doesn't override the DBI's default method
            # then we might as well just call the DBI's default method on the client
            # (which may, in turn, call other methods that are forwarded, like get_info)
            if ($dbh->{dbi_default_methods}{$method} && $dbh->{go_policy}->skip_default_methods()) {
                $dbh->trace_msg("    !! $method: using local default as remote method is also default\n");
                return $dbh->$super_name(@_);
            }

            my $cache;
            my $cache_key;
            if (my $cache_it = $dbh->{go_policy}->$policy_name(undef, $dbh, @_)) {
                $cache = $dbh->{go_meta_cache} ||= {}; # keep separate from go_cache
                $cache_key = sprintf "%s_wa%d(%s)", $policy_name, wantarray||0,
                    join(",\t", map { # XXX basic but sufficient for now
                         !ref($_)            ? DBI::neat($_,1e6)
                        : ref($_) eq 'ARRAY' ? DBI::neat_list($_,1e6,",\001")
                        : ref($_) eq 'HASH'  ? do { my @k = sort keys %$_; DBI::neat_list([@k,@{$_}{@k}],1e6,",\002") }
                        : do { warn "unhandled argument type ($_)"; $_ }
                    } @_);
                if ($rv = $cache->{$cache_key}) {
                    $dbh->trace_msg("$method(@_) returning previously cached value ($cache_key)\n",4);
                    my @cache_rv = @$rv;
                    # if it's an sth we have to clone it
                    $cache_rv[0] = $cache_rv[0]->go_clone_sth if UNIVERSAL::isa($cache_rv[0],'DBI::st');
                    return (wantarray) ? @cache_rv : $cache_rv[0];
                }
            }

            $rv = [ (wantarray)
                ?       ($dbh->go_dbh_method(undef, $method, @_))
                : scalar $dbh->go_dbh_method(undef, $method, @_)
            ];

            if ($cache) {
                $dbh->trace_msg("$method(@_) caching return value ($cache_key)\n",4);
                my @cache_rv = @$rv;
                # if it's an sth we have to clone it
                #$cache_rv[0] = $cache_rv[0]->go_clone_sth
                #   if UNIVERSAL::isa($cache_rv[0],'DBI::st');
                $cache->{$cache_key} = \@cache_rv
                    unless UNIVERSAL::isa($cache_rv[0],'DBI::st'); # XXX cloning sth not yet done
            }

            return (wantarray) ? @$rv : $rv->[0];
        };
        no strict 'refs';
        *$method = $sub;
    }


    # Methods that can use the DBI defaults for some situations/drivers
    for my $method (qw(
        quote quote_identifier
    )) {    # XXX keep DBD::Gofer::Policy::Base in sync
        my $policy_name = "locally_$method";
        my $super_name  = "SUPER::$method";
        my $sub = sub {
            my $dbh = shift;

            # if we know the remote side doesn't override the DBI's default method
            # then we might as well just call the DBI's default method on the client
            # (which may, in turn, call other methods that are forwarded, like get_info)
            if ($dbh->{dbi_default_methods}{$method} && $dbh->{go_policy}->skip_default_methods()) {
                $dbh->trace_msg("    !! $method: using local default as remote method is also default\n");
                return $dbh->$super_name(@_);
            }

            # false:    use remote gofer
            # 1:        use local DBI default method
            # code ref: use the code ref
            my $locally = $dbh->{go_policy}->$policy_name($dbh, @_);
            if ($locally) {
                return $locally->($dbh, @_) if ref $locally eq 'CODE';
                return $dbh->$super_name(@_);
            }
            return $dbh->go_dbh_method(undef, $method, @_); # propagate context
        };
        no strict 'refs';
        *$method = $sub;
    }


    # Methods that should always fail
    for my $method (qw(
        begin_work commit rollback
    )) {
        no strict 'refs';
        *$method = sub { return shift->set_err($DBI::stderr, "$method not available with DBD::Gofer") }
    }


    sub do {
        my ($dbh, $sql, $attr, @args) = @_;
        delete $dbh->{Statement}; # avoid "Modification of non-creatable hash value attempted"
        $dbh->{Statement} = $sql; # for profiling and ShowErrorStatement
        my $meta = { go_last_insert_id_args => $attr->{go_last_insert_id_args} };
        return $dbh->go_dbh_method($meta, 'do', $sql, $attr, @args);
    }

    sub ping {
        my $dbh = shift;
        return $dbh->set_err(0, "can't ping while not connected") # warning
            unless $dbh->SUPER::FETCH('Active');
        my $skip_ping = $dbh->{go_policy}->skip_ping();
        return ($skip_ping) ? 1 : $dbh->go_dbh_method(undef, 'ping', @_);
    }

    sub last_insert_id {
        my $dbh = shift;
        my $response = $dbh->{go_response} or return undef;
        return $response->last_insert_id;
    }

    sub FETCH {
        my ($dbh, $attrib) = @_;

        # FETCH is effectively already cached because the DBI checks the
        # attribute cache in the handle before calling FETCH
        # and this FETCH copies the value into the attribute cache

        # forward driver-private attributes (except ours)
        if ($attrib =~ m/^[a-z]/ && $attrib !~ /^go_/) {
            my $value = $dbh->go_dbh_method(undef, 'FETCH', $attrib);
            $dbh->{$attrib} = $value; # XXX forces caching by DBI
            return $dbh->{$attrib} = $value;
        }

        # else pass up to DBI to handle
        return $dbh->SUPER::FETCH($attrib);
    }

    sub STORE {
        my ($dbh, $attrib, $value) = @_;
        if ($attrib eq 'AutoCommit') {
            croak "Can't enable transactions when using DBD::Gofer" if !$value;
            return $dbh->SUPER::STORE($attrib => ($value) ? -901 : -900);
        }
        return $dbh->SUPER::STORE($attrib => $value)
            # we handle this attribute locally
            if $dbh_local_store_attrib{$attrib}
            # or it's a private_ (application) attribute
            or $attrib =~ /^private_/
            # or not yet connected (ie being called by DBI->connect)
            or not $dbh->FETCH('Active');

        return $dbh->SUPER::STORE($attrib => $value)
            if $DBD::Gofer::xxh_local_store_attrib_if_same_value{$attrib}
            && do { # values are the same
                my $crnt = $dbh->FETCH($attrib);
                local $^W;
                (defined($value) ^ defined($crnt))
                    ? 0 # definedness differs
                    : $value eq $crnt;
            };

        # dbh attributes are set at connect-time - see connect()
        carp("Can't alter \$dbh->{$attrib} after handle created with DBD::Gofer") if $dbh->FETCH('Warn');
        return $dbh->set_err($DBI::stderr, "Can't alter \$dbh->{$attrib} after handle created with DBD::Gofer");
    }

    sub disconnect {
        my $dbh = shift;
        $dbh->{go_transport} = undef;
        $dbh->STORE(Active => 0);
    }

    sub prepare {
        my ($dbh, $statement, $attr)= @_;

        return $dbh->set_err($DBI::stderr, "Can't prepare when disconnected")
            unless $dbh->FETCH('Active');

        $attr = { %$attr } if $attr; # copy so we can edit

        my $policy     = delete($attr->{go_policy}) || $dbh->{go_policy};
        my $lii_args   = delete $attr->{go_last_insert_id_args};
        my $go_prepare = delete($attr->{go_prepare_method})
                      || $dbh->{go_prepare_method}
                      || $policy->prepare_method($dbh, $statement, $attr)
                      || 'prepare'; # e.g. for code not using placeholders
        my $go_cache = delete $attr->{go_cache};
        # set to undef if there are no attributes left for the actual prepare call
        $attr = undef if $attr and not %$attr;

        my ($sth, $sth_inner) = DBI::_new_sth($dbh, {
            Statement => $statement,
            go_prepare_call => [ 0, $go_prepare, $statement, $attr ],
            # go_method_calls => [], # autovivs if needed
            go_request => $dbh->{go_request},
            go_transport => $dbh->{go_transport},
            go_policy => $policy,
            go_last_insert_id_args => $lii_args,
            go_cache => $go_cache,
        });
        $sth->STORE(Active => 0);

        my $skip_prepare_check = $policy->skip_prepare_check($attr, $dbh, $statement, $attr, $sth);
        if (not $skip_prepare_check) {
            $sth->go_sth_method() or return undef;
        }

        return $sth;
    }

    sub prepare_cached {
        my ($dbh, $sql, $attr, $if_active)= @_;
        $attr ||= {};
        return $dbh->SUPER::prepare_cached($sql, {
            %$attr,
            go_prepare_method => $attr->{go_prepare_method} || 'prepare_cached',
        }, $if_active);
    }

    *go_cache = \&DBD::Gofer::go_cache;
}


{   package DBD::Gofer::st; # ====== STATEMENT ======
    $imp_data_size = 0;
    use strict;

    my %sth_local_store_attrib = (%DBD::Gofer::xxh_local_store_attrib, NUM_OF_FIELDS => 1);

    sub go_sth_method {
        my ($sth, $meta) = @_;

        if (my $ParamValues = $sth->{ParamValues}) {
            my $ParamAttr = $sth->{ParamAttr};
            # XXX the sort here is a hack to work around a DBD::Sybase bug
            # but only works properly for params 1..9
            # (reverse because of the unshift)
            my @params = reverse sort keys %$ParamValues;
            if (@params > 9 && ($sth->{Database}{go_dsn}||'') =~ /dbi:Sybase/) {
                # if more than 9 then we need to do a proper numeric sort
                # also warn to alert user of this issue
                warn "Sybase param binding order hack in use";
                @params = sort { $b <=> $a } @params;
            }
            for my $p (@params) {
                # unshift to put binds before execute call
                unshift @{ $sth->{go_method_calls} },
                    [ 'bind_param', $p, $ParamValues->{$p}, $ParamAttr->{$p} ];
            }
        }

        my $dbh = $sth->{Database} or die "panic";
        ++$dbh->{go_request_count};

        my $request = $sth->{go_request};
        $request->init_request($sth->{go_prepare_call}, $sth);
        $request->sth_method_calls(delete $sth->{go_method_calls})
            if $sth->{go_method_calls};
        $request->sth_result_attr({}); # (currently) also indicates this is an sth request

        $request->dbh_last_insert_id_args($meta->{go_last_insert_id_args})
            if $meta->{go_last_insert_id_args};

        my $go_policy = $sth->{go_policy};
        my $dbh_attribute_update = $go_policy->dbh_attribute_update();
        $request->dbh_attributes( $go_policy->dbh_attribute_list() )
            if $dbh_attribute_update eq 'every'
            or $dbh->{go_request_count}==1;

        my $transport = $sth->{go_transport}
            or return $sth->set_err($DBI::stderr, "Not connected (no transport)");

        local $transport->{go_cache} = $sth->{go_cache}
            if defined $sth->{go_cache};

        my ($response, $retransmit_sub) = $transport->transmit_request($request);
        $response ||= $transport->receive_response($request, $retransmit_sub);
        $sth->{go_response} = $response
            or die "No response object returned by $transport";
        $dbh->{go_response} = $response; # mainly for last_insert_id

        if (my $dbh_attributes = $response->dbh_attributes) {
            # XXX we don't STORE here, we just stuff the value into the attribute cache
            $dbh->{$_} = $dbh_attributes->{$_}
                for keys %$dbh_attributes;
            # record the values returned, so we know that we have fetched
            # values are which we have fetched (see dbh->FETCH method)
            $dbh->{go_dbh_attributes_fetched} = $dbh_attributes;
        }

        my $rv = $response->rv; # may be undef on error
        if ($response->sth_resultsets) {
            # setup first resultset - including sth attributes
            $sth->more_results;
        }
        else {
            $sth->STORE(Active => 0);
            $sth->{go_rows} = $rv;
        }
        # set error/warn/info (after more_results as that'll clear err)
        DBD::Gofer::set_err_from_response($sth, $response);

        return $rv;
    }


    sub bind_param {
        my ($sth, $param, $value, $attr) = @_;
        $sth->{ParamValues}{$param} = $value;
        $sth->{ParamAttr}{$param}   = $attr
            if defined $attr; # attr is sticky if not explicitly set
        return 1;
    }


    sub execute {
        my $sth = shift;
        $sth->bind_param($_, $_[$_-1]) for (1..@_);
        push @{ $sth->{go_method_calls} }, [ 'execute' ];
        my $meta = { go_last_insert_id_args => $sth->{go_last_insert_id_args} };
        return $sth->go_sth_method($meta);
    }


    sub more_results {
        my $sth = shift;

        $sth->finish;

        my $response = $sth->{go_response} or do {
            # e.g., we haven't sent a request yet (ie prepare then more_results)
            $sth->trace_msg("    No response object present", 3);
            return;
        };

        my $resultset_list = $response->sth_resultsets
            or return $sth->set_err($DBI::stderr, "No sth_resultsets");

        my $meta = shift @$resultset_list
            or return undef; # no more result sets
        #warn "more_results: ".Data::Dumper::Dumper($meta);

        # pull out the special non-attributes first
        my ($rowset, $err, $errstr, $state)
            = delete @{$meta}{qw(rowset err errstr state)};

        # copy meta attributes into attribute cache
        my $NUM_OF_FIELDS = delete $meta->{NUM_OF_FIELDS};
        $sth->STORE('NUM_OF_FIELDS', $NUM_OF_FIELDS);
        # XXX need to use STORE for some?
        $sth->{$_} = $meta->{$_} for keys %$meta;

        if (($NUM_OF_FIELDS||0) > 0) {
            $sth->{go_rows}           = ($rowset) ? @$rowset : -1;
            $sth->{go_current_rowset} = $rowset;
            $sth->{go_current_rowset_err} = [ $err, $errstr, $state ]
                if defined $err;
            $sth->STORE(Active => 1) if $rowset;
        }

        return $sth;
    }


    sub go_clone_sth {
        my ($sth1) = @_;
        # clone an (un-fetched-from) sth - effectively undoes the initial more_results
        # not 100% so just for use in caching returned sth e.g. table_info
        my $sth2 = $sth1->{Database}->prepare($sth1->{Statement}, { go_skip_prepare_check => 1 });
        $sth2->STORE($_, $sth1->{$_}) for qw(NUM_OF_FIELDS Active);
        my $sth2_inner = tied %$sth2;
        $sth2_inner->{$_} = $sth1->{$_} for qw(NUM_OF_PARAMS FetchHashKeyName);
        die "not fully implemented yet";
        return $sth2;
    }


    sub fetchrow_arrayref {
        my ($sth) = @_;
        my $resultset = $sth->{go_current_rowset} || do {
            # should only happen if fetch called after execute failed
            my $rowset_err = $sth->{go_current_rowset_err}
                || [ 1, 'no result set (did execute fail)' ];
            return $sth->set_err( @$rowset_err );
        };
        return $sth->_set_fbav(shift @$resultset) if @$resultset;
        $sth->finish;     # no more data so finish
        return undef;
    }
    *fetch = \&fetchrow_arrayref; # alias


    sub fetchall_arrayref {
        my ($sth, $slice, $max_rows) = @_;
        my $resultset = $sth->{go_current_rowset} || do {
            # should only happen if fetch called after execute failed
            my $rowset_err = $sth->{go_current_rowset_err}
                || [ 1, 'no result set (did execute fail)' ];
            return $sth->set_err( @$rowset_err );
        };
        my $mode = ref($slice) || 'ARRAY';
        return $sth->SUPER::fetchall_arrayref($slice, $max_rows)
            if ref($slice) or defined $max_rows;
        $sth->finish;     # no more data after this so finish
        return $resultset;
    }


    sub rows {
        return shift->{go_rows};
    }


    sub STORE {
        my ($sth, $attrib, $value) = @_;

        return $sth->SUPER::STORE($attrib => $value)
            if $sth_local_store_attrib{$attrib} # handle locally
            # or it's a private_ (application) attribute
            or $attrib =~ /^private_/;

        # otherwise warn but do it anyway
        # this will probably need refining later
        my $msg = "Altering \$sth->{$attrib} won't affect proxied handle";
        Carp::carp($msg) if $sth->FETCH('Warn');

        # XXX could perhaps do
        #   push @{ $sth->{go_method_calls} }, [ 'STORE', $attrib, $value ]
        #       if not $sth->FETCH('Executed');
        # but how to handle repeat executions? How to we know when an
        # attribute is being set to affect the current resultset or the
        # next execution?
        # Could just always use go_method_calls I guess.

        # do the store locally anyway, just in case
        $sth->SUPER::STORE($attrib => $value);

        return $sth->set_err($DBI::stderr, $msg);
    }

    # sub bind_param_array
    # we use DBI's default, which sets $sth->{ParamArrays}{$param} = $value
    # and calls bind_param($param, undef, $attr) if $attr.

    sub execute_array {
        my $sth = shift;
        my $attr = shift;
        $sth->bind_param_array($_, $_[$_-1]) for (1..@_);
        push @{ $sth->{go_method_calls} }, [ 'execute_array', $attr ];
        return $sth->go_sth_method($attr);
    }

    *go_cache = \&DBD::Gofer::go_cache;
}

1;

__END__

=head1 NAME

DBD::Gofer - A stateless-proxy driver for communicating with a remote DBI

=head1 SYNOPSIS

  use DBI;

  $original_dsn = "dbi:..."; # your original DBI Data Source Name

  $dbh = DBI->connect("dbi:Gofer:transport=$transport;...;dsn=$original_dsn",
                      $user, $passwd, \%attributes);

  ... use $dbh as if it was connected to $original_dsn ...


The C<transport=$transport> part specifies the name of the module to use to
transport the requests to the remote DBI. If $transport doesn't contain any
double colons then it's prefixed with C<DBD::Gofer::Transport::>.

The C<dsn=$original_dsn> part I<must be the last element> of the DSN because
everything after C<dsn=> is assumed to be the DSN that the remote DBI should
use.

The C<...> represents attributes that influence the operation of the Gofer
driver or transport. These are described below or in the documentation of the
transport module being used.

=encoding ISO8859-1

=head1 DESCRIPTION

DBD::Gofer is a DBI database driver that forwards requests to another DBI
driver, usually in a separate process, often on a separate machine. It tries to
be as transparent as possible so it appears that you are using the remote
driver directly.

DBD::Gofer is very similar to DBD::Proxy. The major difference is that with
DBD::Gofer no state is maintained on the remote end. That means every
request contains all the information needed to create the required state. (So,
for example, every request includes the DSN to connect to.) Each request can be
sent to any available server. The server executes the request and returns a
single response that includes all the data.

This is very similar to the way http works as a stateless protocol for the web.
Each request from your web browser can be handled by a different web server process.

=head2 Use Cases

This may seem like pointless overhead but there are situations where this is a
very good thing. Let's consider a specific case.

Imagine using DBD::Gofer with an http transport. Your application calls
connect(), prepare("select * from table where foo=?"), bind_param(), and execute().
At this point DBD::Gofer builds a request containing all the information
about the method calls. It then uses the httpd transport to send that request
to an apache web server.

This 'dbi execute' web server executes the request (using DBI::Gofer::Execute
and related modules) and builds a response that contains all the rows of data,
if the statement returned any, along with all the attributes that describe the
results, such as $sth->{NAME}. This response is sent back to DBD::Gofer which
unpacks it and presents it to the application as if it had executed the
statement itself.

=head2 Advantages

Okay, but you still don't see the point? Well let's consider what we've gained:

=head3 Connection Pooling and Throttling

The 'dbi execute' web server leverages all the functionality of web
infrastructure in terms of load balancing, high-availability, firewalls, access
management, proxying, caching.

At its most basic level you get a configurable pool of persistent database connections.

=head3 Simple Scaling

Got thousands of processes all trying to connect to the database? You can use
DBD::Gofer to connect them to your smaller pool of 'dbi execute' web servers instead.

=head3 Caching

Client-side caching is as simple as adding "C<cache=1>" to the DSN.
This feature alone can be worth using DBD::Gofer for.

=head3 Fewer Network Round-trips

DBD::Gofer sends as few requests as possible (dependent on the policy being used).

=head3 Thin Clients / Unsupported Platforms

You no longer need drivers for your database on every system.  DBD::Gofer is pure perl.

=head1 CONSTRAINTS

There are some natural constraints imposed by the DBD::Gofer 'stateless' approach.
But not many:

=head2 You can't change database handle attributes after connect()

You can't change database handle attributes after you've connected.
Use the connect() call to specify all the attribute settings you want.

This is because it's critical that when a request is complete the database
handle is left in the same state it was when first connected.

An exception is made for attributes with names starting "C<private_>":
They can be set after connect() but the change is only applied locally.

=head2 You can't change statement handle attributes after prepare()

You can't change statement handle attributes after prepare.

An exception is made for attributes with names starting "C<private_>":
They can be set after prepare() but the change is only applied locally.

=head2 You can't use transactions

AutoCommit only. Transactions aren't supported.

(In theory transactions could be supported when using a transport that
maintains a connection, like C<stream> does. If you're interested in this
please get in touch via dbi-dev@perl.org)

=head2 You can't call driver-private sth methods

But that's rarely needed anyway.

=head1 GENERAL CAVEATS

A few important things to keep in mind when using DBD::Gofer:

=head2 Temporary tables, locks, and other per-connection persistent state

You shouldn't expect any per-session state to persist between requests.
This includes locks and temporary tables.

Because the server-side may execute your requests via a different
database connections, you can't rely on any per-connection persistent state,
such as temporary tables, being available from one request to the next.

This is an easy trap to fall into. A good way to check for this is to test your
code with a Gofer policy package that sets the C<connect_method> policy to
'connect' to force a new connection for each request. The C<pedantic> policy does this.

=head2 Driver-private Database Handle Attributes

Some driver-private dbh attributes may not be available if the driver has not
implemented the private_attribute_info() method (added in DBI 1.54).

=head2 Driver-private Statement Handle Attributes

Driver-private sth attributes can be set in the prepare() call. TODO

Some driver-private sth attributes may not be available if the driver has not
implemented the private_attribute_info() method (added in DBI 1.54).

=head2 Multiple Resultsets

Multiple resultsets are supported only if the driver supports the more_results() method
(an exception is made for DBD::Sybase).

=head2 Statement activity that also updates dbh attributes

Some drivers may update one or more dbh attributes after performing activity on
a child sth.  For example, DBD::mysql provides $dbh->{mysql_insertid} in addition to
$sth->{mysql_insertid}. Currently mysql_insertid is supported via a hack but a
more general mechanism is needed for other drivers to use.

=head2 Methods that report an error always return undef

With DBD::Gofer, a method that sets an error always return an undef or empty list.
That shouldn't be a problem in practice because the DBI doesn't define any
methods that return meaningful values while also reporting an error.

=head2 Subclassing only applies to client-side

The RootClass and DbTypeSubclass attributes are not passed to the Gofer server.

=head1 CAVEATS FOR SPECIFIC METHODS

=head2 last_insert_id

To enable use of last_insert_id you need to indicate to DBD::Gofer that you'd
like to use it.  You do that my adding a C<go_last_insert_id_args> attribute to
the do() or prepare() method calls. For example:

    $dbh->do($sql, { go_last_insert_id_args => [...] });

or

    $sth = $dbh->prepare($sql, { go_last_insert_id_args => [...] });

The array reference should contains the args that you want passed to the
last_insert_id() method.

=head2 execute_for_fetch

The array methods bind_param_array() and execute_array() are supported.
When execute_array() is called the data is serialized and executed in a single
round-trip to the Gofer server. This makes it very fast, but requires enough
memory to store all the serialized data.

The execute_for_fetch() method currently isn't optimised, it uses the DBI
fallback behaviour of executing each tuple individually.
(It could be implemented as a wrapper for execute_array() - patches welcome.)

=head1 TRANSPORTS

DBD::Gofer doesn't concern itself with transporting requests and responses to and fro.
For that it uses special Gofer transport modules.

Gofer transport modules usually come in pairs: one for the 'client' DBD::Gofer
driver to use and one for the remote 'server' end. They have very similar names:

    DBD::Gofer::Transport::<foo>
    DBI::Gofer::Transport::<foo>

Sometimes the transports on the DBD and DBI sides may have different names. For
example DBD::Gofer::Transport::http is typically used with DBI::Gofer::Transport::mod_perl
(DBD::Gofer::Transport::http and DBI::Gofer::Transport::mod_perl modules are
part of the GoferTransport-http distribution).

=head2 Bundled Transports

Several transport modules are provided with DBD::Gofer:

=head3 null

The null transport is the simplest of them all. It doesn't actually transport the request anywhere.
It just serializes (freezes) the request into a string, then thaws it back into
a data structure before passing it to DBI::Gofer::Execute to execute. The same
freeze and thaw is applied to the results.

The null transport is the best way to test if your application will work with Gofer.
Just set the DBI_AUTOPROXY environment variable to "C<dbi:Gofer:transport=null;policy=pedantic>"
(see L</Using DBI_AUTOPROXY> below) and run your application, or ideally its test suite, as usual.

It doesn't take any parameters.

=head3 pipeone

The pipeone transport launches a subprocess for each request. It passes in the
request and reads the response.

The fact that a new subprocess is started for each request ensures that the
server side is truly stateless. While this does make the transport I<very> slow,
it is useful as a way to test that your application doesn't depend on
per-connection state, such as temporary tables, persisting between requests.

It's also useful both as a proof of concept and as a base class for the stream
driver.

=head3 stream

The stream driver also launches a subprocess and writes requests and reads
responses, like the pipeone transport.  In this case, however, the subprocess
is expected to handle more that one request. (Though it will be automatically
restarted if it exits.)

This is the first transport that is truly useful because it can launch the
subprocess on a remote machine using C<ssh>. This means you can now use DBD::Gofer
to easily access any databases that's accessible from any system you can login to.
You also get all the benefits of ssh, including encryption and optional compression.

See L</Using DBI_AUTOPROXY> below for an example.

=head2 Other Transports

Implementing a Gofer transport is I<very> simple, and more transports are very welcome.
Just take a look at any existing transports that are similar to your needs.

=head3 http

See the GoferTransport-http distribution on CPAN: http://search.cpan.org/dist/GoferTransport-http/

=head3 Gearman

I know Ask Bjørn Hansen has implemented a transport for the C<gearman> distributed
job system, though it's not on CPAN at the time of writing this.

=head1 CONNECTING

Simply prefix your existing DSN with "C<dbi:Gofer:transport=$transport;dsn=>"
where $transport is the name of the Gofer transport you want to use (see L</TRANSPORTS>).
The C<transport> and C<dsn> attributes must be specified and the C<dsn> attributes must be last.

Other attributes can be specified in the DSN to configure DBD::Gofer and/or the
Gofer transport module being used. The main attributes after C<transport>, are
C<url> and C<policy>. These and other attributes are described below.

=head2 Using DBI_AUTOPROXY

The simplest way to try out DBD::Gofer is to set the DBI_AUTOPROXY environment variable.
In this case you don't include the C<dsn=> part. For example:

    export DBI_AUTOPROXY="dbi:Gofer:transport=null"

or, for a more useful example, try:

    export DBI_AUTOPROXY="dbi:Gofer:transport=stream;url=ssh:user@example.com"

=head2 Connection Attributes

These attributes can be specified in the DSN. They can also be passed in the
\%attr parameter of the DBI connect method by adding a "C<go_>" prefix to the name.

=head3 transport

Specifies the Gofer transport class to use. Required. See L</TRANSPORTS> above.

If the value does not include C<::> then "C<DBD::Gofer::Transport::>" is prefixed.

The transport object can be accessed via $h->{go_transport}.

=head3 dsn

Specifies the DSN for the remote side to connect to. Required, and must be last.

=head3 url

Used to tell the transport where to connect to. The exact form of the value depends on the transport used.

=head3 policy

Specifies the policy to use. See L</CONFIGURING BEHAVIOUR POLICY>.

If the value does not include C<::> then "C<DBD::Gofer::Policy>" is prefixed.

The policy object can be accessed via $h->{go_policy}.

=head3 timeout

Specifies a timeout, in seconds, to use when waiting for responses from the server side.

=head3 retry_limit

Specifies the number of times a failed request will be retried. Default is 0.

=head3 retry_hook

Specifies a code reference to be called to decide if a failed request should be retried.
The code reference is called like this:

  $transport = $h->{go_transport};
  $retry = $transport->go_retry_hook->($request, $response, $transport);

If it returns true then the request will be retried, up to the C<retry_limit>.
If it returns a false but defined value then the request will not be retried.
If it returns undef then the default behaviour will be used, as if C<retry_hook>
had not been specified.

The default behaviour is to retry requests where $request->is_idempotent is true,
or the error message matches C</induced by DBI_GOFER_RANDOM/>.

=head3 cache

Specifies that client-side caching should be performed.  The value is the name
of a cache class to use.

Any class implementing get($key) and set($key, $value) methods can be used.
That includes a great many powerful caching classes on CPAN, including the
Cache and Cache::Cache distributions.

You can use "C<cache=1>" is a shortcut for "C<cache=DBI::Util::CacheMemory>".
See L<DBI::Util::CacheMemory> for a description of this simple fast default cache.

The cache object can be accessed via $h->go_cache. For example:

    $dbh->go_cache->clear; # free up memory being used by the cache

The cache keys are the frozen (serialized) requests, and the values are the
frozen responses.

The default behaviour is to only use the cache for requests where
$request->is_idempotent is true (i.e., the dbh has the ReadOnly attribute set
or the SQL statement is obviously a SELECT without a FOR UPDATE clause.)

For even more control you can use the C<go_cache> attribute to pass in an
instantiated cache object. Individual methods, including prepare(), can also
specify alternative caches via the C<go_cache> attribute. For example, to
specify no caching for a particular query, you could use

    $sth = $dbh->prepare( $sql, { go_cache => 0 } );

This can be used to implement different caching policies for different statements.

It's interesting to note that DBD::Gofer can be used to add client-side caching
to any (gofer compatible) application, with no code changes and no need for a
gofer server.  Just set the DBI_AUTOPROXY environment variable like this:

    DBI_AUTOPROXY='dbi:Gofer:transport=null;cache=1'

=head1 CONFIGURING BEHAVIOUR POLICY

DBD::Gofer supports a 'policy' mechanism that allows you to fine-tune the number of round-trips to the Gofer server.
The policies are grouped into classes (which may be subclassed) and referenced by the name of the class.

The L<DBD::Gofer::Policy::Base> class is the base class for all the policy
packages and describes all the available policies.

Three policy packages are supplied with DBD::Gofer:

L<DBD::Gofer::Policy::pedantic> is most 'transparent' but slowest because it
makes more  round-trips to the Gofer server.

L<DBD::Gofer::Policy::classic> is a reasonable compromise - it's the default policy.

L<DBD::Gofer::Policy::rush> is fastest, but may require code changes in your applications.

Generally the default C<classic> policy is fine. When first testing an existing
application with Gofer it is a good idea to start with the C<pedantic> policy
first and then switch to C<classic> or a custom policy, for final testing.


=head1 AUTHOR

Tim Bunce, L<http://www.tim.bunce.name>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2007, Tim Bunce, Ireland. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=head1 ACKNOWLEDGEMENTS

The development of DBD::Gofer and related modules was sponsored by
Shopzilla.com (L<http://Shopzilla.com>), where I currently work.

=head1 SEE ALSO

L<DBI::Gofer::Request>, L<DBI::Gofer::Response>, L<DBI::Gofer::Execute>.

L<DBI::Gofer::Transport::Base>, L<DBD::Gofer::Policy::Base>.

L<DBI>

=head1 Caveats for specific drivers

This section aims to record issues to be aware of when using Gofer with specific drivers.
It usually only documents issues that are not natural consequences of the limitations
of the Gofer approach - as documented above.

=head1 TODO

This is just a random brain dump... (There's more in the source of the Changes file, not the pod)

Document policy mechanism

Add mechanism for transports to list config params and for Gofer to apply any that match (and warn if any left over?)

Driver-private sth attributes - set via prepare() - change DBI spec

add hooks into transport base class for checking & updating a result set cache
   ie via a standard cache interface such as:
   http://search.cpan.org/~robm/Cache-FastMmap/FastMmap.pm
   http://search.cpan.org/~bradfitz/Cache-Memcached/lib/Cache/Memcached.pm
   http://search.cpan.org/~dclinton/Cache-Cache/
   http://search.cpan.org/~cleishman/Cache/
Also caching instructions could be passed through the httpd transport layer
in such a way that appropriate http cache headers are added to the results
so that web caches (squid etc) could be used to implement the caching.
(MUST require the use of GET rather than POST requests.)

Rework handling of installed_methods to not piggyback on dbh_attributes?

Perhaps support transactions for transports where it's possible (ie null and stream)?
Would make stream transport (ie ssh) more useful to more people.

Make sth_result_attr more like dbh_attributes (using '*' etc)

Add @val = FETCH_many(@names) to DBI in C and use in Gofer/Execute?

Implement _new_sth in C.

=cut
