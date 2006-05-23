package Slim::Formats::Parse;

# $Id$

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Slim::Formats::Playlists;
use Slim::Utils::Misc;

sub registerParser {

	msg("Warning! - Slim::Formats::Parse::registerParser is deprecated!\n");
	msg("Please update your code to use: Slim::Formats::Playlists->registerParser(\$type, \$playlistClass)\n");
	msg("Make sure your \$playlistClass has a ->read() method, and an optional ->write() method\n");
	bt();
}

sub parseList {

	msg("Warning! - Slim::Formats::Parse::parseList is deprecated!\n");
	msg("Please update your call to be Slim::Formats::Playlists->parseList()\n");
	bt();

	return Slim::Formats::Playlists->parseList(@_);
}

sub writeList {

	msg("Warning! - Slim::Formats::Parse::writeList is deprecated!\n");
	msg("Please update your call to be Slim::Formats::Playlists->writeList()\n");
	bt();

	return Slim::Formats::Playlists->writeList(@_);
}

sub _updateMetaData {

	msg("Warning! - Slim::Formats::Parse::_updateMetaData is deprecated!\n");
	msg("Please update your code to inherit from Slim::Formats::Playlists::Base\n");
	bt();

	return Slim::Formats::Playlists::Base->_updateMetaData(@_);
}

sub readM3U {
	msg("Warning! - Slim::Formats::Parse::readM3U is deprecated!\n");
	msg("Please update your code to call Slim::Formats::Playlists::M3U->read()\n");
	bt();

	return Slim::Formats::Playlists::M3U->read(@_);
}

sub readPLS {
	msg("Warning! - Slim::Formats::Parse::readPLS is deprecated!\n");
	msg("Please update your code to call Slim::Formats::Playlists::PLS->read()\n");
	bt();

	return Slim::Formats::Playlists::PLS->read(@_);
}

sub writeM3U {
	msg("Warning! - Slim::Formats::Parse::writeM3U is deprecated!\n");
	msg("Please update your code to call Slim::Formats::Playlists::M3U->write()\n");
	bt();

	return Slim::Formats::Playlists::M3U->write(@_);
}

sub readWPL {
	my $wplfile = shift;
	my $wpldir  = shift;
	my $url     = shift;

	my @items  = ();

	# Handles version 1.0 WPL Windows Medial Playlist files...
	my $wpl_playlist = {};

	eval {
		$wpl_playlist = XMLin($wplfile);
	};

	$::d_parse && msg("parsing WPL: $wplfile url: [$url]\n");

	if (exists($wpl_playlist->{body}->{seq}->{media})) {
		
		my @media;
		if (ref $wpl_playlist->{body}->{seq}->{media} ne 'ARRAY') {
			push @media, $wpl_playlist->{body}->{seq}->{media};
		} else {
			@media = @{$wpl_playlist->{body}->{seq}->{media}};
		}
		
		for my $entry_info (@media) {

			my $entry=$entry_info->{src};

			$::d_parse && msg("  entry from file: $entry\n");
		
			$entry = Slim::Utils::Misc::fixPath($entry, $wpldir);

			if (playlistEntryIsValid($entry, $url)) {

				$::d_parse && msg("    entry: $entry\n");

				push @items, _updateMetaData($entry, undef);
			}
		}
	}

	$::d_parse && msg("parsed " . scalar(@items) . " items in wpl playlist\n");

	return @items;
}

