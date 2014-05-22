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
	push @{$params->{extended_menus}}, {};
	

	$class->SUPER::handler($client, $params);
}

1;

__END__
