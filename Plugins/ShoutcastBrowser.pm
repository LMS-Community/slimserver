# ShoutcastBrowser.pm Copyright (C) 2003 Peter Heslin
# version 3.0, 5 Apr, 2004
#$Id$
#
# A Slim plugin for browsing the Shoutcast directory of mp3
# streams.  Inspired by streamtuner.
#
# With contributions from Okko, Kevin Walsh and Rob Funk.
#
# This code is derived from code with the following copyright message:
#
# Slim Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# To Do:
#
# * Get rid of hard-coded @genre_keywords, and generate it
#  instead from a word frequency list -- which will mean a list of
#  excluded, rather than included, words.
#
# * Add a web interface

package Plugins::ShoutcastBrowser;

use strict;

use IO::Socket qw(:DEFAULT :crlf);
use File::Spec::Functions ();
use Slim::Control::Command;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Display::Display;
use HTML::Entities ();
use XML::Simple ();

eval { require Compress::Zlib };

our $have_zlib = 1 unless $@;

################### Configuration Section ########################

### These first few preferences can only be set by editing this file
our (%genre_aka, @genre_keywords, $munge_genres, @legit_genres);

# By default, we normalize genres based on keywords, because otherwise
# there are nearly as many genres as there are streams.  If you would
# like to see the genre listing as defined by each stream, set this to
# 0.

$munge_genres = 1;

# If you choose to munge the genres, here is the list of keywords that
# define various genres.  If any of these words or phrases is found in
# the genre of a stream, then the stream is allocated to the genre
# indicated by those word(s) or phrase(s).  In phrases, indicate a
# space by means of an underscore.  The order is significant if
# @genre_criteria contains "keywords".

@genre_keywords = qw{
	rock pop trance dance techno various house alternative 80s metal
	college jazz talk world rap ambient oldies electronic blues country
	punk reggae 70s classical live latin indie downtempo gospel
	industrial scanner unknown 90s hardcore folk comedy urban funk
	progressive ska 60s breakbeat smooth anime news soul lounge goa
	soundtrack bluegrass salsa dub swing chillout contemporary garage
	chinese russian greek jpop kpop jungle zabavna african punjabi
	sports asian disco korean hindi japanese psychedelic indian
	dancehall adult instrumental vietnam narodna eurodance celtic 50s
	merengue hardstyle persian tamil gothic npr spanish remix community
	cpop arabic jrock space international freeform acid bhangra
	kabar opera german iranian dominicana deephouse africa rave
	hardhouse irish turkish malay stoner ethnic rocksteady remixes
	croatian hardtrance polka glam americana mexican pakistani
	iraqi hungarian bosna bossa italian didjeridu acadian coptic brazil
	greece kurd rockabilly top_40 hard_rock hard_core video_game
	big_band classic_rock easy_listening pink_floyd new_age zouk
};

# Here are keywords defined in terms of other, variant keywords.  The
# form on the left is the canonical form, and on the right is the
# variant or list of variants which should be transformed into that
# canonical form.

%genre_aka = (
	'50s' => '50', '60s' => '60', '70s' => '70', '80s' => '80', '90s' => '90',
	top_40 => [qw(top40 chart top_hits)],
	'drum_&_bass' => [qw(dnb d&b d_&_b drum_and_bass drum bass)],
	 rap => [qw(hiphop hip_hop)],
	comedy => [qw(humor humour)],
	old_school => [qw(oldskool old_skool oldschool)],
	dutch => [qw(holland netherland nederla)],
	various => [qw(any every mixed eclectic mix variety random misc)],
	'r_&_b' => [qw(rnb r_n_b r&b)], reggae => [qw(ragga dancehall dance_hall)],
	hungarian => 'hungar', african => 'africa', classical => 'symphonic',
	video_game => [qw(videogame gaming)], psychedelic => 'psych',
	spiritual =>
	[qw(christian praise worship prayer inspirational bible religious)],
	freeform => 'freestyle', greek => 'greece', punjabi => 'punjab',
	breakbeat => 'breakbeats', new_age => 'newage',
	british => [qw(britpop)],
	community => 'local', low_fi => [qw(lowfi lofi)],
	anime => 'animation', electronic => [qw(electro electronica)],
	trance => 'tranc', talk => [qw(spoken politics)], gothic => 'goth',
	oldies => 'oldie', soundtrack => [qw(film movie)],
	live => 'vivo'
);

## These are useful, descriptive genres, which should not be removed
## from the list, even when they only have one stream and we are
## lumping singletons together.  So we eliminate the more obscure and
## regional genres from this list.

@legit_genres = qw(
	rock pop trance dance techno various house alternative 80s metal
	college jazz talk world rap ambient oldies blues country punk reggae
	70s classical live latin indie downtempo gospel industrial scanner 90s
	folk comedy urban funk progressive ska 60s news soul lounge soundtrack
	bluegrass salsa swing sports disco 50s merengue opera top_40 hard_rock
	hard_core video_game big_band classic_rock easy_listening new_age
);

### Warning: These preferences can (and should) be set via the web
### interface. If you set them here, they will be overriden by the
### settings in your preferences file put there by the web
### configuration interface.  If for some reason you want to specify
### these values here (eg. you really want to have a tertiary sorting
### criterion), then set $prefs_override to a true value.
our ($prefs_override, @genre_criteria, @stream_criteria, $how_many_streams);
our ($min_bitrate, $max_bitrate, $recent_max);
our $lump_singletons = 1;

# Maximum number of streams to fetch (default is 300; 2000 is max)
# $how_many_streams = 2000;

# Sorting criteria for genres: a list of any of the following strings
# name (alphabetical), name_reverse (reverse alphabetical), keyword
# (order given in the array @genre_keywords above), keyword_reverse
# (opposite order), streams (number of streams, high to low),
# streams_reverse (low to high).

# @genre_criteria = qw(streams name);

# Sorting criteria for streams: a list of any of the following strings:
# "bitrate" (high to low), "bitrate_reverse" (low to high),
# "listeners" (many to few), "listeners_reverse" (few to many), "name"
# (alphabetical), "name_reverse" (reverse alphabetical).  The first
# sorting criterion listed is used first, then if any two streams are
# equal, the second criterion is used, and so forth.

# @stream_criteria = qw(listeners bitrate name);

################### End Configuration Section ####################

## Order for info sub-mode
our @info_order = ('Bitrate', 'Name', 'Listeners', 'Genre', 'Was Playing', 'Url' );
our @info_index = ( 4,		 2,	  3,		   6,	   5,			 0	);

our $all_name = '';
our $sort_bitrate_up = 0;

our ($recent_name, $misc_genre, $position_of_recent);
our (%recent_filename, %recent_data);
our $recent_dirname = 'ShoutcastBrowser_Recently_Played';
our $recent_dir = File::Spec::Functions::catdir(Slim::Utils::Prefs::get('playlistdir'), $recent_dirname);
mkdir $recent_dir unless (-d $recent_dir);

our ($top_limit, $most_popular_name, $custom_genres, %custom_genres);

our $debug = 0;
our (%current_genre, %current_stream, %status, %number, %current_info, %old_stream);
our $last_time = 0;

