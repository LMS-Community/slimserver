package Net::DNS::Packet;
#
# $Id$
#
use strict;

BEGIN { 
    eval { require bytes; }
}

use vars qw(@ISA @EXPORT_OK $VERSION $AUTOLOAD);

use Carp;
use Net::DNS ;
use Net::DNS::Question;
use Net::DNS::RR;



require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(dn_expand);


$VERSION = (qw$LastChangedRevision: 546 $)[1];



=head1 NAME

Net::DNS::Packet - DNS packet object class

=head1 SYNOPSIS

C<use Net::DNS::Packet;>

=head1 DESCRIPTION

A C<Net::DNS::Packet> object represents a DNS packet.

=head1 METHODS

=head2 new

    $packet = Net::DNS::Packet->new("example.com");
    $packet = Net::DNS::Packet->new("example.com", "MX", "IN");

    $packet = Net::DNS::Packet->new(\$data);
    $packet = Net::DNS::Packet->new(\$data, 1);  # set debugging

    ($packet, $err) = Net::DNS::Packet->new(\$data);

If passed a domain, type, and class, C<new> creates a packet
object appropriate for making a DNS query for the requested
information.  The type and class can be omitted; they default
to A and IN.

If passed a reference to a scalar containing DNS packet data,
C<new> creates a packet object from that data.  A second argument
can be passed to turn on debugging output for packet parsing.

