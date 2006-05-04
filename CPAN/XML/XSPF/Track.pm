package XML::XSPF::Track;

# $Id: /mirror/slim/trunk/server/CPAN/XML/XSPF/Track.pm 12555 2006-05-04T20:40:11.700353Z dsully  $

use strict;
use base qw(XML::XSPF::Base);

{
	my $class = __PACKAGE__;

	$class->mk_accessors(qw(
		locations identifiers links metas title creator 
		annotation info image album trackNum duration
	));
}

sub new {
	my $class = shift;
	my $self  = $class->SUPER::new();

	for my $key (qw(locations identifiers metas links extensions)) {

		$self->set($key, []);
	}

	return $self;
}

# According to the XSPF Spec http://www.xspf.org/xspf-v1.html - 
#
# "xspf:track elements MAY contain zero or more location elements, but a
# user-agent MUST NOT render more than one of the named resources."

sub location {
	my $self = shift;

	if (@_) {
		$self->append('locations', @_);
	}

	if (ref($self->locations) eq 'ARRAY') {

		my @location = @{$self->locations};

		return $location[0];

	} else {

		return $self->locations;
	}
}

sub identifiers {
	shift->_asArray('identifiers', @_);
}

sub links {
	shift->_asArray('links', @_);
}

sub metas {
	shift->_asArray('metas', @_);
}

sub trackNum {
	shift->_validateNonNegative('trackNum', @_);
}

sub duration {
	shift->_validateNonNegative('duration', @_);
}

sub _validateNonNegative {
	my $self = shift;
	my $key  = shift;

	if (defined $_[0]) {

		if ($_[0] !~ /^\d+$/ || $_[0] < 0) {
			Carp::confess("Error: $key is not a XML Schema nonNegativeInteger!\n");
			return undef;
		}

		return $self->set($key, $_[0]);
	}

	return $self->get($key);
}

1;

__END__
