package Net::DNS::Question;
#
# $Id$
#
use strict;
BEGIN { 
    eval { require bytes; }
} 

use vars qw($VERSION $AUTOLOAD);

use Carp;
use Net::DNS;

$VERSION = (qw$LastChangedRevision: 546 $)[1];

=head1 NAME

Net::DNS::Question - DNS question class

=head1 SYNOPSIS

C<use Net::DNS::Question>

=head1 DESCRIPTION

A C<Net::DNS::Question> object represents a record in the
question section of a DNS packet.

=head1 METHODS

=head2 new

    $question = Net::DNS::Question->new("example.com", "MX", "IN");

Creates a question object from the domain, type, and class passed
as arguments.

=cut

sub new {
	my $class = shift;
	my %self = (
		"qname"		=> undef,
		"qtype"		=> undef,
		"qclass"	=> undef,
	);

	my ($qname, $qtype, $qclass) = @_;

	$qname  = "" if !defined($qname);

	$qtype  = defined($qtype)  ? uc($qtype)  : "ANY";
	$qclass = defined($qclass) ? uc($qclass) : "ANY";

	# Check if the caller has the type and class reversed.
	# We are not that kind for unknown types.... :-)
	if ((!exists $Net::DNS::typesbyname{$qtype} ||
	     !exists $Net::DNS::classesbyname{$qclass})
	    && exists $Net::DNS::classesbyname{$qtype}
	    && exists $Net::DNS::typesbyname{$qclass}) {

		($qtype, $qclass) = ($qclass, $qtype);
	}

	$qname =~ s/^\.+//o;
	$qname =~ s/\.+$//o;

	$self{"qname"}  = $qname;
	$self{"qtype"}  = $qtype;
	$self{"qclass"} = $qclass;

	bless \%self, $class;
}




#
# Some people have reported that Net::DNS dies because AUTOLOAD picks up
# calls to DESTROY.
#
sub DESTROY {}

=head2 qname, zname

    print "qname = ", $question->qname, "\n";
    print "zname = ", $question->zname, "\n";

Returns the domain name.  In dynamic update packets, this field is
known as C<zname> and refers to the zone name.

=head2 qtype, ztype

    print "qtype = ", $question->qtype, "\n";
    print "ztype = ", $question->ztype, "\n";

Returns the record type.  In dymamic update packets, this field is
known as C<ztype> and refers to the zone type (must be SOA).

=head2 qclass, zclass

    print "qclass = ", $question->qclass, "\n";
    print "zclass = ", $question->zclass, "\n";

Returns the record class.  In dynamic update packets, this field is
known as C<zclass> and refers to the zone's class.

=cut

sub AUTOLOAD {
	my ($self) = @_;
	
	my $name = $AUTOLOAD;
	$name =~ s/.*://o;

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


sub zname  { &qname;  }
sub ztype  { &qtype;  }
sub zclass { &qclass; }

=head2 print

    $question->print;

Prints the question record on the standard output.

=cut

sub print {	print $_[0]->string, "\n"; }

=head2 string

    print $qr->string, "\n";

Returns a string representation of the question record.

=cut

sub string {
	my $self = shift;
	return "$self->{qname}.\t$self->{qclass}\t$self->{qtype}";
}

=head2 data

    $qdata = $question->data($packet, $offset);

Returns the question record in binary format suitable for inclusion
in a DNS packet.

Arguments are a C<Net::DNS::Packet> object and the offset within
that packet's data where the C<Net::DNS::Question> record is to
be stored.  This information is necessary for using compressed
domain names.

=cut

sub data {
	my ($self, $packet, $offset) = @_;

	my $data = $packet->dn_comp($self->{"qname"}, $offset);

	$data .= pack("n", Net::DNS::typesbyname(uc($self->{"qtype"})));
	$data .= pack("n", Net::DNS::classesbyname(uc($self->{"qclass"})));
	
	return $data;
}

=head1 COPYRIGHT

Copyright (c) 1997-2002 Michael Fuhr. 

Portions Copyright (c) 2002-2004 Chris Reinhardt.

All rights reserved.  This program is free software; you may redistribute
it and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl(1)>, L<Net::DNS>, L<Net::DNS::Resolver>, L<Net::DNS::Packet>,
L<Net::DNS::Update>, L<Net::DNS::Header>, L<Net::DNS::RR>,
RFC 1035 Section 4.1.2

=cut

1;
