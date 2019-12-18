package Net::HTTPS::NB;

use strict;
use Net::HTTP;
use IO::Socket::SSL 0.98;
use Exporter;
use Errno qw(EWOULDBLOCK EAGAIN);
use vars qw($VERSION @ISA @EXPORT $HTTPS_ERROR);

$VERSION = 0.15;

=head1 NAME

Net::HTTPS::NB - Non-blocking HTTPS client

=head1 SYNOPSIS

=over

=item Example of sending request and receiving response

	use strict;
	use Net::HTTPS::NB;
	use IO::Select;
	use Errno qw/EAGAIN EWOULDBLOCK/;
	
	my $s = Net::HTTPS::NB->new(Host => "pause.perl.org") || die $@;
	$s->write_request(GET => "/");
	
	my $sel = IO::Select->new($s);
	
	READ_HEADER: {
		die "Header timeout" unless $sel->can_read(10);
		my($code, $mess, %h) = $s->read_response_headers;
		redo READ_HEADER unless $code;
	}
	
	# Net::HTTPS::NB uses internal buffer for reading
	# so we should check it before socket check by calling read_entity_body()
	# it is error to wait data on socket before read_entity_body() will return undef
	# with $! set to EAGAIN or EWOULDBLOCK
	# make socket non-blocking, so read_entity_body() will not block
	$s->blocking(0);
	
	while (1) {
		my $buf;
		my $n;
		# try to read until error or all data received
		while (1) {
			my $tmp_buf;
			$n = $s->read_entity_body($tmp_buf, 1024);
			if ($n == -1 || (!defined($n) && ($! == EWOULDBLOCK || $! == EAGAIN))) {
				last; # no data available this time
			}
			elsif ($n) {
				$buf .= $tmp_buf; # data received
			}
			elsif (defined $n) {
				last; # $n == 0, all readed
			}
			else {
				die "Read error occured: ", $!; # $n == undef
			}
		}
	
		print $buf if length $buf;
		last if defined $n && $n == 0; # all readed
		die "Body timeout" unless $sel->can_read(10); # wait for new data
	}

=item Example of non-blocking connect

	use strict;
	use Net::HTTPS::NB;
	use IO::Select;

	my $sock = Net::HTTPS::NB->new(Host => 'encrypted.google.com', Blocking => 0);
	my $sele = IO::Select->new($sock);

	until ($sock->connected) {
		if ($HTTPS_ERROR == HTTPS_WANT_READ) {
			$sele->can_read();
		}
		elsif($HTTPS_ERROR == HTTPS_WANT_WRITE) {
			$sele->can_write();
		}
		else {
			die 'Unknown error: ', $HTTPS_ERROR;
		}
	}

=back

See `examples' subdirectory for more examples.

=head1 DESCRIPTION

Same interface as Net::HTTPS but it will never try multiple reads when the
read_response_headers() or read_entity_body() methods are invoked. In addition
allows non-blocking connect.

=over

=item If read_response_headers() did not see enough data to complete the headers an empty list is returned. 

=item If read_entity_body() did not see new entity data in its read the value -1 is returned.

=back

=cut

# we only supports IO::Socket::SSL now
# use it force
$Net::HTTPS::SSL_SOCKET_CLASS = 'IO::Socket::SSL';
require Net::HTTPS;

# make aliases to IO::Socket::SSL variables and constants
use constant {
	HTTPS_WANT_READ  => SSL_WANT_READ,
	HTTPS_WANT_WRITE => SSL_WANT_WRITE,
};
*HTTPS_ERROR = \$SSL_ERROR;

=head1 PACKAGE CONSTANTS

Imported by default

	HTTPS_WANT_READ
	HTTPS_WANT_WRITE

=head1 PACKAGE VARIABLES

Imported by default

	$HTTPS_ERROR

=cut

# need export some stuff for error handling
@EXPORT = qw($HTTPS_ERROR HTTPS_WANT_READ HTTPS_WANT_WRITE);
@ISA = qw(Net::HTTPS Exporter);

=head1 METHODS

=head2 new(%cfg)

Same as Net::HTTPS::new, but in addition allows `Blocking' parameter. By setting
this parameter to 0 you can perform non-blocking connect. See connected() to
determine when connection completed.

=cut

