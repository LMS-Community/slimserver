package Slim::Plugin::ExtendedBrowseModes::Libraries;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Music::VirtualLibraries;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

use constant AUDIOBOOK_LIBRARY_ID => 'audioBooks';

my $prefs = preferences('plugin.extendedbrowsemodes');

sub initPlugin {
	Slim::Music::Import->addImporter( shift, {
		type   => 'post',
		use    => 1,
		weight => 90,		# must be smaller than VirtualLibrary!
	} );
}

sub startScan {
	my ($class) = @_;
	$class->initLibraries();
	Slim::Music::Import->endImporter($class);
}

sub initLibraries {
	my ($class) = @_;

	if ( $prefs->get('enableLosslessPreferred') ) {
		Slim::Music::VirtualLibraries->registerLibrary({
			id     => 'losslessPreferred',
			name   => string('PLUGIN_EXTENDED_BROWSEMODES_LOSSLESS_PREFERRED'),
			string => 'PLUGIN_EXTENDED_BROWSEMODES_LOSSLESS_PREFERRED',
			sql    => qq{
				INSERT OR IGNORE INTO library_track (library, track)
					SELECT '%s', tracks.id
					FROM tracks, albums
					WHERE albums.id = tracks.album
					AND (
						tracks.lossless
						OR 1 NOT IN (
							SELECT 1
							FROM tracks other
							JOIN albums otheralbums ON other.album
							WHERE other.title = tracks.title
							AND other.lossless
							AND other.primary_artist = tracks.primary_artist
							AND other.tracknum = tracks.tracknum
							AND other.year = tracks.year
							AND otheralbums.title = albums.title
						)
					)
			}
		});
	}

	if ( $prefs->get('enableAudioBooks') ) {
		my $ids = $class->valueToId($prefs->get('audioBooksGenres'), 'genre_id');

		Slim::Music::VirtualLibraries->registerLibrary({
			id     => AUDIOBOOK_LIBRARY_ID,
			name   => string('PLUGIN_EXTENDED_BROWSEMODES_AUDIOBOOKS'),
			string => 'PLUGIN_EXTENDED_BROWSEMODES_AUDIOBOOKS',
			ignoreOnlineArtists => 1,
			sql    => qq{
				INSERT OR IGNORE INTO library_track (library, track)
					SELECT '%s', tracks.id
					FROM tracks, genre_track
					WHERE genre_track.track = tracks.id
					AND genre_track.genre IN ($ids)
			}
		});

		Slim::Music::VirtualLibraries->registerLibrary({
			id     => 'noAudioBooks',
			name   => string('PLUGIN_EXTENDED_BROWSEMODES_NO_AUDIOBOOKS'),
			string => 'PLUGIN_EXTENDED_BROWSEMODES_NO_AUDIOBOOKS',
			sql    => qq{
				INSERT OR IGNORE INTO library_track (library, track)
					SELECT '%s', tracks.id
					FROM tracks, genre_track
					WHERE genre_track.track = tracks.id
					AND genre_track.genre NOT IN ($ids)
			}
		});
	}
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
			$_ = Slim::Utils::Text::ignoreCase($_, 1);

			if ( !Slim::Schema->rs($schema)->find($_) && (my $item = Slim::Schema->rs($schema)->search({ 'namesearch' => $_ })->first) ) {
				$_ = $item->id;
			}

			$_;
		} split(/,/, $value) );
	}

	return $value || -1;
}

1;