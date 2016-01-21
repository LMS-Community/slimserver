package DBI::Gofer::Execute;

#   $Id: Execute.pm 14282 2010-07-26 00:12:54Z David $
#
#   Copyright (c) 2007, Tim Bunce, Ireland
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

use strict;
use warnings;

use Carp;

use DBI qw(dbi_time);
use DBI::Gofer::Request;
use DBI::Gofer::Response;

use base qw(DBI::Util::_accessor);

our $VERSION = "0.014283";

our @all_dbh_methods = sort map { keys %$_ } $DBI::DBI_methods{db}, $DBI::DBI_methods{common};
our %all_dbh_methods = map { $_ => (DBD::_::db->can($_)||undef) } @all_dbh_methods;

our $local_log = $ENV{DBI_GOFER_LOCAL_LOG}; # do extra logging to stderr

our $current_dbh;   # the dbh we're using for this request


# set trace for server-side gofer
# Could use DBI_TRACE env var when it's an unrelated separate process
# but using DBI_GOFER_TRACE makes testing easier for subprocesses (eg stream)
DBI->trace(split /=/, $ENV{DBI_GOFER_TRACE}, 2) if $ENV{DBI_GOFER_TRACE};


# define valid configuration attributes (args to new())
# the values here indicate the basic type of values allowed
my %configuration_attributes = (
    gofer_execute_class => 1,
    default_connect_dsn => 1,
    forced_connect_dsn  => 1,
    default_connect_attributes => {},
    forced_connect_attributes  => {},
    track_recent => 1,
    check_request_sub => sub {},
    check_response_sub => sub {},
    forced_single_resultset => 1,
    max_cached_dbh_per_drh => 1,
    max_cached_sth_per_dbh => 1,
    forced_response_attributes => {},
    forced_gofer_random => 1,
    stats => {},
);

__PACKAGE__->mk_accessors(
    keys %configuration_attributes
);



sub new {
    my ($self, $args) = @_;
    $args->{default_connect_attributes} ||= {};
    $args->{forced_connect_attributes}  ||= {};
    $args->{max_cached_sth_per_dbh}     ||= 1000;
    $args->{stats} ||= {};
    return $self->SUPER::new($args);
}


sub valid_configuration_attributes {
    my $self = shift;
    return { %configuration_attributes };
}


my %extra_attr = (
    # Only referenced if the driver doesn't support private_attribute_info method.
    # What driver-specific attributes should be returned for the driver being used?
    # keyed by $dbh->{Driver}{Name}
    # XXX for sth should split into attr specific to resultsets (where NUM_OF_FIELDS > 0) and others
    # which would reduce processing/traffic for non-select statements
    mysql  => {
        dbh => [qw(
            mysql_errno mysql_error mysql_hostinfo mysql_info mysql_insertid
            mysql_protoinfo mysql_serverinfo mysql_stat mysql_thread_id
        )],
        sth => [qw(
            mysql_is_blob mysql_is_key mysql_is_num mysql_is_pri_key mysql_is_auto_increment
            mysql_length mysql_max_length mysql_table mysql_type mysql_type_name mysql_insertid
        )],
        # XXX this dbh_after_sth stuff is a temporary, but important, hack.
        # should be done via hash instead of arrays where the hash value contains
        # flags that can indicate which attributes need to be handled in this way
        dbh_after_sth => [qw(
            mysql_insertid
        )],
    },
    Pg  => {
        dbh => [qw(
            pg_protocol pg_lib_version pg_server_version
            pg_db pg_host pg_port pg_default_port
            pg_options pg_pid
        )],
        sth => [qw(
            pg_size pg_type pg_oid_status pg_cmd_status
        )],
    },
    Sybase => {
        dbh => [qw(
            syb_dynamic_supported syb_oc_version syb_server_version syb_server_version_string
        )],
        sth => [qw(
            syb_types syb_proc_status syb_result_type
        )],
    },
    SQLite => {
        dbh => [qw(
            sqlite_version
        )],
        sth => [qw(
        )],
    },
    ExampleP => {
        dbh => [qw(
            examplep_private_dbh_attrib
        )],
        sth => [qw(
            examplep_private_sth_attrib
        )],
        dbh_after_sth => [qw(
            examplep_insertid
        )],
    },
);