our (@genres, %streams, %stream_data, %bitrates, %current_bitrate);

our %genre_transform;

for my $key (keys %genre_aka) {
	my $rx;
	
	if (ref $genre_aka{$key}) {
		$rx = join '|', @{ $genre_aka{$key} };
	} else {
		$rx = $genre_aka{$key};
	}
	
	$rx = "\L$rx";
	$rx =~ s/_/ /g;
	
	unless (grep {$_ eq $key} @genre_keywords) {
		push @genre_keywords, $key;
	}
	
	$key = "\L$key";
	$key =~ s/_/ /g;
	$genre_transform{$rx} = $key;
}

our $genre_list = join '|', @genre_keywords;

$genre_list = "\L$genre_list";
$genre_list =~ s/_/ /g;

our %keyword_index;

if (grep {$_ =~ m/keyword/i} @genre_criteria) {
	my $i = 1;
	
	for (@genre_keywords) {
		$keyword_index{$_} = $i;
		$i++;
	}
}

our %legit_genres;

for my $g (@legit_genres) {
	$g = "\L$g";
	$g =~ s/\s+/ /g;
	$g =~ s/^ //;
	$g =~ s/ $//;
	$g = "\u$g";
	$legit_genres{$g}++;
}

sub getDisplayName {
	return 'PLUGIN_SHOUTCASTBROWSER_MODULE_NAME';
}

sub strings {
	local $/ = undef;

	my $strings = <DATA>;
	close DATA;

	return $strings;
}

sub get_prefs {
	if ((not $prefs_override) and
			Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_how_many_streams')) {
		$how_many_streams =
		Slim::Utils::Prefs::get('plugin_shoutcastbrowser_how_many_streams');
	}
	
	if ((not $prefs_override) and
			Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_genre_primary_criterion')
			and 
			Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_genre_secondary_criterion')) {
		@genre_criteria =
			( Slim::Utils::Prefs::get('plugin_shoutcastbrowser_genre_primary_criterion'),
			Slim::Utils::Prefs::get('plugin_shoutcastbrowser_genre_secondary_criterion'));
	}
	
	if ((not $prefs_override) and
			Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_stream_primary_criterion')
			and
			Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_stream_secondary_criterion')) {
		@stream_criteria =
			( Slim::Utils::Prefs::get('plugin_shoutcastbrowser_stream_primary_criterion'),
			Slim::Utils::Prefs::get('plugin_shoutcastbrowser_stream_secondary_criterion'));
	}
	
	if ((not $prefs_override) and
			Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_min_bitrate')) {
		$min_bitrate = Slim::Utils::Prefs::get('plugin_shoutcastbrowser_min_bitrate');
	}
	
	if ((not $prefs_override) and
			Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_max_bitrate')) {
		$max_bitrate = Slim::Utils::Prefs::get('plugin_shoutcastbrowser_max_bitrate');
	}
	
	if ((not $prefs_override) and
			Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_max_recent')) {
		$recent_max = Slim::Utils::Prefs::get('plugin_shoutcastbrowser_max_recent');
	}
	
	if ((not $prefs_override) and
			Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_max_popular')) {
		$top_limit = Slim::Utils::Prefs::get('plugin_shoutcastbrowser_max_popular');
	}
	
	if ((not $prefs_override) and
		Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_custom_genres')) {
		$custom_genres = Slim::Utils::Prefs::get('plugin_shoutcastbrowser_custom_genres');
	}

	# Fallback defaults if undefined in prefs or at start of this file
	$how_many_streams = 300 unless $how_many_streams;
	@genre_criteria  = qw(streams name) unless @genre_criteria;
	@stream_criteria = qw(listeners bitrate name) unless @stream_criteria;
	
	$lump_singletons = 1 if ($genre_criteria[0] =~ m/default/i);
	$recent_max = 50 unless defined $recent_max;
}

sub setup_custom_genres {
	my $i = 1;
	
	open FH, $custom_genres or return;
	{
		while(my $entry = <FH>) {
			
			chomp $entry;
			
			next if $entry =~ m/^\s*$/;
			my ($genre, @patterns) = split ' ', $entry;
			
			$genre =~ s/_/ /g;
			
			for (@patterns)
			{
				$_ = "\L$_";
				$_ =~ s/_/ /g;
			}
			
			$custom_genres{$genre} = join '|', @patterns;
			$genre = lc($genre);
			$keyword_index{$genre} = $i;
			$i++;
		}
		
	close FH;
	}
}

##### Main mode for genres #####

