#   -*- perl -*-
#
#
#   DBD::Proxy - DBI Proxy driver
#
#
#   Copyright (c) 1997,1998  Jochen Wiedmann
#
#   The DBD::Proxy module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself. In particular permission
#   is granted to Tim Bunce for distributing this as a part of the DBI.
#
#
#   Author: Jochen Wiedmann
#           Am Eisteich 9
#           72555 Metzingen
#           Germany
#
#           Email: joe@ispsoft.de
#           Phone: +49 7123 14881
#

use strict;
use Carp;

require DBI;
DBI->require_version(1.0201);

use RPC::PlClient 0.2000; # XXX change to 0.2017 once it's released

{	package DBD::Proxy::RPC::PlClient;
    	@DBD::Proxy::RPC::PlClient::ISA = qw(RPC::PlClient);
	sub Call {
	    my $self = shift;
	    if ($self->{debug}) {
		my ($rpcmeth, $obj, $method, @args) = @_;
		local $^W; # silence undefs
		Carp::carp("Server $rpcmeth $method(@args)");
	    }
	    return $self->SUPER::Call(@_);
	}
}


package DBD::Proxy;

use vars qw($VERSION $drh %ATTR);

$VERSION = "0.2004";

$drh = undef;		# holds driver handle once initialised

%ATTR = (	# common to db & st, see also %ATTR in DBD::Proxy::db & ::st
    'Warn'	=> 'local',
    'Active'	=> 'local',
    'Kids'	=> 'local',
    'CachedKids' => 'local',
    'PrintError' => 'local',
    'RaiseError' => 'local',
    'HandleError' => 'local',
    'TraceLevel' => 'cached',
    'CompatMode' => 'local',
);

sub driver ($$) {
    if (!$drh) {
	my($class, $attr) = @_;

	$class .= "::dr";

	$drh = DBI::_new_drh($class, {
	    'Name' => 'Proxy',
	    'Version' => $VERSION,
	    'Attribution' => 'DBD::Proxy by Jochen Wiedmann',
	});
	$drh->STORE(CompatMode => 1); # disable DBI dispatcher attribute cache (for FETCH)
    }
    $drh;
}

sub CLONE {
    undef $drh;
}