sub _connect {
    my ($self, $request) = @_;

    my $stats = $self->{stats};

    # discard CachedKids from time to time
    if (++$stats->{_requests_served} % 1000 == 0 # XXX config?
        and my $max_cached_dbh_per_drh = $self->{max_cached_dbh_per_drh}
    ) {
        my %drivers = DBI->installed_drivers();
        while ( my ($driver, $drh) = each %drivers ) {
            next unless my $CK = $drh->{CachedKids};
            next unless keys %$CK > $max_cached_dbh_per_drh;
            next if $driver eq 'Gofer'; # ie transport=null when testing
            DBI->trace_msg(sprintf "Clearing %d cached dbh from $driver",
                scalar keys %$CK, $self->{max_cached_dbh_per_drh});
            $_->{Active} && $_->disconnect for values %$CK;
            %$CK = ();
        }
    }

    # local $ENV{...} can leak, so only do it if required
    local $ENV{DBI_AUTOPROXY} if $ENV{DBI_AUTOPROXY};

    my ($connect_method, $dsn, $username, $password, $attr) = @{ $request->dbh_connect_call };
    $connect_method ||= 'connect_cached';
    $stats->{method_calls_dbh}->{$connect_method}++;

    # delete attributes we don't want to affect the server-side
    # (Could just do this on client-side and trust the client. DoS?)
    delete @{$attr}{qw(Profile InactiveDestroy AutoInactiveDestroy HandleError HandleSetErr TraceLevel Taint TaintIn TaintOut)};

    $dsn = $self->forced_connect_dsn || $dsn || $self->default_connect_dsn
        or die "No forced_connect_dsn, requested dsn, or default_connect_dsn for request";

    my $random = $self->{forced_gofer_random} || $ENV{DBI_GOFER_RANDOM} || '';

    my $connect_attr = {

        # the configured default attributes, if any
        %{ $self->default_connect_attributes },

        # pass username and password as attributes
        # then they can be overridden by forced_connect_attributes
        Username => $username,
        Password => $password,

        # the requested attributes
        %$attr,

        # force some attributes the way we'd like them
        PrintWarn  => $local_log,
        PrintError => $local_log,

        # the configured default attributes, if any
        %{ $self->forced_connect_attributes },

        # RaiseError must be enabled
        RaiseError => 1,

        # reset Executed flag (of the cached handle) so we can use it to tell
        # if errors happened before the main part of the request was executed
        Executed => 0,

        # ensure this connect_cached doesn't have the same args as the client
        # because that causes subtle issues if in the same process (ie transport=null)
        # include pid to avoid problems with forking (ie null transport in mod_perl)
        # include gofer-random to avoid random behaviour leaking to other handles
        dbi_go_execute_unique => join("|", __PACKAGE__, $$, $random),
    };

    # XXX implement our own private connect_cached method? (with rate-limited ping)
    my $dbh = DBI->$connect_method($dsn, undef, undef, $connect_attr);

    $dbh->{ShowErrorStatement} = 1 if $local_log;

    # XXX should probably just be a Callbacks => arg to connect_cached
    # with a cache of pre-built callback hooks (memoized, without $self)
    if (my $random = $self->{forced_gofer_random} || $ENV{DBI_GOFER_RANDOM}) {
        $self->_install_rand_callbacks($dbh, $random);
    }

    my $CK = $dbh->{CachedKids};
    if ($CK && keys %$CK > $self->{max_cached_sth_per_dbh}) {
        %$CK = (); #  clear all statement handles
    }

    #$dbh->trace(0);
    $current_dbh = $dbh;
    return $dbh;
}


