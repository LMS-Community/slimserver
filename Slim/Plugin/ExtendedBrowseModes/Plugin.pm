package Slim::Plugin::ExtendedBrowseModes::Plugin;

# Logitech Media Server Copyright 2001-2014 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Menu::BrowseLibrary;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings;
use Slim::Utils::Text;

my $prefs = preferences('plugin.extendedbrowsemodes');
my $serverPrefs = preferences('server');

$prefs->init({
	additionalMenuItems => [{
		name    => Slim::Utils::Strings::string('PLUGIN_EXTENDED_BROWSEMODES_BROWSE_BY_COMPOSERS'),
		params  => { role_id => 'COMPOSER' },
		feed    => 'artists',
		icon    => 'html/images/artists.png',
		id      => 'myMusicArtistsComposers',
		weight  => 12,
		enabled => 0,
	},{
		name    => 'Classical Music by Conductor',
		params  => { role_id => 'CONDUCTOR', genre_id => 'Classical' },
		feed    => 'artists',
		icon    => 'html/images/artists.png',
		id      => 'myMusicArtistsConductors',
		weight  => 13,
		enabled => 0,
	},{
		name    => 'Jazz Composers',
		params  => { role_id => 'COMPOSER', genre_id => 'Jazz' },
		feed    => 'artists',
		icon    => 'html/images/artists.png',
		id      => 'myMusicArtistsJazzComposers',
		weight  => 13,
		enabled => 0,
	},{
		name    => 'Audiobooks',
		params  => { genre_id => 'Audiobooks, Spoken, Speech' },
		feed    => 'albums',
		icon    => 'html/images/albums.png',
		id      => 'myMusicAudiobooks',
		weight  => 14,
		enabled => 0,
	}]
});

$prefs->setChange( \&initMenus, 'additionalMenuItems' );

sub initPlugin {
	my ( $class ) = @_;

	if ( main::WEBUI ) {
		require Slim::Plugin::ExtendedBrowseModes::Settings;
		Slim::Plugin::ExtendedBrowseModes::Settings->new;
	}
	
	$class->registerBrowseMode({
		name    => 'PLUGIN_EXTENDED_BROWSEMODES_COMPILATIONS',
		params  => { artist_id => Slim::Music::Info::variousArtistString() },
		feed    => 'albums',
		icon    => 'html/images/albums.png',
		id      => 'myMusicAlbumsVariousArtists',
		weight  => 22,
	});

	$class->initMenus();
}

sub initMenus {
	foreach (@{$prefs->get('additionalMenuItems') || []}) {
		next if $_->{id} =~ /AlbumArtists/;

		# remove menu item before adding it back in - we might have changed its definition
		Slim::Menu::BrowseLibrary->deregisterNode($_->{id});
		$serverPrefs->set('disabled_' . $_->{id}, $_->{enabled} ? 0 : 1);
		
		__PACKAGE__->registerBrowseMode($_);
	}
}

sub registerBrowseMode {
	my ($class, $item) = @_;
	
	# create string token if it doesn't exist already
	my $nameToken = $class->registerCustomString($item->{name});

	# replace feed placeholders
	my $feed = \&Slim::Menu::BrowseLibrary::_artists;
	if ( $item->{feed} =~ /\balbums$/ ) {
		$feed = \&Slim::Menu::BrowseLibrary::_albums;
	}
	
	my %params = map {
		$_ => Slim::Plugin::ExtendedBrowseModes::Plugin->valueToId($item->{params}->{$_}, $_)
	} keys %{$item->{params}};
	
	Slim::Menu::BrowseLibrary->registerNode({
		type         => 'link',
		name         => $nameToken,
		params       => {
			mode => $item->{feed},
			%params,
		},
		feed         => $feed,
		icon         => $item->{icon},
		jiveIcon     => $item->{icon},
		homeMenuText => $nameToken,
		condition    => $item->{condition} || \&Slim::Menu::BrowseLibrary::isEnabledNode,
		id           => $item->{id},
		weight       => $item->{weight},
	});
}

sub registerCustomString {
	my ($class, $string) = @_;
	
	if ( !Slim::Utils::Strings::stringExists($string) ) {
		my $token = Slim::Utils::Text::ignoreCaseArticles($string, 1);
		
		$token =~ s/\s/_/g;
		$token = 'PLUGIN_EXTENDED_BROWSEMODES_' . $token;
		 
		Slim::Utils::Strings::storeExtraStrings([{
			strings => { EN => $string},
			token   => $token,
		}]);

		return $token;
	}
	
	return $string;
}

# transform genre_id/artist_id into real IDs if a text is used (eg. "Various Artists")
sub valueToId {
	my ($class, $value, $key) = @_;
	
	if ($key eq 'role_id') {
		return join(',', grep {
			$_ !~ /\D/
		} map {
			s/^\s+|\s+$//g; 
			uc($_);
			Slim::Schema::Contributor->typeToRole($_);
		} split(/,/, $value) );
	}
	
	return (defined $value ? $value : 0) unless $value && $key =~ /^(genre|artist)_id/;
	
	my $category = $1;
	
	my $schema;
	if ($category eq 'genre') {
		$schema = 'Genre';
	}
	elsif ($category eq 'artist') {
		$schema = 'Contributor';
	}
	
	# replace names with IDs
	if ( $schema && Slim::Schema::hasLibrary() ) {
		$value = join(',', grep {
			$_ !~ /\D/
		} map {
			s/^\s+|\s+$//g; 

			$_ = Slim::Utils::Unicode::utf8decode_locale($_);
			$_ = Slim::Utils::Text::ignoreCaseArticles($_, 1);
			
			if ( !Slim::Schema->rs($schema)->find($_) && (my $item = Slim::Schema->rs($schema)->search({ 'namesearch' => $_ })->first) ) {
				$_ = $item->id;
			}
			
			$_;
		} split(/,/, $value) );
	}

	return $value || -1;
}	

1;