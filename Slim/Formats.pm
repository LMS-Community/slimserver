package Slim::Formats;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Class::Data::Inheritable);

use Audio::Scan;

use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;

# Map our tag functions - so they can be dynamically loaded.
our (%tagClasses, %loadedTagClasses);

my $init = 0;
my $log  = logger('formats');

=head1 NAME

Slim::Formats

=head1 SYNOPSIS

my $tags = Slim::Formats->readTags( $file );

=head1 METHODS

=head2 init()

Initialze the Formats/Metadata reading classes and subsystem.

=cut

sub init {
	my $class = shift;

	if ($init) {
		return 1;
	}

	# Our loader classes for tag formats.
	%tagClasses = (
		'mp3' => 'Slim::Formats::MP3',
		'mp2' => 'Slim::Formats::MP3',
		'ogg' => 'Slim::Formats::Ogg',
		'flc' => 'Slim::Formats::FLAC',
		'wav' => 'Slim::Formats::Wav',
		'aif' => 'Slim::Formats::AIFF',
		'wma' => 'Slim::Formats::WMA',
		'wmap' => 'Slim::Formats::WMA',
		'wmal' => 'Slim::Formats::WMA',
		'alc' => 'Slim::Formats::Movie',
		'aac' => 'Slim::Formats::Movie',
		'mp4' => 'Slim::Formats::Movie',
		'sls' => 'Slim::Formats::Movie',
		'shn' => 'Slim::Formats::Shorten',
		'mpc' => 'Slim::Formats::Musepack',
		'ape' => 'Slim::Formats::APE',
		'wvp' => 'Slim::Formats::WavPack',
		'ogf' => 'Slim::Formats::OggFLAC',

		# Playlist types
		'asx' => 'Slim::Formats::Playlists::ASX',
		'cue' => 'Slim::Formats::Playlists::CUE',
		'm3u' => 'Slim::Formats::Playlists::M3U',
		'pls' => 'Slim::Formats::Playlists::PLS',
		'pod' => 'Slim::Formats::Playlists::XML',
		'wax' => 'Slim::Formats::Playlists::ASX',
		'wpl' => 'Slim::Formats::Playlists::WPL',
		'xml' => 'Slim::Formats::Playlists::XML',
		'xpf' => 'Slim::Formats::Playlists::XSPF',
	);

	if ($Audio::Scan::VERSION =~ /^0\.9[45]$/) {
		$tagClasses{'dff'} = 'Slim::Formats::DFF';
		$tagClasses{'dsf'} = 'Slim::Formats::DSF';
	}

	$init = 1;

	return 1;
}

=head2 loadTagFormatForType( $type )

Dynamically load the class needed to read the passed file type. 

Returns true on success, false on failure.

Example: Slim::Formats->loadTagFormatForType('flc');

=cut

sub loadTagFormatForType {
	my ( $class, $type ) = @_;
	
	return 1 if $loadedTagClasses{$type};
	
	eval "use $tagClasses{$type}";
	
	if ( $@ ) {
		logBacktrace("Couldn't load module: $tagClasses{$type} ($type) : [$@]");
		return 0;
	}
	
	$loadedTagClasses{$type} = 1;
	
	return 1;
}

=head2 classForFormat( $type )

Returns the class associated with the passed file type.

=cut

sub classForFormat {
	my $class = shift;
	my $type  = shift;

	$class->init;

	return $tagClasses{$type};
}

=head2 readTags( $filename )

Read and return the tags for any file we're handed.

=cut

my %tagCache;

