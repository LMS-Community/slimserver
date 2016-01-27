package Slim::Formats::Playlists::ASX;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# ASX 3.0 official documentation can be found here:
# http://msdn.microsoft.com/en-us/library/bb249663%28VS.85%29.aspx

use strict;
use base qw(Slim::Formats::Playlists::Base);

use File::Slurp;
use XML::Simple;
use URI;

use Slim::Player::ProtocolHandlers;
use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Utils::Misc;

sub read {
	my ($class, $file, $baseDir, $url) = @_;

	my @items   = ();
	my $content = read_file($file);
	my $log     = logger('formats.playlists');

	# First try for version 3.0 ASX
	if ($content =~ /<ASX/i) {
		
		main::INFOLOG && $log->info("Parsing ASX 3.0: $file url: [$url]");
		
		# Deal with the common parsing problem of unescaped ampersands 	 
		# found in many ASX files on the web. 	 
		$content =~ s/&(?!(#|amp;|quot;|lt;|gt;|apos;))/&amp;/g;
		
		# Remove HTML comments
		$content =~ s{<!.*?(--.*?--\s*)+.*?>}{}sgx;
		
		# Convert all tags to upper case as ASX allows mixed case tags, XML does not!
		$content =~ s{(<[^\s>]+)}{\U$1\E}mg;
		$content =~ s/href\s*=/HREF=/ig;
		
		# Change ENTRYREF tags to ENTRY so they stay in the proper order
		$content =~ s/ENTRYREF/ENTRY/g;
		
		# Make sure playlist is UTF-8
		my $encoding = Slim::Utils::Unicode::encodingFromString( $content );
		main::DEBUGLOG && $log->is_debug && $log->debug( "Encoding of ASX playlist: $encoding" );
		
		if ( $encoding ne 'utf8' ) {		
			$content = Slim::Utils::Unicode::utf8decode_guess( $content, $encoding );
		}
		
		my $parsed = eval {
			XMLin(
				\$content,
				ForceArray => [
					'ENTRY',
					'REF',
				],
				SuppressEmpty => undef,
			);
		};
		
		if ( $@ ) {
			$log->error( "Unable to parse ASX playlist:\n$@\n$content" );
			$parsed = {};
		}
		
		my @entries = ();
		
		# Move entry items inside repeat tags
		if ( my $repeat = $parsed->{REPEAT} ) {
			$parsed->{ENTRY} ||= [];
			push @{ $parsed->{ENTRY} }, @{ $repeat->{ENTRY} };
		}
		
		for my $entry ( @{ $parsed->{ENTRY} || [] } ) {
			if ( my $href = $entry->{HREF} ) {
				# It was an entryref tag
				push @entries, {
					href => $href,
				}
			}
			else {
				# It's a normal entry tag
				my $title    = $entry->{TITLE} || $parsed->{TITLE};
				my $author   = $entry->{AUTHOR} || $parsed->{AUTHOR};
				my $duration = $entry->{DURATION};
				my $refs     = $entry->{REF} || [];
			
				for my $ref ( @{$refs} ) {
					if ( my $href = $ref->{HREF} ) {
						next if $href !~ /^(http|mms)/i;
						push @entries, {
							title  => $title,
							author => $author,
							href   => $href,
						};
						
						# XXX: Including multiple ref entries per entry is not exactly
						# correct.  Additional refs here should only be played if the
						# first one fails, but this is difficult to implement in our
						# current architecture.
					}
				}
			}
		}

		my %seenhref = ();
		for my $entry ( @entries ) {
		
			my $title    = $entry->{title};
			my $author   = $entry->{author};
			my $duration = $entry->{duration};
			my $href     = $entry->{href};
			
			if ( ref $title ) {
				$title = undef;
			}
			
			# Ignore .nsc files (multicast streams)
			# and non-HTTP/MMS protocols such as RTSP
			next if $href =~ /\.nsc$/i;
			next if $href !~ /^(http|mms)/i;
			
			# Bug 3160 (partial)
			# 'ref' tags should refer to audio content, so we need to force
			# the use of the MMS protocol handler by making sure the URI starts with mms
			$href =~ s/^http/mms/;
			next if defined ($seenhref{$href}) ;
			$seenhref{$href} = 1;

			main::INFOLOG && $log->info("Found an entry: $href, title ", $title || '');

			# We've found URLs in ASX files that should be
			# escaped to be legal - specifically, they contain
			# spaces. For now, deal with this specific case.
			# If this seems to happen in other ways, maybe we
			# should URL escape before continuing.
			$href =~ s/ /%20/;

			$href = Slim::Utils::Misc::fixPath($href, $baseDir);

			if ($class->playlistEntryIsValid($href, $url)) {
			
				my $secs;
				if ($duration) {
					my @F = split(':', $duration);
					my $secs = $F[-1] + $F[-2] * 60;
					if (@F > 2) {$secs += $F[-3] * 3600;}
				}
				
				push @items, $class->_updateMetaData( $href, {
					TITLE      => $title,
					ARTISTNAME => $author,
					SECS       => $secs,					
				}, $url );
			}
		}
		
		if ( main::DEBUGLOG && $log->is_info ) {
			if ( scalar @items == 0 ) {
				$log->info( "Input ASX we didn't parse:\n$content\n" . Data::Dump::dump($parsed) );
			}
		}
	}

	# Next is version 2.0 ASX
	elsif ($content =~ /\[Reference\]/i) {

		main::INFOLOG && $log->info("Parsing ASX 2.0: $file url: [$url]");

		while ($content =~ /^Ref(\d+)=(.*)$/gm) {

			my $entry = URI->new($2);

			# XXX We've found that ASX 2.0 refers to http: URLs, when it
			# really means mms: URLs. Wouldn't it be nice if there were
			# a real spec?
			if ($entry->scheme eq 'http') {
				$entry->scheme('mms');
			}

			if ($class->playlistEntryIsValid($entry->as_string, $url)) {

				push @items, $class->_updateMetaData($entry->as_string, undef, $url);
			}
		}
	}

	# And finally version 1.0 ASX
	else {

		main::INFOLOG && $log->info("Parsing ASX 1.0: $file url: [$url]");

		while ($content =~ /^(.*)$/gm) {

			my $entry = $1;

			if ($class->playlistEntryIsValid($entry, $url)) {

				push @items, $class->_updateMetaData($entry, undef, $url);
			}
		}
	}

	if ( main::INFOLOG && $log->is_info ) {
		$log->info("parsed " . scalar(@items) . " items out of ASX");
	}		

	return @items;
}

1;

__END__
