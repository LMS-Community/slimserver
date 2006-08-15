package Slim::Music::TitleFormatter;

# $Id$

# SlimServer Copyright (c) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use Scalar::Util qw(blessed);

use Slim::Music::Info;
use Slim::Utils::DateTime;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Unicode;

our ($elemstring, @elements, $elemRegex, %parsedFormats);

sub init {

	%parsedFormats = ();

	# for relating track attributes to album/artist attributes
	my @trackAttrs = ();

	# Subs for all regular track attributes
	for my $attr (keys %{Slim::Schema::Track->attributes}) {

		$parsedFormats{uc $attr} = sub {

			my $output = $_[0]->get_column($attr);
			return (defined $output ? $output : '');
		};
	}

	# Override album
	$parsedFormats{'ALBUM'} = sub {

		my $output = '';
		my $album = $_[0]->album();
		if ($album) {
			$output = $album->title();
			$output = '' if $output eq string('NO_ALBUM');
		}
		return (defined $output ? $output : '');
	};

	# add album related
	$parsedFormats{'ALBUMSORT'} = sub {

		my $output = '';
		my $album = $_[0]->album();
		if ($album) {
			$output = $album->get_column('namesort');
		}
		return (defined $output ? $output : '');
	};

	$parsedFormats{'DISCC'} = sub {

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

		my $disc = $_[0]->disc;

		if ($disc && $disc == 1) {

			my $album = $_[0]->album;

			if ($album) {

				my $discc = $album->discc;

				# suppress disc when only 1 disc in set
				if (!$discc || $discc < 2) {
					$disc = '';
				}
			}
		}

		return ($disc ? $disc : '');
	};

	# add artist related
	$parsedFormats{'ARTIST'} = sub {

		my @output  = ();
		my @artists = $_[0]->artists;

		for my $artist (@artists) {

			my $name = $artist->get_column('name');

			next if $name eq string('NO_ARTIST');

			push @output, $name;
		}

		return (scalar @output ? join(' & ', @output) : '');
	};

	$parsedFormats{'ARTISTSORT'} = sub {

		my $output = '';
		my $artist = $_[0]->artist();
		if ($artist) {
			$output = $artist->get_column('namesort');
		}
		return (defined $output ? $output : '');
	};

	# add other contributors
	for my $attr (qw(composer conductor band genre)) {

		$parsedFormats{uc($attr)} = sub {

			my $output = '';
			my ($item) = $_[0]->$attr();

			if ($item) {
				$output = $item->name();
			}

			return (defined $output ? $output : '');
		};
	}

	# add genre
	$parsedFormats{'GENRE'} = sub {

		my $output = '';
		my ($item) = $_[0]->genre();

		if ($item) {
			$output = $item->name();
			$output = '' if $output eq string('NO_GENRE');
		}

		return (defined $output ? $output : '');
	};

	# add comment and duration
	for my $attr (qw(comment duration)) {

		$parsedFormats{uc($attr)} = sub {
			my $output = $_[0]->$attr();
			return (defined $output ? $output : '');
		};
	}
	
	# add file info
	$parsedFormats{'VOLUME'} = sub {

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

		my $output = '';
		my $url = $_[0]->get('url');

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
		Slim::Utils::DateTime::timeF();
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

	return 1;
}

sub addFormat {
	my $format = shift;
	my $formatSubRef = shift;
	
	# only add format if it is not already defined
	if (!defined $parsedFormats{$format}) {
		$parsedFormats{$format} = $formatSubRef;
		$::d_info && msg("Format $format added.\n");
	} else {
		$::d_info && msg("Format $format already exists.\n");
	}
	
	if ($format !~ /\W/) {
		# format is a single word, so make it an element
		push @elements, $format;
		$elemstring = join "|", @elements;
		$elemRegex = qr/$elemstring/;
	}
}

my %endbrackets = (
		'(' => qr/(.+?)(\))/,
		'[' => qr/(.+?)(\])/,
		'{' => qr/(.+?)(\})/,
		'"' => qr/(.+?)(")/, # " # syntax highlighters are easily confused
		"'" => qr/(.+?)(')/, # ' # syntax highlighters are easily confused
		);

my $bracketstart = qr/(.*?)([{[("'])/; # '" # syntax highlighters are easily confused

# The fillFormat routine takes a track and references to parsed data arrays describing
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

sub fillFormat {
	my ($track, $prefix, $indprefix, $elemlookup, $suffix) = @_;
	my $output = '';
	my $hasPrev;
	my $index = 0;
	for my $elemref (@{$elemlookup}) {
		my $elementtext = $elemref->($track);
		if (defined($elementtext) && $elementtext gt '') {
			# The element had a value, so build this portion of the output.
			# Add in the prefix only if some previous element also had a value
			$output .= join('', ($hasPrev ? $prefix->[$index] : ''),
					$indprefix->[$index],
					$elementtext,
					$suffix->[$index]);
			$hasPrev ||= 1;
		}
		$index++;
	}
	return $output;
}

sub parseFormat {
	my $format = shift;
	my $formatparsed = $format; # $format will be modified, so stash the original value
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
		$elemlookups[$index] = $parsedFormats{$elem} || parseFormat($elem);
		$index++;
	}

	$parsedFormats{$formatparsed} = sub {
		my $track = shift;

		return fillFormat($track, \@prefixes, \@indprefixes, \@elemlookups, \@suffixes);
	};
	
	return $parsedFormats{$formatparsed};
}

sub infoFormat {
	my $fileOrObj = shift; # item whose information will be formatted
	my $str       = shift; # format string to use
	my $safestr   = shift; # format string to use in the event that after filling the first string, there is nothing left
	my $output    = '';
	my $format;

	# Optimize calls out to objectForUrl
	my $blessed   = blessed($fileOrObj);
	my $track     = $fileOrObj;

	if (!$blessed || !($blessed eq 'Slim::Schema::Track' || $blessed eq 'Slim::Schema::Playlist')) {

		$track = Slim::Schema->rs('Track')->objectForUrl({
			'url'    => $fileOrObj,
			'create' => 1,
		});
	}

	if (!blessed($track) || !$track->can('id')) {

		return '';
	}

	# use a safe format string if none specified
	# Users can input strings in any locale - we need to convert that to
	# UTF-8 first, otherwise perl will segfault in the nasty regex below.
	if ($str && $] > 5.007) {

		eval {
			Encode::from_to($str, Slim::Utils::Unicode::currentLocale(), 'utf8');
			Encode::_utf8_on($str);
		};

	} elsif (!defined $str) {

		$str = 'TITLE';
	}

	# Get the formatting function from the hash, or parse it
	$format = $parsedFormats{$str} || parseFormat($str);

	$output = $format->($track) if ref($format) eq 'CODE';

	if ($output eq "" && defined($safestr)) {

		# if there isn't any output, use the safe string, if supplied
		return infoFormat($track,$safestr);

	} else {
		$output =~ s/%([0-9a-fA-F][0-9a-fA-F])%/chr(hex($1))/eg;
	}

	return $output;
}

1;

__END__