sub reset_dbh {
    my ($self, $dbh) = @_;
    $dbh->set_err(undef, undef); # clear any error state
}


sub new_response_with_err {
    my ($self, $rv, $eval_error, $dbh) = @_;
    # this is the usual way to create a response for both success and failure
    # capture err+errstr etc and merge in $eval_error ($@)

    my ($err, $errstr, $state) = ($DBI::err, $DBI::errstr, $DBI::state);

    if ($eval_error) {
        $err ||= $DBI::stderr || 1; # ensure err is true
        if ($errstr) {
            $eval_error =~ s/(?: : \s)? \Q$errstr//x if $errstr;
            chomp $errstr;
            $errstr .= "; $eval_error";
        }
        else {
            $errstr = $eval_error;
        }
    }
    chomp $errstr if $errstr;

    my $flags;
    # (XXX if we ever add transaction support then we'll need to take extra
    # steps because the commit/rollback would reset Executed before we get here)
    $flags |= GOf_RESPONSE_EXECUTED if $dbh && $dbh->{Executed};

    my $response = DBI::Gofer::Response->new({
        rv     => $rv,
        err    => $err,
        errstr => $errstr,
        state  => $state,
        flags  => $flags,
    });

    return $response;
}


sub execute_request {
    my ($self, $request) = @_;
    # should never throw an exception

    DBI->trace_msg("-----> execute_request\n");

    my @warnings;
    local $SIG{__WARN__} = sub {
        push @warnings, @_;
        warn @_ if $local_log;
    };

    my $response = eval {

        if (my $check_request_sub = $self->check_request_sub) {
            $request = $check_request_sub->($request, $self)
                or die "check_request_sub failed";
        }

        my $version = $request->version || 0;
        die ref($request)." version $version is not supported"
            if $version < 0.009116 or $version >= 1;

        ($request->is_sth_request)
            ? $self->execute_sth_request($request)
            : $self->execute_dbh_request($request);
    };
    $response ||= $self->new_response_with_err(undef, $@, $current_dbh);

    if (my $check_response_sub = $self->check_response_sub) {
        # not protected with an eval so it can choose to throw an exception
        my $new = $check_response_sub->($response, $self, $request);
        $response = $new if ref $new;
    }

    undef $current_dbh;

    $response->warnings(\@warnings) if @warnings;
    DBI->trace_msg("<----- execute_request\n");
    return $response;
}


sub execute_dbh_request {
    my ($self, $request) = @_;
    my $stats = $self->{stats};

    my $dbh;
    my $rv_ref = eval {
        $dbh = $self->_connect($request);
        my $args = $request->dbh_method_call; # [ wantarray, 'method_name', @args ]
        my $wantarray = shift @$args;
        my $meth      = shift @$args;
        $stats->{method_calls_dbh}->{$meth}++;
        my @rv = ($wantarray)
            ?        $dbh->$meth(@$args)
            : scalar $dbh->$meth(@$args);
        \@rv;
    } || [];
    my $response = $self->new_response_with_err($rv_ref, $@, $dbh);

    return $response if not $dbh;

    # does this request also want any dbh attributes returned?
    if (my $dbh_attributes = $request->dbh_attributes) {
        $response->dbh_attributes( $self->gather_dbh_attributes($dbh, $dbh_attributes) );
    }

    if ($rv_ref and my $lid_args = $request->dbh_last_insert_id_args) {
        $stats->{method_calls_dbh}->{last_insert_id}++;
        my $id = $dbh->last_insert_id( @$lid_args );
        $response->last_insert_id( $id );
    }

    if ($rv_ref and UNIVERSAL::isa($rv_ref->[0],'DBI::st')) {
        # dbh_method_call was probably a metadata method like table_info
        # that returns a statement handle, so turn the $sth into resultset
        my $sth = $rv_ref->[0];
        $response->sth_resultsets( $self->gather_sth_resultsets($sth, $request, $response) );
        $response->rv("(sth)"); # don't try to return actual sth
    }

    # we're finished with this dbh for this request
    $self->reset_dbh($dbh);

    return $response;
}


