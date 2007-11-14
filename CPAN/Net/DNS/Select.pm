package Net::DNS::Select;
#
# $Id: Select.pm 631 2004-02-16 17:30:06Z daniel $
#

use IO::Select;
use Carp;

use strict;
use vars qw($VERSION);

$VERSION = (qw$Revision: 1.1 $)[1];

sub new {
	my ($class, @socks) = @_;

	if ($^O eq 'MSWin32') {
		return bless \@socks, $class;
	} else {
		return IO::Select->new(@socks);
	}
}

sub add {
	my ($self, @handles) = @_;
	push @$self, @handles;
}

sub remove {
	# not implemented
}

sub handles {
	my $self = shift;
	return @$self;
}

sub can_read {
	my $self = shift;
	return @$self;
}

1;

__END__


=head1 NAME

Net::DNS::Select - Wrapper Around Select

=head1 SYNOPSIS

 use Net::DNS::Select;
 
 my $sel = Net::DNS::Select->new;

=head1 DESCRIPTION

This class provides a wrapper around L<IO::Select|IO::Select>.  
On UNIX platforms it simply returns a IO::Select object.  On the
Windows platform it implements a simple array of handles.

=head1 BUGS

The current maintainer does not know if this module is still needed.  
Feedback from Windows gurus welcome.

=head1 COPYRIGHT

Copyright (c) 1997-2002 Michael Fuhr. 

Portions Copyright (c) 2002-2003 Chris Reinhardt.

All rights reserved.  This program is free software; you may redistribute
it and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl(1)>, L<Net::DNS>, L<Net::DNS::Resolver>

=cut