sub proxy_set_err {
  my ($h,$errmsg) = @_;
  my ($err, $state) = ($errmsg =~ s/ \[err=(.*?),state=(.*?)\]//)
	? ($1, $2) : (1, ' ' x 5);
  return $h->set_err($err, $errmsg, $state);
}

package DBD::Proxy::dr; # ====== DRIVER ======

$DBD::Proxy::dr::imp_data_size = 0;

sub connect ($$;$$) {
    my($drh, $dsn, $user, $auth, $attr)= @_;
    my($dsnOrig) = $dsn;

    my %attr = %$attr;
    my ($var, $val);
    while (length($dsn)) {
	if ($dsn =~ /^dsn=(.*)/) {
	    $attr{'dsn'} = $1;
	    last;
	}
	if ($dsn =~ /^(.*?);(.*)/) {
	    $var = $1;
	    $dsn = $2;
	} else {
	    $var = $dsn;
	    $dsn = '';
	}
	if ($var =~ /^(.*?)=(.*)/) {
	    $var = $1;
	    $val = $2;
	    $attr{$var} = $val;
	}
    }

    my $err = '';
    if (!defined($attr{'hostname'})) { $err .= " Missing hostname."; }
    if (!defined($attr{'port'}))     { $err .= " Missing port."; }
    if (!defined($attr{'dsn'}))      { $err .= " Missing remote dsn."; }

    # Create a cipher object, if requested
    my $cipherRef = undef;
    if ($attr{'cipher'}) {
	$cipherRef = eval { $attr{'cipher'}->new(pack('H*',
							$attr{'key'})) };
	if ($@) { $err .= " Cannot create cipher object: $@."; }
    }
    my $userCipherRef = undef;
    if ($attr{'userkey'}) {
	my $cipher = $attr{'usercipher'} || $attr{'cipher'};
	$userCipherRef = eval { $cipher->new(pack('H*', $attr{'userkey'})) };
	if ($@) { $err .= " Cannot create usercipher object: $@."; }
    }

    return DBD::Proxy::proxy_set_err($drh, $err) if $err; # Returns undef

    my %client_opts = (
		       'peeraddr'	=> $attr{'hostname'},
		       'peerport'	=> $attr{'port'},
		       'socket_proto'	=> 'tcp',
		       'application'	=> $attr{dsn},
		       'user'		=> $user || '',
		       'password'	=> $auth || '',
		       'version'	=> $DBD::Proxy::VERSION,
		       'cipher'	        => $cipherRef,
		       'debug'		=> $attr{debug}   || 0,
		       'timeout'	=> $attr{timeout} || undef,
		       'logfile'	=> $attr{logfile} || undef
		      );
    # Options starting with 'proxy_rpc_' are forwarded to the RPC layer after
    # stripping the prefix.
    while (my($var,$val) = each %attr) {
	if ($var =~ s/^proxy_rpc_//) {
	    $client_opts{$var} = $val;
	}
    }
    # Create an RPC::PlClient object.
    my($client, $msg) = eval { DBD::Proxy::RPC::PlClient->new(%client_opts) };

    return DBD::Proxy::proxy_set_err($drh, "Cannot log in to DBI::ProxyServer: $@")
	if $@; # Returns undef
    return DBD::Proxy::proxy_set_err($drh, "Constructor didn't return a handle: $msg")
	unless ($msg =~ /^((?:\w+|\:\:)+)=(\w+)/); # Returns undef

    $msg = RPC::PlClient::Object->new($1, $client, $msg);

    my $max_proto_ver;
    my ($server_ver_str) = eval { $client->Call('Version') };
    if ( $@ ) {
      # Server denies call, assume legacy protocol.
      $max_proto_ver = 1;
    } else {
      # Parse proxy server version.
      my ($server_ver_num) = $server_ver_str =~ /^DBI::ProxyServer\s+([\d\.]+)/;
      $max_proto_ver = $server_ver_num >= 0.3 ? 2 : 1;
    }
    my $req_proto_ver;
    if ( exists $attr{proxy_lazy_prepare} ) {
      $req_proto_ver = ($attr{proxy_lazy_prepare} == 0) ? 2 : 1;
      return DBD::Proxy::proxy_set_err($drh, 
                 "DBI::ProxyServer does not support synchronous statement preparation.")
	if $max_proto_ver < $req_proto_ver;
    }

    # Switch to user specific encryption mode, if desired
    if ($userCipherRef) {
	$client->{'cipher'} = $userCipherRef;
    }

    # create a 'blank' dbh
    my $this = DBI::_new_dbh($drh, {
	    'Name' => $dsnOrig,
	    'proxy_dbh' => $msg,
	    'proxy_client' => $client,
	    'RowCacheSize' => $attr{'RowCacheSize'} || 20,
	    'proxy_proto_ver' => $req_proto_ver || 1
   });

    foreach $var (keys %attr) {
	if ($var =~ /proxy_/) {
	    $this->{$var} = $attr{$var};
	}
    }
    $this->SUPER::STORE('Active' => 1);

    $this;
}


sub DESTROY { undef }


package DBD::Proxy::db; # ====== DATABASE ======

$DBD::Proxy::db::imp_data_size = 0;

# XXX probably many more methods need to be added here
# in order to trigger our AUTOLOAD to redirect them to the server.
# (Unless the sub is declared it's bypassed by perl method lookup.)
# See notes in ToDo about method metadata
# The question is whether to add all the methods in %DBI::DBI_methods
# to the corresponding classes (::db, ::st etc)
# Also need to consider methods that, if proxied, would change the server state
# in a way that might not be visible on the client, ie begin_work -> AutoCommit.

sub commit;
sub rollback;
sub ping;

use vars qw(%ATTR $AUTOLOAD);

# inherited: STORE / FETCH against this class.
# local:     STORE / FETCH against parent class.
# cached:    STORE to remote and local objects, FETCH from local.
# remote:    STORE / FETCH against remote object only (default).
#
# Note: Attribute names starting with 'proxy_' always treated as 'inherited'.
#
%ATTR = (	# see also %ATTR in DBD::Proxy::st
    %DBD::Proxy::ATTR,
    RowCacheSize => 'inherited',
    #AutoCommit => 'cached',
    'FetchHashKeyName' => 'cached',
    Statement => 'local',
    Driver => 'local',
    dbi_connect_closure => 'local',
    Username => 'local',
);

sub AUTOLOAD {
    my $method = $AUTOLOAD;
    $method =~ s/(.*::(.*)):://;
    my $class = $1;
    my $type = $2;
    #warn "AUTOLOAD of $method (class=$class, type=$type)";
    my %expand = (
        'method' => $method,
        'class' => $class,
        'type' => $type,
        'call' => "$method(\@_)",
        # XXX was trying to be smart but was tripping up over the DBI's own
        # smartness. Disabled, but left here in case there are issues.
    #   'call' => (UNIVERSAL::can("DBI::_::$type", $method)) ? "$method(\@_)" : "func(\@_, '$method')",
    );

    my $method_code = q{
        package ~class~;
        sub ~method~ {
            my $h = shift;
            local $@;
            my @result = wantarray
                ? eval {        $h->{'proxy_~type~h'}->~call~ }
                : eval { scalar $h->{'proxy_~type~h'}->~call~ };
            return DBD::Proxy::proxy_set_err($h, $@) if $@;
            return wantarray ? @result : $result[0];
        }
    };
    $method_code =~ s/\~(\w+)\~/$expand{$1}/eg;
    local $SIG{__DIE__} = 'DEFAULT';
    my $err = do { local $@; eval $method_code.2; $@ };
    die $err if $err;
    goto &$AUTOLOAD;
}

sub DESTROY {
    my $dbh = shift;
    local $@ if $@;	# protect $@
    $dbh->disconnect if $dbh->SUPER::FETCH('Active');
}


sub connected { } # client-side not server-side, RT#75868

sub disconnect ($) {
    my ($dbh) = @_;

    # Sadly the Proxy too-often disagrees with the backend database
    # on the subject of 'Active'.  In the short term, I'd like the
    # Proxy to ease up and let me decide when it's proper to go over
    # the wire.  This ultimately applies to finish() as well.
    #return unless $dbh->SUPER::FETCH('Active');

    # Drop database connection at remote end
    my $rdbh = $dbh->{'proxy_dbh'};
    if ( $rdbh ) {
        local $SIG{__DIE__} = 'DEFAULT';
        local $@;
	eval { $rdbh->disconnect() } ;
        DBD::Proxy::proxy_set_err($dbh, $@) if $@;
    }
    
    # Close TCP connect to remote
    # XXX possibly best left till DESTROY? Add a config attribute to choose?
    #$dbh->{proxy_client}->Disconnect(); # Disconnect method requires newer PlRPC module
    $dbh->{proxy_client}->{socket} = undef; # hack

    $dbh->SUPER::STORE('Active' => 0);
    1;
}


sub STORE ($$$) {
    my($dbh, $attr, $val) = @_;
    my $type = $ATTR{$attr} || 'remote';

    if ($attr eq 'TraceLevel') {
	warn("TraceLevel $val");
	my $pc = $dbh->{proxy_client} || die;
	$pc->{logfile} ||= 1; # XXX hack
	$pc->{debug} = ($val && $val >= 4);
	$pc->Debug("$pc debug enabled") if $pc->{debug};
    }

    if ($attr =~ /^proxy_/  ||  $type eq 'inherited') {
	$dbh->{$attr} = $val;
	return 1;
    }

    if ($type eq 'remote' ||  $type eq 'cached') {
        local $SIG{__DIE__} = 'DEFAULT';
	local $@;
	my $result = eval { $dbh->{'proxy_dbh'}->STORE($attr => $val) };
	return DBD::Proxy::proxy_set_err($dbh, $@) if $@; # returns undef
	$dbh->SUPER::STORE($attr => $val) if $type eq 'cached';
	return $result;
    }
    return $dbh->SUPER::STORE($attr => $val);
}

sub FETCH ($$) {
    my($dbh, $attr) = @_;
    # we only get here for cached attribute values if the handle is in CompatMode
    # otherwise the DBI dispatcher handles the FETCH itself from the attribute cache.
    my $type = $ATTR{$attr} || 'remote';

    if ($attr =~ /^proxy_/  ||  $type eq 'inherited'  || $type eq 'cached') {
	return $dbh->{$attr};
    }

    return $dbh->SUPER::FETCH($attr) unless $type eq 'remote';

    local $SIG{__DIE__} = 'DEFAULT';
    local $@;
    my $result = eval { $dbh->{'proxy_dbh'}->FETCH($attr) };
    return DBD::Proxy::proxy_set_err($dbh, $@) if $@;
    return $result;
}

sub prepare ($$;$) {
    my($dbh, $stmt, $attr) = @_;
    my $sth = DBI::_new_sth($dbh, {
				   'Statement' => $stmt,
				   'proxy_attr' => $attr,
				   'proxy_cache_only' => 0,
				   'proxy_params' => [],
				  }
			   );
    my $proto_ver = $dbh->{'proxy_proto_ver'};
    if ( $proto_ver > 1 ) {
      $sth->{'proxy_attr_cache'} = {cache_filled => 0};
      my $rdbh = $dbh->{'proxy_dbh'};
      local $SIG{__DIE__} = 'DEFAULT';
      local $@;
      my $rsth = eval { $rdbh->prepare($sth->{'Statement'}, $sth->{'proxy_attr'}, undef, $proto_ver) };
      return DBD::Proxy::proxy_set_err($sth, $@) if $@;
      return DBD::Proxy::proxy_set_err($sth, "Constructor didn't return a handle: $rsth")
	unless ($rsth =~ /^((?:\w+|\:\:)+)=(\w+)/);
    
      my $client = $dbh->{'proxy_client'};
      $rsth = RPC::PlClient::Object->new($1, $client, $rsth);
      
      $sth->{'proxy_sth'} = $rsth;
      # If statement is a positioned update we do not want any readahead.
      $sth->{'RowCacheSize'} = 1 if $stmt =~ /\bfor\s+update\b/i;
    # Since resources are used by prepared remote handle, mark us active.
    $sth->SUPER::STORE(Active => 1);
    }
    $sth;
}

sub quote {
    my $dbh = shift;
    my $proxy_quote = $dbh->{proxy_quote} || 'remote';

    return $dbh->SUPER::quote(@_)
	if $proxy_quote eq 'local' && @_ == 1;

    # For the common case of only a single argument
    # (no $data_type) we could learn and cache the behaviour.
    # Or we could probe the driver with a few test cases.
    # Or we could add a way to ask the DBI::ProxyServer
    # if $dbh->can('quote') == \&DBI::_::db::quote.
    # Tim
    #
    # Sounds all *very* smart to me. I'd rather suggest to
    # implement some of the typical quote possibilities
    # and let the user set
    #    $dbh->{'proxy_quote'} = 'backslash_escaped';
    # for example.
    # Jochen
    local $SIG{__DIE__} = 'DEFAULT';
    local $@;
    my $result = eval { $dbh->{'proxy_dbh'}->quote(@_) };
    return DBD::Proxy::proxy_set_err($dbh, $@) if $@;
    return $result;
}

sub table_info {
    my $dbh = shift;
    my $rdbh = $dbh->{'proxy_dbh'};
    #warn "table_info(@_)";
    local $SIG{__DIE__} = 'DEFAULT';
    local $@;
    my($numFields, $names, $types, @rows) = eval { $rdbh->table_info(@_) };
    return DBD::Proxy::proxy_set_err($dbh, $@) if $@;
    my ($sth, $inner) = DBI::_new_sth($dbh, {
        'Statement' => "SHOW TABLES",
	'proxy_params' => [],
	'proxy_data' => \@rows,
	'proxy_attr_cache' => { 
		'NUM_OF_PARAMS' => 0, 
		'NUM_OF_FIELDS' => $numFields, 
		'NAME' => $names, 
		'TYPE' => $types,
		'cache_filled' => 1
		},
    	'proxy_cache_only' => 1,
    });
    $sth->SUPER::STORE('NUM_OF_FIELDS' => $numFields);
    $inner->{NAME} = $names;
    $inner->{TYPE} = $types;
    $sth->SUPER::STORE('Active' => 1); # already execute()'d
    $sth->{'proxy_rows'} = @rows;
    return $sth;
}

sub tables {
    my $dbh = shift;
    #warn "tables(@_)";
    return $dbh->SUPER::tables(@_);
}


sub type_info_all {
    my $dbh = shift;
    local $SIG{__DIE__} = 'DEFAULT';
    local $@;
    my $result = eval { $dbh->{'proxy_dbh'}->type_info_all(@_) };
    return DBD::Proxy::proxy_set_err($dbh, $@) if $@;
    return $result;
}


package DBD::Proxy::st; # ====== STATEMENT ======

$DBD::Proxy::st::imp_data_size = 0;

use vars qw(%ATTR);

# inherited:  STORE to current object. FETCH from current if exists, else call up
#              to the (proxy) database object.
# local:      STORE / FETCH against parent class.
# cache_only: STORE noop (read-only).  FETCH from private_* if exists, else call
#              remote and cache the result.
# remote:     STORE / FETCH against remote object only (default).
#
# Note: Attribute names starting with 'proxy_' always treated as 'inherited'.
#
%ATTR = (	# see also %ATTR in DBD::Proxy::db
    %DBD::Proxy::ATTR,
    'Database' => 'local',
    'RowsInCache' => 'local',
    'RowCacheSize' => 'inherited',
    'NULLABLE' => 'cache_only',
    'NAME' => 'cache_only',
    'TYPE' => 'cache_only',
    'PRECISION' => 'cache_only',
    'SCALE' => 'cache_only',
    'NUM_OF_FIELDS' => 'cache_only',
    'NUM_OF_PARAMS' => 'cache_only'
);

*AUTOLOAD = \&DBD::Proxy::db::AUTOLOAD;

sub execute ($@) {
    my $sth = shift;
    my $params = @_ ? \@_ : $sth->{'proxy_params'};

    # new execute, so delete any cached rows from previous execute
    undef $sth->{'proxy_data'};
    undef $sth->{'proxy_rows'};

    my $rsth = $sth->{proxy_sth};
    my $dbh = $sth->FETCH('Database');
    my $proto_ver = $dbh->{proxy_proto_ver};

    my ($numRows, @outData);

    local $SIG{__DIE__} = 'DEFAULT';
    local $@;
    if ( $proto_ver > 1 ) {
      ($numRows, @outData) = eval { $rsth->execute($params, $proto_ver) };
      return DBD::Proxy::proxy_set_err($sth, $@) if $@;
      
      # Attributes passed back only on the first execute() of a statement.
      unless ($sth->{proxy_attr_cache}->{cache_filled}) {
	my ($numFields, $numParams, $names, $types) = splice(@outData, 0, 4); 
	$sth->{'proxy_attr_cache'} = {
				      'NUM_OF_FIELDS' => $numFields,
				      'NUM_OF_PARAMS' => $numParams,
				      'NAME'          => $names,
				      'cache_filled'  => 1
				     };
	$sth->SUPER::STORE('NUM_OF_FIELDS' => $numFields);
	$sth->SUPER::STORE('NUM_OF_PARAMS' => $numParams);
      }

    }
    else {
      if ($rsth) {
	($numRows, @outData) = eval { $rsth->execute($params, $proto_ver) };
	return DBD::Proxy::proxy_set_err($sth, $@) if $@;

      }
      else {
	my $rdbh = $dbh->{'proxy_dbh'};
	
	# Legacy prepare is actually prepare + first execute on the server.
        ($rsth, @outData) =
	  eval { $rdbh->prepare($sth->{'Statement'},
				$sth->{'proxy_attr'}, $params, $proto_ver) };
	return DBD::Proxy::proxy_set_err($sth, $@) if $@;
	return DBD::Proxy::proxy_set_err($sth, "Constructor didn't return a handle: $rsth")
	  unless ($rsth =~ /^((?:\w+|\:\:)+)=(\w+)/);
	
	my $client = $dbh->{'proxy_client'};
	$rsth = RPC::PlClient::Object->new($1, $client, $rsth);

	my ($numFields, $numParams, $names, $types) = splice(@outData, 0, 4);
	$sth->{'proxy_sth'} = $rsth;
        $sth->{'proxy_attr_cache'} = {
	    'NUM_OF_FIELDS' => $numFields,
	    'NUM_OF_PARAMS' => $numParams,
	    'NAME'          => $names
        };
	$sth->SUPER::STORE('NUM_OF_FIELDS' => $numFields);
	$sth->SUPER::STORE('NUM_OF_PARAMS' => $numParams);
	$numRows = shift @outData;
      }
    }
    # Always condition active flag.
    $sth->SUPER::STORE('Active' => 1) if $sth->FETCH('NUM_OF_FIELDS'); # is SELECT
    $sth->{'proxy_rows'} = $numRows;
    # Any remaining items are output params.
    if (@outData) {
	foreach my $p (@$params) {
	    if (ref($p->[0])) {
		my $ref = shift @outData;
		${$p->[0]} = $$ref;
	    }
	}
    }

    $sth->{'proxy_rows'} || '0E0';
}

sub fetch ($) {
    my $sth = shift;

    my $data = $sth->{'proxy_data'};

    $sth->{'proxy_rows'} = 0 unless defined $sth->{'proxy_rows'};

    if(!$data || !@$data) {
	return undef unless $sth->SUPER::FETCH('Active');

	my $rsth = $sth->{'proxy_sth'};
	if (!$rsth) {
	    die "Attempt to fetch row without execute";
	}
	my $num_rows = $sth->FETCH('RowCacheSize') || 20;
	local $SIG{__DIE__} = 'DEFAULT';
	local $@;
	my @rows = eval { $rsth->fetch($num_rows) };
	return DBD::Proxy::proxy_set_err($sth, $@) if $@;
	unless (@rows == $num_rows) {
	    undef $sth->{'proxy_data'};
	    # server side has already called finish
	    $sth->SUPER::STORE(Active => 0);
	}
	return undef unless @rows;
	$sth->{'proxy_data'} = $data = [@rows];
    }
    my $row = shift @$data;

    $sth->SUPER::STORE(Active => 0) if ( $sth->{proxy_cache_only} and !@$data );
    $sth->{'proxy_rows'}++;
    return $sth->_set_fbav($row);
}
*fetchrow_arrayref = \&fetch;

sub rows ($) {
    my $rows = shift->{'proxy_rows'};
    return (defined $rows) ? $rows : -1;
}

sub finish ($) {
    my($sth) = @_;
    return 1 unless $sth->SUPER::FETCH('Active');
    my $rsth = $sth->{'proxy_sth'};
    $sth->SUPER::STORE('Active' => 0);
    return 0 unless $rsth; # Something's out of sync
    my $no_finish = exists($sth->{'proxy_no_finish'})
 	? $sth->{'proxy_no_finish'}
	: $sth->FETCH('Database')->{'proxy_no_finish'};
    unless ($no_finish) {
        local $SIG{__DIE__} = 'DEFAULT';
	local $@;
	my $result = eval { $rsth->finish() };
	return DBD::Proxy::proxy_set_err($sth, $@) if $@;
	return $result;
    }
    1;
}

sub STORE ($$$) {
    my($sth, $attr, $val) = @_;
    my $type = $ATTR{$attr} || 'remote';

    if ($attr =~ /^proxy_/  ||  $type eq 'inherited') {
	$sth->{$attr} = $val;
	return 1;
    }

    if ($type eq 'cache_only') {
	return 0;
    }

    if ($type eq 'remote' || $type eq 'cached') {
	my $rsth = $sth->{'proxy_sth'}  or  return undef;
        local $SIG{__DIE__} = 'DEFAULT';
	local $@;
	my $result = eval { $rsth->STORE($attr => $val) };
	return DBD::Proxy::proxy_set_err($sth, $@) if ($@);
	return $result if $type eq 'remote'; # else fall through to cache locally
    }
    return $sth->SUPER::STORE($attr => $val);
}

sub FETCH ($$) {
    my($sth, $attr) = @_;

    if ($attr =~ /^proxy_/) {
	return $sth->{$attr};
    }

    my $type = $ATTR{$attr} || 'remote';
    if ($type eq 'inherited') {
	if (exists($sth->{$attr})) {
	    return $sth->{$attr};
	}
	return $sth->FETCH('Database')->{$attr};
    }

    if ($type eq 'cache_only'  &&
	    exists($sth->{'proxy_attr_cache'}->{$attr})) {
	return $sth->{'proxy_attr_cache'}->{$attr};
    }

    if ($type ne 'local') {
	my $rsth = $sth->{'proxy_sth'}  or  return undef;
        local $SIG{__DIE__} = 'DEFAULT';
	local $@;
	my $result = eval { $rsth->FETCH($attr) };
	return DBD::Proxy::proxy_set_err($sth, $@) if $@;
	return $result;
    }
    elsif ($attr eq 'RowsInCache') {
	my $data = $sth->{'proxy_data'};
	$data ? @$data : 0;
    }
    else {
	$sth->SUPER::FETCH($attr);
    }
}

sub bind_param ($$$@) {
    my $sth = shift; my $param = shift;
    $sth->{'proxy_params'}->[$param-1] = [@_];
}
*bind_param_inout = \&bind_param;

sub DESTROY {
    my $sth = shift;
    $sth->finish if $sth->SUPER::FETCH('Active');
}


1;


__END__

=head1 NAME

DBD::Proxy - A proxy driver for the DBI

=head1 SYNOPSIS

  use DBI;

  $dbh = DBI->connect("dbi:Proxy:hostname=$host;port=$port;dsn=$db",
                      $user, $passwd);

  # See the DBI module documentation for full details

=head1 DESCRIPTION

DBD::Proxy is a Perl module for connecting to a database via a remote
DBI driver. See L<DBD::Gofer> for an alternative with different trade-offs.

This is of course not needed for DBI drivers which already
support connecting to a remote database, but there are engines which
don't offer network connectivity.

Another application is offering database access through a firewall, as
the driver offers query based restrictions. For example you can
restrict queries to exactly those that are used in a given CGI
application.

Speaking of CGI, another application is (or rather, will be) to reduce
the database connect/disconnect overhead from CGI scripts by using
proxying the connect_cached method. The proxy server will hold the
database connections open in a cache. The CGI script then trades the
database connect/disconnect overhead for the DBD::Proxy
connect/disconnect overhead which is typically much less.
I<Note that the connect_cached method is new and still experimental.>


=head1 CONNECTING TO THE DATABASE

Before connecting to a remote database, you must ensure, that a Proxy
server is running on the remote machine. There's no default port, so
you have to ask your system administrator for the port number. See
L<DBI::ProxyServer> for details.

Say, your Proxy server is running on machine "alpha", port 3334, and
you'd like to connect to an ODBC database called "mydb" as user "joe"
with password "hello". When using DBD::ODBC directly, you'd do a

  $dbh = DBI->connect("DBI:ODBC:mydb", "joe", "hello");

With DBD::Proxy this becomes

  $dsn = "DBI:Proxy:hostname=alpha;port=3334;dsn=DBI:ODBC:mydb";
  $dbh = DBI->connect($dsn, "joe", "hello");

You see, this is mainly the same. The DBD::Proxy module will create a
connection to the Proxy server on "alpha" which in turn will connect
to the ODBC database.

Refer to the L<DBI> documentation on the C<connect> method for a way
to automatically use DBD::Proxy without having to change your code.

DBD::Proxy's DSN string has the format

  $dsn = "DBI:Proxy:key1=val1; ... ;keyN=valN;dsn=valDSN";

In other words, it is a collection of key/value pairs. The following
keys are recognized:

=over 4

=item hostname

=item port

Hostname and port of the Proxy server; these keys must be present,
no defaults. Example:

    hostname=alpha;port=3334

=item dsn

The value of this attribute will be used as a dsn name by the Proxy
server. Thus it must have the format C<DBI:driver:...>, in particular
it will contain colons. The I<dsn> value may contain semicolons, hence
this key *must* be the last and it's value will be the complete
remaining part of the dsn. Example:

    dsn=DBI:ODBC:mydb

=item cipher

=item key

=item usercipher

=item userkey

By using these fields you can enable encryption. If you set,
for example,

    cipher=$class;key=$key

(note the semicolon) then DBD::Proxy will create a new cipher object
by executing

    $cipherRef = $class->new(pack("H*", $key));

and pass this object to the RPC::PlClient module when creating a
client. See L<RPC::PlClient>. Example:

    cipher=IDEA;key=97cd2375efa329aceef2098babdc9721

The usercipher/userkey attributes allow you to use two phase encryption:
The cipher/key encryption will be used in the login and authorisation
phase. Once the client is authorised, he will change to usercipher/userkey
encryption. Thus the cipher/key pair is a B<host> based secret, typically
less secure than the usercipher/userkey secret and readable by anyone.
The usercipher/userkey secret is B<your> private secret.

Of course encryption requires an appropriately configured server. See
<DBD::ProxyServer/CONFIGURATION FILE>.

=item debug

Turn on debugging mode

=item stderr

This attribute will set the corresponding attribute of the RPC::PlClient
object, thus logging will not use syslog(), but redirected to stderr.
This is the default under Windows.

    stderr=1

=item logfile

Similar to the stderr attribute, but output will be redirected to the
given file.

    logfile=/dev/null

=item RowCacheSize

The DBD::Proxy driver supports this attribute (which is DBI standard,
as of DBI 1.02). It's used to reduce network round-trips by fetching
multiple rows in one go. The current default value is 20, but this may
change.


=item proxy_no_finish

This attribute can be used to reduce network traffic: If the
application is calling $sth->finish() then the proxy tells the server
to finish the remote statement handle. Of course this slows down things
quite a lot, but is perfectly good for reducing memory usage with
persistent connections.

However, if you set the I<proxy_no_finish> attribute to a TRUE value,
either in the database handle or in the statement handle, then finish()
calls will be suppressed. This is what you want, for example, in small
and fast CGI applications.

=item proxy_quote

This attribute can be used to reduce network traffic: By default calls
to $dbh->quote() are passed to the remote driver.  Of course this slows
down things quite a lot, but is the safest default behaviour.

However, if you set the I<proxy_quote> attribute to the value 'C<local>'
either in the database handle or in the statement handle, and the call
to quote has only one parameter, then the local default DBI quote
method will be used (which will be faster but may be wrong).

=back

=head1 KNOWN ISSUES

=head2 Unproxied method calls

If a method isn't being proxied, try declaring a stub sub in the appropriate
package (DBD::Proxy::db for a dbh method, and DBD::Proxy::st for an sth method).
For example:

    sub DBD::Proxy::db::selectall_arrayref;

That will enable selectall_arrayref to be proxied.

Currently many methods aren't explicitly proxied and so you get the DBI's
default methods executed on the client.

Some of those methods, like selectall_arrayref, may then call other methods
that are proxied (selectall_arrayref calls fetchall_arrayref which calls fetch
which is proxied). So things may appear to work but operate more slowly than
the could.

This may all change in a later version.

=head2 Complex handle attributes

Sometimes handles are having complex attributes like hash refs or
array refs and not simple strings or integers. For example, with
DBD::CSV, you would like to write something like

  $dbh->{"csv_tables"}->{"passwd"} =
        { "sep_char" => ":", "eol" => "\n";

The above example would advice the CSV driver to assume the file
"passwd" to be in the format of the /etc/passwd file: Colons as
separators and a line feed without carriage return as line
terminator.

Surprisingly this example doesn't work with the proxy driver. To understand
the reasons, you should consider the following: The Perl compiler is
executing the above example in two steps:

=over

=item 1

The first step is fetching the value of the key "csv_tables" in the
handle $dbh. The value returned is complex, a hash ref.

=item 2

The second step is storing some value (the right hand side of the
assignment) as the key "passwd" in the hash ref from step 1.

=back

This becomes a little bit clearer, if we rewrite the above code:

  $tables = $dbh->{"csv_tables"};
  $tables->{"passwd"} = { "sep_char" => ":", "eol" => "\n";

While the examples work fine without the proxy, the fail due to a
subtle difference in step 1: By DBI magic, the hash ref
$dbh->{'csv_tables'} is returned from the server to the client.
The client creates a local copy. This local copy is the result of
step 1. In other words, step 2 modifies a local copy of the hash ref,
but not the server's hash ref.

The workaround is storing the modified local copy back to the server:

  $tables = $dbh->{"csv_tables"};
  $tables->{"passwd"} = { "sep_char" => ":", "eol" => "\n";
  $dbh->{"csv_tables"} = $tables;


=head1 AUTHOR AND COPYRIGHT

This module is Copyright (c) 1997, 1998

    Jochen Wiedmann
    Am Eisteich 9
    72555 Metzingen
    Germany

    Email: joe@ispsoft.de
    Phone: +49 7123 14887

The DBD::Proxy module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. In particular permission
is granted to Tim Bunce for distributing this as a part of the DBI.


=head1 SEE ALSO

L<DBI>, L<RPC::PlClient>, L<Storable>

=cut
