package Slim::Formats::Playlists::XML;

# $Id

# Logitech Media Server Copyright 2001-2011 Logitech.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.
#
# This is the old Slim::Formats::Parse::readPodCast() code.

use strict;
use base qw(Slim::Formats::Playlists::Base);

use File::Slurp;
use Scalar::Util qw(blessed);

use Slim::Formats::XML;
use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings;
use Slim::Utils::Unicode;

my $log = logger('formats.playlists');

sub read {
	my ($class, $file, $baseDir, $url) = @_;

	main::INFOLOG && $log->info("Parsing: $file");

	my $content = read_file($file);
	my $xml     = Slim::Formats::XML::xmlToHash(\$content);

	if (!$xml) {

		logError("Failed to parse XML/Podcast: [$@]");

		# TODO: how can we get error message to client?
		return ();
	}

	# Some feeds (slashdot) have items at same level as channel
	my $items  = $xml->{'item'} ? $xml->{'item'} : $xml->{'channel'}->{'item'};
	my @urls   = ();

	for my $item (@$items) {

		my $enclosure = ref($item->{'enclosure'}) eq 'ARRAY' ? $item->{'enclosure'}->[0] : $item->{'enclosure'};

		if (ref($enclosure) ne 'HASH' || !defined $enclosure->{'url'} || $enclosure->{'type'} !~ /audio/i) {

			next;
		}

		if ($item->{'title'}) {

			main::DEBUGLOG && $log->debug("Found title for enclosure: [$item->{'title'}]");

			push @urls, $class->_updateMetaData( $enclosure->{'url'}, {
				'TITLE' => $item->{'title'},
			}, $url );

		} else {

			main::DEBUGLOG && $log->debug("Found url for enclosure: [$enclosure->{'url'}]");

			push @urls, $enclosure->{'url'};

		}
	}

	close($file);

	return @urls;
}

1;

__END__

