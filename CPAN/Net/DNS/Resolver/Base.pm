package Net::DNS::Resolver::Base;
#
# $Id: Base.pm,v 1.1 2004/02/16 17:30:04 daniel Exp $
#

use strict;

use vars qw(
	$VERSION
	$AUTOLOAD
);

use Carp;
use Config ();
use Socket;
use IO::Socket;

use Net::DNS;
use Net::DNS::Packet;
use Net::DNS::Select;

$VERSION = (qw$Revision: 1.1 $)[1];

#
# Set up a closure to be our class data.
#
{
	my %defaults = (
		nameservers	   => ['127.0.0.1'],
		port		   => 53,
		srcaddr        => '0.0.0.0',
		srcport        => 0,
		domain	       => '',
		searchlist	   => [],
		retrans	       => 5,
		retry		   => 4,
		usevc		   => 0,
		stayopen       => 0,
		igntc          => 0,
		recurse        => 1,
		defnames       => 1,
		dnsrch         => 1,
		debug          => 0,
		errorstring	   => 'unknown error or no error',
		tsig_rr        => undef,
		answerfrom     => '',
		answersize     => 0,
		querytime      => undef,
		tcp_timeout    => 120,
		udp_timeout    => undef,
		axfr_sel       => undef,
		axfr_rr        => [],
		axfr_soa_count => 0,
		persistent_tcp => 0,
		persistent_udp => 0,
		dnssec         => 0,
		udppacketsize  => 0,  # The actual default is lower bound by Net::DNS::PACKETSZ
		cdflag         => 1,  # this is only used when {dnssec} == 1
	);
	
	# If we're running under a SOCKSified Perl, use TCP instead of UDP
	# and keep the sockets open.
	if ($Config::Config{'usesocks'}) {
		$defaults{'usevc'} = 1;
		$defaults{'persistent_tcp'} = 1;
	}
	
	sub defaults { \%defaults }
}

# These are the attributes that we let the user specify in the new().
# We also deprecate access to these with AUTOLOAD (some may be useful).
my %public_attr = map { $_ => 1 } qw(
	nameservers
	port
	srcaddr
	srcport
	domain
	searchlist
	retrans
	retry
	usevc
	stayopen
	igntc
	recurse
	defnames
	dnsrch
	debug
	tcp_timeout
	udp_timeout
	persistent_tcp
	persistent_udp
	dnssec
);


sub new {
	my $class = shift;

	my $self = bless({ %{$class->defaults} }, $class);

	$self->_process_args(@_) if @_ and @_ % 2 == 0;
			
	return $self;
}

sub _process_args {
	my ($self, %args) = @_;
	
	if ($args{'config_file'}) {
		$self->read_config_file($args{'config_file'});
	}
	
	foreach my $attr (keys %args) {
		next unless $public_attr{$attr};
	
		if ($attr eq 'nameservers' || $attr eq 'searchlist') {
			die "Net::DNS::Resolver->new(): $attr must be an arrayref\n" unless
				UNIVERSAL::isa($args{$attr}, 'ARRAY');
		}
		
		$self->{$attr} = $args{$attr};
	}
}
			
			
			


#
# Some people have reported that Net::DNS dies because AUTOLOAD picks up
# calls to DESTROY.
#
sub DESTROY {}


sub read_env {
	my ($invocant) = @_;
	my $config     = ref $invocant ? $invocant : $invocant->defaults;
	
	$config->{'nameservers'} = [ split(' ', $ENV{'RES_NAMESERVERS'}) ]
		if exists $ENV{'RES_NAMESERVERS'};

	$config->{'searchlist'}  = [ split(' ', $ENV{'RES_SEARCHLIST'})  ]
		if exists $ENV{'RES_SEARCHLIST'};
	
	$config->{'domain'} = $ENV{'LOCALDOMAIN'}
		if exists $ENV{'LOCALDOMAIN'};

	if (exists $ENV{'RES_OPTIONS'}) {
		foreach (split(' ', $ENV{'RES_OPTIONS'})) {
			my ($name, $val) = split(/:/);
			$val = 1 unless defined $val;
			$config->{$name} = $val if exists $config->{$name};
		}
	}
}

