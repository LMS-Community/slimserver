package Slim::Formats::Playlists::XML;

# $Id

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.
#
# This is the old Slim::Formats::Parse::readPodCast() code.

use strict;
use base qw(Slim::Formats::Playlists::Base);

use Scalar::Util qw(blessed);

use Slim::Music::Info;
use Slim::Utils::Misc;
use Slim::Utils::Strings;
use Slim::Utils::Unicode;

sub read {
	my ($class, $file, $baseDir, $url) = @_;

	my $xml    = eval { XMLin($file, 'forcearray' => ['item'], 'keyattr' => []) };

	if ($@ || !$xml) {

		$::d_parse && msg("Slim::Formats::Playlists::XML->read: failed to parse XML/Podcast: [$@]\n");

		# TODO: how can we get error message to client?
		return ();
	}

        # Some feeds (slashdot) have items at same level as channel
        my $items  = $xml->{'item'} ? $xml->{'item'} : $xml->{'channel'}->{'item'};
	my @urls   = ();

	for my $item (@$items) {

		my $enclosure = ref($item->{'enclosure'}) eq 'ARRAY' ? $item->{'enclosure'}->[0] : $item->{'enclosure'};

		next if ref($enclosure) ne 'HASH' || $enclosure->{'type'} !~ /audio/i;

		push @urls, $enclosure->{'url'};

		if ($item->{'title'}) {

			# associate a title with the url
			push @items, $class->_updateMetaData($enclosure->{'url'}, $item->{'title'});
		}
	}

	close($file);

	return @urls;
}

1;

__END__