sub gather_dbh_attributes {
    my ($self, $dbh, $dbh_attributes) = @_;
    my @req_attr_names = @$dbh_attributes;
    if ($req_attr_names[0] eq '*') { # auto include std + private
        shift @req_attr_names;
        push @req_attr_names, @{ $self->_std_response_attribute_names($dbh) };
    }
    my %dbh_attr_values;
    @dbh_attr_values{@req_attr_names} = $dbh->FETCH_many(@req_attr_names);

    # XXX piggyback installed_methods onto dbh_attributes for now
    $dbh_attr_values{dbi_installed_methods} = { DBI->installed_methods };

    # XXX piggyback default_methods onto dbh_attributes for now
    $dbh_attr_values{dbi_default_methods} = _get_default_methods($dbh);

    return \%dbh_attr_values;
}


sub _std_response_attribute_names {
    my ($self, $h) = @_;
    $h = tied(%$h) || $h; # switch to inner handle

    # cache the private_attribute_info data for each handle
    # XXX might be better to cache it in the executor
    # as it's unlikely to change
    # or perhaps at least cache it in the dbh even for sth
    # as the sth are typically very short lived

    my ($dbh, $h_type, $driver_name, @attr_names);

    if ($dbh = $h->{Database}) {    # is an sth

        # does the dbh already have the answer cached?
        return $dbh->{private_gofer_std_attr_names_sth} if $dbh->{private_gofer_std_attr_names_sth};

        ($h_type, $driver_name) = ('sth', $dbh->{Driver}{Name});
        push @attr_names, qw(NUM_OF_PARAMS NUM_OF_FIELDS NAME TYPE NULLABLE PRECISION SCALE);
    }
    else {                          # is a dbh
        return $h->{private_gofer_std_attr_names_dbh} if $h->{private_gofer_std_attr_names_dbh};

        ($h_type, $driver_name, $dbh) = ('dbh', $h->{Driver}{Name}, $h);
        # explicitly add these because drivers may have different defaults
        # add Name so the client gets the real Name of the connection
        push @attr_names, qw(ChopBlanks LongReadLen LongTruncOk ReadOnly Name);
    }

    if (my $pai = $h->private_attribute_info) {
        push @attr_names, keys %$pai;
    }
    else {
        push @attr_names, @{ $extra_attr{ $driver_name }{$h_type} || []};
    }
    if (my $fra = $self->{forced_response_attributes}) {
        push @attr_names, @{ $fra->{ $driver_name }{$h_type} || []}
    }
    $dbh->trace_msg("_std_response_attribute_names for $driver_name $h_type: @attr_names\n");

    # cache into the dbh even for sth, as the dbh is usually longer lived
    return $dbh->{"private_gofer_std_attr_names_$h_type"} = \@attr_names;
}


