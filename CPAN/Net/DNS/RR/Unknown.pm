package Net::DNS::RR::Unknown;
#
# $Id: Unknown.pm,v 1.1 2004/02/16 17:30:04 daniel Exp $
#
use strict;
use vars qw(@ISA $VERSION);

use Net::DNS;

@ISA     = qw(Net::DNS::RR);
$VERSION = (qw$Revision: 1.1 $)[1];

sub new {
	my ($class, $self, $data, $offset) = @_;
	
	my $length = $self->{'rdlength'};
	
	if ($length > 0) {
	    my $hex = unpack('H*', substr($$data, $offset,$length));
	    $self->{'rdata'} = "\\# $length $hex";
	}

	return bless $self, $class;
}


sub rdatastr {
	my $self = shift;
	return defined $self->{'rdata'} ? $self->{'rdata'} : '# NODATA';

}

sub rr_rdata {
	my $self  = shift;
	my $rdata = '';
	return $rdata;
}

1;
__END__

=head1 NAME

Net::DNS::RR::Unknown - Unknown RR record

=head1 SYNOPSIS

C<use Net::DNS::RR>;

=head1 DESCRIPTION

Class for dealing with unknown RR types (RFC3597)

=head1 METHODS

=head1 COPYRIGHT

Copyright (c) 1997-2002 Michael Fuhr. 

Portions Copyright (c) 2002-2003 Chris Reinhardt.

Portions Copyright (c) 2003  Olaf M. Kolkman, RIPE NCC.

All rights reserved.  This program is free software; you may redistribute
it and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Net::DNS>, L<Net::DNS::RR>, RFC 3597

=cut
