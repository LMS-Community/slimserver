package Slim::Web::Settings::Server::Status;

# $Id: Basic.pm 13299 2007-09-27 08:59:36Z mherger $

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);
use Slim::Utils::Prefs;
use Slim::Menu::SystemInfo;

sub name {
	return 'SERVER_STATUS';
}

sub page {
	return 'settings/server/status.html';
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	if ($paramRef->{'abortScan'}) {
		Slim::Music::Import->abortScan();
	}
	
	$paramRef->{info} = Slim::Menu::SystemInfo->menu( $client );
	$paramRef->{info} = $paramRef->{info}->{items};
	
	$paramRef->{server}  = _extractGroup($paramRef, cstring($client, 'INFORMATION_MENU_SERVER'));
	$paramRef->{library} = _extractGroup($paramRef, cstring($client, 'INFORMATION_MENU_LIBRARY'));
	$paramRef->{players} = _extractGroup($paramRef, cstring($client, 'INFORMATION_MENU_PLAYER'));

	# we only have one player	
	if ($client && !$paramRef->{players}) {
		$paramRef->{players} = {
			items => [
				 _extractGroup($paramRef, $client->name) 
			]
		};
	}

	$paramRef->{folders} = _extractGroup($paramRef, cstring($client, 'FOLDERS'));
	$paramRef->{logs}    = _extractGroup($paramRef, cstring($client, 'SETUP_DEBUG_SERVER_LOG'));

	$paramRef->{'scanning'} = Slim::Music::Import->stillScanning();

	if (Slim::Schema::hasLibrary()) {
		# skeleton for the progress update
		$paramRef->{progress} = ${ Slim::Web::Pages::Progress::progress($client, {
			ajaxUpdate => 1,
			type       => 'importer',
			webroot    => $paramRef->{webroot}
		}) };
	}

	return $class->SUPER::handler($client, $paramRef);
}

sub _extractGroup {
	my ($paramRef, $token) = @_;
	
	my @items = grep { $_->{name} eq $token } @{$paramRef->{info}};
	
	@{$paramRef->{info}} = grep { $_->{name} ne $token } @{$paramRef->{info}};
	
	return shift @items;
}

1;

__END__