sub execute_sth_request {
    my ($self, $request) = @_;
    my $dbh;
    my $sth;
    my $last_insert_id;
    my $stats = $self->{stats};

    my $rv = eval {
        $dbh = $self->_connect($request);

        my $args = $request->dbh_method_call; # [ wantarray, 'method_name', @args ]
        shift @$args; # discard wantarray
        my $meth = shift @$args;
        $stats->{method_calls_sth}->{$meth}++;
        $sth = $dbh->$meth(@$args);
        my $last = '(sth)'; # a true value (don't try to return actual sth)

        # execute methods on the sth, e.g., bind_param & execute
        if (my $calls = $request->sth_method_calls) {
            for my $meth_call (@$calls) {
                my $method = shift @$meth_call;
                $stats->{method_calls_sth}->{$method}++;
                $last = $sth->$method(@$meth_call);
            }
        }

        if (my $lid_args = $request->dbh_last_insert_id_args) {
            $stats->{method_calls_sth}->{last_insert_id}++;
            $last_insert_id = $dbh->last_insert_id( @$lid_args );
        }

        $last;
    };
    my $response = $self->new_response_with_err($rv, $@, $dbh);

    return $response if not $dbh;

    $response->last_insert_id( $last_insert_id )
        if defined $last_insert_id;

    # even if the eval failed we still want to try to gather attribute values
    # (XXX would be nice to be able to support streaming of results.
    # which would reduce memory usage and latency for large results)
    if ($sth) {
        $response->sth_resultsets( $self->gather_sth_resultsets($sth, $request, $response) );
        $sth->finish;
    }

    # does this request also want any dbh attributes returned?
    my $dbh_attr_set;
    if (my $dbh_attributes = $request->dbh_attributes) {
        $dbh_attr_set = $self->gather_dbh_attributes($dbh, $dbh_attributes);
    }
    # XXX needs to be integrated with private_attribute_info() etc
    if (my $dbh_attr = $extra_attr{$dbh->{Driver}{Name}}{dbh_after_sth}) {
        @{$dbh_attr_set}{@$dbh_attr} = $dbh->FETCH_many(@$dbh_attr);
    }
    $response->dbh_attributes($dbh_attr_set) if $dbh_attr_set && %$dbh_attr_set;

    $self->reset_dbh($dbh);

    return $response;
}


sub gather_sth_resultsets {
    my ($self, $sth, $request, $response) = @_;
    my $resultsets = eval {

        my $attr_names = $self->_std_response_attribute_names($sth);
        my $sth_attr = {};
        $sth_attr->{$_} = 1 for @$attr_names;

        # let the client add/remove sth attributes
        if (my $sth_result_attr = $request->sth_result_attr) {
            $sth_attr->{$_} = $sth_result_attr->{$_}
                for keys %$sth_result_attr;
        }
        my @sth_attr = grep { $sth_attr->{$_} } keys %$sth_attr;

        my $row_count = 0;
        my $rs_list = [];
        while (1) {
            my $rs = $self->fetch_result_set($sth, \@sth_attr);
            push @$rs_list, $rs;
            if (my $rows = $rs->{rowset}) {
                $row_count += @$rows;
            }
            last if $self->{forced_single_resultset};
            last if !($sth->more_results || $sth->{syb_more_results});
         }

        my $stats = $self->{stats};
        $stats->{rows_returned_total} += $row_count;
        $stats->{rows_returned_max} = $row_count
            if $row_count > ($stats->{rows_returned_max}||0);

        $rs_list;
    };
    $response->add_err(1, $@) if $@;
    return $resultsets;
}


sub fetch_result_set {
    my ($self, $sth, $sth_attr) = @_;
    my %meta;
    eval {
        @meta{ @$sth_attr } = $sth->FETCH_many(@$sth_attr);
        # we assume @$sth_attr contains NUM_OF_FIELDS
        $meta{rowset}       = $sth->fetchall_arrayref()
            if (($meta{NUM_OF_FIELDS}||0) > 0); # is SELECT
        # the fetchall_arrayref may fail with a 'not executed' kind of error
        # because gather_sth_resultsets/fetch_result_set are called even if
        # execute() failed, or even if there was no execute() call at all.
        # The corresponding error goes into the resultset err, not the top-level
        # response err, so in most cases this resultset err is never noticed.
    };
    if ($@) {
        chomp $@;
        $meta{err}    = $DBI::err    || 1;
        $meta{errstr} = $DBI::errstr || $@;
        $meta{state}  = $DBI::state;
    }
    return \%meta;
}


sub _get_default_methods {
    my ($dbh) = @_;
    # returns a ref to a hash of dbh method names for methods which the driver
    # hasn't overridden i.e., quote(). These don't need to be forwarded via gofer.
    my $ImplementorClass = $dbh->{ImplementorClass} or die;
    my %default_methods;
    for my $method (@all_dbh_methods) {
        my $dbi_sub = $all_dbh_methods{$method}       || 42;
        my $imp_sub = $ImplementorClass->can($method) || 42;
        next if $imp_sub != $dbi_sub;
        #warn("default $method\n");
        $default_methods{$method} = 1;
    }
    return \%default_methods;
}


