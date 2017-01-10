package Slim::Plugin::RemoteLibrary::Plugin;

# Logitech Media Server Copyright 2001-2016 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=pod

This plugin will give access to "remote libraries". This can be another Logitech Media 
Server, or some UPnP/DLNA server.

3rd party plugins can hook into this menu by registering their own browse menu. During
their plugin initialization they call:

	sub init {
		my $class = shift;
		
		... # set up your plugin here
	
		Slim::Plugin::RemoteLibrary::Plugin->addRemoteLibraryProvider($class);
	}

The plugin must provide a method getLibraryList(), which would return menu items for
every remote library they can handle. It is then responsible to provide the navigation
code to drill down from that item.

See the LMS and UPnP implementations for details.

=cut

use base qw(Slim::Plugin::OPMLBased);

use strict;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring string);

my $prefs = preferences('plugin.remotelibrary');

my $log = Slim::Utils::Log->addLogCategory( {
	'category'     => 'plugin.remotelibrary',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_REMOTE_LIBRARY_MODULE_NAME',
} );

my %remoteLibraryProviders;

sub initPlugin {
	my $class = shift;

	$prefs->init({
		useLMS => 1,
		transcodeLMS => 'flac',
		useUPnP => (preferences('server')->get('noupnp') ? 0 : 1),
		ignoreFolders => sub {
			my %ignoreItems = Slim::Utils::OSDetect::getOS->ignoredItems();
			return join( ', ', string('PLUGIN_REMOTE_LIBRARY_IGNORE_MENU_DEFAULT'), grep { $ignoreItems{$_} == 1 } keys %ignoreItems );
		},
	});
	
	# some sanity checks on remote LMS URLs
	$prefs->setChange(sub {
		my ($prefname, $newValue) = @_;
		
		$newValue = [ map {
			$_ = 'http://' . $_ unless m|^http://|i;
			$_ .= ':9000' unless m|:\d+$|;
			$_;
		} @{ $newValue || [] }];
	}, 'remoteLMS');
	
	$prefs->setValidate(sub {
		# localhost is not allowed, as players wouldn't see it
		return 0 if grep /localhost|127\.0\.0\.1/, @{ $_[1] || [] };
		return 1;
	}, 'remoteLMS');
	
	if ( $prefs->get('useLMS') ) {
		require Slim::Plugin::RemoteLibrary::LMS;
		Slim::Plugin::RemoteLibrary::LMS->init();
	}

	if ( $prefs->get('useUPnP') ) {
		require Slim::Plugin::RemoteLibrary::UPnP;
		Slim::Plugin::RemoteLibrary::UPnP->init()
	}
	
	if ( main::WEBUI ) {
		require Slim::Plugin::RemoteLibrary::Settings;	
		Slim::Plugin::RemoteLibrary::Settings->new;
	}
	
	$class->SUPER::initPlugin(
		feed   => \&handleFeed,
		tag    => 'selectRemoteLibrary',
		node   => 'myMusic',
		menu   => 'browse',
		weight => 110,
	);
}

sub getDisplayName { 'PLUGIN_REMOTE_LIBRARY_MODULE_NAME' }

sub addRemoteLibraryProvider {
	my ($class, $provider) = @_;
	$remoteLibraryProviders{$provider}++ if $provider;
}

sub removeRemoteLibraryProvider {
	my ($class, $provider) = @_;
	delete $remoteLibraryProviders{$provider} if $provider;
}

sub handleFeed {
	my ($client, $cb, $args) = @_;

	my $items = [];
	
	# there's a bug in SP which would block the menu when we re-enter a menu with a text area 
	# after we had left from a menu item other than the first one...
	my $isSqueezeplay = ($client && $client->controllerUA && $client->controllerUA =~ /^SqueezePlay/) ? 1 : 0;
	
	foreach my $provider (keys %remoteLibraryProviders) {
		next unless $provider->can('getLibraryList');
		push @$items, @{ $provider->getLibraryList() || [] };
	}
		
	if ( !scalar @$items ) {
		$items = [{
			name => cstring($client, 'PLUGIN_REMOTE_LIBRARY_NOT_FOUND'),
			type => 'textarea'
		}];
	}
	else {
		$items = [ sort { lc($a->{name}) cmp lc($b->{name}) } @$items ];

		if ( !$isSqueezeplay ) {
			unshift @$items, {
				name => cstring($client, 'PLUGIN_REMOTE_LIBRARY_SERVERS_FOUND'),
				type => 'textarea'
			};
		}
	}
	
	$cb->({
		items => $items
	});
}

1;
