package IO::Socket::Socks;

use strict;
use IO::Select;
use Socket;
use Errno qw(EWOULDBLOCK EAGAIN EINPROGRESS ETIMEDOUT ECONNABORTED);
use Carp;
use vars qw( $SOCKET_CLASS @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION $SOCKS_ERROR $SOCKS5_RESOLVE $SOCKS4_RESOLVE $SOCKS_DEBUG %CODES );
require Exporter;

$VERSION = '0.74';

use constant {
	SOCKS_WANT_READ  => 20,
	SOCKS_WANT_WRITE => 21,
	ESOCKSPROTO      => exists &Errno::EPROTO ? &Errno::EPROTO : 7000,
};

@ISA = ('Exporter', $SOCKET_CLASS||'');

tie $SOCKET_CLASS, 'IO::Socket::Socks::SocketClassVar', $SOCKET_CLASS;
unless ($SOCKET_CLASS) {
	if (eval { require IO::Socket::IP; IO::Socket::IP->VERSION(0.36) }) {
		$SOCKET_CLASS = 'IO::Socket::IP';
	}
	else {
		$SOCKET_CLASS = 'IO::Socket::INET';
	}
}

@EXPORT    = qw( $SOCKS_ERROR SOCKS_WANT_READ SOCKS_WANT_WRITE ESOCKSPROTO );
@EXPORT_OK = qw(
  SOCKS5_VER
  SOCKS4_VER
  ADDR_IPV4
  ADDR_DOMAINNAME
  ADDR_IPV6
  CMD_CONNECT
  CMD_BIND
  CMD_UDPASSOC
  AUTHMECH_ANON
  AUTHMECH_USERPASS
  AUTHMECH_INVALID
  AUTHREPLY_SUCCESS
  AUTHREPLY_FAILURE
  ISS_UNKNOWN_ADDRESS
  ISS_BAD_VERSION
  ISS_CANT_RESOLVE
  REPLY_SUCCESS
  REPLY_GENERAL_FAILURE
  REPLY_CONN_NOT_ALLOWED
  REPLY_NETWORK_UNREACHABLE
  REPLY_HOST_UNREACHABLE
  REPLY_CONN_REFUSED
  REPLY_TTL_EXPIRED
  REPLY_CMD_NOT_SUPPORTED
  REPLY_ADDR_NOT_SUPPORTED
  REQUEST_GRANTED
  REQUEST_FAILED
  REQUEST_REJECTED_IDENTD
  REQUEST_REJECTED_USERID
);
%EXPORT_TAGS = (constants => [ 'SOCKS_WANT_READ', 'SOCKS_WANT_WRITE', @EXPORT_OK ]);
tie $SOCKS_ERROR, 'IO::Socket::Socks::ReadOnlyVar', IO::Socket::Socks::Error->new();

$SOCKS5_RESOLVE = 1;
$SOCKS4_RESOLVE = 0;
$SOCKS_DEBUG    = $ENV{SOCKS_DEBUG};

use constant {
	SOCKS5_VER => 5,
	SOCKS4_VER => 4,

	ADDR_IPV4       => 1,
	ADDR_DOMAINNAME => 3,
	ADDR_IPV6       => 4,

	CMD_CONNECT  => 1,
	CMD_BIND     => 2,
	CMD_UDPASSOC => 3,

	AUTHMECH_ANON => 0,

	#AUTHMECH_GSSAPI   => 1,
	AUTHMECH_USERPASS => 2,
	AUTHMECH_INVALID  => 255,

	AUTHREPLY_SUCCESS => 0,
	AUTHREPLY_FAILURE => 10,    # to not intersect with other socks5 constants

	ISS_UNKNOWN_ADDRESS => 500,
	ISS_BAD_VERSION     => 501,
	ISS_CANT_RESOLVE    => 502,
};

$CODES{AUTHMECH}->[AUTHMECH_INVALID]   = "No valid auth mechanisms";
$CODES{AUTHREPLY}->[AUTHREPLY_FAILURE] = "Failed to authenticate";

# socks5
use constant {
	REPLY_SUCCESS             => 0,
	REPLY_GENERAL_FAILURE     => 1,
	REPLY_CONN_NOT_ALLOWED    => 2,
	REPLY_NETWORK_UNREACHABLE => 3,
	REPLY_HOST_UNREACHABLE    => 4,
	REPLY_CONN_REFUSED        => 5,
	REPLY_TTL_EXPIRED         => 6,
	REPLY_CMD_NOT_SUPPORTED   => 7,
	REPLY_ADDR_NOT_SUPPORTED  => 8,
};

$CODES{REPLY}->{&REPLY_SUCCESS}             = "Success";
$CODES{REPLY}->{&REPLY_GENERAL_FAILURE}     = "General failure";
$CODES{REPLY}->{&REPLY_CONN_NOT_ALLOWED}    = "Not allowed";
$CODES{REPLY}->{&REPLY_NETWORK_UNREACHABLE} = "Network unreachable";
$CODES{REPLY}->{&REPLY_HOST_UNREACHABLE}    = "Host unreachable";
$CODES{REPLY}->{&REPLY_CONN_REFUSED}        = "Connection refused";
$CODES{REPLY}->{&REPLY_TTL_EXPIRED}         = "TTL expired";
$CODES{REPLY}->{&REPLY_CMD_NOT_SUPPORTED}   = "Command not supported";
$CODES{REPLY}->{&REPLY_ADDR_NOT_SUPPORTED}  = "Address not supported";

# socks4
use constant {
	REQUEST_GRANTED         => 90,
	REQUEST_FAILED          => 91,
	REQUEST_REJECTED_IDENTD => 92,
	REQUEST_REJECTED_USERID => 93,
};

$CODES{REPLY}->{&REQUEST_GRANTED}         = "request granted";
$CODES{REPLY}->{&REQUEST_FAILED}          = "request rejected or failed";
$CODES{REPLY}->{&REQUEST_REJECTED_IDENTD} = "request rejected because SOCKS server cannot connect to identd on the client";
$CODES{REPLY}->{&REQUEST_REJECTED_USERID} = "request rejected because the client program and identd report different user-ids";

# queue
use constant {
	Q_SUB    => 0,
	Q_ARGS   => 1,
	Q_BUF    => 2,
	Q_READS  => 3,
	Q_SENDS  => 4,
	Q_OKCB   => 5,
	Q_DEBUGS => 6,
};

our $CAN_CHANGE_SOCKET = 1;
sub new_from_fd {
	my ($class, $sock, %arg) = @_;

	bless $sock, $class;

	$sock->autoflush(1);
	if (exists $arg{Timeout}) {
		${*$sock}{'io_socket_timeout'} = delete $arg{Timeout};
	}

	scalar(%arg) or return $sock;
	
	# do not allow to create new socket
	local $CAN_CHANGE_SOCKET = 0;
	$sock->configure(\%arg) || $SOCKS_ERROR == SOCKS_WANT_WRITE || return;
	$sock;
}

*new_from_socket = \&new_from_fd;

sub start_SOCKS {
	my ($class, $sock, %arg) = @_;

	bless $sock, $class;

	$sock->autoflush(1);
	if (exists $arg{Timeout}) {
		${*$sock}{'io_socket_timeout'} = delete $arg{Timeout};
	}

	${*$sock}->{SOCKS} = { RequireAuth => 0 };

	$SOCKS_ERROR->set();
	return $sock->command(%arg) ? $sock : undef;
}

sub socket {
	my $self = shift;

	return $self unless $CAN_CHANGE_SOCKET;
	return $self->SUPER::socket(@_);
}

sub configure {
	my $self = shift;
	my $args = shift;

	$self->_configure($args)
	  or return;

	${*$self}->{SOCKS}->{ProxyAddr} = (
		exists($args->{ProxyAddr})
		? delete($args->{ProxyAddr})
		: undef
	);

	${*$self}->{SOCKS}->{ProxyPort} = (
		exists($args->{ProxyPort})
		? delete($args->{ProxyPort})
		: undef
	);

	${*$self}->{SOCKS}->{COMMAND} = [];

	if (exists($args->{Listen})) {
		$args->{LocalAddr} = ${*$self}->{SOCKS}->{ProxyAddr};
		$args->{LocalPort} = ${*$self}->{SOCKS}->{ProxyPort};
		$args->{Reuse}     = 1;
		${*$self}->{SOCKS}->{Listen} = 1;
	}
	elsif (${*$self}->{SOCKS}->{ProxyAddr} && ${*$self}->{SOCKS}->{ProxyPort}) {
		$args->{PeerAddr} = ${*$self}->{SOCKS}->{ProxyAddr};
		$args->{PeerPort} = ${*$self}->{SOCKS}->{ProxyPort};
	}

	unless (defined ${*$self}->{SOCKS}->{TCP}) {
		$args->{Proto} = "tcp";
		$args->{Type}  = SOCK_STREAM;
	}
	elsif (!defined $args->{Proto}) {
		$args->{Proto} = "udp";
		$args->{Type}  = SOCK_DGRAM;
	}

	$SOCKS_ERROR->set();
	unless ($self->SUPER::configure($args)) {
		if ($SOCKS_ERROR == undef) {
			$SOCKS_ERROR->set($!, $@);
		}
		return;
	}

	return $self;
}

