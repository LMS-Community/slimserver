package Slim::Formats::Playlists::WPL;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Formats::Playlists::Base);

use Scalar::Util qw(blessed);
use XML::Simple;
use URI::Escape;

use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;

my $log     = logger('formats.playlists');

sub read {
	my ($class, $file, $baseDir, $url) = @_;

	my @items = ();

	main::INFOLOG && $log->info("Parsing: $file ($url)");

	# Handles version 1.0 WPL Windows Medial Playlist files...
	my $content = eval { XMLin($file) };

	if ($@) {

		logError("Failed to read [$content] got error: [$@]");
		$content = {};
	}

	if (exists($content->{'body'}->{'seq'}->{'media'})) {
		
		my @media = ();

		if (ref $content->{'body'}->{'seq'}->{'media'} ne 'ARRAY') {

			push @media, $content->{'body'}->{'seq'}->{'media'};

		} else {

			@media = @{$content->{'body'}->{'seq'}->{'media'}};
		}

		for my $entry_info (@media) {

			my $entry = $entry_info->{'src'};

			main::DEBUGLOG && $log->debug("  entry from file: $entry");

			if (main::ISWINDOWS) {
				$entry = Win32::GetANSIPathName($entry);	
			}
			else {
				$entry = Slim::Utils::Unicode::encode_locale($entry);	
			}

			$entry = Slim::Utils::Misc::fixPath($entry, $baseDir);

			if ($class->playlistEntryIsValid($entry, $url)) {

				main::DEBUGLOG && $log->debug("    entry: $entry");

				push @items, $class->_updateMetaData($entry, undef, $url);
			}
		}
	}

	if ( main::INFOLOG && $log->is_info ) {
		$log->info("Parsed " . scalar(@items) . " items from WPL");
	}

	return @items;
}

sub write {
	my $class   = shift;
	my $listref = shift;
	my $playlistname = shift || "Squeezebox " . Slim::Utils::Strings::string("PLAYLIST");
	my $filename = shift;

	# Handles version 1.0 WPL Windows Medial Playlist files...

	# Load the original if it exists (so we don't lose all of the extra crazy info in the playlist...
	my $content = eval { XMLin($filename, KeepRoot => 1, ForceArray => 1) };

	if ($content && ref($content) eq 'HASH') {

		# Clear out the current playlist entries...
		$content->{'smil'}->[0]->{'body'}->[0]->{'seq'}->[0]->{'media'} = [];

	} else {

		# Create a skeleton of the structure we'll need to output a compatible WPL file...
		$content = {
			'smil' => [{
				'body' => [{ 'seq' => [{ 'media' => [] }] }],

				'head' => [{
					'title'  => [''],
					'author' => [''],
					'meta'   => {
						'Generator' => {
							'content' => '',
						}
					}
				}]
			}]
		};
	}

	for my $item (@{$listref}) {

		if (Slim::Music::Info::isURL($item)) {

			my $url = uri_unescape($item);
			   $url = ~s/^file:[\/\\]+//;

			push(@{$content->{'smil'}->[0]->{'body'}->[0]->{'seq'}->[0]->{'media'}}, { 'src' => $url });
		}
	}

	# XXX - Windows Media Player 9 has problems with directories,
	# and files that have an &amp; in them...
	#
	# Generate our XML for output...
	# (the ForceArray option when we do "XMLin" makes the hash messy,
	# but ensures that we get the same style of XML layout back on "XMLout")
	my $xml = eval { XMLout($content, 'XMLDecl' => '<?wpl version="1.0"?>', 'RootName' => undef) };

	if ($@) {

		logError("Couldn't write out [$content] got error: [$@]");
		return undef;
	}

	my $string;

	my $output = $class->_filehandleFromNameOrString($filename, \$string) || return;
	print $output $xml;
	close($output) if $filename;

	return $string;
}

1;

__END__