# XXX would be nice to make this a generic DBI module
sub _install_rand_callbacks {
    my ($self, $dbh, $dbi_gofer_random) = @_;

    my $callbacks = $dbh->{Callbacks} || {};
    my $prev      = $dbh->{private_gofer_rand_fail_callbacks} || {};

    # return if we've already setup this handle with callbacks for these specs
    return if (($callbacks->{_dbi_gofer_random_spec}||'') eq $dbi_gofer_random);
    #warn "$dbh # $callbacks->{_dbi_gofer_random_spec}";
    $callbacks->{_dbi_gofer_random_spec} = $dbi_gofer_random;

    my ($fail_percent, $fail_err, $delay_percent, $delay_duration, %spec_part, @spec_note);
    my @specs = split /,/, $dbi_gofer_random;
    for my $spec (@specs) {
        if ($spec =~ m/^fail=(-?[.\d]+)%?$/) {
            $fail_percent = $1;
            $spec_part{fail} = $spec;
            next;
        }
        if ($spec =~ m/^err=(-?\d+)$/) {
            $fail_err = $1;
            $spec_part{err} = $spec;
            next;
        }
        if ($spec =~ m/^delay([.\d]+)=(-?[.\d]+)%?$/) {
            $delay_duration = $1;
            $delay_percent  = $2;
            $spec_part{delay} = $spec;
            next;
        }
        elsif ($spec !~ m/^(\w+|\*)$/) {
            warn "Ignored DBI_GOFER_RANDOM item '$spec' which isn't a config or a dbh method name";
            next;
        }

        my $method = $spec;
        if ($callbacks->{$method} && $prev->{$method} && $callbacks->{$method} != $prev->{$method}) {
            warn "Callback for $method method already installed so DBI_GOFER_RANDOM callback not installed\n";
            next;
        }
        unless (defined $fail_percent or defined $delay_percent) {
            warn "Ignored DBI_GOFER_RANDOM item '$spec' because not preceded by 'fail=N' and/or 'delayN=N'";
            next;
        }

        push @spec_note, join(",", values(%spec_part), $method);
        $callbacks->{$method} = $self->_mk_rand_callback($method, $fail_percent, $delay_percent, $delay_duration, $fail_err);
    }
    warn "DBI_GOFER_RANDOM failures/delays enabled: @spec_note\n"
        if @spec_note;
    $dbh->{Callbacks} = $callbacks;
    $dbh->{private_gofer_rand_fail_callbacks} = $callbacks;
}

my %_mk_rand_callback_seqn;

sub _mk_rand_callback {
    my ($self, $method, $fail_percent, $delay_percent, $delay_duration, $fail_err) = @_;
    my ($fail_modrate, $delay_modrate);
    $fail_percent  ||= 0;  $fail_modrate  = int(1/(-$fail_percent )*100) if $fail_percent;
    $delay_percent ||= 0;  $delay_modrate = int(1/(-$delay_percent)*100) if $delay_percent;
    # note that $method may be "*" but that's not recommended or documented or wise
    return sub {
        my ($h) = @_;
        my $seqn = ++$_mk_rand_callback_seqn{$method};
        my $delay = ($delay_percent > 0) ? rand(100) < $delay_percent :
                    ($delay_percent < 0) ? !($seqn % $delay_modrate): 0;
        my $fail  = ($fail_percent  > 0) ? rand(100) < $fail_percent  :
                    ($fail_percent  < 0) ? !($seqn % $fail_modrate) : 0;
        #no warnings 'uninitialized';
        #warn "_mk_rand_callback($fail_percent:$fail_modrate, $delay_percent:$delay_modrate): seqn=$seqn fail=$fail delay=$delay";
        if ($delay) {
            my $msg = "DBI_GOFER_RANDOM delaying execution of $method() by $delay_duration seconds\n";
            # Note what's happening in a trace message. If the delay percent is an even
            # number then use warn() instead so it's sent back to the client.
            ($delay_percent % 2 == 1) ? warn($msg) : $h->trace_msg($msg);
            select undef, undef, undef, $delay_duration; # allows floating point value
        }
        if ($fail) {
            undef $_; # tell DBI to not call the method
            # the "induced by DBI_GOFER_RANDOM" is special and must be included in errstr
            # as it's checked for in a few places, such as the gofer retry logic
            return $h->set_err($fail_err || $DBI::stderr,
                "fake error from $method method induced by DBI_GOFER_RANDOM env var ($fail_percent%)");
        }
        return;
    }
}