#
# $class->read_config_file($filename) or $self->read_config_file($file)
#
sub read_config_file {
	my ($invocant, $file) = @_;
	my $config            = ref $invocant ? $invocant : $invocant->defaults;

	
	my @ns;
	my @searchlist;
	
	local *FILE;

	open(FILE, "< $file") or croak "Could not open $file: $!";
	local $/ = "\n";
	local $_;
	
	while (<FILE>) {
		s/\s*[;#].*//;
		
		# Skip ahead unless there's non-whitespace characters 
		next unless m/\S/;

		SWITCH: {
			/^\s*domain\s+(\S+)/ && do {
				$config->{'domain'} = $1;
				last SWITCH;
			};

			/^\s*search\s+(.*)/ && do {
				push(@searchlist, split(' ', $1));
				last SWITCH;
			};

			/^\s*nameserver\s+(.*)/ && do {
				foreach my $ns (split(' ', $1)) {
					$ns = '0.0.0.0' if $ns eq '0';
					next if $ns =~ m/:/;  # skip IPv6 nameservers
					push @ns, $ns;
				}
				last SWITCH;
			};
		}
	}
	close FILE || croak "Could not close $file: $!";

	$config->{'nameservers'} = [ @ns ]         if @ns;
	$config->{'searchlist'}  = [ @searchlist ] if @searchlist;
}


sub print { print $_[0]->string }

sub string {
	my $self = shift;

	my $timeout = defined $self->{'tcp_timeout'} ? $self->{'tcp_timeout'} : 'indefinite';
	
	return <<END;
;; RESOLVER state:
;;  domain       = $self->{domain}
;;  searchlist   = @{$self->{searchlist}}
;;  nameservers  = @{$self->{nameservers}}
;;  port         = $self->{port}
;;  srcport      = $self->{srcport}
;;  srcaddr      = $self->{srcaddr}
;;  tcp_timeout  = $timeout
;;  retrans  = $self->{retrans}  retry    = $self->{retry}
;;  usevc    = $self->{usevc}  stayopen = $self->{stayopen}    igntc = $self->{igntc}
;;  defnames = $self->{defnames}  dnsrch   = $self->{dnsrch}
;;  recurse  = $self->{recurse}  debug    = $self->{debug}
END
}


sub searchlist {
	my $self = shift;
	$self->{'searchlist'} = [ @_ ] if @_;
	return @{$self->{'searchlist'}};
}

sub nameservers {
	my $self   = shift;
	my $defres = Net::DNS::Resolver->new;

	if (@_) {
		my @a;
		foreach my $ns (@_) {
			if ($ns =~ /^\d+(\.\d+){0,3}$/) {
				push @a, ($ns eq '0') ? '0.0.0.0' : $ns;
			}
			else {
				my @names;

				if ($ns !~ /\./) {
					if (defined $defres->searchlist) {
						@names = map { $ns . '.' . $_ }
							    $defres->searchlist;
					}
					elsif (defined $defres->domain) {
						@names = ($ns . '.' . $defres->domain);
					}
				}
				else {
					@names = ($ns);
				}

				my $packet = $defres->search($ns);
				$self->errorstring($defres->errorstring);
				if (defined($packet)) {
					push @a, cname_addr([@names], $packet);
				}
			}
		}

		$self->{'nameservers'} = [ @a ];
	}

	return @{$self->{'nameservers'}};
}

sub nameserver { &nameservers }

sub cname_addr {
	my $names  = shift;
	my $packet = shift;
	my @addr;
	my @names = @{$names};

	my $oct2 = '(?:2[0-4]\d|25[0-5]|[0-1]?\d\d|\d)';

	RR: foreach my $rr ($packet->answer) {
		next RR unless grep {$rr->name} @names;
				
		if ($rr->type eq 'CNAME') {
			push(@names, $rr->cname);
		} elsif ($rr->type eq 'A') {
			# Run a basic taint check.
			next RR unless $rr->address =~ m/^($oct2\.$oct2\.$oct2\.$oct2)$/o;
			
			push(@addr, $1)
		}
	}
	
	
	return @addr;
}


# if ($self->{"udppacketsize"}  > &Net::DNS::PACKETSZ 
# then we use EDNS and $self->{"udppacketsize"} 
# should be taken as the maximum packet_data length
sub _packetsz {
	my ($self) = @_;

	return $self->{"udppacketsize"} > &Net::DNS::PACKETSZ ? 
		   $self->{"udppacketsize"} : &Net::DNS::PACKETSZ; 
}

sub _reset_errorstring {
	my ($self) = @_;
	
	$self->errorstring($self->defaults->{'errorstring'});
}


sub search {
	my $self = shift;
	my ($name, $type, $class) = @_;
	my $ans;

	$type  = 'A'  unless defined($type);
	$class = 'IN' unless defined($class);

	# If the name looks like an IP address then do an appropriate
	# PTR query.
	if ($name =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/) {
		$name = "$4.$3.$2.$1.in-addr.arpa.";
		$type = 'PTR';
	}

	# If the name contains at least one dot then try it as is first.
	if (index($name, '.') >= 0) {
		print ";; search($name, $type, $class)\n" if $self->{'debug'};
		$ans = $self->query($name, $type, $class);
		return $ans if $ans and $ans->header->ancount;
	}

	# If the name doesn't end in a dot then apply the search list.
	if (($name !~ /\.$/) && $self->{'dnsrch'}) {
		foreach my $domain (@{$self->{'searchlist'}}) {
			my $newname = "$name.$domain";
			print ";; search($newname, $type, $class)\n"
				if $self->{'debug'};
			$ans = $self->query($newname, $type, $class);
			return $ans if $ans and $ans->header->ancount;
		}
	}

	# Finally, if the name has no dots then try it as is.
	if (index($name, '.') < 0) {
		print ";; search($name, $type, $class)\n" if $self->{'debug'};
		$ans = $self->query("$name.", $type, $class);
		return $ans if $ans and $ans->header->ancount;
	}

	# No answer was found.
	return undef;
}


sub query {
	my ($self, $name, $type, $class) = @_;

	$type  = 'A'  unless defined($type);
	$class = 'IN' unless defined($class);

	# If the name doesn't contain any dots then append the default domain.
	if ((index($name, '.') < 0) && $self->{'defnames'}) {
		$name .= ".$self->{domain}";
	}

	# If the name looks like an IP address then do an appropriate
	# PTR query.
	if ($name =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/) {
		$name = "$4.$3.$2.$1.in-addr.arpa";
		$type = 'PTR';
	}

	print ";; query($name, $type, $class)\n" if $self->{'debug'};
	my $packet = Net::DNS::Packet->new($name, $type, $class);


	
	my $ans = $self->send($packet);

	return $ans && $ans->header->ancount   ? $ans : undef;
}


sub send {
	my $self = shift;
	my $packet = $self->make_query_packet(@_);
	my $packet_data = $packet->data;

	my $ans;

	if ($self->{'usevc'} || length $packet_data > $self->_packetsz) {
	  
	    $ans = $self->send_tcp($packet, $packet_data);
	    
	} else {
	    $ans = $self->send_udp($packet, $packet_data);
	    
	    if ($ans && $ans->header->tc && !$self->{'igntc'}) {
			print ";;\n;; packet truncated: retrying using TCP\n" if $self->{'debug'};
			$ans = $self->send_tcp($packet, $packet_data);
	    }
	}
	
	return $ans;
}



sub send_tcp {
	my ($self, $packet, $packet_data) = @_;

	unless (@{$self->{'nameservers'}}) {
		$self->errorstring('no nameservers');
		print ";; ERROR: send_tcp: no nameservers\n" if $self->{'debug'};
		return;
	}

	$self->_reset_errorstring;
	my $timeout = $self->{'tcp_timeout'};

	foreach my $ns (@{$self->{'nameservers'}}) {
		my $srcport = $self->{'srcport'};
		my $srcaddr = $self->{'srcaddr'};
		my $dstport = $self->{'port'};

		print ";; send_tcp($ns:$dstport) (src port = $srcport)\n"
			if $self->{'debug'};

		my $sock;
		my $sock_key = "$ns:$dstport";

		if ($self->persistent_tcp && $self->{'sockets'}{$sock_key}) {
			$sock = $self->{'sockets'}{$sock_key};
			print ";; using persistent socket\n"
				if $self->{'debug'};
		}
		else {

			# IO::Socket carps on errors if Perl's -w flag is
			# turned on.  Uncomment the next two lines and the
			# line following the "new" call to turn off these
			# messages.

			#my $old_wflag = $^W;
			#$^W = 0;

			$sock = IO::Socket::INET->new(
			    PeerAddr  => $ns,
			    PeerPort  => $dstport,
			    LocalAddr => $srcaddr,
			    LocalPort => ($srcport || undef),
			    Proto     => 'tcp',
			    Timeout   => $timeout
			);

			#$^W = $old_wflag;

			unless ($sock) {
				$self->errorstring('connection failed');
				print ';; ERROR: send_tcp: connection ',
				      "failed: $!\n" if $self->{'debug'};
				next;
			}

			$self->{'sockets'}{$sock_key} = $sock;
		}

		my $lenmsg = pack('n', length($packet_data));
		print ';; sending ', length($packet_data), " bytes\n"
			if $self->{'debug'};

		# note that we send the length and packet data in a single call
		# as this produces a single TCP packet rather than two. This
		# is more efficient and also makes things much nicer for sniffers.
		# (ethereal doesn't seem to reassemble DNS over TCP correctly)
		unless ($sock->send($lenmsg . $packet_data)) {
			$self->errorstring($!);
			print ";; ERROR: send_tcp: data send failed: $!\n"
				if $self->{'debug'};
			next;
		}

		my $sel = Net::DNS::Select->new($sock);

		if ($sel->can_read($timeout)) {
			my $buf = read_tcp($sock, &Net::DNS::INT16SZ, $self->{'debug'});
			next unless length($buf);
			my ($len) = unpack('n', $buf);
			next unless $len;

			unless ($sel->can_read($timeout)) {
				$self->errorstring('timeout');
				print ";; TIMEOUT\n" if $self->{'debug'};
				next;
			}

			$buf = read_tcp($sock, $len, $self->{'debug'});

			$self->answerfrom($sock->peerhost);
			$self->answersize(length $buf);

			print ';; received ', length($buf), " bytes\n"
				if $self->{'debug'};

			unless (length($buf) == $len) {
				$self->errorstring("expected $len bytes, " .
						   'received ' . length($buf));
				next;
			}

			my ($ans, $err) = Net::DNS::Packet->new(\$buf, $self->{'debug'});
			if (defined $ans) {
				$self->errorstring($ans->header->rcode);
				$ans->answerfrom($self->answerfrom);
				$ans->answersize($self->answersize);
			}
			elsif (defined $err) {
				$self->errorstring($err);
			}

			return $ans;
		}
		else {
			$self->errorstring('timeout');
			next;
		}
	}

	return;
}

sub send_udp {
	my ($self, $packet, $packet_data) = @_;
	my $retrans = $self->{'retrans'};
	my $timeout = $retrans;

	my $stop_time = time + $self->{'udp_timeout'} if $self->{'udp_timeout'};

	$self->_reset_errorstring;

	my $dstport = $self->{'port'};
	my $srcport = $self->{'srcport'};
	my $srcaddr = $self->{'srcaddr'};

	my $sock;

	if ($self->persistent_udp && $self->{'sockets'}{'UDP'}) {
		$sock = $self->{'sockets'}{'UDP'};
		print ";; using persistent socket\n"
			if $self->{'debug'};
	} else {
		# IO::Socket carps on errors if Perl's -w flag is turned on.
		# Uncomment the next two lines and the line following the "new"
		# call to turn off these messages.

		#my $old_wflag = $^W;
		#$^W = 0;

		$sock = IO::Socket::INET->new(
				    LocalAddr => $srcaddr,
				    LocalPort => ($srcport || undef),
				    Proto     => 'udp',
		);

		#$^W = $old_wflag;

		unless ($sock) {
			$self->errorstring("couldn't create socket: $!");
			return;
		}
		$self->{'sockets'}{'UDP'} = $sock if ($self->persistent_udp);
	}

	my @ns = grep { $_->[0] && $_->[1] }
	         map  { [ $_, scalar(sockaddr_in($dstport, inet_aton($_))) ] }
	         @{$self->{'nameservers'}};

	unless (@ns) {
		$self->errorstring('no nameservers');
		return;
	}

	my $sel = Net::DNS::Select->new($sock);

	# Perform each round of retries.
	for (my $i = 0;
	     $i < $self->{'retry'};
	     ++$i, $retrans *= 2, $timeout = int($retrans / (@ns || 1))) {

		$timeout = 1 if ($timeout < 1);

		# Try each nameserver.
		foreach my $ns (@ns) {
			if ($stop_time) {
				my $now = time;
				if ($stop_time < $now) {
					$self->errorstring('query timed out');
					return;
				}
				if ($timeout > 1 && $timeout > ($stop_time-$now)) {
					$timeout = $stop_time-$now;
				}
			}
			my $nsname = $ns->[0];
			my $nsaddr = $ns->[1];

			print ";; send_udp($nsname:$dstport)\n"
				if $self->{'debug'};

			unless ($sock->send($packet_data, 0, $nsaddr)) {
				print ";; send error: $!\n" if $self->{'debug'};
				@ns = grep { $_->[0] ne $nsname } @ns;
				next;
			}

			my @ready = $sel->can_read($timeout);

			foreach my $ready (@ready) {
				my $buf = '';

				if ($ready->recv($buf, $self->_packetsz)) {
				
					$self->answerfrom($ready->peerhost);
					$self->answersize(length $buf);
				
					print ';; answer from ',
					      $ready->peerhost, ':',
					      $ready->peerport, ' : ',
					      length($buf), " bytes\n"
						if $self->{'debug'};
				
					my ($ans, $err) = Net::DNS::Packet->new(\$buf, $self->{'debug'});
				
					if (defined $ans) {
						next unless $ans->header->qr;
						next unless $ans->header->id == $packet->header->id;
						$self->errorstring($ans->header->rcode);
						$ans->answerfrom($self->answerfrom);
						$ans->answersize($self->answersize);
					} elsif (defined $err) {
						$self->errorstring($err);
					}
					
					return $ans;
				} else {
					$self->errorstring($!);
					
					print ';; recv ERROR(',
					      $ready->peerhost, ':',
					      $ready->peerport, '): ',
					      $self->errorstring, "\n"
						if $self->{'debug'};

					@ns = grep { $_->[0] ne $ready->peerhost } @ns;
					
					return unless @ns;
				}
			}
		}
	}

	if ($sel->handles) {
		$self->errorstring('query timed out');
	}
	else {
		$self->errorstring('all nameservers failed');
	}
	return;
}


sub bgsend {
	my $self = shift;

	unless (@{$self->{'nameservers'}}) {
		$self->errorstring('no nameservers');
		return;
	}

	$self->_reset_errorstring;

	my $packet = $self->make_query_packet(@_);
	my $packet_data = $packet->data;

	my $srcaddr = $self->{'srcaddr'};
	my $srcport = $self->{'srcport'};

	my $dstaddr = $self->{'nameservers'}->[0];
	my $dstport = $self->{'port'};

	my $sock = IO::Socket::INET->new(
		Proto => 'udp',
		LocalAddr => $srcaddr,
		LocalPort => ($srcport || undef),
	);

	unless ($sock) {
		$self->errorstring(q|couldn't get socket|);   #'
		return;
	}
	
	my $dst_sockaddr = sockaddr_in($dstport, inet_aton($dstaddr));

	print ";; bgsend($dstaddr:$dstport)\n" if $self->{'debug'};

	unless ($sock->send($packet_data, 0, $dst_sockaddr)) {
		my $err = $!;
		print ";; send ERROR($dstaddr): $err\n" if $self->{'debug'};
		$self->errorstring($err);
		return;
	}

	return $sock;
}


sub bgread {
	my ($self, $sock) = @_;

	my $buf = '';

	my $peeraddr = $sock->recv($buf, $self->_packetsz);
	
	if ($peeraddr) {
		print ';; answer from ', $sock->peerhost, ':',
		      $sock->peerport, ' : ', length($buf), " bytes\n"
			if $self->{'debug'};

		my ($ans, $err) = Net::DNS::Packet->new(\$buf, $self->{'debug'});
		
		if (defined $ans) {
			$self->errorstring($ans->header->rcode);
		} elsif (defined $err) {
			$self->errorstring($err);
		}
		
		return $ans;
	} else {
		$self->errorstring($!);
		return;
	}
}

sub bgisready {
	my $self = shift;
	my $sel = Net::DNS::Select->new(@_);
	my @ready = $sel->can_read(0.0);
	return @ready > 0;
}

sub make_query_packet {
	my $self = shift;
	my $packet;

	if (ref($_[0]) and $_[0]->isa('Net::DNS::Packet')) {
		$packet = shift;
	} else {
		my ($name, $type, $class) = @_;

		$name  ||= '';
		$type  ||= 'A';
		$class ||= 'IN';

		# If the name looks like an IP address then do an appropriate
		# PTR query.
		if ($name =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/) {
			$name = "$4.$3.$2.$1.in-addr.arpa.";
			$type = 'PTR';
		}

		$packet = Net::DNS::Packet->new($name, $type, $class);
	}

	if ($packet->header->opcode eq 'QUERY') {
		$packet->header->rd($self->{'recurse'});
	}

    if ($self->{'dnssec'}) {
	    # RFC 3225
    	print ";; Adding EDNS extention with UDP packetsize $self->{'udppacketsize'} and DNS OK bit set\n" 
    		if $self->{'debug'};
    	
    	my $optrr = Net::DNS::RR->new(
						Type         => 'OPT',
						Name         => '',
						Class        => $self->{'udppacketsize'},  # Decimal UDPpayload
						ednsflags    => 0x8000, # first bit set see RFC 3225 
				   );
				 
	    $packet->push('additional', $optrr);
	    
	} elsif ($self->{'udppacketsize'} > &Net::DNS::PACKETSZ) {
	    print ";; Adding EDNS extention with UDP packetsize  $self->{'udppacketsize'}.\n" if $self->{'debug'};
	    # RFC 3225
	    my $optrr = Net::DNS::RR->new( 
						Type         => 'OPT',
						Name         => '',
						Class        => $self->{'udppacketsize'},  # Decimal UDPpayload
						TTL          => 0x0000 # RCODE 32bit Hex
				    );
				    
	    $packet->push('additional', $optrr);
	}
	

	if ($self->{'tsig_rr'}) {
		if (!grep { $_->type eq 'TSIG' } $packet->additional) {
			$packet->push('additional', $self->{'tsig_rr'});
		}
	}

	return $packet;
}

sub axfr {
	my $self = shift;
	my @zone;

	if ($self->axfr_start(@_)) {
		my ($rr, $err);
		while (($rr, $err) = $self->axfr_next, $rr && !$err) {
			push @zone, $rr;
		}
		@zone = () if $err;
	}

	return @zone;
}

sub axfr_old {
	croak "Use of Net::DNS::Resolver::axfr_old() is deprecated, use axfr() or axfr_start().";
}

sub axfr_start {
	my $self = shift;
	my ($dname, $class) = @_;
	$dname ||= $self->{'searchlist'}->[0];
	$class ||= 'IN';

	unless ($dname) {
		print ";; ERROR: axfr: no zone specified\n" if $self->{'debug'};
		$self->errorstring('no zone');
		return;
	}

	print ";; axfr_start($dname, $class)\n" if $self->{'debug'};

	unless (@{$self->{'nameservers'}}) {
		$self->errorstring('no nameservers');
		print ";; ERROR: no nameservers\n" if $self->{'debug'};
		return;
	}

	my $packet = $self->make_query_packet($dname, 'AXFR', $class);
	my $packet_data = $packet->data;

	my $ns = $self->{'nameservers'}->[0];

	print ";; axfr_start nameserver = $ns\n" if $self->{'debug'};

	my $srcport = $self->{'srcport'};

	my $sock;
	my $sock_key = "$ns:$self->{'port'}";

	if ($self->{'persistent_tcp'} && $self->{'sockets'}->{$sock_key}) {
	    $sock = $self->{'sockets'}->{$sock_key};
	    print ";; using persistent socket\n" if $self->{'debug'};
	    
	} else {

		# IO::Socket carps on errors if Perl's -w flag is turned on.
		# Uncomment the next two lines and the line following the "new"
		# call to turn off these messages.

		#my $old_wflag = $^W;
		#$^W = 0;

		$sock = IO::Socket::INET->new(
		    PeerAddr  => $ns,
		    PeerPort  => $self->{'port'},
		    LocalAddr => $self->{'srcaddr'},
		    LocalPort => ($srcport || undef),
		    Proto     => 'tcp',
		    Timeout   => $self->{'tcp_timeout'}
		 );

		#$^W = $old_wflag;

		unless ($sock) {
			$self->errorstring(q|couldn't connect|);
			return;
		}

		$self->{'sockets'}->{$sock_key} = $sock;
	}

	my $lenmsg = pack('n', length($packet_data));

	unless ($sock->send($lenmsg)) {
		$self->errorstring($!);
		return;
	}

	unless ($sock->send($packet_data)) {
		$self->errorstring($!);
		return;
	}

	my $sel = Net::DNS::Select->new($sock);

	$self->{'axfr_sel'}       = $sel;
	$self->{'axfr_rr'}        = [];
	$self->{'axfr_soa_count'} = 0;

	return $sock;
}


sub axfr_next {
	my $self = shift;
	my $err  = '';
	
	unless (@{$self->{'axfr_rr'}}) {
		unless ($self->{'axfr_sel'}) {
			my $err = 'no zone transfer in progress';
			
			print ";; $err\n" if $self->{'debug'};
			$self->errorstring($err);
					
			return wantarray ? (undef, $err) : undef;
		}

		my $sel = $self->{'axfr_sel'};
		my $timeout = $self->{'tcp_timeout'};

		#--------------------------------------------------------------
		# Read the length of the response packet.
		#--------------------------------------------------------------

		my @ready = $sel->can_read($timeout);
		unless (@ready) {
			$err = 'timeout';
			$self->errorstring($err);
			return wantarray ? (undef, $err) : undef;
		}

		my $buf = read_tcp($ready[0], &Net::DNS::INT16SZ, $self->{'debug'});
		unless (length $buf) {
			$err = 'truncated zone transfer';
			$self->errorstring($err);
			return wantarray ? (undef, $err) : undef;
		}

		my ($len) = unpack('n', $buf);
		unless ($len) {
			$err = 'truncated zone transfer';
			$self->errorstring($err);
			return wantarray ? (undef, $err) : undef;
		}

		#--------------------------------------------------------------
		# Read the response packet.
		#--------------------------------------------------------------

		@ready = $sel->can_read($timeout);
		unless (@ready) {
			$err = 'timeout';
			$self->errorstring($err);
			return wantarray ? (undef, $err) : undef;
		}

		$buf = read_tcp($ready[0], $len, $self->{'debug'});

		print ';; received ', length($buf), " bytes\n"
			if $self->{'debug'};

		unless (length($buf) == $len) {
			$err = "expected $len bytes, received " . length($buf);
			$self->errorstring($err);
			print ";; $err\n" if $self->{'debug'};
			return wantarray ? (undef, $err) : undef;
		}

		my $ans;
		($ans, $err) = Net::DNS::Packet->new(\$buf, $self->{'debug'});

		if ($ans) {
			if ($ans->header->rcode ne 'NOERROR') {	
				$self->errorstring('Response code from server: ' . $ans->header->rcode);
				print ';; Response code from server: ' . $ans->header->rcode . "\n" if $self->{'debug'};
				return wantarray ? (undef, $err) : undef;
			}
			if ($ans->header->ancount < 1) {
				$err = 'truncated zone transfer';
				$self->errorstring($err);
				print ";; $err\n" if $self->{'debug'};
				return wantarray ? (undef, $err) : undef;
			}
		}
		else {
			$err ||= 'unknown error during packet parsing';
			$self->errorstring($err);
			print ";; $err\n" if $self->{'debug'};
			return wantarray ? (undef, $err) : undef;
		}

		foreach my $rr ($ans->answer) {
			if ($rr->type eq 'SOA') {
				if (++$self->{'axfr_soa_count'} < 2) {
					push @{$self->{'axfr_rr'}}, $rr;
				}
			}
			else {
				push @{$self->{'axfr_rr'}}, $rr;
			}
		}

		if ($self->{'axfr_soa_count'} >= 2) {
			$self->{'axfr_sel'} = undef;
			# we need to mark the transfer as over if the responce was in 
			# many answers.  Otherwise, the user will call axfr_next again
			# and that will cause a 'no transfer in progress' error.
			push(@{$self->{'axfr_rr'}}, undef);
		}
	}

	my $rr = shift @{$self->{'axfr_rr'}};

	return wantarray ? ($rr, undef) : $rr;
}


sub tsig {
	my $self = shift;

	if (@_ == 1) {
		if ($_[0] && ref($_[0])) {
			$self->{'tsig_rr'} = $_[0];
		}
		else {
			$self->{'tsig_rr'} = undef;
		}
	}
	elsif (@_ == 2) {
		my ($key_name, $key) = @_;
		$self->{'tsig_rr'} = Net::DNS::RR->new("$key_name TSIG $key");
	}

	return $self->{'tsig_rr'};
}

#
# Usage:  $data = read_tcp($socket, $nbytes, $debug);
#
sub read_tcp {
	my ($sock, $nbytes, $debug) = @_;
	my $buf = '';

	while (length($buf) < $nbytes) {
		my $nread = $nbytes - length($buf);
		my $read_buf = '';

		print ";; read_tcp: expecting $nread bytes\n" if $debug;

		# During some of my tests recv() returned undef even
		# though there wasn't an error.  Checking for the amount
		# of data read appears to work around that problem.

		unless ($sock->recv($read_buf, $nread)) {
			if (length($read_buf) < 1) {
				my $errstr = $!;

				print ";; ERROR: read_tcp: recv failed: $!\n"
					if $debug;

				if ($errstr eq 'Resource temporarily unavailable') {
					warn "ERROR: read_tcp: recv failed: $errstr\n";
					warn "ERROR: try setting \$res->timeout(undef)\n";
				}

				last;
			}
		}

		print ';; read_tcp: received ', length($read_buf), " bytes\n"
			if $debug;

		last unless length($read_buf);
		$buf .= $read_buf;
	}

	return $buf;
}

sub AUTOLOAD {
	my ($self) = @_;

	my $name = $AUTOLOAD;
	$name =~ s/.*://;

	Carp::croak "$name: no such method" unless exists $self->{$name};
	
	no strict q/refs/;
	
	
	*{$AUTOLOAD} = sub {
		my ($self, $new_val) = @_;
		
		if (defined $new_val) {
			$self->{"$name"} = $new_val;
		}
		
		return $self->{"$name"};
	};

	
	goto &{$AUTOLOAD};	
}

1;

__END__

=head1 NAME

Net::DNS::Resolver::Base - Common Resolver Class

=head1 SYNOPSIS

 use base qw/Net::DNS::Resolver::Base/;

=head1 DESCRIPTION

This class is the common base class for the different platform
sub-classes of L<Net::DNS::Resolver|Net::DNS::Resolver>.  

No user serviceable parts inside, see L<Net::DNS::Resolver|Net::DNS::Resolver>
for all your resolving needs.

=head1 COPYRIGHT

Copyright (c) 1997-2002 Michael Fuhr. 

Portions Copyright (c) 2002-2003 Chris Reinhardt.

All rights reserved.  This program is free software; you may redistribute
it and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl(1)>, L<Net::DNS>, L<Net::DNS::Resolver>

=cut


