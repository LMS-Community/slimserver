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

		no warnings;

		# Deal with the common parsing problem of unescaped ampersands
		# found in many ASX files on the web.
		$content =~ s/&(?!(#|amp;|quot;|lt;|gt;|apos;))/&amp;/g;

		# Convert all tags to upper case as ASX allows mixed case tags, XML does not!
		$content =~ s{(<[^\s>]+)}{\U$1\E}mg;

		my $parsed = eval {
			# We need to send a ProtocolEncoding option to XML::Parser,
			# but XML::Simple carps at it. Unfortunately, we don't 
			# have a choice - we can't change the XML, as the
			# XML::Simple warning suggests.
			XMLin(\$content, ForceArray => ['ENTRY', 'REF'], ParserOpts => [ ProtocolEncoding => 'ISO-8859-1' ]);
		};

		if ($@) {
			errorMsg("ASX->read: Couldn't parse XML: [$content] - got error: [$@]\n");
			$parsed = {};
		}
		
		$::d_parse && msg("parsing ASX: $file url: [$url]\n");

		my $entries = $parsed->{'ENTRY'} || $parsed->{'REPEAT'}->{'ENTRY'};

		if (!defined $entries || !ref($entries) || scalar @$entries == 0) {

			return @items;
		}

		for my $entry (@$entries) {
			
			my $title = $entry->{'TITLE'};
			my $refs  = $entry->{'REF'};
			my $path  = undef;

			$::d_parse && msg("Found an entry title: $title\n");

			if (defined($refs)) {

				for my $ref (@$refs) {

					my $href = $ref->{'href'} || $ref->{'Href'} || $ref->{'HREF'};
					
					# We've found URLs in ASX files that should be
					# escaped to be legal - specifically, they contain
					# spaces. For now, deal with this specific case.
					# If this seems to happen in other ways, maybe we
					# should URL escape before continuing.
					$href =~ s/ /%20/;

					# Bug 3160 (partial)
					# 'ref' tags refer to audio content, so we need to force
					# the use of the MMS protocol handler by making sure the URI starts with mms
					$href =~ s/^http/mms/;

					if ( $href =~ /^mms/ ) {
						$path = $href;
						last;
					}
				}
			}

			if (defined($path)) {

				$path = Slim::Utils::Misc::fixPath($path, $baseDir);

				if ($class->playlistEntryIsValid($path, $url)) {

					push @items, $class->_updateMetaData( $path, {
						'TITLE' => $title,
					} );
				}
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
