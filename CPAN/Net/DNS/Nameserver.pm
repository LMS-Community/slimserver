package Net::DNS::Nameserver;
#
# $Id$
#

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

use constant	STATE_ACCEPTED => 1;
use constant	STATE_GOT_LENGTH => 2;
use constant	STATE_SENDING => 3;
use Net::IP qw(ip_is_ipv4 ip_is_ipv6 ip_normalize); 

$VERSION = (qw$LastChangedRevision: 535 $)[1];

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

	# while we are here, print incomplete lines as they come along.
	local $| = 1 if $self{"Verbose"};

 	foreach my $localaddress (@localaddresses){
  
 	    $port = $self{"LocalPort"} || $DEFAULT_PORT;

 	    if ($has_inet6){
 		$addr = $localaddress;
	    }else{
 		$addr = $localaddress || inet_ntoa($DEFAULT_ADDR[0]);
	    }

	    # If not, it will do DNS lookups trying to resolve it as a hostname
	    # We could also just set it to undef?

	    $addr = inet_ntoa($addr) unless (ip_is_ipv4($addr) || ip_is_ipv6($addr));

	    # Pretty IP-addresses, if they are otherwise binary.
	    my $addrname = $addr;
	    $addrname = inet_ntoa($addrname) unless $addrname =~ /^[\w\.:\-]+$/;

 	    print "Setting up listening sockets for $addrname...\n" if $self{"Verbose"};

 	    print "Creating TCP socket for $addrname - " if $self{"Verbose"};
  
 	    #--------------------------------------------------------------------------
 	    # Create the TCP socket.
 	    #--------------------------------------------------------------------------
 		
	    my $sock_tcp = inet_new(
 						    LocalAddr => $addr,
 						    LocalPort => $port,
 						    Listen	  => 64,
 						    Proto	  => "tcp",
 						    Reuse	  => 1,
 						    );
 	    if (! $sock_tcp) {
 	        cluck "Couldn't create TCP socket: $!";
 	        return;
 	    }
 	    push @sock_tcp, $sock_tcp;
 	    print "done.\n" if $self{"Verbose"};
 	    
 	    #--------------------------------------------------------------------------
 	    # Create the UDP Socket.
 	    #--------------------------------------------------------------------------
 	    
 	    print "Creating UDP socket for $addrname - " if $self{"Verbose"};
 	    
 	    my $sock_udp = inet_new(
 						   LocalAddr => $addr,
 						   LocalPort => $port,
 						   Proto => "udp",
 						   );
 		
 	    if (!$sock_udp) {
 		cluck "Couldn't create UDP socket: $!";
 		return;
 	    }
 	    push @sock_udp, $sock_udp;
 	    print "done.\n" if $self{"Verbose"};
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
# inet_new - Calls the constructor in the correct module for making sockets.
#------------------------------------------------------------------------------

sub inet_new {
	if ($has_inet6) {
	    return IO::Socket::INET6->new(@_);
	} else {
	    return IO::Socket::INET->new(@_);
	}
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
			": ($qname, $qclass, $qtype) - " if $self->{"Verbose"};
			
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
# readfromtcp - read from a TCP client
#------------------------------------------------------------------------------

sub readfromtcp {
  	my ($self, $sock) = @_;
	return -1 unless defined $self->{"_tcp"}{$sock};
	my $peer = $self->{"_tcp"}{$sock}{"peer"};
	my $charsread = $sock->sysread(
	    $self->{"_tcp"}{$sock}{"inbuffer"}, 
	    16384);
	$self->{"_tcp"}{$sock}{"timeout"} = time()+120; # Reset idle timer
	print "Received $charsread octets from $peer\n" if $self->{"Verbose"};
	if ($charsread == 0) { # 0 octets means socket has closed
	  print "Connection to $peer closed or lost.\n" if $self->{"Verbose"};
	  $self->{"select"}->remove($sock);
	  $sock->close();
	  delete $self->{"_tcp"}{$sock};
	  return $charsread;
	}
	return $charsread;
}

#------------------------------------------------------------------------------
# tcp_connection - Handle a TCP connection.
#------------------------------------------------------------------------------

sub tcp_connection {
	my ($self, $sock) = @_;
	
	if (not $self->{"_tcp"}{$sock}) {
		# We go here if we are called with a listener socket.
		my $client = $sock->accept;
		if (not defined $client) {
	  		print "TCP connection closed by peer before we could accept it.\n" if $self->{"Verbose"};
	  		return 0;
		}
		my $peerport= $client->peerport;
		my $peerhost = $client->peerhost;

		print "TCP connection from $peerhost:$peerport\n" if $self->{"Verbose"};
		$client->blocking(0);
		$self->{"_tcp"}{$client}{"peer"} = "tcp:".$peerhost.":".$peerport;
		$self->{"_tcp"}{$client}{"state"} = STATE_ACCEPTED;
		$self->{"_tcp"}{$client}{"socket"} = $client;
		$self->{"_tcp"}{$client}{"timeout"} = time()+120;
 		$self->{"select"}->add($client);
		# After we accepted we will look at the socket again 
		# to see if there is any data there. ---Olaf
		$self->loop_once(0);
	} else {
		# We go here if we are called with a client socket
		my $peer = $self->{"_tcp"}{$sock}{"peer"};

		if ($self->{"_tcp"}{$sock}{"state"} == STATE_ACCEPTED) {
		  if (not $self->{"_tcp"}{$sock}{"inbuffer"} =~ s/^(..)//s) {
		    return; # Still not 2 octets ready
		  }
		  my $msglen = unpack("n", $1);
		  print "Removed 2 octets from the input buffer from $peer.\n".
		  	"$peer said his query contains $msglen octets.\n"
		  	if $self->{"Verbose"};
		  $self->{"_tcp"}{$sock}{"state"} = STATE_GOT_LENGTH;
		  $self->{"_tcp"}{$sock}{"querylength"} = $msglen;
		}
		# Not elsif, because we might already have all the data
		if ($self->{"_tcp"}{$sock}{"state"} == STATE_GOT_LENGTH) {
			# return if not all data has been received yet.
		  	return if $self->{"_tcp"}{$sock}{"querylength"} > length $self->{"_tcp"}{$sock}{"inbuffer"};

			my $qbuf = substr($self->{"_tcp"}{$sock}{"inbuffer"}, 0, $self->{"_tcp"}{$sock}{"querylength"});
			substr($self->{"_tcp"}{$sock}{"inbuffer"}, 0, $self->{"_tcp"}{$sock}{"querylength"}) = "";
		  	my $query = Net::DNS::Packet->new(\$qbuf);
		  	my $reply = $self->make_reply($query, $sock->peerhost);
		  	if (not defined $reply) {
		    		print "I couldn't create a reply for $peer. Closing socket.\n"
		    			if $self->{"Verbose"};
				$self->{"select"}->remove($sock);
				$sock->close();
				delete $self->{"_tcp"}{$sock};
				return;
		  	}
		  	my $reply_data = $reply->data;
			my $len = length $reply_data;
			$self->{"_tcp"}{$sock}{"outbuffer"} = pack("n", $len) . $reply_data;
			print "Queued ",
				length $self->{"_tcp"}{$sock}{"outbuffer"},
				" octets to $peer\n"
				if $self->{"Verbose"};
			# We are done.
		  	$self->{"_tcp"}{$sock}{"state"} = STATE_SENDING;
		}
	}
}

#------------------------------------------------------------------------------
# udp_connection - Handle a UDP connection.
#------------------------------------------------------------------------------

sub udp_connection {
	my ($self, $sock) = @_;

	my $buf = "";

 	$sock->recv($buf, &Net::DNS::PACKETSZ);
 	my ($peerhost,$peerport) = ($sock->peerhost, $sock->peerport);
 
 	print "UDP connection from $peerhost:$peerport\n" if $self->{"Verbose"};

	my $query = Net::DNS::Packet->new(\$buf);

	my $reply = $self->make_reply($query, $peerhost) || return;
	my $reply_data = $reply->data;

	local $| = 1 if $self->{"Verbose"};
	print "Writing response - " if $self->{"Verbose"};
	# die() ?!??  I think we need something better. --robert
	$sock->send($reply_data) or die "send: $!";
	print "done\n" if $self->{"Verbose"};
}


sub get_open_tcp {
    my $self=shift;
    return keys %{$self->{"_tcp"}};
}


#------------------------------------------------------------------------------
# loop_once - Just check "once" on sockets already set up
#------------------------------------------------------------------------------

# This function might not actually return immediately. If an AXFR request is
# coming in which will generate a huge reply, we will not relinquish control
# until our outbuffers are empty.

#
#  NB  this method may be subject to change and is therefore left 'undocumented'
#

sub loop_once {
  my ($self, $timeout) = @_;
  $timeout=0 unless defined($timeout);
  print ";loop_once called with $timeout \n" if $self->{"Verbose"} >4;
  foreach my $sock (keys %{$self->{"_tcp"}}) {
      $timeout = 0.1 if $self->{"_tcp"}{$sock}{"outbuffer"};
  }
  my @ready = $self->{"select"}->can_read($timeout);
  
  foreach my $sock (@ready) {
      my $protonum = $sock->protocol;
      # This is a weird and nasty hack. Although not incorrect,
      # I just don't know why ->protocol won't tell me the protocol
      # on a connected socket. --robert
      $protonum = getprotobyname('tcp') if not defined $protonum and $self->{"_tcp"}{$sock};
      
      my $proto = getprotobynumber($protonum);
      if (!$proto) {
	  print "ERROR: connection with unknown protocol\n"
	      if $self->{"Verbose"};
      } elsif (lc($proto) eq "tcp") {
	  
	  $self->readfromtcp($sock) &&
	      $self->tcp_connection($sock);
      } elsif (lc($proto) eq "udp") {
	  $self->udp_connection($sock);
      } else {
	  print "ERROR: connection with unsupported protocol $proto\n"
	      if $self->{"Verbose"};
      }
  }
  my $now = time();
  # Lets check if any of our TCP clients has pending actions.
  # (outbuffer, timeout)
  foreach my $s (keys %{$self->{"_tcp"}}) {
      my $sock = $self->{"_tcp"}{$s}{"socket"};
      if ($self->{"_tcp"}{$s}{"outbuffer"}) {
	  # If we have buffered output, then send as much as the OS will accept
	  # and wait with the rest
	  my $len = length $self->{"_tcp"}{$s}{"outbuffer"};
	  my $charssent = $sock->syswrite($self->{"_tcp"}{$s}{"outbuffer"});
	  print "Sent $charssent of $len octets to ",$self->{"_tcp"}{$s}{"peer"},".\n"
	      if $self->{"Verbose"};
	  substr($self->{"_tcp"}{$s}{"outbuffer"}, 0, $charssent) = "";
	  if (length $self->{"_tcp"}{$s}{"outbuffer"} == 0) {
	      delete $self->{"_tcp"}{$s}{"outbuffer"};
	      $self->{"_tcp"}{$s}{"state"} = STATE_ACCEPTED;
	      if (length $self->{"_tcp"}{$s}{"inbuffer"} >= 2) {
		  # See if the client has send us enough data to process the
		  # next query.
		  # We do this here, because we only want to process (and buffer!!)
		  # a single query at a time, per client. If we allowed a STATE_SENDING
		  # client to have new requests processed. We could be easilier
		  # victims of DoS (client sending lots of queries and never reading
		  # from it's socket).
		  # Note that this does not disable serialisation on part of the
		  # client. The split second it should take for us to lookip the
		  # next query, is likely faster than the time it takes to
		  # send the response... well, unless it's a lot of tiny queries,
		  # in which case we will be generating an entire TCP packet per
		  # reply. --robert
		  $self->tcp_connection($self->{"_tcp"}{"socket"});
	      }
	  }
	  $self->{"_tcp"}{$s}{"timeout"} = time()+120;
      } else {
	  # Get rid of idle clients.
	  my $timeout = $self->{"_tcp"}{$s}{"timeout"};
	  if ($timeout - $now < 0) {
	      print $self->{"_tcp"}{$s}{"peer"}," has been idle for too long and will be disconnected.\n"
		  if $self->{"Verbose"};
	      $self->{"select"}->remove($sock);
	      $sock->close();
	      delete $self->{"_tcp"}{$s};
	  }
      }
  }
}

#------------------------------------------------------------------------------
# main_loop - Main nameserver loop.
#------------------------------------------------------------------------------

sub main_loop {
    my $self = shift;
    
    while (1) {
	print "Waiting for connections...\n" if $self->{"Verbose"};
	# You really need an argument otherwise you'll be burning
	# CPU.
	$self->loop_once(10);
    }
}

1;

__END__

=head1 NAME

Net::DNS::Nameserver - DNS server class

=head1 SYNOPSIS

C<use Net::DNS::Nameserver;>

=head1 DESCRIPTION

Instances of the C<Net::DNS::Nameserver> class represent DNS server
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
addresses to listen to. 

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

Start accepting queries. Calling main_loop never returns.

=cut

#####
#
#  The functionality might change. Left "undocumented" for now.
#
=head2 loop_once

	$ns->loop_once( [TIMEOUT_IN_SECONDS] );

Start accepting queries, but returns. If called without a parameter,
the call will not return until a request has been received (and
replied to). If called with a number, that number specifies how many
seconds (even fractional) to maximum wait before returning. If called
with 0 it will return immediately unless there's something to do.

Handling a request and replying obviously depends on the speed of
ReplyHandler. Assuming ReplyHandler is super fast, loop_once should spend
just a fraction of a second, if called with a timeout value of 0 seconds.
One exception is when an AXFR has requested a huge amount of data that
the OS is not ready to receive in full. In that case, it will keep
running through a loop (while servicing new requests) until the reply
has been sent.

In case loop_once accepted a TCP connection it will immediatly check
if there is data to be read from the socket. If not it will return and
you will have to call loop_once() again to check if there is any data
waiting on the socket to be processed. In most cases you will have to
count on calling "loop_once" twice.

A code fragment like:
	$ns->loop_once(10);
        while( $ns->get_open_tcp() ){
	      $ns->loop_once(0);
	}

Would wait for 10 seconds for the initial connection and would then
process all TCP sockets until none is left. 

=head2 get_open_tcp

In scalar context returns the number of TCP connections for which state
is maintained. In array context it returns IO::Socket objects, these could
be useful for troubleshooting but be careful using them.

=head1 EXAMPLE

The following example will listen on port 5353 and respond to all queries
for A records with the IP address 10.1.2.3.	 All other queries will be
answered with NXDOMAIN.	 Authority and additional sections are left empty.
The $peerhost variable catches the IP address of the peer host, so that
additional filtering on its basis may be applied.

 #!/usr/bin/perl 
 
 use Net::DNS::Nameserver;
 use strict;
 use warnings;
 
 sub reply_handler {
	 my ($qname, $qclass, $qtype, $peerhost) = @_;
	 my ($rcode, @ans, @auth, @add);
	 
	 if ($qtype eq "A" && qname eq "foo.example.com" ) {
		 my ($ttl, $rdata) = (3600, "10.1.2.3");
		 push @ans, Net::DNS::RR->new("$qname $ttl $qclass $qtype $rdata");
		 $rcode = "NOERROR";
	 }elsif( qname eq "foo.example.com" ) {
		 $rcode = "NOERROR";

	 }else{
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

Limitations in perl 5.8.6 makes it impossible to guarantee that
replies to UDP queries from Net::DNS::Nameserver are sent from the
IP-address they were received on. This is a problem for machines with
multiple IP-addresses and causes violation of RFC2181 section 4.
Thus a UDP socket created listening to INADDR_ANY (all available
IP-addresses) will reply not necessarily with the source address being
the one to which the request was sent, but rather with the address that
the operating system choses. This is also often called "the closest
address". This should really only be a problem on a server which has
more than one IP-address (besides localhost - any experience with IPv6
complications here, would be nice). If this is a problem for you, a
work-around would be to not listen to INADDR_ANY but to specify each
address that you want this module to listen on. A seperate set of
sockets will then be created for each IP-address.

=head1 COPYRIGHT

Copyright (c) 1997-2002 Michael Fuhr. 

Portions Copyright (c) 2002-2004 Chris Reinhardt.

Portions Copyright (c) 2005 O.M, Kolkman, RIPE NCC.
 
Portions Copyright (c) 2005 Robert Martin-Legene.

All rights reserved.  This program is free software; you may redistribute
it and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl(1)>, L<Net::DNS>, L<Net::DNS::Resolver>, L<Net::DNS::Packet>,
L<Net::DNS::Update>, L<Net::DNS::Header>, L<Net::DNS::Question>,
L<Net::DNS::RR>, RFC 1035

=cut