sub update_stats {
    my ($self,
        $request, $response,
        $frozen_request, $frozen_response,
        $time_received,
        $store_meta, $other_meta,
    ) = @_;

    # should always have a response object here
    carp("No response object provided") unless $request;

    my $stats = $self->{stats};
    $stats->{frozen_request_max_bytes} = length($frozen_request)
        if $frozen_request
        && length($frozen_request)  > ($stats->{frozen_request_max_bytes}||0);
    $stats->{frozen_response_max_bytes} = length($frozen_response)
        if $frozen_response
        && length($frozen_response) > ($stats->{frozen_response_max_bytes}||0);

    my $recent;
    if (my $track_recent = $self->{track_recent}) {
        $recent = {
            request  => $frozen_request,
            response => $frozen_response,
            time_received => $time_received,
            duration => dbi_time()-$time_received,
            # for any other info
            ($store_meta) ? (meta => $store_meta) : (),
        };
        $recent->{request_object} = $request
            if !$frozen_request && $request;
        $recent->{response_object} = $response
            if !$frozen_response;
        my @queues =  ($stats->{recent_requests} ||= []);
        push @queues, ($stats->{recent_errors}   ||= [])
            if !$response or $response->err;
        for my $queue (@queues) {
            push @$queue, $recent;
            shift @$queue if @$queue > $track_recent;
        }
    }
    return $recent;
}


1;
__END__

=head1 NAME

DBI::Gofer::Execute - Executes Gofer requests and returns Gofer responses

=head1 SYNOPSIS

  $executor = DBI::Gofer::Execute->new( { ...config... });

  $response = $executor->execute_request( $request );

=head1 DESCRIPTION

Accepts a DBI::Gofer::Request object, executes the requested DBI method calls,
and returns a DBI::Gofer::Response object.

Any error, including any internal 'fatal' errors are caught and converted into
a DBI::Gofer::Response object.

This module is usually invoked by a 'server-side' Gofer transport module.
They usually have names in the "C<DBI::Gofer::Transport::*>" namespace.
Examples include: L<DBI::Gofer::Transport::stream> and L<DBI::Gofer::Transport::mod_perl>.

=head1 CONFIGURATION

=head2 check_request_sub

If defined, it must be a reference to a subroutine that will 'check' the request.
It is passed the request object and the executor as its only arguments.

The subroutine can either return the original request object or die with a
suitable error message (which will be turned into a Gofer response).

It can also construct and return a new request that should be executed instead
of the original request.

=head2 check_response_sub

If defined, it must be a reference to a subroutine that will 'check' the response.
It is passed the response object, the executor, and the request object.
The sub may alter the response object and return undef, or return a new response object.

This mechanism can be used to, for example, terminate the service if specific
database errors are seen.

=head2 forced_connect_dsn

If set, this DSN is always used instead of the one in the request.

=head2 default_connect_dsn

If set, this DSN is used if C<forced_connect_dsn> is not set and the request does not contain a DSN itself.

=head2 forced_connect_attributes

A reference to a hash of connect() attributes. Individual attributes in
C<forced_connect_attributes> will take precedence over corresponding attributes
in the request.