sub setMode {
	my $client = shift;
	
	$client->lines(\&lines);
	$status{$client} = 0;
	$number{$client} = undef;
	
	$client->update();
	
	&get_prefs;
	
	$recent_name = $client->string('PLUGIN_SHOUTCASTBROWSER_RECENT');
	$most_popular_name = $client->string('PLUGIN_SHOUTCASTBROWSER_MOST_POPULAR');
	$misc_genre= $client->string('PLUGIN_SHOUTCASTBROWSER_MISC');
	$recent_filename{$client} = File::Spec::Functions::catfile($recent_dir, $client->name() . '.m3u');

	# Get streams
	unless (@genres) {
		%stream_data = ();
		%streams = ();
		%bitrates = ();
		$current_genre{$client} = 0;
		$current_stream{$client} = 0;
		$current_bitrate{$client} = 0;
		
		my %in_genres;
		
		$all_name = $client->string('PLUGIN_SHOUTCASTBROWSER_ALL_STREAMS');

		my $u = unpack 'u', q{M:'1T<#HO+W-H;W5T8V%S="YC;VTO<V)I;B]X;6QL:7-T97(N<&AT;6P_<V5R+=FEC93U3;&E-4#,`};
		
		$u .= '&no_compress=1' unless $have_zlib;
		$u .= "&limit=$how_many_streams" if $how_many_streams;
		
		my $http = Slim::Player::Source::openRemoteStream($u) || do {
			$status{$client} = -1;
			$client->update();
			return;
		};

		my $xml  = $http->content();
		$http->close();
		
		$last_time = time;
		&setup_custom_genres() if $custom_genres;
		
		unless ($xml) {
			$status{$client} = -1;
			$client->update();
			return;
		}
		
		if ($have_zlib) {
			$xml = Compress::Zlib::uncompress($xml);
		}

		# Using XML::Simple reduces the memory footprint by nearly 2 megs vs the old manual scanning.
		my $data  = XML::Simple::XMLin($xml);
		my $label = $data->{'playlist'}->{'label'};

		for my $entry (@{$data->{'playlist'}->{'entry'}}) {

			my $url		 = $entry->{'Playstring'};
			my $name		= $entry->{'Name'};
			my $genre	   = $entry->{'Genre'};
			my $now_playing = $entry->{'Nowplaying'};
			my $listeners   = $entry->{'Listeners'};
			my $bitrate	 = $entry->{'Bitrate'};
	
			next if ($min_bitrate and $bitrate < $min_bitrate);
			next if ($max_bitrate and $bitrate > $max_bitrate);
	
			$genre =~ s/%([\dA-F][\dA-F])/chr hex $1/gei;#encoded chars
			$name =~ s/%([\dA-F][\dA-F])/chr hex $1/gei;
			$now_playing =~ s/%([\dA-F][\dA-F])/chr hex $1/gei;
	
			HTML::Entities::decode_entities($name);
			HTML::Entities::decode_entities($genre);
			HTML::Entities::decode_entities($now_playing);
	
			$name =~ s#\b([\w-]) ([\w-]) #$1$2#g;#S P A C E D  W O R D S
			$name =~ s#\b(ICQ|AIM|MP3Pro)\b##i;# we don't care
			$name =~ s#\W\W\W\W+# #g;# excessive non-word characters
			$name =~ s#^\W+##;# leading non-word characters
			$genre =~ s/\s+/ /g;
	
			my $full_text;
			my @keywords = ();
			my $original = $genre;
	
			if ($custom_genres) {
				$genre = "\L$genre";
				$genre =~ s/\s+/ /g;
				$genre =~ s/^ //;
				$genre =~ s/ $//;
			
				my $match = 0;
			
				for my $key (keys %custom_genres) {
					my $re = $custom_genres{$key};
					while ($genre =~ m/$re/g) {
						push @keywords, $key;
						$match++;
					}
				}
			
				if ($match == 0) {
					@keywords = ($misc_genre);
				}
			
				$full_text= "$name | ${bitrate}kbps | $listeners online | $original | ";
			
			} elsif ($munge_genres) {
				$genre = "\L$genre";
				$genre =~ s/\s+/ /g;
				$genre =~ s/^ //;
				$genre =~ s/ $//;
	
				for (keys %genre_transform) {
					$genre =~ s/$_/$genre_transform{$_}/g;
				}
			
				while ($genre =~ m/($genre_list)/g) {
					push @keywords, "\u$1";
				}
			
				$genre = "\u$genre";
				$genre = 'Unknown' if ($genre eq ' ' or $genre eq '');
	
				$full_text= "$name | ${bitrate}kbps | $listeners online | $original | ";
				@keywords = ($genre) unless @keywords;
			
			} else {
				$full_text= "$name | ${bitrate}kbps | $listeners online | ";
				@keywords = ($genre);
			}
	
			my $data = [$url, $full_text, $name, $listeners, $bitrate, $now_playing, $original];
	
			foreach my $g (@keywords) {
				$stream_data{$g}{$name}{$bitrate} = $data;
				$in_genres{$name}++;
			}
			
			$stream_data{$all_name}{$name}{$bitrate} = $data;
		}
	
		undef $xml;
		undef $data;
	
		if ($lump_singletons and not $custom_genres) {
	
			foreach my $g (keys %stream_data) {
	
				if ((exists $legit_genres{$g}) or (keys %{ $stream_data{$g} } > 1)) {
					push @genres, $g;
				} else {
					my ($n) = keys %{ $stream_data{$g} };
					
					unless (exists $stream_data{$misc_genre}{$n}) {
						$in_genres{$n}--;
						
						if ($in_genres{$n} == 0) {
							$stream_data{$misc_genre}{$n} = $stream_data{$g}{$n};
						}
						
						delete $stream_data{$g};
					}
				}
			}
		}
		
		@genres = sort genre_sort keys %stream_data;
	
		unshift @genres, $most_popular_name;
	
		unshift @genres, $recent_name;
		$position_of_recent = 0;
	}
	
	$status{$client} = 1;
	$client->update();
}

sub genre_sort {
	my $r = 0;
	
	return -1 if $a eq $all_name;
	return 1  if $b eq $all_name;
	return 1  if $a eq $misc_genre;
	return -1 if $b eq $misc_genre;
	
	for my $criterion (@genre_criteria) {
		
		if ($criterion =~ m/^streams/i)	{
			$r = keys %{ $stream_data{$b} } <=> keys %{ $stream_data{$a} };
		} elsif ($criterion =~ m/^keyword/i) {
		
			if ($keyword_index{lc($a)}) {
		
				if ($keyword_index{lc($b)}) {
					$r = $keyword_index{lc($a)} <=> $keyword_index{lc($b)};
				} else {
					$r = -1; 
				}
		
			} else {
				
				if ($keyword_index{lc($b)}) { 
					$r = 1; 
				} else {
					$r = 0;
				}
				
			}
		
		} elsif ($criterion =~ m/^name/i or $criterion =~ m/^default/i) {
			$r = (lc($a) cmp lc($b));
		}
		
		$r = -1 * $r if $criterion =~ m/reverse$/i;
		return $r if $r;
	}
	return $r;
}

sub reload_xml {
	my $client = shift;
	
	if (time() < $last_time + 60) {
	
		$status{$client} = -2;
		$client->update();
		sleep 1;
		$status{$client} = 1;
		$client->update();
	
	} else {
	
		$status{$client} = 0;
		$client->update();
		@genres = ();
		&setMode($client);
	
	}
}

our %functions = (
	
	'up' => sub {
		my $client = shift;
		
		$number{$client} = undef;
		$current_genre{$client} =
		
		Slim::Buttons::Common::scroll(
						$client,
						-1,
						$#genres + 1,
						$current_genre{$client} || 0,
						);
		
		$client->update();
	},
	
	'down' => sub {
		my $client = shift;
		
		$number{$client} = undef;
		$current_genre{$client} =
		
		Slim::Buttons::Common::scroll(
						$client,
						1,
						$#genres + 1,
						$current_genre{$client} || 0,
						);
		
		$client->update();
	},
	
	'left' => sub {
		my $client = shift;
		$number{$client} = undef;
		Slim::Buttons::Common::popModeRight($client);
	},
	
	'right' => sub {
		my $client = shift;
		$number{$client} = undef;
		Slim::Buttons::Common::pushModeLeft($client, 'ShoutcastStreams');
	},
	
	'jump_rew' => sub {
		my $client = shift;
		
		$number{$client} = undef;
		&reload_xml($client);
	},
	
	'numberScroll' => sub {
		my ($client, $button, $digit) = @_;
		
		if ($digit == 0 and (not $number{$client})) {
			$current_genre{$client} = 0;
		} else {
			$number{$client} .= $digit;
			$current_genre{$client} = $number{$client} - 1;
		}
		
		$client->update();
	}
);

sub lines {
	my $client = shift;
	my (@lines);

	$current_genre{$client} ||= 0;

	if ($status{$client} == 0) {
		$lines[0] = $client->string('PLUGIN_SHOUTCASTBROWSER_CONNECTING');
		$lines[1] = '';
	
	} elsif ($status{$client} == -1) {
		$lines[0] = $client->string('PLUGIN_SHOUTCASTBROWSER_NETWORK_ERROR');
		$lines[1] = '';
	
	} elsif ($status{$client} == -2) {
		$lines[0] = $client->string('PLUGIN_SHOUTCASTBROWSER_TOO_SOON');
		$lines[1] = '';
	
	} elsif ($status{$client} == 1) {
		my $current_stream = $genres[$current_genre{$client}];
	
		$lines[0] = $client->string('PLUGIN_SHOUTCASTBROWSER_GENRES').
			' (' .
			($current_genre{$client} + 1) .  ' ' .
				$client->string('OF') .  ' ' .
					($#genres + 1) .  ') ' ;
		$lines[1] = $current_stream;
		$lines[3] = Slim::Display::Display::symbol('rightarrow');
	}

	return @lines;
}

sub getFunctions { return \%functions; }

sub addMenu {
	my $menu = "RADIO";
	return $menu;
}

sub setupGroup
{
	my %setupGroup = (
		PrefOrder => [
			'plugin_shoutcastbrowser_how_many_streams',
			'plugin_shoutcastbrowser_custom_genres',
			'plugin_shoutcastbrowser_genre_primary_criterion',
			'plugin_shoutcastbrowser_genre_secondary_criterion',
			'plugin_shoutcastbrowser_stream_primary_criterion',
			'plugin_shoutcastbrowser_stream_secondary_criterion',
			'plugin_shoutcastbrowser_min_bitrate',
			'plugin_shoutcastbrowser_max_bitrate',
			'plugin_shoutcastbrowser_max_recent',
			'plugin_shoutcastbrowser_max_popular'
		],
		GroupHead => Slim::Utils::Strings::string('SETUP_GROUP_PLUGIN_SHOUTCASTBROWSER'),
		GroupDesc => Slim::Utils::Strings::string('SETUP_GROUP_PLUGIN_SHOUTCASTBROWSER_DESC'),
		GroupLine => 1,
		GroupSub => 1,
		Suppress_PrefSub => 1,
		Suppress_PrefLine => 1
	);

	my %genre_options = (
		name_reverse => Slim::Utils::Strings::string('SETUP_PLUGIN_SHOUTCASTBROWSER_ALPHA_REVERSE'),
		streams => Slim::Utils::Strings::string('SETUP_PLUGIN_SHOUTCASTBROWSER_NUMBEROFSTREAMS'),
		streams_reverse => Slim::Utils::Strings::string('SETUP_PLUGIN_SHOUTCASTBROWSER_NUMBEROFSTREAMS_REVERSE'),
		default => Slim::Utils::Strings::string('SETUP_PLUGIN_SHOUTCASTBROWSER_DEFAULT_ALPHA'),
		keyword => Slim::Utils::Strings::string('SETUP_PLUGIN_SHOUTCASTBROWSER_KEYWORD'),
		keyword_reverse => Slim::Utils::Strings::string('SETUP_PLUGIN_SHOUTCASTBROWSER_KEYWORD_REVERSE'),
	);

	my %stream_options = (
		name_reverse => Slim::Utils::Strings::string('SETUP_PLUGIN_SHOUTCASTBROWSER_ALPHA_REVERSE'),
		listeners => Slim::Utils::Strings::string('SETUP_PLUGIN_SHOUTCASTBROWSER_NUMBEROFLISTENERS'),
		listeners_reverse => Slim::Utils::Strings::string('SETUP_PLUGIN_SHOUTCASTBROWSER_NUMBEROFSTREAMS_REVERSE'),
		default => Slim::Utils::Strings::string('SETUP_PLUGIN_SHOUTCASTBROWSER_DEFAULT_ALPHA'),
	);


	my %setupPrefs = (
		plugin_shoutcastbrowser_how_many_streams => {
 			validate => \&Slim::Web::Setup::validateInt,
 			validateArgs => [1,2000,1,2000]
		},
		
		plugin_shoutcastbrowser_custom_genres => {
			validate => \&validateIsFile,
			PrefSize => 'large'
		},
		
		plugin_shoutcastbrowser_genre_primary_criterion => {
			options => \%genre_options
		},
	
		plugin_shoutcastbrowser_genre_secondary_criterion => {
			options => \%genre_options
		},
		
		plugin_shoutcastbrowser_stream_primary_criterion => {
			options => \%stream_options
		},
		
		plugin_shoutcastbrowser_stream_secondary_criterion => {
			options => \%stream_options
		},
		
		plugin_shoutcastbrowser_min_bitrate => {
			validate => \&Slim::Web::Setup::validateInt,
			validateArgs => [0, undef, 0]
		},
		
		plugin_shoutcastbrowser_max_bitrate => {
			validate => \&Slim::Web::Setup::validateInt,
			validateArgs => [0, undef, 0]
		},
		
		plugin_shoutcastbrowser_max_recent => {
			validate => \&Slim::Web::Setup::validateInt,
			validateArgs => [0, undef, 0]
		},
		
		plugin_shoutcastbrowser_max_popular => {
			validate => \&Slim::Web::Setup::validateInt,
			validateArgs => [0, undef, 0]
		}
	);
	
	&checkDefaults;
	
	return (\%setupGroup,\%setupPrefs);
}

sub validateIsFile {
	my $val = shift;
	
	if (not defined $val) {
		return '';
	} elsif (-f $val or $val eq '') {
		return $val;
	} else {
		return (undef, string("SETUP_BAD_DIRECTORY"));
	}
}

sub checkDefaults {
	
	if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_how_many_streams')) {
		Slim::Utils::Prefs::set('plugin_shoutcastbrowser_how_many_streams', 300);
	}
	
	if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_genre_primary_criterion')) {
		Slim::Utils::Prefs::set('plugin_shoutcastbrowser_genre_primary_criterion', 'default');
	}
	
	if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_genre_secondary_criterion')) {
		Slim::Utils::Prefs::set('plugin_shoutcastbrowser_genre_secondary_criterion', 'default');
	}
	
	if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_stream_primary_criterion')) {
		Slim::Utils::Prefs::set('plugin_shoutcastbrowser_stream_primary_criterion', 'default');
	}
	
	if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_stream_secondary_criterion')) {
		Slim::Utils::Prefs::set('plugin_shoutcastbrowser_stream_secondary_criterion', 'default');
	}
	
	if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_min_bitrate')) {
		Slim::Utils::Prefs::set('plugin_shoutcastbrowser_min_bitrate', 0);
	}
	
	if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_max_bitrate')) {
		Slim::Utils::Prefs::set('plugin_shoutcastbrowser_max_bitrate', 0);
	}
	
	if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_max_recent')) {
		Slim::Utils::Prefs::set('plugin_shoutcastbrowser_max_recent', 50);
	}
	
	if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_max_popular')) {
		Slim::Utils::Prefs::set('plugin_shoutcastbrowser_max_popular', 40);
	}
}