sub new {
	my ($class, %args) = @_;
	
	my %ssl_opts;
	while (my $name = each %args) {
		if (substr($name, 0, 4) eq 'SSL_') {
			$ssl_opts{$name} = delete $args{$name};
		}
	}
	
	unless (exists $args{PeerPort}) {
		$args{PeerPort} = 443;
	}
	
	# create plain socket first
	my $self = Net::HTTP->new(%args)
		or return;
	
	# and upgrade it to SSL then                                        for SNI
	$class->start_SSL($self, %ssl_opts, SSL_startHandshake => 0, PeerHost => $args{Host})
		or return;
	
	if (!exists($args{Blocking}) || $args{Blocking}) {
		# blocking connect
		$self->connected()
			or return;
	}
	# non-blocking handshake will be started after plain socket connected
	
	return $self;
}

=head2 connected()

Returns true value when connection completed (https handshake done). Otherwise
returns false. In this case you can check $HTTPS_ERROR to determine what handshake
need for, read or write. $HTTPS_ERROR could be HTTPS_WANT_READ or HTTPS_WANT_WRITE
respectively. See L</SYNOPSIS>.

=cut

sub connected {
	my $self = shift;
	
	if (exists ${*$self}{httpsnb_connected}) {
		# already connected or disconnected
		return ${*$self}{httpsnb_connected} && getpeername($self);
	}
	
	if ($self->connect_SSL()) {
		return ${*$self}{httpsnb_connected} = 1;
	}
	elsif ($! != EWOULDBLOCK && $! != EAGAIN) {
		$HTTPS_ERROR = $!;
	}
	return 0;
}

sub close {
	my $self = shift;
	# need some cleanup
	${*$self}{httpsnb_connected} = 0;
	return $self->SUPER::close();
}

=head2 blocking($flag)

As opposed to Net::HTTPS where blocking method consciously broken you
can set socket blocking. For example you can return socket to blocking state
after non-blocking connect.

=cut

sub blocking {
	# blocking() is breaked in Net::HTTPS
	# restore it here
	my $self = shift;
	$self->IO::Socket::blocking(@_);
}

# code below copied from Net::HTTP::NB with some modifications
# Author: Gisle Aas

sub sysread {
	my $self = shift;
	unless (${*$self}{'httpsnb_reading'}) {
		# allow reading without restrictions when called
		# not from our methods
		return $self->SUPER::sysread(@_);
	}
	
	if (${*$self}{'httpsnb_read_count'}++) {
		${*$self}{'http_buf'} = ${*$self}{'httpsnb_save'};
		die "Multi-read\n";
	}
	
	my $offset = $_[2] || 0;
	my $n = $self->SUPER::sysread($_[0], $_[1], $offset);
	${*$self}{'httpsnb_save'} .= substr($_[0], $offset);
	return $n;
}

sub read_response_headers {
	my $self = shift;
	${*$self}{'httpsnb_reading'} = 1;
	${*$self}{'httpsnb_read_count'} = 0;
	${*$self}{'httpsnb_save'} = ${*$self}{'http_buf'};
	my @h = eval { $self->SUPER::read_response_headers(@_) };
	${*$self}{'httpsnb_reading'} = 0;
	if ($@) {
		return if $@ eq "Multi-read\n" || $HTTPS_ERROR == HTTPS_WANT_READ;
		die;
	}
	return @h;
}

sub read_entity_body {
	my $self = shift;
	${*$self}{'httpsnb_reading'} = 1;
	${*$self}{'httpsnb_read_count'} = 0;
	${*$self}{'httpsnb_save'} = ${*$self}{'http_buf'};
	
	my $chunked = ${*$self}{'http_chunked'};
	my $bytes   = ${*$self}{'http_bytes'};
	my $first_body = ${*$self}{'http_first_body'};
	my @request_method = @{${*$self}{'http_request_method'}}; 
	
	# XXX I'm not so sure this does the correct thing in case of
	# transfer-encoding tranforms
	my $n = eval { $self->SUPER::read_entity_body(@_) };
	${*$self}{'httpsnb_reading'} = 0;
	if ($@ || (!defined($n) && $HTTPS_ERROR == HTTPS_WANT_READ)) {
		if ($@ eq "Multi-read\n") {
			# Reset some internals of Net::HTTP::Methods
			${*$self}{'http_chunked'} = $chunked;
			${*$self}{'http_bytes'} = $bytes;
			${*$self}{'http_first_body'} = $first_body;
			${*$self}{'http_request_method'} = \@request_method;
		}
		$_[0] = "";
		return -1;
	}
	return $n;
}

1;

=head1 SEE ALSO

L<Net::HTTP>, L<Net::HTTP::NB>, L<Net::HTTPS>

=head1 COPYRIGHT

Copyright 2011-2015 Oleg G <oleg@cpan.org>.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