sub writeWPL {
	my $listref = shift;
	my $playlistname = shift || "SlimServer " . Slim::Utils::Strings::string("PLAYLIST");
	my $filename = shift;

	# Handles version 1.0 WPL Windows Medial Playlist files...

	# Load the original if it exists (so we don't lose all of the extra crazy info in the playlist...
	my $wpl_playlist = {};

	eval {
		$wpl_playlist = XMLin($filename, KeepRoot => 1, ForceArray => 1);
	};

	if($wpl_playlist) {
		# Clear out the current playlist entries...
		$wpl_playlist->{smil}->[0]->{body}->[0]->{seq}->[0]->{media} = [];

	} else {
		# Create a skeleton of the structure we'll need to output a compatible WPL file...
		$wpl_playlist={
			smil => [{
				body => [{
					seq => [{
						media => [
						]
					}]
				}],
				head => [{
					title => [''],
					author => [''],
					meta => {
						Generator => {
							content => '',
						}
					}
				}]
			}]
		};
	}

	for my $item (@{$listref}) {

		if (Slim::Music::Info::isURL($item)) {
			my $url=uri_unescape($item);
			$url=~s/^file:[\/\\]+//;
			push(@{$wpl_playlist->{smil}->[0]->{body}->[0]->{seq}->[0]->{media}},{src => $url});
		}
	}

	# XXX - Windows Media Player 9 has problems with directories,
	# and files that have an &amp; in them...

	# Generate our XML for output...
	# (the ForceArray option when we do "XMLin" makes the hash messy,
	# but ensures that we get the same style of XML layout back on
	# "XMLout")
	my $wplfile = XMLout($wpl_playlist, XMLDecl => '<?wpl version="1.0"?>', RootName => undef);

	my $string;

	my $output = _filehandleFromNameOrString($filename, \$string) || return;
	print $output $wplfile;
	close $output if $filename;

	return $string;
}

