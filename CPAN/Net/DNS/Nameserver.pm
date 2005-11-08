package Net::DNS::Nameserver;
#
# $Id: Nameserver.pm 460 2005-07-15 19:18:22Z olaf $
#


BEGIN { 
    eval { require bytes; }
} 


use Net::DNS;
use IO::Socket;
use IO::Socket::INET;
use IO::Select;
use Carp qw(cluck);

use strict;
use vars qw($VERSION
 	    $has_inet6
 	    @DEFAULT_ADDR       
 	    $DEFAULT_PORT
 	    );

$VERSION = (qw$LastChangedRevision: 460 $)[1];

#@DEFAULT_ADDR is set in the BEGIN block 
$DEFAULT_PORT=53;
 	    
 
 
BEGIN {
    my $force_inet4_only=0;
    
    if ($force_inet4_only){
 	$has_inet6=0;
    }elsif ( eval {require Socket6;} &&
 	     # INET6 more recent than 2.01 will not work; sorry.
 	     eval {require IO::Socket::INET6; IO::Socket::INET6->VERSION("2.00");}) {
 	import Socket6;
 	$has_inet6=1;
 	no  strict 'subs';
 	@DEFAULT_ADDR= ( 0  );
    }else{
 	$has_inet6=0;
 	@DEFAULT_ADDR= ( INADDR_ANY );
    }
}


#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Constructor.
#------------------------------------------------------------------------------

sub new {
	my ($class, %self) = @_;


	if (!$self{"ReplyHandler"} || !ref($self{"ReplyHandler"})) {
		cluck "No reply handler!";
		return;
	}


 	my $addr;
 	my $port;
 	
 	# make sure we have an array.
 	$self{"LocalAddr"}= \@DEFAULT_ADDR unless defined $self{"LocalAddr"};
 	$self{"LocalAddr"}= [ $self{"LocalAddr"} ] unless (ref($self{"LocalAddr"})eq "ARRAY");
  
 	my @localaddresses = @{$self{"LocalAddr"}};
 	
  
  
 	my @sock_tcp;   # All the TCP sockets we will listen to.
 	my @sock_udp;   # All the UDP sockets we will listen to.
  
 	foreach my $localaddress (@localaddresses){
 	    print "Dealing with $localaddress...\n" if $self{"Verbose"};
  
 	    my $sock_tcp ;
  
 	    if ($has_inet6){
  
 		$addr = $localaddress;
 		$port = $self{"LocalPort"} || $DEFAULT_PORT;
  
  
 		#--------------------------------------------------------------------------
 		# Create the IPv4/IPv6 ONLY TCP socket.
 		#--------------------------------------------------------------------------
 		
 		print "creating TCP socket for $localaddress" if $self{"Verbose"};
 
 		$sock_tcp  = IO::Socket::INET6->new(
 						    LocalAddr => $addr,
 						    LocalPort => $port,
 						    Listen	  => 5,
 						    Proto	  => "tcp",
 						    Reuse	  => 1,
 						    );
 
 
 
 		if (! $sock_tcp) {
 		    cluck "couldn't create TCP socket: $!";
 		    return;
 		}
 		push @sock_tcp, $sock_tcp;
 		print "done.\n" if $self{"Verbose"};
 		
 		
 	    }else{
 		$addr = $localaddress || inet_ntoa($DEFAULT_ADDR[0]);
 		$port = $self{"LocalPort"} || $DEFAULT_PORT;
 
 		
 		#--------------------------------------------------------------------------
 		# Create the IPv4 ONLY TCP socket.
 		#--------------------------------------------------------------------------
 		
 		print "creating TCP socket for $localaddress" if $self{"Verbose"};
 
 
 		$sock_tcp  = IO::Socket::INET->new(
 						   LocalAddr => $addr,
 						   LocalPort => $port,
 						   Listen	  => 5,
 						   Proto	  => "tcp",
 						   Reuse	  => 1,
 						   );
 		
 		
 		if (! $sock_tcp) {
 		    cluck "couldn't create TCP socket: $!";
 		    return;
 		}
 		push @sock_tcp, $sock_tcp;
 		print "done.\n" if $self{"Verbose"};
 		
  
  
 	    }
 	    
 	    
 	    
 	    #--------------------------------------------------------------------------
 	    # Create the UDP Socket.
 	    #--------------------------------------------------------------------------
 	    
 	    print "creating UDP socket..." if $self{"Verbose"};
 	    
 	    my $sock_udp;
 	    if ($has_inet6){
 		$sock_udp = IO::Socket::INET6->new(
 						   LocalAddr => $addr,
 						   LocalPort => $port,
 						   Proto => "udp",
 						   );
 		
 	    }else{
 		$sock_udp = IO::Socket::INET->new(
 						  LocalAddr => $addr,
 						  LocalPort => $port,
 						  Proto => "udp",
 						  );
 	    }
 	    if (!$sock_udp) {
 		cluck "couldn't create UDP socket: $!";
 		return;
 	    }
 	    

 	    print "done.\n" if $self{"Verbose"};
 	    push @sock_udp, $sock_udp;
 	}
 	
  	#--------------------------------------------------------------------------
  	# Create the Select object.
  	#--------------------------------------------------------------------------
  
  	$self{"select"} = IO::Select->new;
 
 	foreach my $sock_tcp  (@sock_tcp){
 	    $self{"select"}->add($sock_tcp);
 	}
 
 	foreach my $sock_udp  (@sock_udp){
 	    $self{"select"}->add($sock_udp);
 	}
  
	#--------------------------------------------------------------------------
	# Return the object.
	#--------------------------------------------------------------------------

	my $self = bless \%self, $class;
	return $self;
}

