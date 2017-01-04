package Slim::Music::TitleFormatter;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Music::TitleFormatter

=head1 DESCRIPTION

L<Slim::Music::TitleFormatter>

=cut

use strict;

use Scalar::Util qw(blessed);
use File::Spec::Functions qw(splitpath);

use Slim::Music::Info;
use Slim::Utils::DateTime;
use Slim::Utils::Log;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Unicode;

our ($elemstring, @elements, $elemRegex, %parsedFormats, $nocacheRegex, @noCache, %formatCache, $externalFormats);

my $log = logger('database.info');

sub init {

	%parsedFormats = ();

	# for relating track attributes to album/artist attributes
	my @trackAttrs = ();
	
	require Slim::Schema::Track;

	# Subs for all regular track attributes
	for my $attr (keys %{Slim::Schema::Track->attributes}) {

		$parsedFormats{uc($attr)} = sub {

			if ( ref $_[0] eq 'HASH' ) {
				return $_[0]->{ lc($attr) } || $_[0]->{ 'tracks.' . lc($attr) } || '';
			}
			
			my $output = $_[0]->get_column($attr);
			return (defined $output ? $output : '');
		};
	}
	
	# localize content type where possible
	$parsedFormats{'CT'} = sub {
		my $output = $parsedFormats{'CONTENT_TYPE'}->(@_);
		
		if (!$output && ref $_[0] eq 'HASH' ) {
			$output = $_[0]->{ct} || $_[0]->{ 'tracks.ct' } || '';
		}
		
		$output = Slim::Utils::Strings::getString( uc($output) ) if $output;
		
		return $output;
	};

	# Override album
	$parsedFormats{'ALBUM'} = sub {
		
		if ( ref $_[0] eq 'HASH' ) {
			return $_[0]->{album} || $_[0]->{'albums.title'} || '';
		}

		my $output = '';
		$output = $_[0]->albumname();
		$output = '' if !defined($output) || $output eq string('NO_ALBUM');

		return (defined $output ? $output : '');
	};

	# add album related
	$parsedFormats{'ALBUMSORT'} = sub {
		
		if ( ref $_[0] eq 'HASH' ) {
			return $_[0]->{albumsort} || $_[0]->{'albums.titlesort'} || '';
		}

		my $output = '';
		my $album  = $_[0]->album();

		if ($album) {
			$output = $album->namesort;
		}

		return (defined $output ? $output : '');
	};

	$parsedFormats{'DISCC'} = sub {
		
		if ( ref $_[0] eq 'HASH' ) {
			return $_[0]->{discc} || $_[0]->{'albums.discc'} || '';
		}

		my $output = '';
		my $album = $_[0]->album();
		if ($album) {
			my $discc = $album->get('discc');
			# suppress disc counts of 1 or less
			$output = $discc && $discc > 1 ? $discc : '';
		}
		return (defined $output ? $output : '');
	};

	$parsedFormats{'DISC'} = sub {
		
		if ( ref $_[0] eq 'HASH' ) {
			return $_[0]->{disc} || $_[0]->{'tracks.disc'} || '';
		}

		my $disc = $_[0]->disc;

		if ($disc && $disc == 1) {
			
			my $albumDiscc_sth = Slim::Schema->dbh->prepare_cached("SELECT discc FROM albums WHERE id = ?");

			$albumDiscc_sth->execute($_[0]->albumid);

			my ($discc) = $albumDiscc_sth->fetchrow_array;
			$albumDiscc_sth->finish;

			# suppress disc when only 1 disc in set
			if (!$discc || $discc < 2) {
				$disc = '';
			}
		}

		return ($disc ? $disc : '');
	};

	# add artist related
	$parsedFormats{'ARTIST'} = sub {
		
		if ( ref $_[0] eq 'HASH' ) {
			return $_[0]->{artist} || $_[0]->{albumartist} || $_[0]->{trackartist} || $_[0]->{'contributors.name'} || '';
		}

		my @output  = ();

		for my $artist ($_[0]->artists) {

			my $name = $artist->get_column('name');

			next if $name eq string('NO_ARTIST');

			push @output, $name;
		}
		
		# Bug 12162: cope with objects that only have artistName and no artists
		if (!(scalar @output) && $_[0]->can('artistName')) {
			my $name = $_[0]->artistName();
			if ($name && $name ne string('NO_ARTIST')) {
				push @output, $name;
			}
		}

		return (scalar @output ? join(' & ', @output) : '');
	};

	$parsedFormats{'ARTISTSORT'} = sub {
		
		if ( ref $_[0] eq 'HASH' ) {
			return $_[0]->{artistsort} || $_[0]->{'contributors.titlesort'} || '';
		}

		my @output  = ();
		my @artists = $_[0]->artists;

		for my $artist (@artists) {

			my $name = $artist->get_column('namesort');

			next if $name eq Slim::Utils::Text::ignoreCaseArticles(string('NO_ARTIST'));

			push @output, $name;
		}

		return (scalar @output ? join(' & ', @output) : '');
	};

	# add other contributors
	for my $attr (qw(composer conductor band)) {

		$parsedFormats{uc($attr)} = sub {
			
			if ( ref $_[0] eq 'HASH' ) {
				return $_[0]->{$attr} || '';
			}

			my $output = '';
			
			eval {
				my ($item) = $_[0]->$attr();
	
				if ($item) {
					$output = $item->name();
				}
			};

			return (defined $output ? $output : '');
		};
	}

	# add genre
	$parsedFormats{'GENRE'} = sub {
		
		if ( ref $_[0] eq 'HASH' ) {
			return $_[0]->{genre} || $_[0]->{'genres.name'} || '';
		}

		my $output = '';
		my ($item) = $_[0]->genre();

		if ($item) {
			$output = $item->name();
			$output = '' if $output eq string('NO_GENRE');
		}

		return (defined $output ? $output : '');
	};

	# add comment
	$parsedFormats{uc('COMMENT')} = sub {
		if ( ref $_[0] eq 'HASH' ) {
			return $_[0]->{comment} || $_[0]->{'tracks.comment'} || '';
		}

		my $output = $_[0]->comment();
		return (defined $output ? $output : '');
	};

	# duration - already formatted for local tracks, but often seconds only for remote tracks
	$parsedFormats{'DURATION'} = sub {
		if ( ref $_[0] eq 'HASH' ) {
			my $duration = $_[0]->{duration} || $_[0]->{'tracks.duration'} || $_[0]->{'secs'} || '';
			
			# format if we got a number only
			return sprintf('%s:%02s', int($duration / 60), $duration % 60) if $duration * 1 eq $duration;
			return $duration;
		}

		my $output = $_[0]->duration();
		return (defined $output ? $output : '');
	};

	# dito for bitrate: format if needed
	$parsedFormats{BITRATE} = sub {
		if ( ref $_[0] eq 'HASH' ) {
			my $bitrate = $_[0]->{bitrate} || $_[0]->{'tracks.bitrate'} || '';

			if ( $bitrate * 1 eq $bitrate ) {
				# assume we're dealing with bits vs. kb if number is larger than 5000 (should cover hires)
				$bitrate /= 1000 if $bitrate > 5000;
				$bitrate = sprintf('%d%s', $bitrate, string('KBPS'));
			}

			return $bitrate || '';
		}

		return Slim::Music::Info::getCurrentBitrate($_[0]->url) || $_[0]->prettyBitRate;
	};
	
	# add file info
	$parsedFormats{'VOLUME'} = sub {
		
		if ( ref $_[0] eq 'HASH' ) {
			return $_[0]->{volume} || '';
		}

		my $output = '';
		my $url = $_[0]->get('url');

		if ($url) {

			if (Slim::Music::Info::isFileURL($url)) {
				$url = Slim::Utils::Misc::pathFromFileURL($url);
			}

			$output = (splitpath($url))[0];
		}

		return (defined $output ? $output : '');
	};

	$parsedFormats{'PATH'} = sub {
		
		if ( ref $_[0] eq 'HASH' ) {
			return $_[0]->{path} || '';
		}

		my $output = '';
		my $url = $_[0]->get('url');

		if ($url) {

			if (Slim::Music::Info::isFileURL($url)) {
				$url = Slim::Utils::Misc::pathFromFileURL($url);
			}

			$output = (splitpath($url))[1];
		}

		return (defined $output ? $output : '');
	};

	$parsedFormats{'FILE'} = sub {
		
		my $url;
		if ( ref $_[0] eq 'HASH' ) {
			if ( $_[0]->{url} ) {
				$url = $_[0]->{url};
			}
			else {
				return $_[0]->{file} || '';
			}
		}
		else {
			$url = $_[0]->get('url');
		}

		my $output = '';

		if ($url) {

			if (Slim::Music::Info::isFileURL($url)) {
				$url = Slim::Utils::Misc::pathFromFileURL($url);
			}

			$output = (splitpath($url))[2];
			$output =~ s/\.[^\.]*?$//;
		}

		return (defined $output ? $output : '');
	};

	$parsedFormats{'EXT'} = sub {
		
		if ( ref $_[0] eq 'HASH' ) {
			return $_[0]->{ext} || '';
		}
		
		my $output = '';
		my $url = $_[0]->get('url');

		if ($url) {

			if (Slim::Music::Info::isFileURL($url)) {
				$url = Slim::Utils::Misc::pathFromFileURL($url);
			}

			my $file = (splitpath($url))[2];
			($output) = $file =~ /\.([^\.]*?)$/;
		}

		return (defined $output ? $output : '');
	};

	# Add date/time elements
	$parsedFormats{'LONGDATE'}  = sub {
		return Slim::Utils::DateTime::longDateF(); 
	};
	
	$parsedFormats{'SHORTDATE'} = sub {
		return Slim::Utils::DateTime::shortDateF();
	};
	
	$parsedFormats{'CURRTIME'}  = sub {
		return Slim::Utils::DateTime::timeF();
	};
	
	# Add localized from/by
	$parsedFormats{'FROM'} = sub { return string('FROM'); };
	$parsedFormats{'BY'}   = sub { return string('BY'); };

	# fill element related variables
	@elements = keys %parsedFormats;

	# add placeholder element for bracketed items
	push @elements, '_PLACEHOLDER_';

	$elemstring = join "|", @elements;
	$elemRegex  = qr/$elemstring/;

	# Add lightweight FILE.EXT format
	$parsedFormats{'FILE.EXT'} = sub {
		
		if ( ref $_[0] eq 'HASH' ) {
			return $_[0]->{'file.ext'} || '';
		}

		my $output = '';
		my $url = $_[0]->get('url');

		if ($url) {

			if (Slim::Music::Info::isFileURL($url)) {
				$url = Slim::Utils::Misc::pathFromFileURL($url);
			}

			$output = (splitpath($url))[2];
		}

		return (defined $output ? $output : '');
	};

	# Define built in formats which should not be cached
	@noCache = qw( LONGDATE SHORTDATE CURRTIME );

	my $nocache = join "|", @noCache;
	$nocacheRegex = qr/$nocache/;

	return 1;
}