sub readASX {
	my $asxfile = shift;
	my $asxdir  = shift;
	my $url     = shift;

	my @items  = ();

	my $asx_playlist={};
	my $asxstr = '';
	while (<$asxfile>) {
		$asxstr .= $_;
	}
	close $asxfile;

	# First try for version 3.0 ASX
	if ($asxstr =~ /<ASX/i) {
		# Deal with the common parsing problem of unescaped ampersands
		# found in many ASX files on the web.
		$asxstr =~ s/&(?!(#|amp;|quot;|lt;|gt;|apos;))/&amp;/g;

		# Convert all tags to upper case as ASX allows mixed case tags, XML does not!
		$asxstr =~ s{(<[^\s>]+)}{\U$1\E}mg;

		eval {
			# We need to send a ProtocolEncoding option to XML::Parser,
			# but XML::Simple carps at it. Unfortunately, we don't 
			# have a choice - we can't change the XML, as the
			# XML::Simple warning suggests.
			no warnings;
			$asx_playlist = XMLin($asxstr, ForceArray => ['ENTRY', 'REF'], ParserOpts => [ ProtocolEncoding => 'ISO-8859-1' ]);
		};
		
		$::d_parse && msg("parsing ASX: $asxfile url: [$url]\n");

		my $entries = $asx_playlist->{ENTRY} || $asx_playlist->{REPEAT}->{ENTRY};

		if (defined($entries)) {

			for my $entry (@$entries) {
				
				my $title = $entry->{TITLE};

				$::d_parse && msg("Found an entry title: $title\n");

				my $path;
				my $refs = $entry->{REF};

				if (defined($refs)) {

					for my $ref (@$refs) {

						my $href = $ref->{href} || $ref->{Href} || $ref->{HREF};
						
						# We've found URLs in ASX files that should be
						# escaped to be legal - specifically, they contain
						# spaces. For now, deal with this specific case.
						# If this seems to happen in other ways, maybe we
						# should URL escape before continuing.
						$href =~ s/ /%20/;

						my $url = URI->new($href);

						$::d_parse && msg("Checking if we can handle the url: $url\n");
						
						my $scheme = $url->scheme();

						if ($scheme =~ s/^mms(.?)/mms/) {
							$url->scheme($scheme);
							$href = $url->as_string();
						}

						if (exists $Slim::Player::Source::protocolHandlers{lc $scheme}) {

							$::d_parse && msg("Found a handler for: $url\n");
							$path = $href;
							last;
						}
					}
				}
				
				if (defined($path)) {

					$path = Slim::Utils::Misc::fixPath($path, $asxdir);

					if (playlistEntryIsValid($path, $url)) {

						push @items, _updateMetaData($path, $title);
					}
				}
			}
		}
	}

	# Next is version 2.0 ASX
	elsif ($asxstr =~ /[Reference]/) {
		while ($asxstr =~ /^Ref(\d+)=(.*)$/gm) {

			my $entry = URI->new($2);

			# XXX We've found that ASX 2.0 refers to http: URLs, when it
			# really means mms: URLs. Wouldn't it be nice if there were
			# a real spec?
			if ($entry->scheme eq 'http') {
				$entry->scheme('mms');
			}

			if (playlistEntryIsValid($entry->as_string, $url)) {

				push @items, _updateMetaData($entry->as_string);
			}
		}
	}

	# And finally version 1.0 ASX
	else {
		while ($asxstr =~ /^(.*)$/gm) {

			my $entry = $1;

			if (playlistEntryIsValid($entry, $url)) {

				push @items, _updateMetaData($entry);
			}
		}
	}

	$::d_parse && msg("parsed " . scalar(@items) . " items in asx playlist\n");

	return @items;
}

sub readPodcast {
	my $in = shift;

	#$::d_parse && msg("Parsing podcast...\n");

	my @urls = ();

	# async http request succeeded.  Parse XML
	# forcearray to treat items as array,
	# keyattr => [] prevents id attrs from overriding
	my $xml = eval { XMLin($in, forcearray => ["item"], keyattr => []) };

	if ($@) {
		$::d_parse && msg("Parse: failed to parse podcast because:\n$@\n");
		# TODO: how can we get error message to client?
		return undef;
	}

	# some feeds (slashdot) have items at same level as channel
	my $items;
	if ($xml->{item}) {
		$items = $xml->{item};
	} else {
		$items = $xml->{channel}->{item};
	}

	for my $item (@$items) {
		my $enclosure = $item->{enclosure};

		if (ref $enclosure eq 'ARRAY') {
			$enclosure = $enclosure->[0];
		}

		if ($enclosure) {
			if ($enclosure->{type} =~ /audio/) {
				push @urls, $enclosure->{url};
				if ($item->{title}) {
					# associate a title with the url
					# XXX calling routine beginning with "_"
					Slim::Formats::Parse::_updateMetaData($enclosure->{url}, $item->{title});
				}
			}
		}
	}

	# it seems like the caller of this sub should be the one to close,
	# since they openned it.  But I'm copying other read routines
	# which call close at the end.
	close $in;

	return @urls;
}

sub _pathForItem {
	my $item = shift;

	if (Slim::Music::Info::isFileURL($item) && !Slim::Music::Info::isFragment($item)) {
		return Slim::Utils::Misc::pathFromFileURL($item);
	}

	return $item;
}

sub _filehandleFromNameOrString {
	my $filename  = shift;
	my $outstring = shift;

	my $output;

	if ($filename) {

		$output = FileHandle->new($filename, "w") || do {
			msg("Could not open $filename for writing.\n");
			return undef;
		};

		# Always write out in UTF-8 with a BOM.
		if ($] > 5.007) {

			binmode($output, ":raw");

			print $output $File::BOM::enc2bom{'utf8'};

			binmode($output, ":encoding(utf8)");
		}

	} else {

		$output = IO::String->new($$outstring);
	}

	return $output;
}

sub playlistEntryIsValid {
	my ($entry, $url) = @_;

	my $caller = (caller(1))[3];

	if (Slim::Music::Info::isRemoteURL($entry)) {

		return 1;
	}

	# Be verbose to the user - this will let them fix their files / playlists.
	if ($entry eq $url) {

		msg("$caller:\nWARNING:\n\tFound self-referencing playlist in:\n\t$entry == $url\n\t - skipping!\n\n");
		return 0;
	}

	if (!Slim::Music::Info::isFile($entry)) {

		msg("$caller:\nWARNING:\n\t$entry found in playlist:\n\t$url doesn't exist on disk - skipping!\n\n");
		return 0;
	}

	return 1;
}

1;

__END__
