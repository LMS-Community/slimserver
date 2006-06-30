package Slim::Formats::Playlists::WPL;

# $Id$

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
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
use Slim::Utils::Misc;
use Slim::Utils::Unicode;

sub read {
	my ($class, $file, $baseDir, $url) = @_;

	my @items  = ();

	# Handles version 1.0 WPL Windows Medial Playlist files...
	my $content = eval { XMLin($file) };

	if ($@) {
		errorMsg("WPL->read failed to read [$content] got error: [$@]\n");
		$content = {};
	}

	$::d_parse && msg("parsing WPL: $file url: [$url]\n");

	if (exists($content->{'body'}->{'seq'}->{'media'})) {
		
		my @media = ();

		if (ref $content->{'body'}->{'seq'}->{'media'} ne 'ARRAY') {

			push @media, $content->{'body'}->{'seq'}->{'media'};

		} else {

			@media = @{$content->{'body'}->{'seq'}->{'media'}};
		}

		for my $entry_info (@media) {

			my $entry = $entry_info->{'src'};

			$::d_parse && msg("  entry from file: $entry\n");

			$entry = Slim::Utils::Unicode::utf8encode_locale($entry);
			$entry = Slim::Utils::Misc::fixPath($entry, $baseDir);

			if ($class->playlistEntryIsValid($entry, $url)) {

				$::d_parse && msg("    entry: $entry\n");

				push @items, $class->_updateMetaData($entry);
			}
		}
	}

	$::d_parse && msg("parsed " . scalar(@items) . " items in wpl playlist\n");

	return @items;
}

sub write {
	my $class   = shift;
	my $listref = shift;
	my $playlistname = shift || "SlimServer " . Slim::Utils::Strings::string("PLAYLIST");
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
		errorMsg("WPL->write: Couldn't write out [$content] got error: [$@]\n");
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