sub _configure {
	my $self = shift;
	my $args = shift;

	${*$self}->{SOCKS}->{Version} = (
		exists($args->{SocksVersion})
		? (
			$args->{SocksVersion} == 4
			  || $args->{SocksVersion} == 5
			  || ( exists $args->{Listen}
				&& ref $args->{SocksVersion} eq 'ARRAY'
				&& _validate_multi_version($args->{SocksVersion}))
			? delete($args->{SocksVersion})
			: croak("Unsupported socks version specified. Should be 4 or 5")
		  )
		: 5
	);

	${*$self}->{SOCKS}->{AuthType} = (
		exists($args->{AuthType})
		? delete($args->{AuthType})
		: "none"
	);

	${*$self}->{SOCKS}->{RequireAuth} = (
		exists($args->{RequireAuth})
		? delete($args->{RequireAuth})
		: 0
	);

	${*$self}->{SOCKS}->{UserAuth} = (
		exists($args->{UserAuth})
		? delete($args->{UserAuth})
		: undef
	);

	${*$self}->{SOCKS}->{Username} = (
		exists($args->{Username}) ? delete($args->{Username})
		: (
			(${*$self}->{SOCKS}->{AuthType} eq "none") ? undef
			: croak("If you set AuthType to userpass, then you must provide a username.")
		)
	);

	${*$self}->{SOCKS}->{Password} = (
		exists($args->{Password}) ? delete($args->{Password})
		: (
			(${*$self}->{SOCKS}->{AuthType} eq "none") ? undef
			: croak("If you set AuthType to userpass, then you must provide a password.")
		)
	);

	${*$self}->{SOCKS}->{Debug} = (
		exists($args->{SocksDebug})
		? delete($args->{SocksDebug})
		: $SOCKS_DEBUG
	);

	${*$self}->{SOCKS}->{Resolve} = (
		exists($args->{SocksResolve})
		? delete($args->{SocksResolve})
		: undef
	);

	${*$self}->{SOCKS}->{AuthMethods} = [ 0, 0, 0 ];
	${*$self}->{SOCKS}->{AuthMethods}->[AUTHMECH_ANON] = 1
	  unless ${*$self}->{SOCKS}->{RequireAuth};

	#${*$self}->{SOCKS}->{AuthMethods}->[AUTHMECH_GSSAPI] = 1
	#    if (${*$self}->{SOCKS}->{AuthType} eq "gssapi");
	${*$self}->{SOCKS}->{AuthMethods}->[AUTHMECH_USERPASS] = 1
	  if (
		(!exists($args->{Listen}) && (${*$self}->{SOCKS}->{AuthType} eq "userpass"))
		|| (exists($args->{Listen})
			&& defined(${*$self}->{SOCKS}->{UserAuth}))
	  );

	if (exists($args->{BindAddr}) && exists($args->{BindPort})) {
		${*$self}->{SOCKS}->{CmdAddr} = delete($args->{BindAddr});
		${*$self}->{SOCKS}->{CmdPort} = delete($args->{BindPort});
		${*$self}->{SOCKS}->{Bind}    = 1;
	}
	elsif (exists($args->{UdpAddr}) && exists($args->{UdpPort})) {
		if (${*$self}->{SOCKS}->{Version} == 4) {
			croak("Socks v4 doesn't support UDP association");
		}
		${*$self}->{SOCKS}->{CmdAddr} = delete($args->{UdpAddr});
		${*$self}->{SOCKS}->{CmdPort} = delete($args->{UdpPort});
		${*$self}->{SOCKS}->{TCP} = __PACKAGE__->new(    # TCP backend for UDP socket
			Timeout  => $args->{Timeout},
			Proto    => 'tcp',
			PeerAddr => $args->{ProxyAddr},
			PeerPort => $args->{ProxyPort},
			exists $args->{Blocking} ?
				(Blocking => $args->{Blocking}) : ()
		) or return;
	}
	elsif (exists($args->{ConnectAddr}) && exists($args->{ConnectPort})) {
		${*$self}->{SOCKS}->{CmdAddr} = delete($args->{ConnectAddr});
		${*$self}->{SOCKS}->{CmdPort} = delete($args->{ConnectPort});
	}

	return 1;
}

sub version {
	my $self = shift;
	return ${*$self}->{SOCKS}->{Version};
}

sub connect {
	my $self = shift;

	croak("Undefined IO::Socket::Socks object passed to connect.")
	  unless defined($self);

	my $ok =
	  defined(${*$self}->{SOCKS}->{TCP})
	  ? 1
	  : $self->SUPER::connect(@_);

	if (($! == EINPROGRESS || $! == EWOULDBLOCK) && 
	    (${*$self}->{SOCKS}->{TCP} || $self)->blocking == 0) {
		${*$self}->{SOCKS}->{_in_progress} = 1;
		$SOCKS_ERROR->set(SOCKS_WANT_WRITE, 'Socks want write');
	}
	elsif (!$ok) {
		$SOCKS_ERROR->set($!, $@ = "Connection to proxy failed: $!");
		return;
	}
	else {
		# connect() may be called several times by SUPER class
		$SOCKS_ERROR->set();
	}

	return $ok # proxy address was not specified, so do not make socks handshake
		unless ${*$self}->{SOCKS}->{ProxyAddr} && ${*$self}->{SOCKS}->{ProxyPort};
	
	$self->_connect();
}

sub _connect {
	my $self = shift;
	${*$self}->{SOCKS}->{ready} = 0;

	if (${*$self}->{SOCKS}->{Version} == 4) {
		${*$self}->{SOCKS}->{queue} = [

			# [sub, [@args], buf, [@reads], sends_cnt]
			[ '_socks4_connect_command', [ ${*$self}->{SOCKS}->{Bind} ? CMD_BIND : CMD_CONNECT ], undef, [], 0 ],
			[ '_socks4_connect_reply', [], undef, [], 0 ]
		];
	}
	else {
		${*$self}->{SOCKS}->{queue} = [
			[ '_socks5_connect',         [], undef, [], 0 ],
			[ '_socks5_connect_if_auth', [], undef, [], 0 ],
			[
				'_socks5_connect_command',
				[
					  ${*$self}->{SOCKS}->{Bind} ? CMD_BIND
					: ${*$self}->{SOCKS}->{TCP}  ? CMD_UDPASSOC
					:                              CMD_CONNECT
				],
				undef,
				[],
				0
			],
			[ '_socks5_connect_reply', [], undef, [], 0 ]
		];
	}

	if (delete ${*$self}->{SOCKS}->{_in_progress}) { # socket connection not estabilished yet
		if ($self->isa('IO::Socket::IP')) {
			# IO::Socket::IP requires multiple connect calls
			# when performing non-blocking multi-homed connect
			unshift @{ ${*$self}->{SOCKS}->{queue} }, ['_socket_connect', [], undef, [], 0];
			
			# IO::Socket::IP::connect() returns false for non-blocking connections in progress
			# IO::Socket::INET::connect() returns true for non-blocking connections in progress
			# LOL
			return; # connect() return value
		}
	}
	else {
		defined($self->_run_queue())
			or return;
	}

	return $self;
}

sub _socket_connect {
	my $self = shift;
	my $sock = ${*$self}->{SOCKS}->{TCP} || $self;
	
	return 1 if $sock->SUPER::connect();
	if ($! == EINPROGRESS || $! == EWOULDBLOCK) {
		$SOCKS_ERROR->set(SOCKS_WANT_WRITE, 'Socks want write');
		return -1;
	}
	
	$SOCKS_ERROR->set($!, $@ = "Connection to proxy failed: $!");
	return;
}

sub _run_queue {
	# run tasks from queue, return undef on error, -1 if one of the task
    # returned not completed because of the possible blocking on network operation
    my $self = shift;

	my $retval;
	my $sub;

	while (my $elt = ${*$self}->{SOCKS}->{queue}[0]) {
		$sub    = $elt->[Q_SUB];
		$retval = $self->$sub(@{ $elt->[Q_ARGS] });
		unless (defined $retval) {
			${*$self}->{SOCKS}->{queue}         = [];
			${*$self}->{SOCKS}->{queue_results} = {};
			last;
		}

		last if ($retval == -1);
		${*$self}->{SOCKS}->{queue_results}{$sub} = $retval;
		if ($elt->[Q_OKCB]) {
			$elt->[Q_OKCB]->();
		}
		shift @{ ${*$self}->{SOCKS}->{queue} };
	}

	if (defined($retval) && !@{ ${*$self}->{SOCKS}->{queue} }) {
		${*$self}->{SOCKS}->{queue_results} = {};
		${*$self}->{SOCKS}->{ready}         = $SOCKS_ERROR ? 0 : 1;
	}

	return $retval;
}

sub ready {
	my $self = shift;

	$self->_run_queue();
	return ${*$self}->{SOCKS}->{ready};
}

sub _socks5_connect {
	my $self = shift;
	my $debug = IO::Socket::Socks::Debug->new() if ${*$self}->{SOCKS}->{Debug};
	my ($reads, $sends, $debugs) = (0, 0, 0);
	my $sock =
	  defined(${*$self}->{SOCKS}->{TCP})
	  ? ${*$self}->{SOCKS}->{TCP}
	  : $self;

	#--------------------------------------------------------------------------
	# Send the auth mechanisms
	#--------------------------------------------------------------------------
	# +----+----------+----------+
	# |VER | NMETHODS | METHODS  |
	# +----+----------+----------+
	# | 1  |    1     | 1 to 255 |
	# +----+----------+----------+

	my $nmethods = 0;
	my $methods;
	foreach my $method (0 .. $#{ ${*$self}->{SOCKS}->{AuthMethods} }) {
		if (${*$self}->{SOCKS}->{AuthMethods}->[$method] == 1) {
			$methods .= pack('C', $method);
			$nmethods++;
		}
	}

	my $reply;
	$reply = $sock->_socks_send(pack('CCa*', SOCKS5_VER, $nmethods, $methods), ++$sends)
	  or return _fail($reply);

	if ($debug && !$self->_debugged(++$debugs)) {
		$debug->add(
			ver      => SOCKS5_VER,
			nmethods => $nmethods,
			methods  => join('', unpack("C$nmethods", $methods))
		);
		$debug->show('Client Send: ');
	}

	#--------------------------------------------------------------------------
	# Read the reply
	#--------------------------------------------------------------------------
	# +----+--------+
	# |VER | METHOD |
	# +----+--------+
	# | 1  |   1    |
	# +----+--------+

	$reply = $sock->_socks_read(2, ++$reads)
	  or return _fail($reply);

	my ($version, $auth_method) = unpack('CC', $reply);

	if ($debug && !$self->_debugged(++$debugs)) {
		$debug->add(
			ver    => $version,
			method => $auth_method
		);
		$debug->show('Client Recv: ');
	}

	if ($auth_method == AUTHMECH_INVALID) {
		$! = ESOCKSPROTO;
		$SOCKS_ERROR->set(AUTHMECH_INVALID, $@ = $CODES{AUTHMECH}->[$auth_method]);
		return;
	}

	return $auth_method;
}

sub _socks5_connect_if_auth {
	my $self = shift;
	if (${*$self}->{SOCKS}->{queue_results}{'_socks5_connect'} != AUTHMECH_ANON) {
		unshift @{ ${*$self}->{SOCKS}->{queue} }, [ '_socks5_connect_auth', [], undef, [], 0 ];
		(${*$self}->{SOCKS}->{queue}[0], ${*$self}->{SOCKS}->{queue}[1]) = (${*$self}->{SOCKS}->{queue}[1], ${*$self}->{SOCKS}->{queue}[0]);
	}

	1;
}

sub _socks5_connect_auth {
	# rfc1929
    my $self = shift;
	my $debug = IO::Socket::Socks::Debug->new() if ${*$self}->{SOCKS}->{Debug};
	my ($reads, $sends, $debugs) = (0, 0, 0);
	my $sock =
	  defined(${*$self}->{SOCKS}->{TCP})
	  ? ${*$self}->{SOCKS}->{TCP}
	  : $self;

	#--------------------------------------------------------------------------
	# Send the auth
	#--------------------------------------------------------------------------
	# +----+------+----------+------+----------+
	# |VER | ULEN |  UNAME   | PLEN |  PASSWD  |
	# +----+------+----------+------+----------+
	# | 1  |  1   | 1 to 255 |  1   | 1 to 255 |
	# +----+------+----------+------+----------+

	my $uname  = ${*$self}->{SOCKS}->{Username};
	my $passwd = ${*$self}->{SOCKS}->{Password};
	my $ulen   = length($uname);
	my $plen   = length($passwd);
	my $reply;
	$reply = $sock->_socks_send(pack("CCa${ulen}Ca*", 1, $ulen, $uname, $plen, $passwd), ++$sends)
	  or return _fail($reply);

	if ($debug && !$self->_debugged(++$debugs)) {
		$debug->add(
			ver    => 1,
			ulen   => $ulen,
			uname  => $uname,
			plen   => $plen,
			passwd => $passwd
		);
		$debug->show('Client Send: ');
	}

	#--------------------------------------------------------------------------
	# Read the reply
	#--------------------------------------------------------------------------
	# +----+--------+
	# |VER | STATUS |
	# +----+--------+
	# | 1  |   1    |
	# +----+--------+

	$reply = $sock->_socks_read(2, ++$reads)
	  or return _fail($reply);

	my ($ver, $status) = unpack('CC', $reply);

	if ($debug && !$self->_debugged(++$debugs)) {
		$debug->add(
			ver    => $ver,
			status => $status
		);
		$debug->show('Client Recv: ');
	}

	if ($status != AUTHREPLY_SUCCESS) {
		$! = ESOCKSPROTO;
		$SOCKS_ERROR->set(AUTHREPLY_FAILURE, $@ = "Authentication failed with SOCKS5 proxy");
		return;
	}

	return 1;
}