##### Sub-mode for streams #####

our $mode_sub = sub {
	my $client = shift;

	$current_bitrate{$client} = 0;
	$client->lines(\&streamsLines);
	$status{$client} = -3;
	$number{$client} = undef;
	$current_stream{$client} = $old_stream{$client}{$current_genre{$client}};
	$client->update();

	# Closure for the sake of $client
	my $stream_sort = sub {
		my $r = 0;
	
		for my $criterion (@stream_criteria) {
			if ($criterion =~ m/^listener/i) {
				my ($aa, $bb) = (0, 0);
				my $current_genre = $genres[$current_genre{$client}];
				
				$aa += $stream_data{$current_genre}{$a}{$_}[3]
				
				foreach keys %{ $stream_data{$current_genre}{$a} };
				
				$bb += $stream_data{$current_genre}{$b}{$_}[3]
				
				foreach keys %{ $stream_data{$current_genre}{$b} };
				
				$r = $bb <=> $aa;
			
			} elsif ($criterion =~ m/^name/i or $criterion =~ m/default/i) {
				$r = lc($a) cmp lc($b);
			}
			
			$r = -1 * $r if $criterion =~ m/reverse$/i;
			
			return $r if $r;
		}
		
		return $r;
	};

	my $popular_sort = sub {
		my $r = 0;
		my ($aa, $bb) = (0, 0);
		
		$aa += $stream_data{$all_name}{$a}{$_}[3]
		
		foreach keys %{ $stream_data{$all_name}{$a} };
		
		$bb += $stream_data{$all_name}{$b}{$_}[3]
		
		foreach keys %{ $stream_data{$all_name}{$b} };
		
		$r = $bb <=> $aa;
		
		return $r if $r;
		
		$r = lc($a) cmp lc($b);
		
		return $r;
	};

	# %streams is indexed by client, since the streams for recently
	# played are different for each; for the others, this is somewhat
	# wasteful of memory.
	unless(exists $streams{$client}{$current_genre{$client}}) {
		my $current_genre = $genres[$current_genre{$client}];

		if ($current_genre eq $recent_name) {
			$streams{$client}{$current_genre{$client}} = get_recent_streams($client);
		
		} elsif ($current_genre eq $most_popular_name) {
			my @top = sort $popular_sort keys %{ $stream_data{$all_name} };
			
			splice @top, $top_limit;
			$streams{$client}{$current_genre{$client}} = [ @top ];
			$stream_data{$most_popular_name} = $stream_data{$all_name}
		
		} else {
			$streams{$client}{$current_genre{$client}} =
			[ sort $stream_sort keys %{ $stream_data{$current_genre} } ];
		}
	}
	
	$status{$client} = 1;
	$client->update();
};