=head2 default_connect_attributes

A reference to a hash of connect() attributes. Individual attributes in the
request take precedence over corresponding attributes in C<default_connect_attributes>.

=head2 max_cached_dbh_per_drh

If set, the loaded drivers will be checked to ensure they don't have more than
this number of cached connections. There is no default value. This limit is not
enforced for every request.

=head2 max_cached_sth_per_dbh

If set, all the cached statement handles will be cleared once the number of
cached statement handles rises above this limit. The default is 1000.

=head2 forced_single_resultset

If true, then only the first result set will be fetched and returned in the response.

=head2 forced_response_attributes

A reference to a data structure that can specify extra attributes to be returned in responses.

  forced_response_attributes => {
      DriverName => {
          dbh => [ qw(dbh_attrib_name) ],
          sth => [ qw(sth_attrib_name) ],
      },
  },

This can be useful in cases where the driver has not implemented the
private_attribute_info() method and DBI::Gofer::Execute's own fallback list of
private attributes doesn't include the driver or attributes you need.

=head2 track_recent

If set, specifies the number of recent requests and responses that should be
kept by the update_stats() method for diagnostics. See L<DBI::Gofer::Transport::mod_perl>.

Note that this setting can significantly increase memory use. Use with caution.

=head2 forced_gofer_random

Enable forced random failures and/or delays for testing. See L</DBI_GOFER_RANDOM> below.

=head1 DRIVER-SPECIFIC ISSUES

Gofer needs to know about any driver-private attributes that should have their
values sent back to the client.

If the driver doesn't support private_attribute_info() method, and very few do,
then the module fallsback to using some hard-coded details, if available, for
the driver being used. Currently hard-coded details are available for the
mysql, Pg, Sybase, and SQLite drivers.

=head1 TESTING

DBD::Gofer, DBD::Execute and related packages are well tested by executing the
DBI test suite with DBI_AUTOPROXY configured to route all DBI calls via DBD::Gofer.

Because Gofer includes timeout and 'retry on error' mechanisms there is a need
for some way to trigger delays and/or errors. This can be done via the
C<forced_gofer_random> configuration item, or else the DBI_GOFER_RANDOM environment
variable.

=head2 DBI_GOFER_RANDOM

The value of the C<forced_gofer_random> configuration item (or else the
DBI_GOFER_RANDOM environment variable) is treated as a series of tokens
separated by commas.

The tokens can be one of three types:

=over 4

=item fail=R%

Set the current failure rate to R where R is a percentage.
The value R can be floating point, e.g., C<fail=0.05%>.
Negative values for R have special meaning, see below.

=item err=N

Sets the current failure err value to N (instead of the DBI's default 'standard
err value' of 2000000000). This is useful when you want to simulate a
specific error.

=item delayN=R%

Set the current random delay rate to R where R is a percentage, and set the
current delay duration to N seconds. The values of R and N can be floating point,
e.g., C<delay0.5=0.2%>.  Negative values for R have special meaning, see below.

If R is an odd number (R % 2 == 1) then a message is logged via warn() which
will be returned to, and echoed at, the client.

=item methodname

Applies the current fail, err, and delay values to the named method.
If neither a fail nor delay have been set yet then a warning is generated.

=back

For example:

  $executor = DBI::Gofer::Execute->new( {
    forced_gofer_random => "fail=0.01%,do,delay60=1%,execute",
  });

will cause the do() method to fail for 0.01% of calls, and the execute() method to
fail 0.01% of calls and be delayed by 60 seconds on 1% of calls.

If the percentage value (C<R>) is negative then instead of the failures being
triggered randomly (via the rand() function) they are triggered via a sequence
number. In other words "C<fail=-20%>" will mean every fifth call will fail.
Each method has a distinct sequence number.

=head1 AUTHOR

Tim Bunce, L<http://www.tim.bunce.name>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2007, Tim Bunce, Ireland. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=cut
