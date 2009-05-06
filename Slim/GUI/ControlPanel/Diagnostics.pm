package Slim::GUI::ControlPanel::Diagnostics;

# SqueezeCenter Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base 'Wx::Panel';

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON);

use Net::Ping;
use Socket;
use Symbol;

use Slim::Utils::Light;
use Slim::Utils::ServiceManager;

my $svcMgr = Slim::Utils::ServiceManager->new();

use constant SN => 'www.squeezenetwork.com';

my @checks;
my $cache;

sub new {
	my ($self, $nb) = @_;

	$self = $self->SUPER::new($nb);

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);


	my $scBoxSizer = Wx::StaticBoxSizer->new( 
		Wx::StaticBox->new($self, -1, string('SQUEEZECENTER')),
		wxVERTICAL
	);
	my $scSizer = Wx::FlexGridSizer->new(0, 2, 5, 10);
	$scSizer->AddGrowableCol(0, 2);
	$scSizer->AddGrowableCol(1, 1);
	$scSizer->SetFlexibleDirection(wxHORIZONTAL);

	$self->_addItem($scSizer, string('SQUEEZECENTER') . string('COLON'), sub {
		$svcMgr->checkServiceState() == SC_STATE_RUNNING ? string('RUNNING') : string('STOPPED');
	});
	$self->_addItem($scSizer, string('INFORMATION_SERVER_IP') . string('COLON'), \&getHostIP);
	$self->_addItem($scSizer, string('CONTROLPANEL_PORTNO', '', '3483', 'slimproto'), sub {
		checkPort(getHostIP(), '3483');
	});
	
	my $httpPort = Slim::GUI::ControlPanel->getPref('httpport') || 9000;
	$self->_addItem($scSizer, string('CONTROLPANEL_PORTNO', '', $httpPort, 'HTTP'), sub {
		checkPort(getHostIP(), $httpPort);
	});

	my $cliPort = Slim::GUI::ControlPanel->getPref('cliport', 'cli.prefs') || 9090;
	$self->_addItem($scSizer, string('CONTROLPANEL_PORTNO', '', $cliPort, 'CLI'), sub {
		checkPort(getHostIP(), $cliPort);
	});
	
	$scBoxSizer->Add($scSizer, 0, wxLEFT | wxRIGHT | wxGROW, 10);
	$mainSizer->Add($scBoxSizer, 0, wxALL | wxGROW, 10);


	my $snBoxSizer = Wx::StaticBoxSizer->new( 
		Wx::StaticBox->new($self, -1, string('SQUEEZENETWORK')),
		wxVERTICAL
	);
	my $snSizer = Wx::FlexGridSizer->new(0, 2, 5, 10);
	$snSizer->AddGrowableCol(0, 2);
	$snSizer->AddGrowableCol(1, 1);
	$snSizer->SetFlexibleDirection(wxHORIZONTAL);

	$self->_addItem($snSizer, string('INFORMATION_SERVER_IP') . string('COLON'), \&getSNAddress);

	# check port 80 on squeezenetwork, as echo isn't available
	$self->_addItem($snSizer, string('CONTROLPANEL_PING'), sub {
		checkPing(SN, 80);
	});
	
	$self->_addItem($snSizer, string('CONTROLPANEL_PORTNO', '', '3483', 'slimproto'), sub {
		checkPort(getSNAddress(), '3483');
	});
	$self->_addItem($snSizer, string('CONTROLPANEL_PORTNO', '', '9000', 'HTTP'), sub {
		checkPort(getSNAddress(), '9000');
	});
	
	$snBoxSizer->Add($snSizer, 0, wxLEFT | wxRIGHT | wxGROW, 10);
	$mainSizer->Add($snBoxSizer, 0, wxALL | wxGROW, 10);

	$mainSizer->AddStretchSpacer();	
	
	my $btnsizer = Wx::StdDialogButtonSizer->new();

	my $btnRefresh = Wx::Button->new( $self, -1, string('CONTROLPANEL_REFRESH') );
	EVT_BUTTON( $self, $btnRefresh, sub {
		$self->_update();
	} );
	$btnsizer->SetAffirmativeButton($btnRefresh);
	
	$btnsizer->Realize();

	$mainSizer->Add($btnsizer, 0, wxALIGN_BOTTOM | wxALL | wxALIGN_RIGHT, 10);
	
	
	$self->SetSizer($mainSizer);

	return $self;
}

sub _addItem {
	my ($self, $sizer, $label, $checkCB) = @_;
	
	$sizer->Add(Wx::StaticText->new($self, -1, string($label)));
	
	my $labelText = Wx::StaticText->new($self, -1, '', [-1, -1], [-1, -1], wxALIGN_RIGHT);
	push @checks, {
		label => $labelText,
		cb    => ref $checkCB eq 'CODE' ? $checkCB : sub { $checkCB },
	};
	
	$sizer->Add($labelText);
}

sub _update {
	my ($self, $event) = @_;

	$self->Update;
	
	foreach my $check (@checks) {

		if (defined $check->{cb} && $check->{cb} && $check->{label}) {
			eval {
				my $val = &{$check->{cb}};
				$check->{label}->SetLabel($val) if defined $val;
				
				$self->Layout();
			};
			
			print "$@" if $@;
		}
	}
	
	$self->Layout();
}

sub getHostIP {
	return $cache->{SC}->{IP} if $cache->{SC} && $cache->{SC}->{ttl} < time;

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

	my $scAddress;
	$scAddress = inet_ntoa($address) if $address;

	$cache->{SC} = {
		ttl => time() + 60,
		IP  => $scAddress,
	} ;
	
	return $scAddress;
}

sub getSNAddress {
	return $cache->{SN}->{IP} if $cache->{SN} && $cache->{SN}->{ttl} < time;
	
	my @addrs = (gethostbyname(SN))[4];
	
	my $snAddress;
	$snAddress = inet_ntoa($addrs[0]) if defined $addrs[0];

	$cache->{SN} = {
		ttl => time() + 60,
		IP  => $snAddress,
	} ;
	
	return $snAddress;
}

sub checkPort {
	my ($raddr, $rport) = @_;
	
	return string('CONTROLPANEL_FAILED') unless $raddr && $rport;

	my $iaddr = inet_aton($raddr);
	my $paddr = sockaddr_in($rport, $iaddr);

	socket(SSERVER, PF_INET, SOCK_STREAM, getprotobyname('tcp'));

	if (connect(SSERVER, $paddr)) {

		close(SSERVER);
		return string('CONTROLPANEL_OK');
	}

	return string('CONTROLPANEL_FAILED');
}

sub checkPing {
	my ($host, $port) = @_;
	
	return string('CONTROLPANEL_FAILED') unless $host;

	my $p = Net::Ping->new('tcp', 2);

	$p->{port_num} = $port if $port;
	
	my $result = $p->ping($host) ? 'CONTROLPANEL_OK' : 'CONTROLPANEL_FAILED';
	$p->close();

	return string($result);
}


1;