sub _socks5_connect_command {
	my $self    = shift;
	my $command = shift;
	my $debug   = IO::Socket::Socks::Debug->new() if ${*$self}->{SOCKS}->{Debug};
	my ($reads, $sends, $debugs) = (0, 0, 0);
	my $resolve = defined(${*$self}->{SOCKS}->{Resolve}) ? ${*$self}->{SOCKS}->{Resolve} : $SOCKS5_RESOLVE;
	my $sock =
	  defined(${*$self}->{SOCKS}->{TCP})
	  ? ${*$self}->{SOCKS}->{TCP}
	  : $self;

	#--------------------------------------------------------------------------
	# Send the command
	#--------------------------------------------------------------------------
	# +----+-----+-------+------+----------+----------+
	# |VER | CMD |  RSV  | ATYP | DST.ADDR | DST.PORT |
	# +----+-----+-------+------+----------+----------+
	# | 1  |  1  | X'00' |  1   | Variable |    2     |
	# +----+-----+-------+------+----------+----------+

	my ($atyp, $dstaddr) = $resolve ? (ADDR_DOMAINNAME, ${*$self}->{SOCKS}->{CmdAddr}) : _resolve(${*$self}->{SOCKS}->{CmdAddr})
	  or $SOCKS_ERROR->set(ISS_CANT_RESOLVE, $@ = "Can't resolve `" . ${*$self}->{SOCKS}->{CmdAddr} . "'"), return;
	my $hlen = length($dstaddr) if $resolve;
	my $dstport = pack('n', ${*$self}->{SOCKS}->{CmdPort});
	my $reply;
	$reply = $sock->_socks_send(pack('C4', SOCKS5_VER, $command, 0, $atyp) . (defined($hlen) ? pack('C', $hlen) : '') . $dstaddr . $dstport, ++$sends)
	  or return _fail($reply);

	if ($debug && !$self->_debugged(++$debugs)) {
		$debug->add(
			ver  => SOCKS5_VER,
			cmd  => $command,
			rsv  => 0,
			atyp => $atyp
		);
		$debug->add(hlen => $hlen) if defined $hlen;
		$debug->add(
			dstaddr => $resolve ? $dstaddr : _addr_ntoa($dstaddr, $atyp),
			dstport => ${*$self}->{SOCKS}->{CmdPort}
		);
		$debug->show('Client Send: ');
	}

	return 1;
}

sub _socks5_connect_reply {
	my $self = shift;
	my $debug = IO::Socket::Socks::Debug->new() if ${*$self}->{SOCKS}->{Debug};
	my ($reads, $sends, $debugs) = (0, 0, 0);
	my $sock =
	  defined(${*$self}->{SOCKS}->{TCP})
	  ? ${*$self}->{SOCKS}->{TCP}
	  : $self;

	#--------------------------------------------------------------------------
	# Read the reply
	#--------------------------------------------------------------------------
	# +----+-----+-------+------+----------+----------+
	# |VER | REP |  RSV  | ATYP | BND.ADDR | BND.PORT |
	# +----+-----+-------+------+----------+----------+
	# | 1  |  1  | X'00' |  1   | Variable |    2     |
	# +----+-----+-------+------+----------+----------+

	my $reply;
	$reply = $sock->_socks_read(4, ++$reads)
	  or return _fail($reply);

	my ($ver, $rep, $rsv, $atyp) = unpack('C4', $reply);

	if ($debug) {
		$debug->add(
			ver  => $ver,
			rep  => $rep,
			rsv  => $rsv,
			atyp => $atyp
		);
	}

	my ($bndaddr, $bndport);

	if ($atyp == ADDR_DOMAINNAME) {
		length($reply = $sock->_socks_read(1, ++$reads))
		  or return _fail($reply);

		my $hlen = unpack('C', $reply);
		$bndaddr = $sock->_socks_read($hlen, ++$reads)
		  or return _fail($bndaddr);

		if ($debug) {
			$debug->add(hlen => $hlen);
		}
	}
	elsif ($atyp == ADDR_IPV4) {
		$bndaddr = $sock->_socks_read(4, ++$reads)
		  or return _fail($bndaddr);
	}
	elsif ($atyp == ADDR_IPV6) {
		$bndaddr = $sock->_socks_read(16, ++$reads)
		  or return _fail($bndaddr);
	}
	else {
		$! = ESOCKSPROTO;
		$SOCKS_ERROR->set(ISS_UNKNOWN_ADDRESS, $@ = "Unsupported address type returned by socks server: $atyp");
		return;
	}

	$reply = $sock->_socks_read(2, ++$reads)
	  or return _fail($reply);
	$bndport = unpack('n', $reply);

	${*$self}->{SOCKS}->{DstAddrType} = $atyp;
	${*$self}->{SOCKS}->{DstAddr}     = $bndaddr;
	${*$self}->{SOCKS}->{DstPort}     = $bndport;

	if ($debug && !$self->_debugged(++$debugs)) {
		my ($addr) = $self->dst;
		$debug->add(
			bndaddr => $addr,
			bndport => $bndport
		);
		$debug->show('Client Recv: ');
	}

	if ($rep != REPLY_SUCCESS) {
		$! = ESOCKSPROTO;
		unless (exists $CODES{REPLY}->{$rep}) {
			$rep = REPLY_GENERAL_FAILURE;
		}
		$SOCKS_ERROR->set($rep, $@ = $CODES{REPLY}->{$rep});
		return;
	}

	return 1;
}


sub _socks4_connect_command {
	# http://ss5.sourceforge.net/socks4.protocol.txt
	# http://ss5.sourceforge.net/socks4A.protocol.txt
	my $self    = shift;
	my $command = shift;
	my $debug   = IO::Socket::Socks::Debug->new() if ${*$self}->{SOCKS}->{Debug};
	my ($reads, $sends, $debugs) = (0, 0, 0);
	my $resolve = defined(${*$self}->{SOCKS}->{Resolve}) ? ${*$self}->{SOCKS}->{Resolve} : $SOCKS4_RESOLVE;

	#--------------------------------------------------------------------------
	# Send the command
	#--------------------------------------------------------------------------
	# +-----+-----+----------+---------------+----------+------+
	# | VER | CMD | DST.PORT |   DST.ADDR    |  USERID  | NULL |
	# +-----+-----+----------+---------------+----------+------+
	# |  1  |  1  |    2     |       4       | variable |  1   |
	# +-----+-----+----------+---------------+----------+------+

	my $dstaddr = $resolve ? inet_aton('0.0.0.1') : inet_aton(${*$self}->{SOCKS}->{CmdAddr})
	  or $SOCKS_ERROR->set(ISS_CANT_RESOLVE, $@ = "Can't resolve `" . ${*$self}->{SOCKS}->{CmdAddr} . "'"), return;
	my $dstport = pack('n', ${*$self}->{SOCKS}->{CmdPort});
	my $userid = ${*$self}->{SOCKS}->{Username} || '';
	my $dsthost = '';
	if ($resolve) {    # socks4a
		$dsthost = ${*$self}->{SOCKS}->{CmdAddr} . pack('C', 0);
	}

	my $reply;
	$reply = $self->_socks_send(pack('CC', SOCKS4_VER, $command) . $dstport . $dstaddr . $userid . pack('C', 0) . $dsthost, ++$sends)
	  or return _fail($reply);

	if ($debug && !$self->_debugged(++$debugs)) {
		$debug->add(
			ver     => SOCKS4_VER,
			cmd     => $command,
			dstport => ${*$self}->{SOCKS}->{CmdPort},
			dstaddr => length($dstaddr) == 4 ? inet_ntoa($dstaddr) : undef,
			userid  => $userid,
			null    => 0
		);
		if ($dsthost) {
			$debug->add(
				dsthost => ${*$self}->{SOCKS}->{CmdAddr},
				null    => 0
			);
		}
		$debug->show('Client Send: ');
	}

	return 1;
}

sub _socks4_connect_reply {
	my $self = shift;
	my $debug = IO::Socket::Socks::Debug->new() if ${*$self}->{SOCKS}->{Debug};
	my ($reads, $sends, $debugs) = (0, 0, 0);

	#--------------------------------------------------------------------------
	# Read the reply
	#--------------------------------------------------------------------------
	# +-----+-----+----------+---------------+
	# | VER | REP | BND.PORT |   BND.ADDR    |
	# +-----+-----+----------+---------------+
	# |  1  |  1  |    2     |       4       |
	# +-----+-----+----------+---------------+

	my $reply;
	$reply = $self->_socks_read(8, ++$reads)
	  or return _fail($reply);

	my ($ver, $rep, $bndport) = unpack('CCn', $reply);
	substr($reply, 0, 4) = '';

	${*$self}->{SOCKS}->{DstAddrType} = ADDR_IPV4;
	${*$self}->{SOCKS}->{DstAddr}     = $reply;
	${*$self}->{SOCKS}->{DstPort}     = $bndport;

	if ($debug && !$self->_debugged(++$debugs)) {
		my ($addr) = $self->dst;

		$debug->add(
			ver     => $ver,
			rep     => $rep,
			bndport => $bndport,
			bndaddr => $addr
		);
		$debug->show('Client Recv: ');
	}

	if ($rep != REQUEST_GRANTED) {
		$! = ESOCKSPROTO;
		unless (exists $CODES{REPLY}->{$rep}) {
			$rep = REQUEST_FAILED;
		}
		$SOCKS_ERROR->set($rep, $@ = $CODES{REPLY}->{$rep});
		return;
	}

	return 1;
}