sub readTags {
	my $class = shift;
	my $file  = shift || return {};

	my $isDebug = main::DEBUGLOG && $log->is_debug;

	my ($filepath, $tags, $anchor);

	if (Slim::Music::Info::isFileURL($file)) {
		$filepath = Slim::Utils::Misc::pathFromFileURL($file);
		$anchor   = Slim::Utils::Misc::anchorFromURL($file);
	} else {
		$filepath = $file;
	}

	# Get the type without updating the DB
	my $type   = Slim::Music::Info::typeFromPath($filepath);
	my $remote = Slim::Music::Info::isRemoteURL($file);

	# Only read local audio.
	if (Slim::Music::Info::isSong($file, $type) && !$remote) {
		
		# Bug 4402, ignore if the file has gone away
		if ( !-e $filepath ) {
			$log->error("File missing: $filepath");
			return {};
		}

		# Extract tag and audio info per format
		eval {
			if (my $tagReaderClass = $class->classForFormat($type)) {
				if ( !$loadedTagClasses{$type} ) {
					eval "use $tagReaderClass";
					if ( $@ ) {
						logError("Unable to load $tagReaderClass: $@");
						return {};
					}
				}

				($tags, my $ctOverride) = $tagReaderClass->getTag($filepath, $anchor);

				if ($ctOverride) {
					$type = $ctOverride;
				}
				
				$loadedTagClasses{$type} = 1;
			}
		};

		if ($@) {
			logBacktrace("While trying to ->getTag($filepath) : $@");
		}

		if (!defined $tags) {
			main::INFOLOG && $log->is_info && $log->info("No tags found for $filepath");
			return {};
		}

		# Return early if we have a DRM track
		if ($tags->{'DRM'}) {
			return $tags;
		}

		# Turn the tag SET into DISC and DISCC if it looks like # or #/#
		if ($tags->{'SET'} and $tags->{'SET'} =~ /(\d+)(?:\/(\d+))?/) {

			# Strip leading 0s so that numeric compare at the db level works.
			$tags->{'DISC'}  = int($1);
			$tags->{'DISCC'} = int($2) if defined $2;
		}

		if (!defined $tags->{'TITLE'}) {

			main::INFOLOG && $log->is_info && $log->info("No title found, using plain title for $file");

			#$tags->{'TITLE'} = Slim::Music::Info::plainTitle($file, $type);
			Slim::Music::Info::guessTags($file, $type, $tags);
		}

		# Mark it as audio in the database.
		if (!defined $tags->{'AUDIO'}) {

			$tags->{'AUDIO'} = 1;
		}

		# Set some defaults for the track if the tag reader didn't pull them.
		for my $key (qw(DRM LOSSLESS)) {

			$tags->{$key} ||= 0;
		}
	}

	# Last resort
	if (!defined $tags->{'TITLE'} || $tags->{'TITLE'} =~ /^\s*$/) {

		main::INFOLOG && $log->is_info && $log->info("No title found, calculating title from url for $file");

		$tags->{'TITLE'} = Slim::Music::Info::plainTitle($file, $type);
	}

	# Bug 2996 - check for multiple DISC tags.
	if (ref($tags->{'DISC'}) eq 'ARRAY') {

		$tags->{'DISC'} = $tags->{'DISC'}->[0];
	}

	if (-e $filepath) {
		# cache the file size & date
		($tags->{'FILESIZE'}, $tags->{'TIMESTAMP'}) = (stat(_))[7,9];
	}

	# Only set if we couldn't read it from the file.
	$tags->{'CONTENT_TYPE'} ||= $type;

	main::DEBUGLOG && $isDebug && $log->debug("Report for $file:");
	
	# XXX: can Audio::Scan make these regexes unnecessary?
	
	# Bug: 2381 - FooBar2k seems to add UTF8 boms to their values.
	# Bug: 3769 - Strip trailing nulls
	# Bug: 3998 - Strip UTF-16 BOMs from multiple genres (or other values).
	while (my ($tag, $value) = each %{$tags}) {

		if (defined $value) {
			my $original = $value;

			use bytes;
			if ( my $cached = $tagCache{$value} ) {
				$tags->{$tag} = $cached;
				next;

			} elsif (ref($value) eq 'ARRAY') {

				for (my $i = 0; $i < scalar @{$value}; $i++) {

					next unless defined $value->[$i];

					$value->[$i] =~ s/$Slim::Utils::Unicode::bomRE//;
					$value->[$i] =~ s/\000$//;
				}

			} else {

				$value =~ s/$Slim::Utils::Unicode::bomRE//;
				$value =~ s/\000$//;
				$tags->{$tag} = $value;
			}
			
			# Bug 14587, sanity check all MusicBrainz ID tags to ensure it is a UUID and nothing more
			if ( $tag =~ /^MUSICBRAINZ.*ID$/ ) {

				# DiscID has a different format:
				# http://wiki.musicbrainz.org/Disc_ID_Calculation
				if ( $tag eq 'MUSICBRAINZ_DISCID' && $value =~ /^[0-9a-z_\.-]{28}$/i ) {
					$value = lc($1);
				} elsif ( $value =~ /([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i ) {
					$value = lc($1);
				}
				else {
					if ( main::DEBUGLOG && $log->is_debug ) {
						$log->debug("Invalid MusicBrainz tag found in $file: $tag -> $value");
					}
					delete $tags->{$tag};
					next;
				}
				$tags->{$tag} = $value;
			}

			$tagCache{$original} = $value;
		}
		
		main::DEBUGLOG && $isDebug && $value && $log->debug(". $tag : $value");
	}
			
	if (scalar (keys %tagCache) > 50) {
		%tagCache = ();
	}

	return $tags;
}

1;

__END__
