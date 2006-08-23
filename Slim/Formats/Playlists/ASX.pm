package Slim::Formats::Playlists::ASX;

# $Id$

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Formats::Playlists::Base);

use File::Slurp;
use XML::Simple;
use URI;

use Slim::Player::ProtocolHandlers;
use Slim::Music::Info;
use Slim::Utils::Misc;

sub read {
	my ($class, $file, $baseDir, $url) = @_;

	my @items   = ();
	my $content  = read_file($file);

	# First try for version 3.0 ASX
	if ($content =~ /<ASX/i) {
		
		# Forget trying to parse this as XML, all we care about are REF and ENTRYREF elements
		$::d_parse && msg("parsing ASX: $file url: [$url]\n");
		
		my @refs      = $content =~ m{<ref\s+href\s*=\s*"([^"]+)"}ig;
		my @entryrefs = $content =~ m{<entryref\s+href\s*=\s*"([^"]+)"}ig;
		
		for my $href ( @refs, @entryrefs ) {
			
			# Bug 3160 (partial)
			# 'ref' tags should refer to audio content, so we need to force
			# the use of the MMS protocol handler by making sure the URI starts with mms
			$href =~ s/^http/mms/;
			
			$::d_parse && msg("Found an entry: $href\n");
			
			# We've found URLs in ASX files that should be
			# escaped to be legal - specifically, they contain
			# spaces. For now, deal with this specific case.
			# If this seems to happen in other ways, maybe we
			# should URL escape before continuing.
			$href =~ s/ /%20/;
			
			$href = Slim::Utils::Misc::fixPath($href, $baseDir);

			if ($class->playlistEntryIsValid($href, $url)) {

				push @items, $class->_updateMetaData($href);
			}
		}
	}

	# Next is version 2.0 ASX
	elsif ($content =~ /[Reference]/) {
		while ($content =~ /^Ref(\d+)=(.*)$/gm) {

			my $entry = URI->new($2);

			# XXX We've found that ASX 2.0 refers to http: URLs, when it
			# really means mms: URLs. Wouldn't it be nice if there were
			# a real spec?
			if ($entry->scheme eq 'http') {
				$entry->scheme('mms');
			}

			if ($class->playlistEntryIsValid($entry->as_string, $url)) {

				push @items, $class->_updateMetaData($entry->as_string);
			}
		}
	}

	# And finally version 1.0 ASX
	else {

		while ($content =~ /^(.*)$/gm) {

			my $entry = $1;

			if ($class->playlistEntryIsValid($entry, $url)) {

				push @items, $class->_updateMetaData($entry);
			}
		}
	}

	$::d_parse && msg("parsed " . scalar(@items) . " items in asx playlist\n");

	return @items;
}

1;

__END__
