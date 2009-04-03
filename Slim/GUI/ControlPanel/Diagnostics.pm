package Slim::GUI::ControlPanel::Diagnostics;

# SqueezeCenter Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use base 'Wx::Panel';

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON EVT_CHILD_FOCUS);
use Socket;
use Symbol;

use Slim::Utils::Light;

use constant SN => 'www.squeezenetwork.com';

my @checks;

sub new {
	my ($self, $nb, $parent, $args) = @_;

	$self = $self->SUPER::new($nb);
	$self->{args} = $args;

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);

	my $checkSizer = Wx::FlexGridSizer->new(0, 2, 5, 10);
	$checkSizer->AddGrowableCol(0, 1);
	$checkSizer->SetFlexibleDirection(wxHORIZONTAL);
	
	$self->_addItem($checkSizer, 'SQUEEZECENTER');
	$self->_addItem($checkSizer, 'INFORMATION_SERVER_IP', \&getHostIP);

	$self->_addItem($checkSizer, 'SQUEEZENETWORK', SN);
	$self->_addItem($checkSizer, 'INFORMATION_SERVER_IP', sub {
		my @addrs = (gethostbyname(SN))[4];
		return defined $addrs[0] ? inet_ntoa($addrs[0]) : 'n/a';
	});

	EVT_CHILD_FOCUS($self, sub {
		my ($self, $event) = @_;
		$self->_update($event);
	});
	
	$mainSizer->Add($checkSizer, 1, wxALL | wxGROW, 5);
	
	$self->SetSizer($mainSizer);

	return $self;
}

sub _addItem {
	my ($self, $checkSizer, $label, $checkCB) = @_;
	
	$checkSizer->Add(Wx::StaticText->new($self, -1, string($label)));
	
	my $labelText = Wx::StaticText->new($self, -1, '', [-1, -1], [-1, -1], wxALIGN_RIGHT);
	push @checks, {
		label => $labelText,
		cb    => ref $checkCB eq 'CODE' ? $checkCB : sub { $checkCB },
	};
	
	$checkSizer->Add($labelText);
}

sub _update {
	my ($self, $event) = @_;

	foreach my $check (@checks) {

		if (defined $check->{cb} && $check->{cb} && $check->{label}) {
			eval {
				my $val = &{$check->{cb}};
				$check->{label}->SetLabel($val) if $val;
			};
			
			print "$@\n" if $@; 
		}
	}
	
	$self->Layout();
}

sub getHostIP {
	# This code used to try and connect to www.google.com:80 in order to
	# find the local IP address.
	# 
	# Thanks to trick from Bill Fenner, trying to use a UDP socket won't
	# send any packets out over the network, but will cause the routing
	# table to do a lookup, so we can find our address. Don't use a high
	# level abstraction like IO::Socket, as it dies when connect() fails.
	#
	# time.nist.gov - though it doesn't really matter.
	my $raddr = '192.43.244.18';
	my $rport = 123;

	my $proto = (getprotobyname('udp'))[2];
	my $pname = (getprotobynumber($proto))[0];
	my $sock  = Symbol::gensym();

	my $iaddr = inet_aton($raddr) || return;
	my $paddr = sockaddr_in($rport, $iaddr);
	socket($sock, PF_INET, SOCK_DGRAM, $proto) || return;
	connect($sock, $paddr) || return;

	# Find my half of the connection
	my ($port, $address) = sockaddr_in( (getsockname($sock))[0] );

	return inet_ntoa($address);
}

1;