sub accept {
	my $self = shift;

	croak("Undefined IO::Socket::Socks object passed to accept.")
	  unless defined($self);

	if (${*$self}->{SOCKS}->{Listen}) {
		my $client = $self->SUPER::accept(@_);

		if (!$client) {
			if ($! == EAGAIN || $! == EWOULDBLOCK) {
				$SOCKS_ERROR->set(SOCKS_WANT_READ, "Socks want read");
			}
			else {
				$SOCKS_ERROR->set($!, $@ = "Proxy accept new client failed: $!");
			}
			return;
		}

		my $ver =
		    ref ${*$self}->{SOCKS}->{Version}
		  ? @{ ${*$self}->{SOCKS}->{Version} } > 1
			  ? ${*$self}->{SOCKS}->{Version}
			  : ${*$self}->{SOCKS}->{Version}->[0]
		  : ${*$self}->{SOCKS}->{Version};

		# inherit some socket parameters
		${*$client}->{SOCKS}->{Debug}       = ${*$self}->{SOCKS}->{Debug};
		${*$client}->{SOCKS}->{Version}     = $ver;
		${*$client}->{SOCKS}->{AuthMethods} = ${*$self}->{SOCKS}->{AuthMethods};
		${*$client}->{SOCKS}->{UserAuth}    = ${*$self}->{SOCKS}->{UserAuth};
		${*$client}->{SOCKS}->{Resolve}     = ${*$self}->{SOCKS}->{Resolve};
		${*$client}->{SOCKS}->{ready}       = 0;
		$client->blocking($self->blocking);    # temporarily

		if (ref $ver) {
			${*$client}->{SOCKS}->{queue} = [ [ '_socks_accept', [], undef, [], 0 ] ];
		}
		elsif ($ver == 4) {
			${*$client}->{SOCKS}->{queue} = [ [ '_socks4_accept_command', [], undef, [], 0 ] ];

		}
		else {
			${*$client}->{SOCKS}->{queue} = [
				[ '_socks5_accept',         [], undef, [], 0 ],
				[ '_socks5_accept_if_auth', [], undef, [], 0 ],
				[ '_socks5_accept_command', [], undef, [], 0 ]
			];
		}

		defined($client->_run_queue())
		  or return;

		$client->blocking(1);    # new socket should be in blocking mode
		return $client;
	}
	else {
		${*$self}->{SOCKS}->{ready} = 0;
		if ({*$self}->{SOCKS}->{Version} == 4) {
			push @{ ${*$self}->{SOCKS}->{queue} }, [ '_socks4_connect_reply', [], undef, [], 0 ];
		}
		else {
			push @{ ${*$self}->{SOCKS}->{queue} }, [ '_socks5_connect_reply', [], undef, [], 0 ];
		}

		defined($self->_run_queue())
		  or return;

		return $self;
	}
}

sub _socks_accept {
	# when 4 and 5 version allowed
    my $self = shift;

	my $request;
	$request = $self->_socks_read(1, 0)
	  or return _fail($request);

	my $ver = unpack('C', $request);
	if ($ver == 4) {
		${*$self}->{SOCKS}->{Version} = 4;
		push @{ ${*$self}->{SOCKS}->{queue} }, [ '_socks4_accept_command', [$ver], undef, [], 0 ];
	}
	elsif ($ver == 5) {
		${*$self}->{SOCKS}->{Version} = 5;
		push @{ ${*$self}->{SOCKS}->{queue} },
		  [ '_socks5_accept', [$ver], undef, [], 0 ],
		  [ '_socks5_accept_if_auth', [], undef, [], 0 ],
		  [ '_socks5_accept_command', [], undef, [], 0 ];
	}
	else {
		$! = ESOCKSPROTO;
		$SOCKS_ERROR->set(ISS_BAD_VERSION, $@ = "Socks version should be 4 or 5, $ver recieved");
		return;
	}

	1;
}

sub _socks5_accept {
	my ($self, $ver) = @_;
	my $debug = IO::Socket::Socks::Debug->new() if ${*$self}->{SOCKS}->{Debug};
	my ($reads, $sends, $debugs) = (0, 0, 0);

	#--------------------------------------------------------------------------
	# Read the auth mechanisms
	#--------------------------------------------------------------------------
	# +----+----------+----------+
	# |VER | NMETHODS | METHODS  |
	# +----+----------+----------+
	# | 1  |    1     | 1 to 255 |
	# +----+----------+----------+

	my $request;
	$request = $self->_socks_read($ver ? 1 : 2, ++$reads)
	  or return _fail($request);

	unless ($ver) {
		$ver = unpack('C', $request);
	}
	my $nmethods = unpack('C', substr($request, -1, 1));

	$request = $self->_socks_read($nmethods, ++$reads)
	  or return _fail($request);

	my @methods = unpack('C' x $nmethods, $request);

	if ($debug && !$self->_debugged(++$debugs)) {
		$debug->add(
			ver      => $ver,
			nmethods => $nmethods,
			methods  => join('', @methods)
		);
		$debug->show('Server Recv: ');
	}

	if ($ver != SOCKS5_VER) {
		$! = ESOCKSPROTO;
		$SOCKS_ERROR->set(ISS_BAD_VERSION, $@ = "Socks version should be 5, $ver recieved");
		return;
	}

	if ($nmethods == 0) {
		$! = ESOCKSPROTO;
		$SOCKS_ERROR->set(AUTHMECH_INVALID, $@ = "No auth methods sent");
		return;
	}

	my $authmech;

	foreach my $method (@methods) {
		if (${*$self}->{SOCKS}->{AuthMethods}->[$method] == 1) {
			$authmech = $method;
			last;
		}
	}

	if (!defined($authmech)) {
		$authmech = AUTHMECH_INVALID;
	}

	#--------------------------------------------------------------------------
	# Send the reply
	#--------------------------------------------------------------------------
	# +----+--------+
	# |VER | METHOD |
	# +----+--------+
	# | 1  |   1    |
	# +----+--------+

	$request = $self->_socks_send(pack('CC', SOCKS5_VER, $authmech), ++$sends)
	  or return _fail($request);

	if ($debug && !$self->_debugged(++$debugs)) {
		$debug->add(
			ver    => SOCKS5_VER,
			method => $authmech
		);
		$debug->show('Server Send: ');
	}

	if ($authmech == AUTHMECH_INVALID) {
		$! = ESOCKSPROTO;
		$SOCKS_ERROR->set(AUTHMECH_INVALID, $@ = "No available auth methods");
		return;
	}

	return $authmech;
}

sub _socks5_accept_if_auth {
	my $self = shift;

	if (${*$self}->{SOCKS}->{queue_results}{'_socks5_accept'} == AUTHMECH_USERPASS) {
		unshift @{ ${*$self}->{SOCKS}->{queue} }, [ '_socks5_accept_auth', [], undef, [], 0 ];
		(${*$self}->{SOCKS}->{queue}[0], ${*$self}->{SOCKS}->{queue}[1]) = (${*$self}->{SOCKS}->{queue}[1], ${*$self}->{SOCKS}->{queue}[0]);
	}

	1;
}

sub _socks5_accept_auth {
	my $self = shift;
	my $debug = IO::Socket::Socks::Debug->new() if ${*$self}->{SOCKS}->{Debug};
	my ($reads, $sends, $debugs) = (0, 0, 0);

	#--------------------------------------------------------------------------
	# Read the auth
	#--------------------------------------------------------------------------
	# +----+------+----------+------+----------+
	# |VER | ULEN |  UNAME   | PLEN |  PASSWD  |
	# +----+------+----------+------+----------+
	# | 1  |  1   | 1 to 255 |  1   | 1 to 255 |
	# +----+------+----------+------+----------+

	my $request;
	$request = $self->_socks_read(2, ++$reads)
	  or return _fail($request);

	my ($ver, $ulen) = unpack('CC', $request);
	$request = $self->_socks_read($ulen + 1, ++$reads)
	  or return _fail($request);

	my $uname = substr($request, 0, $ulen);
	my $plen = unpack('C', substr($request, $ulen));
	my $passwd;
	$passwd = $self->_socks_read($plen, ++$reads)
	  or return _fail($passwd);

	if ($debug && !$self->_debugged(++$debugs)) {
		$debug->add(
			ver    => $ver,
			ulen   => $ulen,
			uname  => $uname,
			plen   => $plen,
			passwd => $passwd
		);
		$debug->show('Server Recv: ');
	}

	my $status = 1;
	if (defined(${*$self}->{SOCKS}->{UserAuth})) {
		$status = &{ ${*$self}->{SOCKS}->{UserAuth} }($uname, $passwd);
	}

	#--------------------------------------------------------------------------
	# Send the reply
	#--------------------------------------------------------------------------
	# +----+--------+
	# |VER | STATUS |
	# +----+--------+
	# | 1  |   1    |
	# +----+--------+

	$status = $status ? AUTHREPLY_SUCCESS : 1;    #XXX AUTHREPLY_FAILURE broken
	$request = $self->_socks_send(pack('CC', 1, $status), ++$sends)
	  or return _fail($request);

	if ($debug && !$self->_debugged(++$debugs)) {
		$debug->add(
			ver    => 1,
			status => $status
		);
		$debug->show('Server Send: ');
	}

	if ($status != AUTHREPLY_SUCCESS) {
		$! = ESOCKSPROTO;
		$SOCKS_ERROR->set(AUTHREPLY_FAILURE, $@ = "Authentication failed with SOCKS5 proxy");
		return;
	}

	return 1;
}

sub _socks5_accept_command {
	my $self = shift;
	my $debug = IO::Socket::Socks::Debug->new() if ${*$self}->{SOCKS}->{Debug};
	my ($reads, $sends, $debugs) = (0, 0, 0);

	@{ ${*$self}->{SOCKS}->{COMMAND} } = ();

	#--------------------------------------------------------------------------
	# Read the command
	#--------------------------------------------------------------------------
	# +----+-----+-------+------+----------+----------+
	# |VER | CMD |  RSV  | ATYP | DST.ADDR | DST.PORT |
	# +----+-----+-------+------+----------+----------+
	# | 1  |  1  | X'00' |  1   | Variable |    2     |
	# +----+-----+-------+------+----------+----------+

	my $request;
	$request = $self->_socks_read(4, ++$reads)
	  or return _fail($request);

	my ($ver, $cmd, $rsv, $atyp) = unpack('CCCC', $request);
	if ($debug && !$self->_debugged(++$debugs)) {
		$debug->add(
			ver  => $ver,
			cmd  => $cmd,
			rsv  => $rsv,
			atyp => $atyp
		);
	}

	my $dstaddr;
	if ($atyp == ADDR_DOMAINNAME) {
		length($request = $self->_socks_read(1, ++$reads))
		  or return _fail($request);

		my $hlen = unpack('C', $request);
		$dstaddr = $self->_socks_read($hlen, ++$reads)
		  or return _fail($dstaddr);

		if ($debug && !$self->_debugged(++$debugs)) {
			$debug->add(hlen => $hlen);
		}
	}
	elsif ($atyp == ADDR_IPV4) {
		$request = $self->_socks_read(4, ++$reads)
		  or return _fail($request);

		$dstaddr = length($request) == 4 ? inet_ntoa($request) : undef;
	}
	elsif ($atyp == ADDR_IPV6) {
		$request = $self->_socks_read(16, ++$reads)
		  or return _fail($request);

		$dstaddr = length($request) == 16 ? Socket::inet_ntop(AF_INET6, $request) : undef;
	}
	else {    # unknown address type - how many bytes to read?
		push @{${*$self}->{SOCKS}->{queue}}, [
			'_socks5_accept_command_reply', [ REPLY_ADDR_NOT_SUPPORTED, '0.0.0.0', 0 ], undef, [], 0,
			sub {
				$! = ESOCKSPROTO;
				$SOCKS_ERROR->set(REPLY_ADDR_NOT_SUPPORTED, $@ = $CODES{REPLY}->{REPLY_ADDR_NOT_SUPPORTED});
			}
		];
		
		return 0;
	}

	$request = $self->_socks_read(2, ++$reads)
	  or return _fail($request);

	my $dstport = unpack('n', $request);

	if ($debug && !$self->_debugged(++$debugs)) {
		$debug->add(
			dstaddr => $dstaddr,
			dstport => $dstport
		);
		$debug->show('Server Recv: ');
	}

	@{ ${*$self}->{SOCKS}->{COMMAND} } = ($cmd, $dstaddr, $dstport, $atyp);

	return 1;
}