#------------------------------------------------------------------------------
# make_reply - Make a reply packet.
#------------------------------------------------------------------------------

sub make_reply {
	my ($self, $query, $peerhost) = @_;
	
	my $reply;
	my $headermask;
	
	if (not $query) {
		print "ERROR: invalid packet\n" if $self->{"Verbose"};
		$reply = Net::DNS::Packet->new("", "ANY", "ANY");
		$reply->header->rcode("FORMERR");
		
		return $reply;
	}
	
	if ($query->header->qr()) {
		print "ERROR: invalid packet (qr was set, dropping)\n" if $self->{"Verbose"};
		return;
	}

	
	my $qr = ($query->question)[0];
	
	my $qname  = $qr ? $qr->qname  : "";
	my $qclass = $qr ? $qr->qclass : "ANY";
	my $qtype  = $qr ? $qr->qtype  : "ANY";
	
	$reply = Net::DNS::Packet->new($qname, $qtype, $qclass);
	
	if ($query->header->opcode eq "QUERY") {
		if ($query->header->qdcount == 1) {
			print "query ", $query->header->id,
			": ($qname, $qclass, $qtype)..." if $self->{"Verbose"};
			
			my ($rcode, $ans, $auth, $add);
			
			($rcode, $ans, $auth, $add, $headermask) =
				&{$self->{"ReplyHandler"}}($qname, $qclass, $qtype, $peerhost, $query);
			
			print "$rcode\n" if $self->{"Verbose"};
			
			$reply->header->rcode($rcode);
			
			$reply->push("answer",	   @$ans)  if $ans;
			$reply->push("authority",  @$auth) if $auth;
			$reply->push("additional", @$add)  if $add;
		} else {
			print "ERROR: qdcount ", $query->header->qdcount,
				"unsupported\n" if $self->{"Verbose"};
			$reply->header->rcode("FORMERR");
		}
	} else {
		print "ERROR: opcode ", $query->header->opcode, " unsupported\n"
			if $self->{"Verbose"};
		$reply->header->rcode("FORMERR");
	}

	
	
	if (!defined ($headermask)) {
		$reply->header->ra(1);
		$reply->header->ad(0);
	} else {
		$reply->header->aa(1) if $headermask->{'aa'};
		$reply->header->ra(1) if $headermask->{'ra'};
		$reply->header->ad(1) if $headermask->{'ad'};
	}
	
	
	$reply->header->qr(1);
	$reply->header->cd($query->header->cd);
	$reply->header->rd($query->header->rd);	
	$reply->header->id($query->header->id);
	
	
	$reply->header->print if $self->{"Verbose"} && defined $headermask;
	
	return $reply;
}

