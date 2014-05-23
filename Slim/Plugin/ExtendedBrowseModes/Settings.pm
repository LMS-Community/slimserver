package Slim::Plugin::ExtendedBrowseModes::Settings;

# Logitech Media Server Copyright 2001-2014 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);
use Storable;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

my $prefs = preferences('plugin.extendedbrowsemodes');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_EXTENDED_BROWSEMODES');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/ExtendedBrowseModes/settings/browsemodes.html');
}

sub prefs {
	return ($prefs);
}

sub handler {
	my ($class, $client, $params) = @_;
	
	# Restart if restart=1 param is set
	if ( $params->{restart} ) {
		$params = Slim::Web::Settings::Server::Plugins->restartServer($params, 1);
	}

	if ($params->{'saveSettings'}) {
		my $menus = $prefs->get('menus');
		
		for (my $i = 1; defined $params->{"id$i"}; $i++) {
			
			if ( $params->{"delete$i"} ) {
				$menus = [ grep { $_->{id} ne $params->{"id$i"} } @$menus ];
				next;
			}

			my ($menu) = $params->{"id$i"} eq '_new_' ? {} : grep { $_->{id} eq $params->{"id$i"} } @$menus;

			next unless $menu;

			$menu->{enabled} = $params->{"enabled$i"};
			
			if ($menu->{dontEdit}) {
				next;
			}
			else {
				next unless $params->{"name$i"} && $params->{"feed$i"} && ($params->{"roleid$i"} || $params->{"genreid$i"});

				if ( $params->{"id$i"} eq '_new_' ) {
					
					$menu = {
						id => join('_', $params->{"feed$i"}, $params->{"roleid$i"} || '', $params->{"genreid$i"} || '', time),
						enabled => 1,
					};
					
					if ( $params->{"feed$i"} eq 'albums' ) {
						$menu->{id}     = 'myMusicAlbums' . $menu->{id};
						$menu->{weight} = 25;
					}
					else {
						$menu->{id}     = 'myMusicArtists' . $menu->{id};
						$menu->{weight} = 15;
					}
					
					push @$menus, $menu;
				}

				# adjust icon and weight if the feed type has changed
				$menu->{icon} = 'html/images/' . $params->{"feed$i"} . '.png';
				$menu->{weight} = ($params->{"feed$i"} eq 'albums' ? 25 : 15) unless $menu->{feed} && $menu->{feed} eq $params->{"feed$i"};
				
				foreach (qw(feed name)) {
					$menu->{$_} = $params->{$_ . $i};
				}
				
				if ($params->{"roleid$i"}) {
					$menu->{params}->{role_id} = $params->{"roleid$i"}; 
				}
				else {
					delete $menu->{params}->{role_id};
				}
				
				if ($params->{"genreid$i"}) {
					$menu->{params}->{genre_id} = $params->{"genreid$i"}; 
				}
				else {
					delete $menu->{params}->{genre_id};
				}
			}
		}
		
		$prefs->set('menus', $menus);
		
		$params = Slim::Web::Settings::Server::Plugins->getRestartMessage($params, Slim::Utils::Strings::string('CLEANUP_PLEASE_RESTART_SC'));
	}

	my $rs = Slim::Schema->search('Genre');
	
	# Extract each genre name into a hash
	$params->{genre_list} = {};

	while (my $genre = $rs->next) {

		my $name = $genre->name;

		# Put the name here as well so the hash can be passed to
		# INPUT.Choice as part of listRef later on
		$params->{genre_list}->{$genre->name} = $genre->id;
	}
	
	$params->{roles} = { map { $_ => Slim::Schema::Contributor->typeToRole($_) } Slim::Schema::Contributor->contributorRoles };
	$params->{extended_menus} = [ sort { $b->{dontEdit} <=> $a->{dontEdit} } @{ Storable::dclone($prefs->get('menus')) } ];
	push @{$params->{extended_menus}}, { id => '_new_' };
	

	$class->SUPER::handler($client, $params);
}

1;

__END__