# This does not currently have any callers in the Logitech Media Server tree.
sub addFormat {
	my $format = shift;
	my $formatSubRef = shift;
	my $nocache = shift;

	my ($package) = caller();
	$externalFormats->{$format}++ if $package !~ /^Slim/;
	
	# only add format if it is not already defined
	if (!defined $parsedFormats{$format}) {

		$parsedFormats{$format} = $formatSubRef;

		main::DEBUGLOG && $log->debug("Format $format added.");

		if ($format !~ /\W/) {
			# format is a single word, so make it an element
			push @elements, $format;
			$elemstring = join "|", @elements;
			$elemRegex = qr/$elemstring/;
		}

		if ($nocache) {
			# format must not be cached per track
			push @noCache, $format;
			my $nocache = join "|", @noCache;
			$nocacheRegex = qr/$nocache/;
		}

	} else {

		main::DEBUGLOG && $log->debug("Format $format already exists.");
	}

	return 1;
}

# some 3rd party plugins register their own format handlers
# this method can tell a caller whether we have such external formatters
sub externalFormats {
	return [ keys %$externalFormats ];
}

my %endbrackets = (
	'(' => qr/(.+?)(\))/,
	'[' => qr/(.+?)(\])/,
	'{' => qr/(.+?)(\})/,
	'"' => qr/(.+?)(")/, # " # syntax highlighters are easily confused
	"'" => qr/(.+?)(')/, # ' # syntax highlighters are easily confused
);

my $bracketstart = qr/(.*?)([{[("'])/; # '" # syntax highlighters are easily confused

# The _fillFormat routine takes a track and references to parsed data arrays describing
# a desired information format and returns a string containing the formatted data.
# The prefix array contains separator elements that should only be included in the output
#   if the corresponding element contains data, and any element preceding it contained data.
# The indprefix array is like the prefix array, but it only requires the corresponding
#   element to contain data.
# The elemlookup array contains code references which are passed the track object and return
#   a string if that track has data for that element.
# The suffix array contains separator elements that should only be included if the corresponding
#   element contains data.
# The data for each item is placed in the string in the order prefix + indprefix + element + suffix.

sub _fillFormat {
	my ($track, $prefix, $indprefix, $elemlookup, $suffix) = @_;

	my $output = '';
	my $hasPrev;
	my $index = 0;

	for my $elemref (@{$elemlookup}) {

		my $elementtext = $elemref->($track);

		if (defined($elementtext) && $elementtext !~ /^\s*$/) {

			# The element had a value, so build this portion of the output.
			# Add in the prefix only if some previous element also had a value
			$output .= join('',
				($hasPrev ? $prefix->[$index] : ''),
				$indprefix->[$index],
				$elementtext,
				$suffix->[$index],
			);

			$hasPrev ||= 1;
		}

		$index++;
	}

	return $output;
}

sub _parseFormat {
	my $format = shift;

	# $format will be modified, so stash the original value
	my $formatparsed = $format;
	my $newstr = '';
	my (@parsed, @placeholders, @prefixes, @indprefixes, @elemlookups, @suffixes);

	# don't rebuild formats
	return $parsedFormats{$format} if exists $parsedFormats{$format};

	# find bracketed items so that we can collapse them correctly
	while ($format =~ s/$bracketstart//) {

		$newstr .= $1 . $2;

		my $endbracketRegex = $endbrackets{$2};

		if ($format =~ s/$endbracketRegex//) {

			push @placeholders, $1;
			$newstr .= '_PLACEHOLDER_' . $2;
		}
	}

	$format = $newstr . $format;

	# break up format string into separators and elements
	# elements must be separated by non-word characters
	@parsed = ($format =~ m/(.*?)\b($elemRegex)\b/gc);
	
	# add anything remaining at the end
	# perl 5.6 doesn't like retaining the pos() on m//gc in list context, 
	# so use the length of the joined matches to determine where we left off
	push @parsed, substr($format,length(join '', @parsed));

	if (scalar(@parsed) < 2) {
		# pure text, just return that text as the function
		my $output = shift(@parsed);
		$parsedFormats{$formatparsed} = sub { return $output; };
		return $parsedFormats{$formatparsed};
	}

	# Every other item in the parsed array is an element, which will be replaced later
	# by a code reference which will return a string to replace the element
	while (scalar(@parsed) > 1) {
		push @prefixes, shift(@parsed);
		push @indprefixes, '';
		push @elemlookups, shift(@parsed);
		push @suffixes, '';
	}

	# the first item will never have anything before it, so move it from the prefixes array
	# to the independent prefixes array
	$indprefixes[0] = $prefixes[0];
	$prefixes[0] = '';

	# if anything is left in the parsed array (there were an odd number of items, put it in
	# as the last item in the suffixes array
	if (@parsed) {
		$suffixes[-1] = $parsed[0];
	}

	# replace placeholders with their original values, and replace the element text with the
	# code references to look up the value for the element.
	my $index = 0;

	for my $elem (@elemlookups) {

		if ($elem eq '_PLACEHOLDER_') {

			$elemlookups[$index] = shift @placeholders;

			if ($index < $#prefixes) {
				# move closing bracket from the prefix of the element following
				# to the suffix of the current element
				$suffixes[$index] = substr($prefixes[$index + 1],0,1,'');
			}

			if ($index) {
				# move opening bracket from the prefix dependent on previous content
				# to the independent prefix for this element, but only attempt this
				# when this isn't the first element, since that has already had the
				# prefix moved to the independent prefix
				$indprefixes[$index] = substr($prefixes[$index],length($prefixes[$index]) - 1,1,'');
			}
		}

		# replace element with code ref from parsed formats. If the element does not exist in
		# the hash, it needs to be parsed and created.
		$elemlookups[$index] = $parsedFormats{$elem} || _parseFormat($elem);
		$index++;
	}

	$parsedFormats{$formatparsed} = sub {
		my $track = shift;

		return _fillFormat($track, \@prefixes, \@indprefixes, \@elemlookups, \@suffixes);
	};

	return $parsedFormats{$formatparsed};
}

sub cacheFormat {
	my $format = shift;
	# return if format result is valid for duration of a track and hence can be cached
	return ($format !~ $nocacheRegex);
}

sub infoFormat {
	my $fileOrObj = shift; # item whose information will be formatted
	my $str       = shift; # format string to use
	my $safestr   = shift; # format string to use in the event that after filling the first string, there is nothing left
	my $meta      = shift; # optional metadata hash to use instead of object data
	my $output    = '';
	my $format;
	
	# use a safe format string if none specified
	# Bug: 1146 - Users can input strings in any locale - we need to convert that to
	# UTF-8 first, otherwise perl will segfault in the nasty regex below.
	if ($str && $] > 5.007) {
		
		my $old = $str;
		if ( !($str = $formatCache{$old}) ) {
			$str = $old;
			eval {
				Encode::from_to($str, Slim::Utils::Unicode::currentLocale(), 'UTF-8');
				$str = Encode::decode('UTF-8', $str);
			};
			$formatCache{$old} = $str;
		}


	} elsif (!defined $str) {

		$str = 'TITLE';
	}

	# Get the formatting function from the hash, or parse it
	$format = $parsedFormats{$str} || _parseFormat($str);
	
	# Short-circuit if we have metadata
	if ( $meta ) {
		# Make sure all keys in meta are lowercase for format lookups
		my @uckeys = grep { $_ =~ /[A-Z]/ } keys %{$meta};
		for my $key ( @uckeys ) {
			$meta->{lc($key)} = $meta->{$key};
		}
		
		$output = $format->($meta) if ref($format) eq 'CODE';
	}
	else {
		# Optimize calls out to objectForUrl
		my $track     = $fileOrObj;

		if (!Slim::Schema::isaTrack($fileOrObj)) {

			$track = Slim::Schema->objectForUrl({
				'url'    => $fileOrObj,
				'create' => 1,
			});
		}

		if (!blessed($track) || !$track->can('id')) {

			return '';
		}

		$output = $format->($track) if ref($format) eq 'CODE';
	}
	
	$output = '' if !defined $output;

	if ($output eq "" && defined($safestr)) {

		# if there isn't any output, use the safe string, if supplied
		return infoFormat($fileOrObj, $safestr, undef, $meta);

	} else {

		$output =~ s/%([0-9a-fA-F][0-9a-fA-F])%/chr(hex($1))/eg;
	}

	return $output;
}

=head1 SEE ALSO

L<Slim::Music::Info>

=cut

1;

__END__