sub _socks5_accept_command_reply {
	my $self    = shift;
	my $reply   = shift;
	my $host    = shift;
	my $port    = shift;
	my $debug   = IO::Socket::Socks::Debug->new() if ${*$self}->{SOCKS}->{Debug};
	my $resolve = defined(${*$self}->{SOCKS}->{Resolve}) ? ${*$self}->{SOCKS}->{Resolve} : $SOCKS5_RESOLVE;
	my ($reads, $sends, $debugs) = (0, 0, 0);

	if (!defined($reply) || !defined($host) || !defined($port)) {
		croak("You must provide a reply, host, and port on the command reply.");
	}

	#--------------------------------------------------------------------------
	# Send the reply
	#--------------------------------------------------------------------------
	# +----+-----+-------+------+----------+----------+
	# |VER | REP |  RSV  | ATYP | BND.ADDR | BND.PORT |
	# +----+-----+-------+------+----------+----------+
	# | 1  |  1  | X'00' |  1   | Variable |    2     |
	# +----+-----+-------+------+----------+----------+

	my ($atyp, $bndaddr) = $resolve ? _resolve($host) : (ADDR_DOMAINNAME, $host)
	  or $SOCKS_ERROR->set(ISS_CANT_RESOLVE, $@ = "Can't resolve `$host'"), return;
	my $hlen = $resolve ? undef : length($bndaddr);
	my $rc;
	$rc = $self->_socks_send(pack('CCCC', SOCKS5_VER, $reply, 0, $atyp) . ($resolve ? '' : pack('C', $hlen)) . $bndaddr . pack('n', $port), ++$sends)
	  or return _fail($rc);

	if ($debug && !$self->_debugged(++$debugs)) {
		$debug->add(
			ver  => SOCKS5_VER,
			rep  => $reply,
			rsv  => 0,
			atyp => $atyp
		);
		$debug->add(hlen => $hlen) unless $resolve;
		$debug->add(
			bndaddr => $resolve ? _addr_ntoa($bndaddr, $atyp) : $bndaddr,
			bndport => $port
		);
		$debug->show('Server Send: ');
	}

	1;
}

sub _socks4_accept_command {
	my ($self, $ver) = @_;
	my $debug = IO::Socket::Socks::Debug->new() if ${*$self}->{SOCKS}->{Debug};
	my $resolve = defined(${*$self}->{SOCKS}->{Resolve}) ? ${*$self}->{SOCKS}->{Resolve} : $SOCKS4_RESOLVE;
	my ($reads, $sends, $debugs) = (0, 0, 0);

	@{ ${*$self}->{SOCKS}->{COMMAND} } = ();

	#--------------------------------------------------------------------------
	# Read the auth mechanisms
	#--------------------------------------------------------------------------
	# +-----+-----+----------+---------------+----------+------+
	# | VER | CMD | DST.PORT |   DST.ADDR    |  USERID  | NULL |
	# +-----+-----+----------+---------------+----------+------+
	# |  1  |  1  |    2     |       4       | variable |  1   |
	# +-----+-----+----------+---------------+----------+------+

	my $request;
	$request = $self->_socks_read($ver ? 7 : 8, ++$reads)
	  or return _fail($request);

	unless ($ver) {
		$ver = unpack('C', $request);
		substr($request, 0, 1) = '';
	}

	my ($cmd, $dstport) = unpack('Cn', $request);
	substr($request, 0, 3) = '';
	my $dstaddr = length($request) == 4 ? inet_ntoa($request) : undef;

	my $userid = '';
	my $c;

	while (1) {
		length($c = $self->_socks_read(1, ++$reads))
		  or return _fail($c);

		if ($c ne "\0") {
			$userid .= $c;
		}
		else {
			last;
		}
	}

	if ($debug && !$self->_debugged(++$debugs)) {
		$debug->add(
			ver     => $ver,
			cmd     => $cmd,
			dstport => $dstport,
			dstaddr => $dstaddr,
			userid  => $userid,
			null    => 0
		);
	}

	my $atyp = ADDR_IPV4;

	if ($resolve && $dstaddr =~ /^0\.0\.0\.[1-9]/) {    # socks4a
		$dstaddr = '';
		$atyp    = ADDR_DOMAINNAME;

		while (1) {
			length($c = $self->_socks_read(1, ++$reads))
			  or return _fail($c);

			if ($c ne "\0") {
				$dstaddr .= $c;
			}
			else {
				last;
			}
		}

		if ($debug && !$self->_debugged(++$debugs)) {
			$debug->add(
				dsthost => $dstaddr,
				null    => 0
			);
		}
	}

	if ($debug && !$self->_debugged(++$debugs)) {
		$debug->show('Server Recv: ');
	}

	if (defined(${*$self}->{SOCKS}->{UserAuth})) {
		unless (&{ ${*$self}->{SOCKS}->{UserAuth} }($userid)) {
			push @{${*$self}->{SOCKS}->{queue}}, [
				'_socks4_accept_command_reply', [ REQUEST_REJECTED_USERID, '0.0.0.0', 0 ], undef, [], 0,
				sub {
					$! = ESOCKSPROTO;
					$SOCKS_ERROR->set(REQUEST_REJECTED_USERID, $@ = 'Authentication failed with SOCKS4 proxy');
				}
			];
			
			return 0;
		}
	}

	if ($ver != SOCKS4_VER) {
		$! = ESOCKSPROTO;
		$SOCKS_ERROR->set(ISS_BAD_VERSION, $@ = "Socks version should be 4, $ver recieved");
		return;
	}

	@{ ${*$self}->{SOCKS}->{COMMAND} } = ($cmd, $dstaddr, $dstport, $atyp);

	return 1;
}

sub _socks4_accept_command_reply {
	my $self  = shift;
	my $reply = shift;
	my $host  = shift;
	my $port  = shift;
	my $debug = IO::Socket::Socks::Debug->new() if ${*$self}->{SOCKS}->{Debug};
	my ($reads, $sends, $debugs) = (0, 0, 0);

	if (!defined($reply) || !defined($host) || !defined($port)) {
		croak("You must provide a reply, host, and port on the command reply.");
	}

	#--------------------------------------------------------------------------
	# Send the reply
	#--------------------------------------------------------------------------
	# +-----+-----+----------+---------------+
	# | VER | REP | BND.PORT |   BND.ADDR    |
	# +-----+-----+----------+---------------+
	# |  1  |  1  |    2     |       4       |
	# +-----+-----+----------+---------------+

	my $bndaddr = inet_aton($host)
	  or $SOCKS_ERROR->set(ISS_CANT_RESOLVE, $@ = "Can't resolve `$host'"), return;
	my $rc;
	$rc = $self->_socks_send(pack('CCna*', 0, $reply, $port, $bndaddr), ++$sends)
	  or return _fail($rc);

	if ($debug && !$self->_debugged(++$debugs)) {
		$debug->add(
			ver     => 0,
			rep     => $reply,
			bndport => $port,
			bndaddr => length($bndaddr) == 4 ? inet_ntoa($bndaddr) : undef
		);
		$debug->show('Server Send: ');
	}

	1;
}

sub command {
	my $self = shift;

	unless (exists ${*$self}->{SOCKS}->{RequireAuth})    # TODO: find more correct way
	{
		return ${*$self}->{SOCKS}->{COMMAND};
	}
	else {
		my @keys = qw(Version AuthType RequireAuth UserAuth Username Password
		  Debug Resolve AuthMethods CmdAddr CmdPort Bind TCP);

		my %tmp;
		$tmp{$_} = ${*$self}->{SOCKS}->{$_} for @keys;

		my %args = @_;
		$self->_configure(\%args);

		if ($self->_connect()) {
			return 1;
		}

		${*$self}->{SOCKS}->{$_} = $tmp{$_} for @keys;
		return 0;
	}
}

sub command_reply {
	my $self = shift;
	${*$self}->{SOCKS}->{ready} = 0;

	if (${*$self}->{SOCKS}->{Version} == 4) {
		${*$self}->{SOCKS}->{queue} = [ [ '_socks4_accept_command_reply', [@_], undef, [], 0 ] ];
	}
	else {
		${*$self}->{SOCKS}->{queue} = [ [ '_socks5_accept_command_reply', [@_], undef, [], 0 ] ];
	}

	$self->_run_queue();
}

sub dst {
	my $self = shift;
	my ($addr, $port, $atype) = @{ ${*$self}->{SOCKS} }{qw/DstAddr DstPort DstAddrType/};
	return (_addr_ntoa($addr, $atype), $port, $atype);
}

sub send {
	my $self = shift;

	unless (defined ${*$self}->{SOCKS}->{TCP}) {
		return $self->SUPER::send(@_);
	}

	my ($msg, $flags, $peer) = @_;
	my $debug = IO::Socket::Socks::Debug->new() if ${*$self}->{SOCKS}->{Debug};
	my $resolve = defined(${*$self}->{SOCKS}->{Resolve}) ? ${*$self}->{SOCKS}->{Resolve} : $SOCKS5_RESOLVE;

	croak "send: Cannot determine peer address"
	  unless defined $peer;

	my ($dstport, $dstaddr, $dstaddr_type);
	if (ref $peer eq 'ARRAY') {
		$dstaddr      = $peer->[0];
		$dstport      = $peer->[1];
		$dstaddr_type = ADDR_DOMAINNAME;
	}
	else {
		unless (($dstport, $dstaddr, $dstaddr_type) = eval { (unpack_sockaddr_in($peer), ADDR_IPV4) }) {
			($dstport, $dstaddr, $dstaddr_type) = ((unpack_sockaddr_in6($peer))[ 0, 1 ], ADDR_IPV6);
		}
	}

	my ($sndaddr, $sndport, $sndaddr_type) = $self->dst;
	if (($sndaddr eq '0.0.0.0' && $sndaddr_type == ADDR_IPV4) || ($sndaddr eq '::' && $sndaddr_type == ADDR_IPV6)) {
		$sndaddr      = ${*$self}->{SOCKS}->{ProxyAddr};
		$sndaddr_type = ADDR_DOMAINNAME;
	}
	if ($sndaddr_type == ADDR_DOMAINNAME) {
		($sndaddr_type, $sndaddr) = _resolve($sndaddr)
		  or $SOCKS_ERROR->set(ISS_CANT_RESOLVE, $@ = "Can't resolve `$sndaddr'"), return;
	}
	else {
		$sndaddr = ${*$self}->{SOCKS}->{DstAddr};
	}

	$peer = $sndaddr_type == ADDR_IPV4 ? pack_sockaddr_in($sndport, $sndaddr) : pack_sockaddr_in6($sndport, $sndaddr);

	my $hlen;
	if ($dstaddr_type == ADDR_DOMAINNAME) {
		if ($resolve) {
			$hlen = length $dstaddr;
		}
		else {
			($dstaddr_type, $dstaddr) = _resolve($dstaddr)
			  or $SOCKS_ERROR->set(ISS_CANT_RESOLVE, $@ = "Can't resolve `$dstaddr'"), return;
		}
	}

	my $msglen = $debug ? length($msg) : 0;

	# we need to add socks header to the message
	# +----+------+------+----------+----------+----------+
	# |RSV | FRAG | ATYP | DST.ADDR | DST.PORT |   DATA   |
	# +----+------+------+----------+----------+----------+
	# | 2  |  1   |  1   | Variable |    2     | Variable |
	# +----+------+------+----------+----------+----------+
	$msg = pack('C4', 0, 0, 0, $dstaddr_type) . (defined $hlen ? pack('C', $hlen) : '') . $dstaddr . pack('n', $dstport) . $msg;

	if ($debug) {
		$debug->add(
			rsv  => '00',
			frag => '0',
			atyp => $dstaddr_type
		);
		$debug->add(hlen => $hlen) if defined $hlen;
		$debug->add(
			dstaddr => defined $hlen ? $dstaddr : _addr_ntoa($dstaddr, $dstaddr_type),
			dstport => $dstport,
			data    => "...($msglen)"
		);
		$debug->show('Client Send: ');
	}

	$self->SUPER::send($msg, $flags, $peer);
}