our $leave_mode_sub = sub {
	my $client = shift;
	
	$number{$client} = undef;
	$old_stream{$client}{$current_genre{$client}} = $current_stream{$client};
};

sub streamsLines {
	my $client = shift;
	my (@lines);
	
	$current_stream{$client} ||= 0;

	if ($status{$client} == 0) {
		$lines[0] = $client->string('PLUGIN_SHOUTCASTBROWSER_CONNECTING');
		$lines[1] = '';
	
	} elsif ($status{$client} == -1) {
		$lines[0] = $client->string('PLUGIN_SHOUTCASTBROWSER_NETWORK_ERROR');
		$lines[1] = '';
	
	} elsif ($status{$client} == -2) {
		$lines[0] = $client->string('PLUGIN_SHOUTCASTBROWSER_TOO_SOON');
		$lines[1] = '';
	
	} elsif ($status{$client} == -3) {
		$lines[0] = $client->string('PLUGIN_SHOUTCASTBROWSER_SORTING');
		$lines[1] = '';
	
	} elsif ($status{$client} == 1) {
	
		# print STDERR join ', ', %streams;
		my @streams = @{ $streams{$client}{$current_genre{$client}} };
	
		my $current_genre = $genres[$current_genre{$client}];
		my $current_stream = $streams[$current_stream{$client}];
	
		$lines[0] = $client->string('PLUGIN_SHOUTCASTBROWSER_SHOUTCAST').': '.
				$genres[$current_genre{$client}] .
				' (' .
					($current_stream{$client} + 1) .  ' ' .
					$client->string('OF') .  ' ' .
						($#streams + 1) .  ') ' ;
		$lines[1] = $current_stream;
		
		if (keys %{ $stream_data{$current_genre}{$current_stream} } > 1) {
			$lines[3] = Slim::Display::Display::symbol('rightarrow');
		}
	}

	return @lines;
}

our %StreamsFunctions = (
	'up' => sub {
		my $client = shift;
		
		$number{$client} = undef;
		
		my @streams = @{ $streams{$client}{$current_genre{$client}} };
		$current_stream{$client} = Slim::Buttons::Common::scroll(
						$client,
						-1,
						$#streams + 1,
						$current_stream{$client} || 0,
					);
		$client->update();
	},
	
	'down' => sub {
		my $client = shift;
		
		$number{$client} = undef;
		
		my @streams = @{ $streams{$client}{$current_genre{$client}} };
		$current_stream{$client} = Slim::Buttons::Common::scroll(
						$client,
						1,
						$#streams + 1,
						$current_stream{$client} || 0,
					);
		$client->update();
	},
	
	'left' => sub {
		my $client = shift;
		
		$number{$client} = undef;
		$leave_mode_sub->($client);
		Slim::Buttons::Common::popModeRight($client);
	},
	
	'right' => sub {
		my $client = shift;
	
		$number{$client} = undef;
		
		my $current_genre = $genres[$current_genre{$client}];
		my @streams = @{ $streams{$client}{$current_genre{$client}} };
		my $current_stream = $streams[$current_stream{$client}];
		
		&bitrate_mode_helper($client);

		if ($current_genre eq $recent_name) {
			$client->bumpRight();
		} else {
		
			if (keys %{ $stream_data{$current_genre}{$current_stream}} == 1) {
				Slim::Buttons::Common::pushModeLeft($client, 'ShoutcastStreamInfo');
			} else {
				Slim::Buttons::Common::pushModeLeft($client, 'ShoutcastBitrates');
			}
		
		}
	},
	
	'play' => sub {
		my $client = shift;
	
		Slim::Control::Command::execute($client, ['playlist', 'clear']);
	
		my $current_genre = $genres[$current_genre{$client}];
		my @streams = @{ $streams{$client}{$current_genre{$client}} };
		my $current_stream = $streams[$current_stream{$client}];
	
		if ($current_genre eq $recent_name) {
			my $playlist_url = $recent_data{$client}{$current_stream};
			
			Slim::Control::Command::execute($client, ['playlist', 'add', $playlist_url]);
			add_recent_stream($client, $current_stream, undef);
			$current_stream{$client} = 0;
		}
		
		# Add all bitrates to current playlist, but only the first
		# one to the recently played list
		my $first = 1;
		
		for my $b (sort bitrate_sort keys %{ $stream_data{$current_genre}{$current_stream} }) {
			my $current_data = $stream_data{$current_genre}{$current_stream}{$b};
			my $playlist_url = $current_data->[0];
			
			Slim::Control::Command::execute($client, ['playlist', 'add', $playlist_url]);
			
			if ($first) {
				add_recent_stream($client, $current_stream, $b, $current_data);
			}
			
			$first = 0;
		}
		
		Slim::Control::Command::execute($client, ['play']);
	},
	
	'add' => sub {
		my $client = shift;
		my $current_genre = $genres[$current_genre{$client}];
		my @streams = @{ $streams{$client}{$current_genre{$client}} };
		my $current_stream = $streams[$current_stream{$client}];
	
		for my $b (sort bitrate_sort keys %{ $stream_data{$current_genre}{$current_stream} }) {
			my $current_data = $stream_data{$current_genre}{$current_stream}{$b};
			my $playlist_url = $current_data->[0];
			
			Slim::Control::Command::execute($client, ['playlist', 'add', $playlist_url]);
		}
	},
	
	'jump_rew' => sub {
		my $client = shift;
	
		$number{$client} = undef;
 		Slim::Buttons::Common::popModeRight($client);
		&reload_xml($client);
	},
	
	'numberScroll' => sub {
		my ($client, $button, $digit) = @_;
	
		if ($digit == 0 and (not $number{$client})) {
			$current_stream{$client} = 0;
		} else {
			$number{$client} .= $digit;
			$current_stream{$client} = $number{$client} - 1;
		}
		
		$client->update();
	}
);

##### Sub-mode for bitrates #####

our $bitrate_mode_sub = sub
{
	my $client = shift;
	unless(exists $bitrates{$current_genre{$client}}{$current_stream{$client}})
	{
	bitrate_mode_helper($client);
	}
	$client->lines(\&bitrateLines);
	$client->update();
};


sub bitrate_mode_helper {
	my $client = shift;
	my $current_genre = $genres[$current_genre{$client}];
	my @streams = @{ $streams{$client}{$current_genre{$client}} };
	my $current_stream = $streams[$current_stream{$client}];

	my @bitrates = sort bitrate_sort keys
		%{ $stream_data{$current_genre}{$current_stream} };

	$bitrates{$current_genre{$client}}{$current_stream{$client}} = [@bitrates];
}

our $leave_bitrate_mode_sub = sub {
	my $client = shift;
};

sub bitrate_sort {
	my $r = $b <=> $a;
	
	$r = -$r if $sort_bitrate_up;
	
	return $r;
}

sub bitrateLines {
	my $client = shift;
	my (@lines);

	my @bitrates = @{ $bitrates{$current_genre{$client}}{$current_stream{$client}} };

	my @streams = @{ $streams{$client}{$current_genre{$client}} };
	my $current_stream = $streams[$current_stream{$client}];

	$lines[0] = $current_stream;
	
	$lines[3] = ' (' . ($current_bitrate{$client} + 1) .  ' ' .
		$client->string('OF') .  ' ' .
		($#bitrates + 1) .  ')' ;

	$lines[1] = $client->string('PLUGIN_SHOUTCASTBROWSER_BITRATE') . ': ' .
		$bitrates[$current_bitrate{$client}] . ' ' .
		$client->string('PLUGIN_SHOUTCASTBROWSER_KBPS');
	
	return @lines;
}

our %BitrateFunctions = (
	'up' => sub {
		my $client = shift;
		my @bitrates = @{ $bitrates{$current_genre{$client}}{$current_stream{$client}} };
		
		$current_bitrate{$client} = Slim::Buttons::Common::scroll(
						$client,
						-1,
						$#bitrates + 1,
						$current_bitrate{$client} || 0,
					);
		$client->update();
	},
	
	'down' => sub {
		my $client = shift;
		my @bitrates = @{ $bitrates{$current_genre{$client}}{$current_stream{$client}} };
		
		$current_bitrate{$client} = Slim::Buttons::Common::scroll(
						$client,
						1,
						$#bitrates + 1,
						$current_bitrate{$client} || 0,
					);
		$client->update();
	},
	
	'left' => sub {
		my $client = shift;
	
		$leave_bitrate_mode_sub->($client);
		Slim::Buttons::Common::popModeRight($client);
	},
	
	'right' => sub {
		my $client = shift;
		
		Slim::Buttons::Common::pushModeLeft($client, 'ShoutcastStreamInfo');
	},
	
	'play' => sub {
		my $client = shift;
		my $current_genre = $genres[$current_genre{$client}];
		my @streams = @{ $streams{$client}{$current_genre{$client}} };
		my $current_stream = $streams[$current_stream{$client}];
		my @bitrates = @{ $bitrates{$current_genre{$client}}{$current_stream{$client}} };
		my $current_bitrate = $bitrates[$current_bitrate{$client}];
		my $current_data = $stream_data{$current_genre}{$current_stream}{$current_bitrate};
		my $playlist_url = $current_data->[0];
		
		Slim::Control::Command::execute($client, ['playlist', 'load', $playlist_url]);
		add_recent_stream($client, $current_stream, $current_bitrate, $current_data);
	},
	
	'add' => sub {
		my $client = shift;
		my $current_genre = $genres[$current_genre{$client}];
		my @streams = @{ $streams{$client}{$current_genre{$client}} };
		my $current_stream = $streams[$current_stream{$client}];
		my @bitrates = @{ $bitrates{$current_genre{$client}}{$current_stream{$client}} };
		my $current_bitrate = $bitrates[$current_bitrate{$client}];
		my $current_data = $stream_data{$current_genre}{$current_stream}{$current_bitrate};
		my $playlist_url = $current_data->[0];
	
		Slim::Control::Command::execute($client, ['playlist', 'add', $playlist_url]);
	},
	
	'jump_rew' => sub {
		my $client = shift;
	
		$number{$client} = undef;
		
		Slim::Buttons::Common::popModeRight($client);
		Slim::Buttons::Common::popModeRight($client);
		
		&reload_xml($client);
	},
);

##### Sub-mode for stream info #####

our $info_mode_sub = sub {
	my $client = shift;

	$current_info{$client} = 0;
	$client->lines(\&infoLines);
	$client->update();
};

our $leave_info_mode_sub = sub {
	my $client = shift;
};

sub infoLines {
	my $client = shift;
	my (@lines);
	
	$current_genre{$client} ||= 0;
	$current_stream{$client} ||= 0;

	my $current_genre = $genres[$current_genre{$client}];
	my @streams = @{ $streams{$client}{$current_genre{$client}} };
	my $current_stream = $streams[$current_stream{$client}];
	my @bitrates = @{ $bitrates{$current_genre{$client}}{$current_stream{$client}} };
	my $current_bitrate = $bitrates[$current_bitrate{$client}];

	my $current_data;
	
	if (defined $current_genre and defined $current_stream and defined $current_bitrate) {
		$current_data = $stream_data{$current_genre}{$current_stream}{$current_bitrate};
	}
	
	my $cur = $current_info{$client} || 0;

	if (defined $current_stream and defined $current_bitrate) {
		$lines[0] = $current_bitrate . 'kbps - ' .$current_stream;
	}
	
	my $info = $current_data->[$info_index[$cur]] || $client->string('PLUGIN_SHOUTCASTBROWSER_NONE');
	
	$lines[1] = $info_order[$cur] . ': ' . $info;

	return @lines;
}

our %InfoFunctions = (
	'up' => sub {
		my $client = shift;
		
		$current_info{$client} = Slim::Buttons::Common::scroll(
						$client,
						-1,
						$#info_order + 1,
						$current_info{$client} || 0,
					);
		$client->update();
	},
	
	'down' => sub {
		my $client = shift;
		
		$current_info{$client} = Slim::Buttons::Common::scroll(
						$client,
						1,
						$#info_order + 1,
						$current_info{$client} || 0,
					);
		$client->update();
	},
	
	'left' => sub {
		my $client = shift;
		
		$leave_info_mode_sub->($client);
		Slim::Buttons::Common::popModeRight($client);
	},
	
	'right' => sub {
		my $client = shift;
	
		$client->bumpRight();
	},
	
	'play' => sub {
		my $client = shift;
		
		my $current_genre = $genres[$current_genre{$client}];
		my @streams = @{ $streams{$client}{$current_genre{$client}} };
		my $current_stream = $streams[$current_stream{$client}];
		my @bitrates = @{ $bitrates{$current_genre{$client}}{$current_stream{$client}} };
		my $current_bitrate = $bitrates[$current_bitrate{$client}];
		my $current_data = $stream_data{$current_genre}{$current_stream}{$current_bitrate};
		my $playlist_url = $current_data->[0];
	
		Slim::Control::Command::execute($client, ['playlist', 'load', $playlist_url]);
		add_recent_stream($client, $current_stream, $current_bitrate, $current_data);
	},
	
	'add' => sub {
		my $client = shift;
		
		my $current_genre = $genres[$current_genre{$client}];
		my @streams = @{ $streams{$client}{$current_genre{$client}} };
		my $current_stream = $streams[$current_stream{$client}];
		my @bitrates = @{ $bitrates{$current_genre{$client}}{$current_stream{$client}} };
		my $current_bitrate = $bitrates[$current_bitrate{$client}];
		my $current_data = $stream_data{$current_genre}{$current_stream}{$current_bitrate};
		my $playlist_url = $current_data->[0];
	
		Slim::Control::Command::execute($client, ['playlist', 'add', $playlist_url]);
	},
	
	'jump_rew' => sub {
		my $client = shift;
	
		$number{$client} = undef;
		
		Slim::Buttons::Common::popModeRight($client);
		Slim::Buttons::Common::popModeRight($client);
		Slim::Buttons::Common::popModeRight($client);
		
		&reload_xml($client);
	},
);


sub get_recent_streams
{
	my $client = shift;

	my @recent = ();
	open FH, $recent_filename{$client} or do {
			return [ $client->string('PLUGIN_SHOUTCASTBROWSER_NONE') ];
	};

	# Using Slim::Formats::Parse::M3U is unreliable, since it
	# forces us to use Slim::Music::Info::title to get the
	# title, but Info.pm may refuse to give it to us if it
	# thinks the data is "invalid" or something.  Also, we
	# want a list of titles with URLs attached, not vice
	# versa.
	my $title;
	
	while(my $entry = <FH>)
	{
		chomp($entry);
		# strip carriage return from dos playlists
		$entry =~ s/\cM//g;

		# strip whitespace from beginning and end
		$entry =~ s/^\s*//;
		$entry =~ s/\s*$//;

		if ($entry =~ /^#EXTINF:.*?,(.*)$/)
		{
			$title = $1;
		}

		next if $entry =~ /^#/;
		next if $entry eq "";
		$entry =~ s|$LF||g;

		if (defined($title))
		{
			$recent_data{$client}{$title} = $entry;
			push @recent, $title;
			$title = undef;
		}
	}

	close FH;
	return [ @recent ];
}

sub add_recent_stream
{
	my ($client, $new, $bitrate, $data) = @_;
	my $url = $data->[0];
	
	if (defined $bitrate)
	{
	$new = "$bitrate kbps: " . $new;
	}
	
	$recent_data{$client}{$new} = $url;

	my @recent;

	if (exists $streams{$client}{$recent_name}) {
		@recent = @ { $streams{$client}{$recent_name} };
	} else {
		@recent = @{ get_recent_streams($client) };
	}
	
	@recent = () if (@recent == 1 and $recent[0] eq $client->string('PLUGIN_SHOUTCASTBROWSER_NONE'));

	my ($i) = grep $recent[$_] eq $new, 0..$#recent;
	
	if (defined $i) {
		splice @recent, $i, 1;
		unshift @recent, $new;
	} else {
		unshift @recent, $new;
		pop @recent if @recent > $recent_max;
	}

	if (defined $recent_filename{$client})
	{
		open FH, ">$recent_filename{$client}" or do {
			print STDERR "Could not open $recent_filename{$client} for writing.\n";
			return;
		};
	
		print FH "#EXTM3U\n";
	
		foreach my $name (@recent) {
			print FH "#EXTINF:-1,$name\n";
			print FH $recent_data{$client}{$name}."\n";
		}
		
		close FH;
	}
	
	$streams{$client}{$position_of_recent} = [ @recent ];
}



# Add extra modes
Slim::Buttons::Common::addMode('ShoutcastStreams', \%StreamsFunctions,
				$mode_sub, $leave_mode_sub);

Slim::Buttons::Common::addMode('ShoutcastBitrates', \%BitrateFunctions,
				$bitrate_mode_sub, $leave_bitrate_mode_sub);

Slim::Buttons::Common::addMode('ShoutcastStreamInfo', \%InfoFunctions,
				$info_mode_sub, $leave_info_mode_sub);

1;

__DATA__
PLUGIN_SHOUTCASTBROWSER_MODULE_NAME
	EN	SHOUTcast Internet Radio
	DE	SHOUTcast Internet Radio

PLUGIN_SHOUTCASTBROWSER_GENRES
	EN	SHOUTcast Internet Radio
	DE	SHOUTcast Musikstile

PLUGIN_SHOUTCASTBROWSER_CONNECTING
	EN	Connecting to SHOUTcast...
	DE	Verbinde mit der SHOUTcast...

PLUGIN_SHOUTCASTBROWSER_NETWORK_ERROR
	EN	Error: SHOUTcast web site not available
	DE	Fehler: SHOUTcast Web-Seite nicht verfügbar

PLUGIN_SHOUTCASTBROWSER_SHOUTCAST
	EN	SHOUTcast
	DE	SHOUTcast

PLUGIN_SHOUTCASTBROWSER_ALL_STREAMS
	EN	All Streams
	DE	Alle Streams

PLUGIN_SHOUTCASTBROWSER_NONE
	EN	None
	DE	Keine

PLUGIN_SHOUTCASTBROWSER_BITRATE
	EN	Bitrate
	DE	Bitrate

PLUGIN_SHOUTCASTBROWSER_KBPS
	EN	kbps
	DE	kbps

PLUGIN_SHOUTCASTBROWSER_RECENT
	EN	Recently played
	DE	Kürzlich gehört

PLUGIN_SHOUTCASTBROWSER_MOST_POPULAR
	EN	Most Popular
	DE	Populäre Streams

PLUGIN_SHOUTCASTBROWSER_MISC
	EN	Misc. genres
	DE	Diverse Stile

PLUGIN_SHOUTCASTBROWSER_TOO_SOON
	EN	Try again in a minute
	DE	Versuche es in einer Minute wieder

PLUGIN_SHOUTCASTBROWSER_SORTING
	EN	Sorting streams ...
	DE	Sortiere Streams...

SETUP_GROUP_PLUGIN_SHOUTCASTBROWSER
	EN	SHOUTcast Internet Radio

SETUP_GROUP_PLUGIN_SHOUTCASTBROWSER_DESC
	EN	Browse SHOUTcast list of Internet Radio streams.  Hit rewind after changing any settings to reload the list of streams.
	DE	Blättere durch die Liste der SHOUTcast Internet Radiostationen. Drücke nach jedem Einstellungswechsel REW, um die Liste neu zu laden.

SETUP_PLUGIN_SHOUTCASTBROWSER_HOW_MANY_STREAMS
	EN	Number of Streams
	DE	Anzahl Streams

SETUP_PLUGIN_SHOUTCASTBROWSER_HOW_MANY_STREAMS_DESC
	EN	How many streams to get.  Default is 300, maximum is 2000.
	DE	Anzahl aufzulistender Streams (Radiostationen). Voreinstellung ist 300, das Maximum 2000.

SETUP_PLUGIN_SHOUTCASTBROWSER_GENRE_PRIMARY_CRITERION
	EN	Main Sort Criterion for Genres
	DE	Haupt Sortierkriterium für Musikstile

SETUP_PLUGIN_SHOUTCASTBROWSER_GENRE_PRIMARY_CRITERION_DESC
	EN	Primary criterion for sorting genres.
	DE	Erstes Kriterium für die Sortierung der Musikstile

SETUP_PLUGIN_SHOUTCASTBROWSER_GENRE_SECONDARY_CRITERION
	EN	Other Sort Criterion for Genres
	DE	Weiteres Sortierkriterium für Musikstile

SETUP_PLUGIN_SHOUTCASTBROWSER_GENRE_SECONDARY_CRITERION_DESC
	EN	Secondary criterion for sorting genres, if the primary is equal.
	DE	Das zweite Sortierkriterium für Musikstile, falls das erste mehrere Vorkommen hat.

SETUP_PLUGIN_SHOUTCASTBROWSER_STREAM_PRIMARY_CRITERION
	EN	Main Sort Criterion for Streams
	DE	Haupt Sortierkriterium für Streams

SETUP_PLUGIN_SHOUTCASTBROWSER_STREAM_PRIMARY_CRITERION_DESC
	EN	Primary criterion for sorting streams.
	DE	Erstes Kriterium für die Sortierung der Streams (Radiostationen)

SETUP_PLUGIN_SHOUTCASTBROWSER_STREAM_SECONDARY_CRITERION
	EN	Other Sort Criterion for Streams
	DE	Weiteres Sortierkriterium für Streams

SETUP_PLUGIN_SHOUTCASTBROWSER_STREAM_SECONDARY_CRITERION_DESC
	EN	Secondary criterion for sorting streams, if the primary is equal.
	DE	Das zweite Sortierkriterium für Streams (Radiostationen), falls das erste mehrere Vorkommen hat.

SETUP_PLUGIN_SHOUTCASTBROWSER_MIN_BITRATE
	EN	Minimum Bitrate
	DE	Minimale Bitrate

SETUP_PLUGIN_SHOUTCASTBROWSER_MIN_BITRATE_DESC
	EN	Minimum Bitrate in which you are interested (0 for no limit).
	DE	Minimal erwünschte Bitrate (0 für unbeschränkt).

SETUP_PLUGIN_SHOUTCASTBROWSER_MAX_BITRATE
	EN	Maximum Bitrate
	DE	Maximale Bitrate

SETUP_PLUGIN_SHOUTCASTBROWSER_MAX_BITRATE_DESC
	EN	Maximum Bitrate in which you are interested (0 for no limit).
	DE	Maximal erwünschte Bitrate (0 für unbeschränkt).

SETUP_PLUGIN_SHOUTCASTBROWSER_MAX_RECENT
	EN	Recent Streams
	DE	Zuletzt gehörte Streams

SETUP_PLUGIN_SHOUTCASTBROWSER_MAX_RECENT_DESC
	EN	Maximum number of recently played streams to remember.
	DE	Anzahl zu merkender Streams (Radiostationen)

SETUP_PLUGIN_SHOUTCASTBROWSER_MAX_POPULAR
	EN	Most Popular
	DE	Populäre Streams

SETUP_PLUGIN_SHOUTCASTBROWSER_MAX_POPULAR_DESC
	EN	Number of streams to include in the category of most popular streams, measured by the total of all listeners at all bitrates.
	DE	Die Anzahl Streams, die unter "Populäre Streams" aufgeführt werden sollen. Die Beliebtheit misst sich an der Anzahl Hörer aller Bitraten.

SETUP_PLUGIN_SHOUTCASTBROWSER_CUSTOM_GENRES
	EN	Custom Genre Definitions
	DE	Eigene Musikstil-Definitionen

SETUP_PLUGIN_SHOUTCASTBROWSER_CUSTOM_GENRES_DESC
	EN	You can define your own SHOUTcast categories by indicating the name of a custom genre definition file here.  Each line in this file defines a category per line, and each line consists of a series of terms separated by whitespace.  The first term is the name of the genre, and each subsequent term is a pattern associated with that genre.  If any of these patterns matches the advertised genre of a stream, that stream is considered to belong to that genre.  You may use an underscore to represent a space within any of these terms, and in the patterns, case does not matter.
	DE	Sie können eigene SHOUTcast-Kategorien definieren, indem Sie hier eine Datei mit den eigenen Musikstil-Definitionen angeben. Jede Zeile dieser Datei bezeichnet eine Kategorie, und besteht aus einer Serie von Ausdrücken, die durch Leerzeichen getrennt sind. Der erste Ausdruck ist der Name des Musikstils, alle folgenden bezeichnen ein Textmuster, das mit diesem Musikstil assoziiert wird. Jeder Stream, dessen Stil eines dieser Textmuster enthält, wird diesem Musikstil zugeordnet. Leerzeichen innerhalb eines Begriffs können durch Unterstriche (_) definiert werden. Gross-/Kleinschreibung ist irrelevant.

SETUP_PLUGIN_SHOUTCASTBROWSER_ALPHA_REVERSE
	EN	Alphabetical (reverse)
	DE	Alphabetisch (umgekehrte Reihenfolge)

SETUP_PLUGIN_SHOUTCASTBROWSER_NUMBEROFSTREAMS
	EN	Number of streams
	DE	Anzahl Streams

SETUP_PLUGIN_SHOUTCASTBROWSER_NUMBEROFSTREAMS_REVERSE
	EN	Number of streams (reverse)
	DE	Anzahl Streams (umgekehrte Reihenfolge)

SETUP_PLUGIN_SHOUTCASTBROWSER_DEFAULT_ALPHA
	EN	Default (alphabetical)
	DE	Standard (alphabetisch)

SETUP_PLUGIN_SHOUTCASTBROWSER_NUMBEROFLISTENERS
	EN	Number of listeners
	DE	Anzahl Hörer

SETUP_PLUGIN_SHOUTCASTBROWSER_NUMBEROFLISTENERS_REVERSE
	EN	Number of listeners (reverse)
	DE	Anzahl Hörer (umgekehrte Reihenfolge)

SETUP_PLUGIN_SHOUTCASTBROWSER_KEYWORD
	EN	Order of definition
	DE	Definitions-Reihenfolge

SETUP_PLUGIN_SHOUTCASTBROWSER_KEYWORD_REVERSE
	EN	Order of definition (reverse)
	DE	Definitions-Reihenfolge (umgekehrt)