#------------------------------------------------------------------------------
# tcp_connection - Handle a TCP connection.
#------------------------------------------------------------------------------

sub tcp_connection {
	my ($self, $sock) = @_;
	my $peerhost = $sock->peerhost;

	print "TCP connection from ", $sock->peerhost, ":", $sock->peerport, "\n"
	  if $self->{"Verbose"};
		
	while (1) {
		my $buf;
		print "reading message length..." if $self->{"Verbose"};
		$sock->read($buf, 2) or last;
		print "done\n" if $self->{"Verbose"};

		my ($msglen) = unpack("n", $buf);
		print "expecting $msglen bytes..." if $self->{"Verbose"};
		$sock->read($buf, $msglen);
		print "got ", length($buf), " bytes\n" if $self->{"Verbose"};

		my $query = Net::DNS::Packet->new(\$buf);
		
		my $reply = $self->make_reply($query, $peerhost) || last;
		my $reply_data = $reply->data;

		print "writing response..." if $self->{"Verbose"};
		$sock->write(pack("n", length($reply_data)) . $reply_data);
		print "done\n" if $self->{"Verbose"};
	}

	print "closing connection..." if $self->{"Verbose"};
	$sock->close;
	print "done\n" if $self->{"Verbose"};
}

#------------------------------------------------------------------------------
# udp_connection - Handle a UDP connection.
#------------------------------------------------------------------------------

sub udp_connection {
	my ($self, $sock) = @_;

	my $buf = "";

 	my ($peerhost,$peerport);
 
 	$sock->recv($buf, &Net::DNS::PACKETSZ);
 
 	print "UDP connection from ", $sock->peerhost, ":", $sock->peerport, "\n"
 	  if $self->{"Verbose"};

	print "UDP connection from $peerhost:$peerport\n" if $self->{"Verbose"};

	my $query = Net::DNS::Packet->new(\$buf);

	my $reply = $self->make_reply($query, $peerhost) || return;
	my $reply_data = $reply->data;

	print "writing response..." if $self->{"Verbose"};
	$sock->send($reply_data) or die "send: $!";
	print "done\n" if $self->{"Verbose"};
}

#------------------------------------------------------------------------------
# main_loop - Main nameserver loop.
#------------------------------------------------------------------------------

sub main_loop {
	my $self = shift;

	local $| = 1;

	while (1) {
		print "waiting for connections..." if $self->{"Verbose"};
		my @ready = $self->{"select"}->can_read;
	
		foreach my $sock (@ready) {
			my $proto = getprotobynumber($sock->protocol);
	
			if (!$proto) {
				print "ERROR: connection with unknown protocol\n"
					if $self->{"Verbose"};
			} elsif (lc($proto) eq "tcp") {
				my $client = $sock->accept;
				$self->tcp_connection($client);
			} elsif (lc($proto) eq "udp") {
				$self->udp_connection($sock);
			} else {
				print "ERROR: connection with unsupported protocol $proto\n"
					if $self->{"Verbose"};
			}
		}
	}
}

1;

__END__

=head1 NAME

Net::DNS::Nameserver - DNS server class

=head1 SYNOPSIS

C<use Net::DNS::Nameserver;>

=head1 DESCRIPTION

Instances of the C<Net::DNS::Nameserver> class represent simple DNS server
objects.  See L</EXAMPLE> for an example.

=head1 METHODS

=head2 new

 my $ns = Net::DNS::Nameserver->new(
	LocalAddr	 => "10.1.2.3",
	LocalPort	 => "5353",
	ReplyHandler => \&reply_handler,
	Verbose		 => 1
 );



 my $ns = Net::DNS::Nameserver->new(
	LocalAddr	 => ['::1' , '127.0.0.1' ],
	LocalPort	 => "5353",
	ReplyHandler => \&reply_handler,
	Verbose		 => 1
 );