sub recv {
	my $self = shift;

	unless (defined ${*$self}->{SOCKS}->{TCP}) {
		return $self->SUPER::recv(@_);
	}

	my $debug = IO::Socket::Socks::Debug->new() if ${*$self}->{SOCKS}->{Debug};

	defined($self->SUPER::recv($_[0], $_[1] + 262, $_[2]))
	  or return;

	# we need to remove socks header from the message
	# +----+------+------+----------+----------+----------+
	# |RSV | FRAG | ATYP | DST.ADDR | DST.PORT |   DATA   |
	# +----+------+------+----------+----------+----------+
	# | 2  |  1   |  1   | Variable |    2     | Variable |
	# +----+------+------+----------+----------+----------+
	my $rsv = join('', unpack('C2', $_[0]));
	substr($_[0], 0, 2) = '';

	my ($frag, $atyp) = unpack('C2', $_[0]);
	substr($_[0], 0, 2) = '';

	if ($debug) {
		$debug->add(
			rsv  => $rsv,
			frag => $frag,
			atyp => $atyp
		);
	}

	my $dstaddr;
	if ($atyp == ADDR_DOMAINNAME) {
		my $hlen = unpack('C', $_[0]);
		$dstaddr = substr($_[0], 1, $hlen);
		substr($_[0], 0, $hlen + 1) = '';

		if ($debug) {
			$debug->add(hlen => $hlen);
		}
	}
	elsif ($atyp == ADDR_IPV4) {
		$dstaddr = substr($_[0], 0, 4);
		substr($_[0], 0, 4) = '';
	}
	elsif ($atyp == ADDR_IPV6) {
		$dstaddr = substr($_[0], 0, 16);
		substr($_[0], 0, 16) = '';
	}
	else {
		$! = ESOCKSPROTO;
		$SOCKS_ERROR->set(ISS_UNKNOWN_ADDRESS, $@ = "Unsupported address type returned by socks server: $atyp");
		return;
	}

	my $dstport = unpack('n', $_[0]);
	substr($_[0], 0, 2) = '';

	if ($debug) {
		$debug->add(
			dstaddr => _addr_ntoa($dstaddr, $atyp),
			dstport => $dstport,
			data    => "...(" . length($_[0]) . ")"
		);
		$debug->show('Client Recv: ');
	}

	return pack_sockaddr_in($dstport, $dstaddr) if $atyp == ADDR_IPV4;
	return pack_sockaddr_in6($dstport, $dstaddr) if $atyp == ADDR_IPV6;
	return [ $dstaddr, $dstport ];
}

#+-----------------------------------------------------------------------------
#| Helper Functions
#+-----------------------------------------------------------------------------
sub _socks_send {
	my $self = shift;
	my $data = shift;
	my $numb = shift;

	local $SIG{PIPE} = 'IGNORE';
	$SOCKS_ERROR->set();

	my $rc;
	my $writed = 0;
	my $blocking = ${*$self}{io_socket_timeout} ? $self->blocking(0) : $self->blocking;

	unless ($blocking || ${*$self}{io_socket_timeout}) {
		if (${*$self}->{SOCKS}->{queue}[0][Q_SENDS] >= $numb) {    # already sent
			return 1;
		}

		if (defined ${*$self}->{SOCKS}->{queue}[0][Q_BUF]) {       # some chunk already sent
			substr($data, 0, ${*$self}->{SOCKS}->{queue}[0][Q_BUF]) = '';
		}

		while (length $data) {
			$rc = $self->syswrite($data);
			if (defined $rc) {
				if ($rc > 0) {
					${*$self}->{SOCKS}->{queue}[0][Q_BUF] += $rc;
					substr($data, 0, $rc) = '';
				}
				else {                                             # XXX: socket closed? if smth writed, but not all?
					last;
				}
			}
			elsif ($! == EWOULDBLOCK || $! == EAGAIN) {
				$SOCKS_ERROR->set(SOCKS_WANT_WRITE, 'Socks want write');
				return undef;
			}
			else {
				$SOCKS_ERROR->set($!, $@ = "send: $!");
				last;
			}
		}

		$writed = int(${*$self}->{SOCKS}->{queue}[0][Q_BUF]);
		${*$self}->{SOCKS}->{queue}[0][Q_BUF] = undef;
		${*$self}->{SOCKS}->{queue}[0][Q_SENDS]++;
		return $writed;
	}

	my $selector = IO::Select->new($self);
	my $start    = time();

	while (1) {
		if (${*$self}{io_socket_timeout} && time() - $start >= ${*$self}{io_socket_timeout}) {
			$! = ETIMEDOUT;
			last;
		}

		unless ($selector->can_write(1)) {    # socket couldn't accept data for now, check if timeout expired and try again
			next;
		}

		$rc = $self->syswrite($data);
		if ($rc > 0) {                        # reduce our message
			$writed += $rc;
			substr($data, 0, $rc) = '';
			if (length($data) == 0) {         # all data successfully writed
				last;
			}
		}
		else {                                # some error in the socket; will return false
			$SOCKS_ERROR->set($!, $@ = "send: $!") unless defined $rc;
			last;
		}
	}

	$self->blocking(1) if $blocking;

	return $writed;
}

sub _socks_read {
	my $self   = shift;
	my $length = shift || 1;
	my $numb   = shift;

	$SOCKS_ERROR->set();
	my $data = '';
	my ($buf, $rc);
	my $blocking = $self->blocking;

	# non-blocking read
	unless ($blocking || ${*$self}{io_socket_timeout}) {    # no timeout should be specified for non-blocking connect
		if (defined ${*$self}->{SOCKS}->{queue}[0][Q_READS][$numb]) {    # already readed
			return ${*$self}->{SOCKS}->{queue}[0][Q_READS][$numb];
		}

		if (defined ${*$self}->{SOCKS}->{queue}[0][Q_BUF]) {             # some chunk already readed
			$data = ${*$self}->{SOCKS}->{queue}[0][Q_BUF];
			$length -= length $data;
		}

		while ($length > 0) {
			$rc = $self->sysread($buf, $length);
			if (defined $rc) {
				if ($rc > 0) {
					$length -= $rc;
					$data .= $buf;
				}
				else {                                                   # XXX: socket closed, if smth readed but not all?
					last;
				}
			}
			elsif ($! == EWOULDBLOCK || $! == EAGAIN) {                  # no data to read
				if (length $data) {                                      # save already readed data in the queue buffer
					${*$self}->{SOCKS}->{queue}[0][Q_BUF] = $data;
				}
				$SOCKS_ERROR->set(SOCKS_WANT_READ, 'Socks want read');
				return undef;
			}
			else {
				$SOCKS_ERROR->set($!, $@ = "read: $!");
				last;
			}
		}

		${*$self}->{SOCKS}->{queue}[0][Q_BUF] = undef;
		${*$self}->{SOCKS}->{queue}[0][Q_READS][$numb] = $data;
		return $data;
	}

	# blocking read
	my $selector = IO::Select->new($self);
	my $start    = time();

	while ($length > 0) {
		if (${*$self}{io_socket_timeout} && time() - $start >= ${*$self}{io_socket_timeout}) {
			$! = ETIMEDOUT;
			last;
		}

		unless ($selector->can_read(1)) {    # no data in socket for now, check if timeout expired and try again
			next;
		}

		$rc = $self->sysread($buf, $length);
		if (defined $rc && $rc > 0) {        # reduce limit and modify buffer
			$length -= $rc;
			$data .= $buf;
		}
		else {                               # EOF or error in the socket
			$SOCKS_ERROR->set($!, $@ = "read: $!") unless defined $rc;
			last;                            # TODO handle unexpected EOF more correct
		}
	}

	# XXX it may return incomplete $data if timed out. Could it break smth?
	return $data;
}

sub _debugged {
	my ($self, $debugs) = @_;

	if (${*$self}->{SOCKS}->{queue}[0][Q_DEBUGS] >= $debugs) {
		return 1;
	}

	${*$self}->{SOCKS}->{queue}[0][Q_DEBUGS] = $debugs;
	return 0;
}

sub _fail {
	if (!@_ || defined($_[0])) {
		$SOCKS_ERROR->set(ECONNABORTED, $@ = 'Socket closed by remote side') if $SOCKS_ERROR == undef;
		return;
	}

	return -1;
}

sub _validate_multi_version {
	my $multi_ver = shift;

	if (@$multi_ver == 1) {
		return $multi_ver->[0] == 4 || $multi_ver->[0] == 5;
	}

	if (@$multi_ver == 2) {
		return
		     $multi_ver->[0] != $multi_ver->[1]
		  && ($multi_ver->[0] == 4 || $multi_ver->[0] == 5)
		  && ($multi_ver->[1] == 4 || $multi_ver->[1] == 5);
	}

	return;
}

sub _resolve {
	my $addr = shift;
	my ($err, @res) = Socket::getaddrinfo($addr, undef, { protocol => Socket::IPPROTO_TCP, socktype => Socket::SOCK_STREAM });
	return if $err;

	for my $r (@res) {
		if ($r->{family} == PF_INET) {
			return (ADDR_IPV4, (unpack_sockaddr_in($r->{addr}))[1]);
		}
	}

	return (ADDR_IPV6, (unpack_sockaddr_in6($res[0]{addr}))[1]);
}

sub _addr_ntoa {
	my ($addr, $atype) = @_;

	return inet_ntoa($addr) if ($atype == ADDR_IPV4);
	return Socket::inet_ntop(AF_INET6, $addr) if ($atype == ADDR_IPV6);
	return $addr;
}