If called in array context, returns a packet object and an
error string.  The error string will only be defined if the
packet object is undefined (i.e., couldn't be created).

Returns B<undef> if unable to create a packet object (e.g., if
the packet data is truncated).'

=cut

sub new {
	my $class = shift;
	my %self;

	$self{"compnames"} = {};

  PARSE: {
	if (ref($_[0])) {
		my $data  = shift;
		my $debug = shift || 0;

		#--------------------------------------------------------------
		# Parse the header section.
		#--------------------------------------------------------------

		print ";; HEADER SECTION\n" if $debug;


		$self{"header"} = Net::DNS::Header->new($data);

		unless (defined $self{"header"}) {
			return wantarray
			       ? (undef, "header section incomplete")
			       : undef;
		}

		$self{"header"}->print if $debug;

		my $offset = Net::DNS::HFIXEDSZ();

		#--------------------------------------------------------------
		# Parse the question/zone section.
		#--------------------------------------------------------------

		if ($debug) {
			print "\n";
			my $section = ($self{"header"}->opcode eq "UPDATE")
			            ? "ZONE"
				    : "QUESTION";
			print ";; $section SECTION (",
			      $self{"header"}->qdcount, " record",
			      $self{"header"}->qdcount == 1 ? "" : "s",
			      ")\n";
		}

		$self{"question"} = [];
		foreach (1 .. $self{"header"}->qdcount) {
			my $qobj;
			($qobj, $offset) = parse_question($data, $offset);

			unless (defined $qobj) {
				last PARSE if $self{"header"}->tc;
				return wantarray
				       ? (undef, "question section incomplete")
				       : undef;
			}

			push(@{$self{"question"}}, $qobj);
			if ($debug) {
				print ";; ";
				$qobj->print;
			}
		}
			
		#--------------------------------------------------------------
		# Parse the answer/prerequisite section.
		#--------------------------------------------------------------

		if ($debug) {
			print "\n";
			my $section = ($self{"header"}->opcode eq "UPDATE")
				    ? "PREREQUISITE"
			            : "ANSWER";
			print ";; $section SECTION (",
			      $self{"header"}->ancount, " record",
			      $self{"header"}->ancount == 1 ? "" : "s",
			      ")\n";
		}

		$self{"answer"} = [];
		foreach (1 .. $self{"header"}->ancount) {
			my $rrobj;
			($rrobj, $offset) = parse_rr($data, $offset);

			unless (defined $rrobj) {
				last PARSE if $self{"header"}->tc;
				return wantarray
				       ? (undef, "answer section incomplete")
				       : undef;
			}
			
			push(@{$self{"answer"}}, $rrobj);
			$rrobj->print if $debug;
		}

		#--------------------------------------------------------------
		# Parse the authority/update section.
		#--------------------------------------------------------------

		if ($debug) {
			print "\n";
			my $section = ($self{"header"}->opcode eq "UPDATE")
			            ? "UPDATE"
				    : "AUTHORITY";
			print ";; $section SECTION (",
			      $self{"header"}->nscount, " record",
			      $self{"header"}->nscount == 1 ? "" : "s",
			      ")\n";
		}

		$self{"authority"} = [];
		foreach (1 .. $self{"header"}->nscount) {
			my $rrobj;
			($rrobj, $offset) = parse_rr($data, $offset);

			unless (defined $rrobj) {
				last PARSE if $self{"header"}->tc;
				return wantarray
				       ? (undef, "authority section incomplete")
				       : undef;
			}
			
			push(@{$self{"authority"}}, $rrobj);
			$rrobj->print if $debug;
		}

		#--------------------------------------------------------------
		# Parse the additional section.
		#--------------------------------------------------------------

		if ($debug) {
			print "\n";
			print ";; ADDITIONAL SECTION (",
			      $self{"header"}->adcount, " record",
			      $self{"header"}->adcount == 1 ? "" : "s",
			      ")\n";
		}

		$self{"additional"} = [];
		foreach (1 .. $self{"header"}->arcount) {
			my $rrobj;
			($rrobj, $offset) = parse_rr($data, $offset);

			unless (defined $rrobj) {
				last PARSE if $self{"header"}->tc;
				return wantarray
				       ? (undef, "additional section incomplete")
				       : undef;
			}

		
			push(@{$self{"additional"}}, $rrobj);
			$rrobj->print if $debug;
		}
	} else {
		my ($qname, $qtype, $qclass) = @_;

		$qtype  = "A"  unless defined $qtype;
		$qclass = "IN" unless defined $qclass;

		$self{"header"} = Net::DNS::Header->new;
		$self{"header"}->qdcount(1);
		$self{"question"} = [ Net::DNS::Question->new($qname,
							      $qtype,
							      $qclass) ];
		$self{"answer"}     = [];
		$self{"authority"}  = [];
		$self{"additional"} = [];
	}
	} # PARSE

	return wantarray
		? ((bless \%self, $class), undef)
		: bless \%self, $class;
}

=head2 data

    $data = $packet->data;

Returns the packet data in binary format, suitable for sending to
a nameserver.

=cut

sub data {
	my $self = shift;


	#----------------------------------------------------------------------
	# Flush the cache of already-compressed names.  This should fix the bug
	# that caused this method to work only the first time it was called.
	#----------------------------------------------------------------------

	$self->{"compnames"} = {};

	#----------------------------------------------------------------------
	# Get the data for each section in the packet.
	#----------------------------------------------------------------------
	# Note that EDNS OPT RR data should inly be appended to the additional
	# section of the packet. TODO: Packet is dropped silently if is tried to
	# have it appended to one of the other section

	# Collect the data first, and count the number of records along
	# the way. ( see rt.cpan.org: Ticket #8608 )
	my $qdcount = 0;
	my $ancount = 0;
	my $nscount = 0;
	my $arcount = 0;
	# Note that the only pieces we;ll fill in later have predefined
        # length.

	my $headerlength=length $self->{"header"}->data;

        my $data = $self->{"header"}->data;
	
	foreach my $question (@{$self->{"question"}}) {
		$data .= $question->data($self, length $data);
		$qdcount++;
	}

	foreach my $rr (@{$self->{"answer"}}) {
		$data .= $rr->data($self, length $data);
		$ancount++;
	}


	foreach my $rr (@{$self->{"authority"}}) {
		$data .= $rr->data($self, length $data);
		$nscount++;
	}


	foreach my $rr (@{$self->{"additional"}}) {
		$data .= $rr->data($self, length $data);
		$arcount++;
	}


	# Fix up the header so the counts are correct.  This overwrites
	# the user's settings, but the user should know what they aredoing.
	$self->{"header"}->qdcount( $qdcount );
	$self->{"header"}->ancount( $ancount );
	$self->{"header"}->nscount( $nscount );
	$self->{"header"}->arcount( $arcount );
	
	# Replace the orginal header with corrected counts.

	return $self->{"header"}->data . substr ($data,$headerlength);


}

=head2 header

    $header = $packet->header;

Returns a C<Net::DNS::Header> object representing the header section
of the packet.

=cut

sub header {
	my $self = shift;
	return $self->{"header"};
}

=head2 question, zone

    @question = $packet->question;

Returns a list of C<Net::DNS::Question> objects representing the
question section of the packet.

In dynamic update packets, this section is known as C<zone> and
specifies the zone to be updated.

=cut

sub question {
	my $self = shift;
	return @{$self->{"question"}};
}

sub zone {
	my $self = shift;
	$self->question(@_);
}

=head2 answer, pre, prerequisite

    @answer = $packet->answer;

Returns a list of C<Net::DNS::RR> objects representing the answer
section of the packet.

In dynamic update packets, this section is known as C<pre> or
C<prerequisite> and specifies the RRs or RRsets which must or
must not preexist.

=cut

sub answer { 
    if (exists($_[0]->{'answer'})) {
	return @{$_[0]->{'answer'}};
    } else {
	return ();
    } 
}
  

sub pre          { &answer }
sub prerequisite { &answer }

=head2 authority, update

    @authority = $packet->authority;

Returns a list of C<Net::DNS::RR> objects representing the authority
section of the packet.

In dynamic update packets, this section is known as C<update> and
specifies the RRs or RRsets to be added or delted.

=cut

sub authority { 
    if (exists($_[0]->{'authority'})) {
	return @{$_[0]->{'authority'}};
    } else {
	return ();
    } 
}

sub update    { &authority }

=head2 additional

    @additional = $packet->additional;

Returns a list of C<Net::DNS::RR> objects representing the additional
section of the packet.

=cut

sub additional { 
    if (exists($_[0]->{'additional'})) {
	return @{$_[0]->{'additional'}};
    } else {
	return ();
    } 
}


=head2 print

    $packet->print;

Prints the packet data on the standard output in an ASCII format
similar to that used in DNS zone files.

=cut

sub print { 
	print $_[0]->string;
}

=head2 string

    print $packet->string;

Returns a string representation of the packet.

=cut

sub string {
	my $self = shift;
	my ($qr, $rr, $section);
	my $retval = "";

	if (exists $self->{"answerfrom"}) {
		$retval .= ";; Answer received from $self->{answerfrom} " .
			   "($self->{answersize} bytes)\n;;\n";
	}

	$retval .= ";; HEADER SECTION\n";
	$retval .= $self->header->string;

	$retval .= "\n";
	$section = ($self->header->opcode eq "UPDATE") ? "ZONE" : "QUESTION";
	$retval .= ";; $section SECTION (" . $self->header->qdcount     . 
		   " record" . ($self->header->qdcount == 1 ? "" : "s") .
		   ")\n";
	foreach $qr ($self->question) {
		$retval .= ";; " . $qr->string . "\n";
	}

	$retval .= "\n";
	$section = ($self->header->opcode eq "UPDATE") ? "PREREQUISITE" : "ANSWER";
	$retval .= ";; $section SECTION (" . $self->header->ancount     .
		   " record" . ($self->header->ancount == 1 ? "" : "s") .
		   ")\n";
	foreach $rr ($self->answer) {
		$retval .= $rr->string . "\n";
	}

	$retval .= "\n";
	$section = ($self->header->opcode eq "UPDATE") ? "UPDATE" : "AUTHORITY";
	$retval .= ";; $section SECTION (" . $self->header->nscount     .
		  " record" . ($self->header->nscount == 1 ? "" : "s") .
		  ")\n";
	foreach $rr ($self->authority) {
		$retval .= $rr->string . "\n";
	}

	$retval .= "\n";
	$retval .= ";; ADDITIONAL SECTION (" . $self->header->arcount   .
		   " record" . ($self->header->arcount == 1 ? "" : "s") .
		   ")\n";
	foreach $rr ($self->additional) {
		$retval .= $rr->string . "\n";
	}

	return $retval;
}

=head2 answerfrom

    print "packet received from ", $packet->answerfrom, "\n";

Returns the IP address from which we received this packet.  User-created
packets will return undef for this method.

=cut

sub answerfrom {
	my $self = shift;

	$self->{"answerfrom"} = shift if @_;

	return exists $self->{"answerfrom"}
	       ? $self->{"answerfrom"}
	       : undef;
}

=head2 answersize

    print "packet size: ", $packet->answersize, " bytes\n";

Returns the size of the packet in bytes as it was received from a
nameserver.  User-created packets will return undef for this method
(use C<< length $packet->data >> instead).

=cut

sub answersize {
	my $self = shift;

	$self->{"answersize"} = shift if @_;

	return exists $self->{"answersize"}
	       ? $self->{"answersize"}
	       : undef;
}

=head2 push

    $packet->push(pre        => $rr);
    $packet->push(update     => $rr);
    $packet->push(additional => $rr);

    $packet->push(update => $rr1, $rr2, $rr3);
    $packet->push(update => @rr);

Adds RRs to the specified section of the packet.


=cut

sub push {
	my ($self, $section, @rr) = @_;
	my $rr;

	return unless $section;

	$section = lc $section;
	if (($section eq "prerequisite") || ($section eq "prereq")) {
		$section = "pre";
	}

	if (($self->{"header"}->opcode eq "UPDATE")
	 && (($section eq "pre") || ($section eq "update")) ) {
		my $zone_class = ($self->zone)[0]->zclass;
		foreach $rr (@rr) {
			unless ($rr->class eq "NONE" || $rr->class eq "ANY") {
				$rr->class($zone_class);
			}
		}
	}

	if ($section eq "answer" || $section eq "pre") {
		push(@{$self->{"answer"}}, @rr);
		my $ancount = $self->{"header"}->ancount;
		$self->{"header"}->ancount($ancount + @rr);
	} elsif ($section eq "authority" || $section eq "update") {
		push(@{$self->{"authority"}}, @rr);
		my $nscount = $self->{"header"}->nscount;
		$self->{"header"}->nscount($nscount + @rr);
	} elsif ($section eq "additional") {
		push(@{$self->{"additional"}}, @rr);
		my $adcount = $self->{"header"}->adcount;
		$self->{"header"}->adcount($adcount + @rr);
	} elsif ($section eq "question") {
		push(@{$self->{"question"}}, @rr);
		my $qdcount = $self->{"header"}->qdcount;
		$self->{"header"}->qdcount($qdcount + @rr);
	} else {
		Carp::carp(qq(invalid section "$section"\n));
		return;
	}
}

=head2 unique_push

    $packet->unique_push(pre        => $rr);
    $packet->unique_push(update     => $rr);
    $packet->unique_push(additional => $rr);

    $packet->unique_push(update => $rr1, $rr2, $rr3);
    $packet->unique_push(update => @rr);

Adds RRs to the specified section of the packet provided that 
the RRs do not already exist in the packet.

=cut

sub unique_push {
	my ($self, $section, @rrs) = @_;
	
	foreach my $rr (@rrs) {
		next if $self->{'seen'}->{$rr->string}++;

		$self->push($section, $rr);
	}
}

=head2 safe_push

A deprecated name for C<unique_push()>.

=cut

sub safe_push {
	carp('safe_push() is deprecated, use unique_push() instead,');
	
	goto &unique_push;
}
	

=head2 pop

    my $rr = $packet->pop("pre");
    my $rr = $packet->pop("update");
    my $rr = $packet->pop("additional");
    my $rr = $packet->pop("question");

Removes RRs from the specified section of the packet.

=cut

sub pop {
	my ($self, $section) = @_;

	return unless $section;
	$section = lc $section;

	if (($section eq "prerequisite") || ($section eq "prereq")) {
		$section = "pre";
	}

	my $rr;

	if ($section eq "answer" || $section eq "pre") {
		my $ancount = $self->{"header"}->ancount;
		if ($ancount) {
			$rr = pop @{$self->{"answer"}};
			$self->{"header"}->ancount($ancount - 1);
		}
	} elsif ($section eq "authority" || $section eq "update") {
		my $nscount = $self->{"header"}->nscount;
		if ($nscount) {
			$rr = pop @{$self->{"authority"}};
			$self->{"header"}->nscount($nscount - 1);
		}
	} elsif ($section eq "additional") {
		my $adcount = $self->{"header"}->adcount;
		if ($adcount) {
			$rr = pop @{$self->{"additional"}};
			$self->{"header"}->adcount($adcount - 1);
		    }
	} elsif ($section eq "question") {
	        my $qdcount = $self->{"header"}->qdcount;
		if ($qdcount) {
		    	$rr = pop @{$self->{"question"}};
			$self->{"header"}->qdcount($qdcount - 1);
		    }
	} else {
		Carp::cluck(qq(invalid section "$section"\n));
	}

	return $rr;
}

=head2 dn_comp

    $compname = $packet->dn_comp("foo.example.com", $offset);

Returns a domain name compressed for a particular packet object, to
be stored beginning at the given offset within the packet data.  The
name will be added to a running list of compressed domain names for
future use.

=cut

sub dn_comp {
	my ($self, $name, $offset) = @_;
	$name="" unless defined($name);
	my $compname="";
	# The Exporter module does not seem to catch this baby...
	my @names=Net::DNS::name2labels($name);

	while (@names) {
		my $dname = join(".", @names);

		if (exists $self->{"compnames"}->{$dname}) {
			my $pointer = $self->{"compnames"}->{$dname};
			$compname .= pack("n", 0xc000 | $pointer);
			last;
		}

		$self->{"compnames"}->{$dname} = $offset;
		my $first  = shift @names;
		my $length = length $first;
		croak "length of $first is larger than 63 octets" if $length>63;
		$compname .= pack("C a*", $length, $first);
		$offset   += $length + 1;
	}

	$compname .= pack("C", 0) unless @names;

	return $compname;
}

=head2 dn_expand

    use Net::DNS::Packet qw(dn_expand);
    ($name, $nextoffset) = dn_expand(\$data, $offset);

    ($name, $nextoffset) = Net::DNS::Packet::dn_expand(\$data, $offset);

Expands the domain name stored at a particular location in a DNS
packet.  The first argument is a reference to a scalar containing
the packet data.  The second argument is the offset within the
packet where the (possibly compressed) domain name is stored.

Returns the domain name and the offset of the next location in the
packet.

Returns B<(undef, undef)> if the domain name couldn't be expanded.

=cut
# '

# This is very hot code, so we try to keep things fast.  This makes for
# odd style sometimes.

sub dn_expand
{
    my ($packet, $offset) = @_;
    my ($name, $roffset);
	if ($Net::DNS::HAVE_XS) {
	    ($name, $roffset)=dn_expand_XS($packet, $offset);
	} else {
	    ($name, $roffset)=dn_expand_PP($packet, $offset);
	}
    
	return ($name, $roffset);

}

sub dn_expand_PP {
	my ($packet, $offset) = @_; # $seen from $_[2] for debugging
	my $name = "";
	my $len;
	my $packetlen = length $$packet;
	my $int16sz = Net::DNS::INT16SZ();

	# Debugging
	# warn "USING PURE PERL dn_expand()\n";
	#if ($seen->{$offset}) {
	#	die "dn_expand: loop: offset=$offset (seen = ",
	#	     join(",", keys %$seen), ")\n";
	#}
	#$seen->{$offset} = 1;

	while (1) {
		return (undef, undef) if $packetlen < ($offset + 1);

		$len = unpack("\@$offset C", $$packet);

		if ($len == 0) {
			$offset++;
			last;
		}
		elsif (($len & 0xc0) == 0xc0) {
			return (undef, undef)
				if $packetlen < ($offset + $int16sz);

			my $ptr = unpack("\@$offset n", $$packet);
			$ptr &= 0x3fff;
			my($name2) = dn_expand_PP($packet, $ptr); # pass $seen for debugging

			return (undef, undef) unless defined $name2;

			$name .= $name2;
			$offset += $int16sz;
			last;
		}
		else {
			$offset++;

			return (undef, undef)
				if $packetlen < ($offset + $len);

			my $elem = substr($$packet, $offset, $len);

			$name .= Net::DNS::wire2presentation($elem).".";

			$offset += $len;
		}
	}

	

	$name =~ s/\.$//o;
	return ($name, $offset);
}

=head2 sign_tsig

    $key_name = "tsig-key";
    $key      = "awwLOtRfpGE+rRKF2+DEiw==";

    $update = Net::DNS::Update->new("example.com");
    $update->push("update", rr_add("foo.example.com A 10.1.2.3"));

    $update->sign_tsig($key_name, $key);

    $response = $res->send($update);

Signs a packet with a TSIG resource record (see RFC 2845).  Uses the
following defaults:

    algorithm   = HMAC-MD5.SIG-ALG.REG.INT
    time_signed = current time
    fudge       = 300 seconds

If you wish to customize the TSIG record, you'll have to create it
yourself and call the appropriate Net::DNS::RR::TSIG methods.  The
following example creates a TSIG record and sets the fudge to 60
seconds:

    $key_name = "tsig-key";
    $key      = "awwLOtRfpGE+rRKF2+DEiw==";

    $tsig = Net::DNS::RR->new("$key_name TSIG $key");
    $tsig->fudge(60);

    $query = Net::DNS::Packet->new("www.example.com");
    $query->sign_tsig($tsig);

    $response = $res->send($query);

You shouldn't modify a packet after signing it; otherwise authentication
will probably fail.

=cut

sub sign_tsig {
	my $self = shift;

	my $tsig;

	if (@_ == 1 && ref($_[0])) {
		$tsig = $_[0];
	}
	elsif (@_ == 2) {
		my ($key_name, $key) = @_;
		if (defined($key_name) && defined($key)) {
			$tsig = Net::DNS::RR->new("$key_name TSIG $key")
		}
	}

	$self->push("additional", $tsig) if $tsig;
	return $tsig;
}



=head2 sign_sig0

SIG0 support is provided through the Net::DNS::RR::SIG class. This class is not part
of the default Net::DNS distribution but resides in the Net::DNS::SEC distribution.

    $update = Net::DNS::Update->new("example.com");
    $update->push("update", rr_add("foo.example.com A 10.1.2.3"));
    $update->sign_sig0("Kexample.com+003+25317.private");


SIG0 support is experimental see Net::DNS::RR::SIG for details.

The method will call C<Carp::croak()> if Net::DNS::RR::SIG cannot be found.


=cut

sub sign_sig0 {
	my $self = shift;
	
	Carp::croak('The sign_sig0() method is only available when the Net::DNS::SEC package is installed.') 
			unless $Net::DNS::DNSSEC;
	
	
	my $sig0;
	
	if (@_ == 1 && ref($_[0])) {
		if (UNIVERSAL::isa($_[0],"Net::DNS::RR::SIG::Private")) {
			Carp::carp('Net::DNS::RR::SIG::Private is deprecated use Net::DNS::SEC::Private instead');
			$sig0 = Net::DNS::RR::SIG->create('', $_[0]) if $_[0];
		
		} elsif (UNIVERSAL::isa($_[0],"Net::DNS::SEC::Private")) {
			$sig0 = Net::DNS::RR::SIG->create('', $_[0]) if $_[0];
		
		} elsif (UNIVERSAL::isa($_[0],"Net::DNS::RR::SIG")) {
			$sig0 = $_[0];
		} else {
		  Carp::croak('You are passing an incompatible class as argument to sign_sig0: ' . ref($_[0]));
		}
	} elsif (@_ == 1 && ! ref($_[0])) {
		my $key_name = $_[0];
		$sig0 = Net::DNS::RR::SIG->create('', $key_name) if $key_name
	}
	
	$self->push('additional', $sig0) if $sig0;
	return $sig0;
}






#------------------------------------------------------------------------------
# parse_question
#
#     ($queryobj, $newoffset) = parse_question(\$data, $offset);
#
# Parses a question section record contained at a particular location within
# a DNS packet.  The first argument is a reference to the packet data.  The
# second argument is the offset within the packet where the question record
# begins.
#
# Returns a Net::DNS::Question object and the offset of the next location
# in the packet.
#
# Returns (undef, undef) if the question object couldn't be created (e.g.,
# if there isn't enough data).
#------------------------------------------------------------------------------

sub parse_question {
	my ($data, $offset) = @_;
	my $qname;

	($qname, $offset) = dn_expand($data, $offset);
	return (undef, undef) unless defined $qname;

	return (undef, undef)
		if length($$data) < ($offset + 2 * Net::DNS::INT16SZ());

	my ($qtype, $qclass) = unpack("\@$offset n2", $$data);
	$offset += 2 * Net::DNS::INT16SZ();

	$qtype  = Net::DNS::typesbyval($qtype);
	$qclass = Net::DNS::classesbyval($qclass);

	return (Net::DNS::Question->new($qname, $qtype, $qclass), $offset);
}

#------------------------------------------------------------------------------
# parse_rr
#
#    ($rrobj, $newoffset) = parse_rr(\$data, $offset);
#
# Parses a DNS resource record (RR) contained at a particular location
# within a DNS packet.  The first argument is a reference to a scalar
# containing the packet data.  The second argument is the offset within
# the data where the RR is located.
#
# Returns a Net::DNS::RR object and the offset of the next location
# in the packet.
#------------------------------------------------------------------------------

sub parse_rr {
	my ($data, $offset) = @_;
	my $name;

	($name, $offset) = dn_expand($data, $offset);
	return (undef, undef) unless defined $name;

	return (undef, undef)
		if length($$data) < ($offset + Net::DNS::RRFIXEDSZ());

	my ($type, $class, $ttl, $rdlength) = unpack("\@$offset n2 N n", $$data);

	$type  = Net::DNS::typesbyval($type)    || $type;

	# Special case for OPT RR where CLASS should be interperted as 16 bit 
	# unsigned 2671 sec 4.3
	if ($type ne "OPT") {
	    $class = Net::DNS::classesbyval($class) || $class;
	} 
	# else just keep at its numerical value

	$offset += Net::DNS::RRFIXEDSZ();

	return (undef, undef)
		if length($$data) < ($offset + $rdlength);

	my $rrobj = Net::DNS::RR->new($name,
				      $type,
				      $class,
				      $ttl,
				      $rdlength, 
				      $data,
				      $offset);

	return (undef, undef) unless defined $rrobj;

	$offset += $rdlength;
	return ($rrobj, $offset);
}



=head1 COPYRIGHT

Copyright (c) 1997-2002 Michael Fuhr. 

Portions Copyright (c) 2002-2004 Chris Reinhardt.

Portions Copyright (c) 2002-2005 Olaf Kolkman

All rights reserved.  This program is free software; you may redistribute
it and/or modify it under the same terms as Perl itself.



=head1 SEE ALSO

L<perl(1)>, L<Net::DNS>, L<Net::DNS::Resolver>, L<Net::DNS::Update>,
L<Net::DNS::Header>, L<Net::DNS::Question>, L<Net::DNS::RR>,
RFC 1035 Section 4.1, RFC 2136 Section 2, RFC 2845

=cut

1;