Creates a nameserver object.  Attributes are:

  LocalAddr		IP address on which to listen.	Defaults to INADDR_ANY.
  LocalPort		Port on which to listen.  	Defaults to 53.
  ReplyHandler		Reference to reply-handling 
			subroutine			Required.
  Verbose		Print info about received 
			queries.			Defaults to 0 (off).


The LocalAddr attribute may alternatively be specified as a list of IP
addresses to liten to. 

If IO::Socket::INET6 and Socket6 are available on the system you can
also list IPv6 addresses and the default is '0' (listen on all interfaces on
IPv6 and IPv4);


The ReplyHandler subroutine is passed the query name, query class,
query type and optionally an argument containing header bit settings
(see below).  It must return the response code and references to the
answer, authority, and additional sections of the response.  Common
response codes are:

  NOERROR	No error
  FORMERR	Format error
  SERVFAIL	Server failure
  NXDOMAIN	Non-existent domain (name doesn't exist)
  NOTIMP	Not implemented
  REFUSED	Query refused

For advanced usage there is an optional argument containing an
hashref with the settings for the C<aa>, C<ra>, and C<ad> 
header bits. The argument is of the form 
C<< { ad => 1, aa => 0, ra => 1 } >>. 


See RFC 1035 and the IANA dns-parameters file for more information:

  ftp://ftp.rfc-editor.org/in-notes/rfc1035.txt
  http://www.isi.edu/in-notes/iana/assignments/dns-parameters

The nameserver will listen for both UDP and TCP connections.  On
Unix-like systems, the program will probably have to run as root
to listen on the default port, 53.	A non-privileged user should
be able to listen on ports 1024 and higher.

Returns a Net::DNS::Nameserver object, or undef if the object
couldn't be created.

See L</EXAMPLE> for an example.	 

=head2 main_loop

	$ns->main_loop;

Start accepting queries.

=head1 EXAMPLE

The following example will listen on port 5353 and respond to all queries
for A records with the IP address 10.1.2.3.	 All other queries will be
answered with NXDOMAIN.	 Authority and additional sections are left empty.
The $peerhost variable catches the IP address of the peer host, so that
additional filtering on its basis may be applied.

 #!/usr/bin/perl 
 
 use Net::DNS;
 use strict;
 use warnings;
 
 sub reply_handler {
	 my ($qname, $qclass, $qtype, $peerhost) = @_;
	 my ($rcode, @ans, @auth, @add);
	 
	 if ($qtype eq "A") {
		 my ($ttl, $rdata) = (3600, "10.1.2.3");
		 push @ans, Net::DNS::RR->new("$qname $ttl $qclass $qtype $rdata");
		 $rcode = "NOERROR";
	 } else {
         $rcode = "NXDOMAIN";
	 }
	 
	 # mark the answer as authoritive (by setting the 'aa' flag
	 return ($rcode, \@ans, \@auth, \@add, { aa => 1 });
 }
 
 my $ns = Net::DNS::Nameserver->new(
     LocalPort    => 5353,
     ReplyHandler => \&reply_handler,
     Verbose      => 1,
 ) || die "couldn't create nameserver object\n";
 
 $ns->main_loop;
 
=head1 BUGS

Net::DNS::Nameserver objects can handle only one query at a time.

Limitations in perl 5.8.6 makes it impossible to guarantee that
replies to UDP queries from Net::DNS::Nameserver are sent from the
IP-address they were received on. This is a problem for machines with
multiple IP-addresses and causes violation of RFC2181 section 4.


=head1 COPYRIGHT

Copyright (c) 1997-2002 Michael Fuhr. 

Portions Copyright (c) 2002-2004 Chris Reinhardt.

Portions Copyright (c) 2005 O.M, Kolkman, RIPE NCC.
 


All rights reserved.  This program is free software; you may redistribute
it and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl(1)>, L<Net::DNS>, L<Net::DNS::Resolver>, L<Net::DNS::Packet>,
L<Net::DNS::Update>, L<Net::DNS::Header>, L<Net::DNS::Question>,
L<Net::DNS::RR>, RFC 1035

=cut

