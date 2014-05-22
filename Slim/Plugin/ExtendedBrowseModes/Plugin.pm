package Slim::Plugin::ExtendedBrowseModes::Plugin;

# Logitech Media Server Copyright 2001-2014 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings;
use Slim::Utils::Text;

my $prefs = preferences('plugin.extendedbrowsemodes');

$prefs->init({
	menus => [{
		name    => 'PLUGIN_EXTENDED_BROWSEMODES_BROWSE_BY_ALBUMARTIST',
		params  => { role_id => 'ALBUMARTIST' },
		feed    => 'artists',
		icon    => 'html/images/artists.png',
		id      => 'myMusicAlbumArtists',
		weight  => 11,
		enabled => 1,
		dontEdit => 1,
	},{
		name    => 'PLUGIN_EXTENDED_BROWSEMODES_BROWSE_BY_COMPOSERS',
		params  => { role_id => 'COMPOSER' },
		feed    => 'artists',
		icon    => 'html/images/artists.png',
		id      => 'myMusicComposers',
		weight  => 12,
		enabled => 1,
	},{
		name    => 'Classical Music by Conductor',
		params  => { role_id => 'CONDUCTOR', genre_id => 'Classical' },
		feed    => 'artists',
		icon    => 'html/images/artists.png',
		id      => 'myMusicConductors',
		weight  => 13,
		enabled => 1,
	},{
		name    => 'Jazz Composers',
		params  => { role_id => 'COMPOSER', genre_id => 'Jazz' },
		feed    => 'artists',
		icon    => 'html/images/artists.png',
		id      => 'myMusicJazzComposers',
		weight  => 13,
		enabled => 1,
	},{
		name    => 'Audiobooks',
		params  => { genre_id => 'Audiobooks' },
		feed    => 'albums',
		icon    => 'html/images/albums.png',
		id      => 'myMusicAudiobooks',
		weight  => 14,
		enabled => 1,
	},{
		name    => Slim::Music::Info::variousArtistString(),
		params  => { artist_id => Slim::Music::Info::variousArtistString() },
		feed    => 'albums',
		icon    => 'html/images/albums.png',
		id      => 'myMusicVariousArtists',
		weight  => 22,
		enabled => 1,
		dontEdit => 1,
	}]
});

$prefs->setChange( \&initMenus, 'menus' );

sub initPlugin {
	my ( $class ) = @_;

	if ( main::WEBUI ) {
		require Slim::Plugin::ExtendedBrowseModes::Settings;
		Slim::Plugin::ExtendedBrowseModes::Settings->new;
	}

	$class->initMenus();
}

sub initMenus {
	foreach (@{$prefs->get('menus') || []}) {
		next unless $_->{enabled};
		__PACKAGE__->registerBrowseMode($_);
	}
}

sub registerBrowseMode {
	my ($class, $item) = @_;

	my $subclass = $item->{id} || return;

	my $package  = __PACKAGE__;
	my $tag      = lc($subclass);
	my $name     = $item->{name};
	my $feed     = $item->{feed};
	my $weight   = $item->{weight};
	my $icon     = $item->{icon};
	my $params   = $item->{params};
	
	# replace feed placeholders
	if ($feed !~ /^Slim::Menu::BrowseLibrary/) {
		$feed = "Slim::Menu::BrowseLibrary::_$feed";
	}
	
	# replace role strings with IDs
	if ($params->{role_id}) {
		$params->{role_id} = join(',', (map { Slim::Schema::Contributor->typeToRole($_) } split(/,/, $params->{role_id})) );
	}
	
	# create string token if it doesn't exist already
	if ( !Slim::Utils::Strings::stringExists($name) ) {
		my $token = Slim::Utils::Text::ignoreCaseArticles($name, 1);
		$token =~ s/\s/_/g;
		$token = 'PLUGIN_EXTENDED_BROWSEMODES_' . $token; 
		Slim::Utils::Strings::storeExtraStrings([{
			strings => { EN => $name},
			token   => $token,
		}]);
		$name = $token;
	}

	my $addSearchTags = '';
	while ( my ($key, $value) = each(%$params) ) {
		$addSearchTags .= qq{
			push \@{\$pt->{searchTags}}, '$key:' . Slim::Plugin::ExtendedBrowseModes::Plugin->valueToId('$value', '$key') unless grep /$key/, \@{\$pt->{searchTags}};
		};
	}

	my $code = qq{
package ${package}::${subclass};

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Plugin::ExtendedBrowseModes::Plugin;
use Slim::Menu::BrowseLibrary;

sub initPlugin {
	my \$class = shift;
	
	\$class->SUPER::initPlugin(
		tag    => '$tag',
		feed   => sub {
			my (\$client, \$callback, \$args, \$pt) = \@_;
			
			\$pt ||= {};
			\$pt->{searchTags} ||= [];
			
			$addSearchTags

			$feed(\$client, \$callback, \$args, \$pt);
		},
		node   => 'myMusic',
		menu   => 'browse',
		weight => $weight,
		type   => 'link',
		icon   => '$icon',
	);
}

sub getDisplayName { '$name' }

sub icon { '$icon' }

sub _pluginDataFor {
	my ( \$class, \$key ) = \@_;

	return \$class->icon if \$key eq 'icon';
	
	return \$class->SUPER::_pluginDataFor(\$key);
}

1;
	};

	eval $code;
	if ( $@ ) {
		logError( "Unable to dynamically create radio class $subclass: $@" );
		next;
	}

	$subclass = "${package}::${subclass}";

	$subclass->initPlugin();
}

# transform genre_id/artist_id into real IDs if a text is used (eg. "Various Artists")
sub valueToId {
	my ($class, $value, $key) = @_;
	
	return (defined $value ? $value : 0) unless $value && $key =~ /^(genre|artist)_id/;
	
	my $category = $1;
	
	my $schema;
	if ($category eq 'genre') {
		$schema = 'Genre';
	}
	elsif ($category eq 'artist') {
		$schema = 'Contributor';
	}
	
	# replace artist name with ID
	if ( $schema && Slim::Schema::hasLibrary() && !Slim::Schema->rs($schema)->find($value) 
		&& (my $item = Slim::Schema->rs($schema)->search({ 'name' => $value })->first) ) 
	{
		$value = $item->id;
	}
	
	return $value;
}	

1;