###############################################################################
#+-----------------------------------------------------------------------------
#| Helper Package to bring some magic in $SOCKS_ERROR
#+-----------------------------------------------------------------------------
###############################################################################

package IO::Socket::Socks::Error;

use overload
  '==' => \&num_eq,
  '!=' => sub { !num_eq(@_) },
  '""' => \&as_str,
  '0+' => \&as_num;

sub new {
	my ($class, $num, $str) = @_;

	my $self = {
		num => $num,
		str => $str,
	};

	bless $self, $class;
}

sub set {
	my ($self, $num, $str) = @_;

	$self->{num} = defined $num ? int($num) : $num;
	$self->{str} = $str;
}

sub as_str {
	my $self = shift;
	return $self->{str};
}

sub as_num {
	my $self = shift;
	return $self->{num};
}

sub num_eq {
	my ($self, $num) = @_;

	unless (defined $num) {
		return !defined($self->{num});
	}
	return $self->{num} == int($num);
}

###############################################################################
#+-----------------------------------------------------------------------------
#| Helper Package to prevent modifications of $SOCKS_ERROR outside this package
#+-----------------------------------------------------------------------------
###############################################################################

package IO::Socket::Socks::ReadOnlyVar;

sub TIESCALAR {
	my ($class, $value) = @_;
	bless \$value, $class;
}

sub FETCH {
	my $self = shift;
	return $$self;
}

*STORE = *UNTIE = sub { Carp::croak 'Modification of readonly value attempted' };

###############################################################################
#+-----------------------------------------------------------------------------
#| Helper Package to handle assigning of $SOCKET_CLASS
#+-----------------------------------------------------------------------------
###############################################################################

package IO::Socket::Socks::SocketClassVar;

sub TIESCALAR {
	my ($class, $value) = @_;
	bless { v => $value }, $class;
}

sub FETCH {
	return $_[0]->{v};
}

sub STORE {
	my ($self, $class) = @_;

	$self->{v} = $class;
	eval "use $class; 1" or die $@;
	$IO::Socket::Socks::ISA[1] = $class;
}

sub UNTIE {
	Carp::croak 'Untie of tied variable is denied';
}

###############################################################################
#+-----------------------------------------------------------------------------
#| Helper Package to display pretty debug messages
#+-----------------------------------------------------------------------------
###############################################################################

package IO::Socket::Socks::Debug;

sub new {
	my ($class) = @_;
	my $self = [];

	bless $self, $class;
}

sub add {
	my $self = shift;
	push @{$self}, @_;
}

sub show {
	my ($self, $tag) = @_;

	$self->_separator($tag);
	$self->_row(0, $tag);
	$self->_separator($tag);
	$self->_row(1, $tag);
	$self->_separator($tag);

	print STDERR "\n";

	@{$self} = ();
}

sub _separator {
	my $self = shift;
	my $tag  = shift;
	my ($row1_len, $row2_len, $len);

	print STDERR $tag, '+';

	for (my $i = 0 ; $i < @$self ; $i += 2) {
		$row1_len = length($self->[$i]);
		$row2_len = length($self->[ $i + 1 ]);
		$len      = ($row1_len > $row2_len ? $row1_len : $row2_len) + 2;

		print STDERR '-' x $len, '+';
	}

	print STDERR "\n";
}

sub _row {
	my $self = shift;
	my $row  = shift;
	my $tag  = shift;
	my ($row1_len, $row2_len, $len);

	print STDERR $tag, '|';

	for (my $i = 0 ; $i < @$self ; $i += 2) {
		$row1_len = length($self->[$i]);
		$row2_len = length($self->[ $i + 1 ]);
		$len      = ($row1_len > $row2_len ? $row1_len : $row2_len);

		printf STDERR ' %-' . $len . 's |', $self->[ $i + $row ];
	}

	print STDERR "\n";
}

1;

__END__

=head1 NAME

IO::Socket::Socks - Provides a way to create socks client or server both 4 and 5 version.

=head1 SYNOPSIS

=head2 Client

  use IO::Socket::Socks;
  
  my $socks_client = IO::Socket::Socks->new(
    ProxyAddr   => "proxy host",
    ProxyPort   => "proxy port",
    ConnectAddr => "remote host",
    ConnectPort => "remote port",
  ) or die $SOCKS_ERROR;
  
  print $socks_client "foo\n";
  $socks_client->close();

=head2 Server

  use IO::Socket::Socks ':constants';
  
  my $socks_server = IO::Socket::Socks->new(
    ProxyAddr   => "localhost",
    ProxyPort   => 8000,
    Listen      => 1,
    UserAuth    => \&auth,
    RequireAuth => 1
  ) or die $SOCKS_ERROR;

  while(1) {
    my $client = $socks_server->accept();
    
    unless ($client) {
      print "ERROR: $SOCKS_ERROR\n";
      next;
    }

    my $command = $client->command();
    if ($command->[0] == CMD_CONNECT) {
       # Handle the CONNECT
       $client->command_reply(REPLY_SUCCESS, addr, port);
    }
    
    ...
    #read from the client and send to the CONNECT address
    ...
    
    $client->close();
  }
  
  sub auth {
    my ($user, $pass) = @_;
    
    return 1 if $user eq "foo" && $pass eq "bar";
    return 0;
  }

=head1 DESCRIPTION

C<IO::Socket::Socks> connects to a SOCKS proxy, tells it to open a
connection to a remote host/port when the object is created.  The
object you receive can be used directly as a socket (with C<IO::Socket> interface)
for sending and receiving data from the remote host. In addition to create socks client
this module could be used to create socks server. See examples below.

=head1 EXAMPLES

For complete examples of socks 4/5 client and server see `examples'
subdirectory in the distribution.

=head1 METHODS

=head2 Socks Client

=head3 new( %cfg )

=head3 new_from_socket($socket, %cfg)

=head3 new_from_fd($socket, %cfg)

Creates a new IO::Socket::Socks client object.  new_from_socket() is the same as
new(), but allows one to create object from an existing and not connected socket 
(new_from_fd is new_from_socket alias). To make IO::Socket::Socks object from
connected socket see C<start_SOCKS>

Both takes the following config hash:

  SocksVersion => 4 or 5. Default is 5
  
  Timeout => connect/accept timeout
  
  Blocking => Since IO::Socket::Socks version 0.5 you can perform non-blocking connect/bind by 
              passing false value for this option. Default is true - blocking. See ready()
              below for more details.
  
  SocksResolve => resolve host name to ip by proxy server or 
                  not (will resolve by client). This
                  overrides value of $SOCKS4_RESOLVE or $SOCKS5_RESOLVE
                  variable. Boolean.
  
  SocksDebug => This will cause all of the SOCKS traffic to
                be presented on the command line in a form
                similar to the tables in the RFCs. This overrides value
                of $SOCKS_DEBUG variable. Boolean.
  
  ProxyAddr => Hostname of the proxy
  
  ProxyPort => Port of the proxy
  
  ConnectAddr => Hostname of the remote machine
  
  ConnectPort => Port of the remote machine
  
  BindAddr => Hostname of the remote machine which will
              connect to the proxy server after bind request
  
  BindPort => Port of the remote machine which will
              connect to the proxy server after bind request
  
  UdpAddr => Expected address where datagrams will be sent. Fill it with address
             of all zeros if address is not known at this moment.
             Proxy server may use this information to limit access to the association.
  
  UdpPort => Expected port where datagrams will be sent. Use zero port
             if port is not known at this moment. Proxy server may use this
             information to limit access to the association.
  
  AuthType => What kind of authentication to support:
              none       - no authentication (default)
              userpass  - Username/Password. For socks5
              proxy only.
  
  RequireAuth => Do not send ANON as a valid auth mechanism.
                 For socks5 proxy only
  
  Username => For socks5 if AuthType is set to userpass, then
              you must provide a username. For socks4 proxy with
              this option you can specify userid.
  
  Password => If AuthType is set to userpass, then you must
              provide a password. For socks5 proxy only.

The following options should be specified:

  (ProxyAddr and ProxyPort)
  (ConnectAddr and ConnectPort) or (BindAddr and BindPort) or (UdpAddr and UdpPort)

Other options are facultative.

=head3
start_SOCKS($socket, %cfg)

This is a class method to start socks handshake on already connected socket. This
will bless passed $socket to IO::Socket::Socks class. %cfg is like hash in the constructor.
Only options listed below makes sence:

  Timeout
  ConnectAddr
  ConnectPort
  BindAddr
  BindPort
  UdpAddr
  UdpPort
  SocksVersion
  SocksDebug
  SocksResolve
  AuthType
  RequireAuth
  Username
  Password
  AuthMethods

On success this method will return same $socket, but as IO::Socket::Socks object. On failure it will
return undef (but socket will be still blessed to IO::Socket::Socks class). See example:

  use IO::Socket;
  use IO::Socket::Socks;
  
  my $sock = IO::Socket::INET->new("$proxy_host:$proxy_port") or die $@;
  $sock = IO::Socket::Socks->start_SOCKS($sock, ConnectAddr => "google.com", ConnectPort => 80) or die $SOCKS_ERROR;

=head3
version( )

Returns socks version for this socket

=head3
ready( )

Returns true when socket becomes ready to transfer data (socks handshake done),
false otherwise. This is useful for non-blocking connect/bind. When this method
returns false value you can determine what socks handshake need for with $SOCKS_ERROR
variable. It may need for read, then $SOCKS_ERROR will be SOCKS_WANT_READ or need for
write, then it will be SOCKS_WANT_WRITE.

Example:

    use IO::Socket::Socks;
    use IO::Select;
    
    my $sock = IO::Socket::Socks->new(
        ProxyAddr => 'localhost', ProxyPort => 1080, ConnectAddr => 'mail.com', ConnectPort => 80, Blocking => 0
    ) or die $SOCKS_ERROR;
    
    my $sel = IO::Select->new($sock);
    until ($sock->ready) {
        if ($SOCKS_ERROR == SOCKS_WANT_READ) {
            $sel->can_read();
        }
        elsif ($SOCKS_ERROR == SOCKS_WANT_WRITE) {
            $sel->can_write();
        }
        else {
            die $SOCKS_ERROR;
        }
        
        # NOTE: when base class ($IO::Socket::Socks::SOCKET_CLASS) is IO::Socket::IP
        # and you are using kqueue or epoll to check for readable/writable sockets
        # you need to readd $sock to kqueue/epoll after each call to ready() (actually until socket will be connected to proxy server),
        # because IO::Socket::IP may change internal socket of $sock for milti-homed hosts.
        # There is no such problem when you are using select/poll
    }
    
    # you may want to return socket to blocking state by $sock->blocking(1)
    $sock->syswrite("I am ready");

=head3
accept( )

Accept an incoming connection after bind request. On failed returns undef.
On success returns socket. No new socket created, returned socket is same
on which this method was called. Because accept(2) is not invoked on the
client side, socks server calls accept(2) and proxify all traffic via socket
opened by client bind request. You can call accept only once on IO::Socket::Socks
client socket.

=head3
command( %cfg )

Allows one to execute socks command on already opened socket. Thus you
can create socks chain. For example see L</EXAMPLES> section.

%cfg is like hash in the constructor. Only options listed below makes sence:

  ConnectAddr
  ConnectPort
  BindAddr
  BindPort
  UdpAddr
  UdpPort
  SocksVersion
  SocksDebug
  SocksResolve
  AuthType
  RequireAuth
  Username
  Password
  AuthMethods

Values of the other options (Timeout for example) inherited from the constructor.
Options like ProxyAddr and ProxyPort are not included.

=head3
dst( )

Return (host, port, address_type) of the remote host after connect/accept or socks server (host, port, address_type)
after bind/udpassoc.

=head2 Socks Server

=head3 new( %cfg )

=head3 new_from_socket($socket, %cfg)

=head3 new_from_fd($socket, %cfg)

Creates a new IO::Socket::Socks server object. new_from_socket() is the same as
new(), but allows one to create object from an existing socket (new_from_fd is new_from_socket alias).
Both takes the following config hash:

  SocksVersion => 4 for socks4, 5 for socks5 or [4,5] if you want accept both 4 and 5. Default is 5
  
  Timeout => Timeout value for various operations
  
  Blocking => Since IO::Socket::Socks version 0.6 you can perform non-blocking accept by 
              passing false value for this option. Default is true - blocking. See ready()
              below for more details.
  
  SocksResolve => For socks v5: return destination address to the client
                  in form of 4 bytes if true, otherwise in form of host
                  length and host name.
                  For socks v4: allow use socks4a protocol extension if
                  true and not otherwise.
                  This overrides value of $SOCKS4_RESOLVE or $SOCKS5_RESOLVE.
                  See also command_reply().
  
  SocksDebug => This will cause all of the SOCKS traffic to
                be presented on the command line in a form
                similar to the tables in the RFCs. This overrides value
                of $SOCKS_DEBUG variable. Boolean.
  
  ProxyAddr => Local host bind address
  
  ProxyPort => Local host bind port
  
  UserAuth => Reference to a function that returns 1 if client
              allowed to use socks server, 0 otherwise. For
              socks5 proxy it takes login and password as
              arguments. For socks4 argument is userid.
  
  RequireAuth => Not allow anonymous access for socks5 proxy.
  
  Listen => Same as IO::Socket::INET listen option. Should be
            specified as number > 0.

The following options should be specified:

  Listen
  ProxyAddr
  ProxyPort

Other options are facultative.

=head3 accept( )

Accept an incoming connection and return a new IO::Socket::Socks
object that represents that connection.  You must call command()
on this to find out what the incoming connection wants you to do,
and then call command_reply() to send back the reply.

=head3 version( )

Returns socks version for socket. It is useful when your server
accepts both 4 and 5 version. Then you should know socks version
to make proper response. Just call C<version()> on socket received
after C<accept()>.

=head3 ready( )

After non-blocking accept you will get new client socket object, which may be
not ready to transfer data (if socks handshake is not done yet). ready() will return
true value when handshake will be done successfully and false otherwise. Note, socket
returned by accept() call will be always in blocking mode. So if your program can't
block you should set non-blocking mode for this socket before ready() call: $socket->blocking(0).
When ready() returns false value you can determine what socks handshake needs for with $SOCKS_ERROR
variable. It may need for read, then $SOCKS_ERROR will be SOCKS_WANT_READ or need for
write, then it will be SOCKS_WANT_WRITE.

Example:

  use IO::Socket::Socks;
  use IO::Select;
  
  my $server = IO::Socket::Socks->new(ProxyAddr => 'localhost', ProxyPort => 1080, Blocking => 0)
      or die $@;
  my $select = IO::Select->new($server);
  $select->can_read(); # wait for client
  
  my $client = $server->accept()
    or die "accept(): $! ($SOCKS_ERROR)";
  $client->blocking(0); # !!!
  $select->add($client);
  $select->remove($server); # no more connections
  
  while (1) {
      if ($client->ready) {
          my $command = $client->command;
          
          ... # do client command
          
          $client->command_reply(IO::Socket::Socks::REPLY_SUCCESS, $command->[1], $command->[2]);
          
          ... # transfer traffic
          
          last;
      }
      elsif ($SOCKS_ERROR == SOCKS_WANT_READ) {
          $select->can_read();
      }
      elsif ($SOCKS_ERROR == SOCKS_WANT_WRITE) {
          $select->can_write();
      }
      else {
          die "Unexpected error: $SOCKS_ERROR";
      }
  }

=head3 command( )

After you call accept() the client has sent the command they want
you to process.  This function should be called on the socket returned
by accept(). It returns a reference to an array with the following format:

  [ COMMAND, ADDRESS, PORT, ADDRESS TYPE ]

=head3 command_reply( REPLY CODE, ADDRESS, PORT )

After you call command() the client needs to be told what the result
is.  The REPLY CODE is one of the constants as follows (integer value):

  For socks v4
  REQUEST_GRANTED(90): request granted
  REQUEST_FAILED(91): request rejected or failed
  REQUEST_REJECTED_IDENTD(92): request rejected because SOCKS server cannot connect to identd on the client
  REQUEST_REJECTED_USERID(93): request rejected because the client program and identd report different user-ids
  
  For socks v5
  REPLY_SUCCESS(0): Success
  REPLY_GENERAL_FAILURE(1): General Failure
  REPLY_CONN_NOT_ALLOWED(2): Connection Not Allowed
  REPLY_NETWORK_UNREACHABLE(3): Network Unreachable
  REPLY_HOST_UNREACHABLE(4): Host Unreachable
  REPLY_CONN_REFUSED(5): Connection Refused
  REPLY_TTL_EXPIRED(6): TTL Expired
  REPLY_CMD_NOT_SUPPORTED(7): Command Not Supported
  REPLY_ADDR_NOT_SUPPORTED(8): Address Not Supported

HOST and PORT are the resulting host and port (where server socket responsible for this command bound).

Note: for 5 version C<command_reply> will try to resolve passed address if
C<SocksResolve> has true value and passed address is domain name. To avoid this just pass ip address
(C<$socket-E<gt>sockhost>) instead of host name or turn off C<SocksResolve> for this server. For version 4
passed host name will always be resolved to ip address even if C<SocksResolve> has false value. Because
this version doesn't support C<ADDRESS> as domain name.

=head1 VARIABLES

=head2 $SOCKS_ERROR

This scalar behaves like $! in that if undef is returned. C<$SOCKS_ERROR> is IO::Socket::Socks::Error
object with some overloaded operators. In string context this variable should contain a string reason for
the error. In numeric context it contains error code.

=head2 $SOCKS4_RESOLVE

If this variable has true value resolving of host names will be done
by proxy server, otherwise resolving will be done locally. Resolving
host by socks proxy version 4 is extension to the protocol also known
as socks4a. So, only socks4a proxy  supports resolving of hostnames.
Default value of this variable is false. This variable is not importable.
See also `SocksResolve' parameter in the constructor.

=head2 $SOCKS5_RESOLVE

If this variable has true value resolving of host names will be done
by proxy server, otherwise resolving will be done locally. Note: some
bugous socks5 servers doesn't support resolving of host names. Default
value is true. This variable is not importable.
See also `SocksResolve' parameter in the constructor.

=head2 $SOCKS_DEBUG

Default value is $ENV{SOCKS_DEBUG}. If this variable has true value and
no SocksDebug option in the constructor specified, then SocksDebug will
has true value. This variable is not importable.

=head2 $SOCKET_CLASS

With this variable you can get/set base socket class for C<IO::Socket::Socks>.
By default it tries to use C<IO::Socket::IP> 0.36+ as socket class. And falls
back to C<IO::Socket::INET> if not available. You can set C<$IO::Socket::Socks::SOCKET_CLASS>
before loading of C<IO::Socket::Socks> and then it will not try to detect proper base class
itself. You can also set it after loading of C<IO::Socket::Socks> and this will automatically
update C<@ISA>, so you shouldn't worry about inheritance.

=head1 CONSTANTS

The following constants could be imported manually or using `:constants' tag:

  SOCKS5_VER
  SOCKS4_VER
  ADDR_IPV4
  ADDR_DOMAINNAME
  ADDR_IPV6
  CMD_CONNECT
  CMD_BIND
  CMD_UDPASSOC
  AUTHMECH_ANON
  AUTHMECH_USERPASS
  AUTHMECH_INVALID
  AUTHREPLY_SUCCESS
  AUTHREPLY_FAILURE
  ISS_UNKNOWN_ADDRESS # address type sent by client/server not supported by I::S::S
  ISS_BAD_VERSION     # socks version sent by client/server != specified version
  ISS_CANT_RESOLVE    # I::S::S failed to resolve some host
  REPLY_SUCCESS
  REPLY_GENERAL_FAILURE
  REPLY_CONN_NOT_ALLOWED
  REPLY_NETWORK_UNREACHABLE
  REPLY_HOST_UNREACHABLE
  REPLY_CONN_REFUSED
  REPLY_TTL_EXPIRED
  REPLY_CMD_NOT_SUPPORTED
  REPLY_ADDR_NOT_SUPPORTED
  REQUEST_GRANTED
  REQUEST_FAILED
  REQUEST_REJECTED_IDENTD
  REQUEST_REJECTED_USERID
  SOCKS_WANT_READ
  SOCKS_WANT_WRITE
  ESOCKSPROTO

SOCKS_WANT_READ, SOCKS_WANT_WRITE and ESOCKSPROTO are imported by default.

=head1 IPv6

Since version 0.66 C<IO::Socket::Socks> supports IPv6 with help of L<IO::Socket::IP>
0.36+. And will use C<IO::Socket::IP> as base class if available. However you can
force set C<$SOCKET_CLASS = "IO::Socket::INET"> to use IPv4 only. See also
L</$SOCKET_CLASS>

=head1 FAQ

=over

=item How to determine is connection to socks server (client accept) failed or some protocol error
occurred?

You can check $! variable. If $! == ESOCKSPROTO constant, then it was error in the protocol. Error
description could be found in $SOCKS_ERROR.

=item How to determine which error in the protocol occurred?

You should compare C<$SOCKS_ERROR> with constants below:

  AUTHMECH_INVALID
  AUTHREPLY_FAILURE
  ISS_UNKNOWN_ADDRESS
  ISS_BAD_VERSION
  REPLY_GENERAL_FAILURE
  REPLY_CONN_NOT_ALLOWED
  REPLY_NETWORK_UNREACHABLE
  REPLY_HOST_UNREACHABLE
  REPLY_CONN_REFUSED
  REPLY_TTL_EXPIRED
  REPLY_CMD_NOT_SUPPORTED
  REPLY_ADDR_NOT_SUPPORTED
  REQUEST_FAILED
  REQUEST_REJECTED_IDENTD
  REQUEST_REJECTED_USERID

=back

=head1 BUGS

The following options are not implemented:

=over

=item GSSAPI authentication

=item UDP server side support

=back

Patches are welcome.

=head1 SEE ALSO

L<IO::Socket::Socks::Wrapper>

=head1 AUTHOR

Original author is Ryan Eatmon

Now maintained by Oleg G <oleg@cpan.org>

=head1 COPYRIGHT

This module is free software, you can redistribute it and/or modify
it under the terms of LGPL.

=cut
