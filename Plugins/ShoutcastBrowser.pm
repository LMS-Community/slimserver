# ShoutcastBrowser.pm Copyright (C) 2003 Peter Heslin
# version 3.0, 5 Apr, 2004
#$Id: ShoutcastBrowser.pm,v 1.7 2004/04/23 16:24:57 dean Exp $
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

# * Get rid of hard-coded @genre_keywords, and generate it
#  instead from a word frequency list -- which will mean a list of
#  excluded, rather than included, words.

package Plugins::ShoutcastBrowser;
use strict;

################### Configuration Section ########################

### These first few preferences can only be set by editing this file
my (%genre_aka, @genre_keywords, $munge_genres, @legit_genres);

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
my ($prefs_override, @genre_criteria, @stream_criteria, $how_many_streams);
my ($min_bitrate, $max_bitrate, $recent_max);
my $lump_singletons = 1;

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
my @info_order = ('Name', 'Listeners', 'Bitrate', 'Was Playing', 'Url', 'Genre');
my @info_index = ( 2,      3,           4,         5,             0,     6     );

my ($recent_name, $misc_genre);
my $position_of_recent = 0;
my $all_name = '';
my $sort_bitrate_up = 0;

my $recent_filename;
# TODO: MacOS X should really store this in a visible, findable place.
if (Slim::Utils::OSDetect::OS() eq 'unix') {
    $recent_filename = '.shoutcastbrowser.recent';
} else {
    $recent_filename ='shoutcastbrowser.recent';
}
# put it in the same folder as the preferences.
$recent_filename = catdir(Slim::Utils::Prefs::preferencesPath(), $recent_filename);

my $debug = 0;
my (%current_genre, %current_stream, %status, %number, %current_info);
my $last_time = 0;

my (@genres, %streams, %stream_data, %bitrates, %current_bitrate);

my %genre_transform;
for my $key (keys %genre_aka)
{
    my $rx;
    if (ref $genre_aka{$key})
    {
	$rx = join '|', @{ $genre_aka{$key} };
    }
    else
    {
	$rx = $genre_aka{$key};
    }
    $rx = "\L$rx";
    $rx =~ s/_/ /g;
    unless (grep {$_ eq $key} @genre_keywords)
    {
	push @genre_keywords, $key;
    }
    $key = "\L$key";
    $key =~ s/_/ /g;
    $genre_transform{$rx} = $key;
}

my $genre_list = join '|', @genre_keywords;
$genre_list = "\L$genre_list";
$genre_list =~ s/_/ /g;

my %keyword_index;
if (grep {$_ =~ m/keyword/i} @genre_criteria)
{
    my $i = 1;
    for (@genre_keywords)
    {
	$keyword_index{$_} = $i;
	$i++;
    }
}

my %legit_genres;
for my $g (@legit_genres)
{
    $g = "\L$g";
    $g =~ s/\s+/ /g;
    $g =~ s/^ //;
    $g =~ s/ $//;
    $g = "\u$g";
    $legit_genres{$g}++;
}

eval {
   use Storable qw(store_fd retrieve_fd);
};
use Fcntl qw(:DEFAULT :flock);
use File::Spec::Functions qw(:ALL);
use Slim::Control::Command;
use Slim::Utils::Strings qw (string);
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Display::Display;
use LWP::Simple;
use HTML::Entities;
my $have_zlib = eval 'use Compress::Zlib; 1;';
my $have_storable = eval 'use Storable; 1;';

sub getDisplayName {return string('PLUGIN_SHOUTCASTBROWSER_MODULE_NAME')}

sub strings
{
    local $/ = undef;
    <DATA>;
}

sub get_prefs
{
    if ((not $prefs_override) and
	Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_how_many_streams'))
    {
	$how_many_streams =
	    Slim::Utils::Prefs::get('plugin_shoutcastbrowser_how_many_streams');
    }
    if ((not $prefs_override) and
	Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_genre_primary_criterion')
	and
	Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_genre_secondary_criterion'))
    {
	@genre_criteria =
	    ( Slim::Utils::Prefs::get('plugin_shoutcastbrowser_genre_primary_criterion'),
	      Slim::Utils::Prefs::get('plugin_shoutcastbrowser_genre_secondary_criterion'));
    }
    if ((not $prefs_override) and
	Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_stream_primary_criterion')
	and
	Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_stream_secondary_criterion'))
    {
	@stream_criteria =
	    ( Slim::Utils::Prefs::get('plugin_shoutcastbrowser_stream_primary_criterion'),
	      Slim::Utils::Prefs::get('plugin_shoutcastbrowser_stream_secondary_criterion'));
    }
    if ((not $prefs_override) and
	Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_min_bitrate'))
    {
	$min_bitrate =
	    Slim::Utils::Prefs::get('plugin_shoutcastbrowser_min_bitrate');
    }
    if ((not $prefs_override) and
	Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_max_bitrate'))
    {
	$max_bitrate =
	    Slim::Utils::Prefs::get('plugin_shoutcastbrowser_max_bitrate');
    }
    if ((not $prefs_override) and
	Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_max_recent'))
    {
	$recent_max =
	    Slim::Utils::Prefs::get('plugin_shoutcastbrowser_max_recent');
    }

    # Fallback defaults if undefined in prefs or at start of this file
    $how_many_streams = 300 unless $how_many_streams;
    @genre_criteria  = qw(streams name) unless @genre_criteria;
    @stream_criteria = qw(listeners bitrate name) unless @stream_criteria;
    $lump_singletons = 1 if ($genre_criteria[0] =~ m/default/i);
    $recent_max = 50 unless defined $recent_max;
}

##### Main mode for genres #####

sub setMode
{
    my $client = shift;
    $client->lines(\&lines);
    $status{$client} = 0;
    $number{$client} = undef;
    $client->update();
    &get_prefs;

    # Get streams
    unless (@genres)
    {
	$recent_name = Slim::Utils::Strings::string('PLUGIN_SHOUTCASTBROWSER_RECENT');
	$misc_genre= Slim::Utils::Strings::string('PLUGIN_SHOUTCASTBROWSER_MISC');
	%stream_data = ();
	%streams = ();
	%bitrates = ();
	$current_genre{$client} = 0;
	$current_stream{$client} = 0;
	$current_bitrate{$client} = 0;
	my %in_genres;
	$all_name = Slim::Utils::Strings::string('PLUGIN_SHOUTCASTBROWSER_ALL_STREAMS');

	my $u = unpack 'u', q{M:'1T<#HO+W-H;W5T8V%S="YC;VTO<V)I;B]X;6QL:7-T97(N<&AT;6P_<V5R
+=FEC93U3;&E-4#,`
};
	$u .= '&no_compress=1' unless $have_zlib;
	$u .= "&limit=$how_many_streams" if $how_many_streams;
	my $xml = get($u);
	$last_time = time;
	unless ($xml)
	{
	    $status{$client} = -1;
	    $client->update();
	    return;
	}
	if ($have_zlib)
	{
	    $xml = Compress::Zlib::uncompress($xml);
	}

	my ($label) = $xml =~ m#<playlist[^>]*label="?([^">]+)"?>#s;

	while ($xml =~ m#<entry([^>]*)>(.*?)</entry>#gs)
	{
	    my $attr = $1;
	    my $entry = $2;
	    my ($url) = $attr =~ m#playstring="?([^">]+)"?#is;
	    my ($name) = $entry =~ m#<name[^>]*>(.*?)</name>#is;
	    my ($genre) = $entry =~ m#<genre[^>]*>(.*?)</genre>#is;
	    my ($now_playing) = $entry =~ m#<Nowplaying[^>]*>(.*?)</Nowplaying>#is;
	    my ($listeners) = $entry =~ m#<listeners[^>]*>(.*?)</listeners>#is;
	    my ($bitrate) = $entry =~ m#<bitrate[^>]*>(.*?)</bitrate>#is;

	    next if ($min_bitrate and $bitrate < $min_bitrate);
	    next if ($max_bitrate and $bitrate > $max_bitrate);

	    $genre =~ s/%([\dA-F][\dA-F])/chr hex $1/gei;#encoded chars
	    $name =~ s/%([\dA-F][\dA-F])/chr hex $1/gei;
	    $now_playing =~ s/%([\dA-F][\dA-F])/chr hex $1/gei;

	    decode_entities ($name);
	    decode_entities ($genre);
	    decode_entities ($now_playing);

	    $name =~ s#\b([\w-]) ([\w-]) #$1$2#g;#S P A C E D  W O R D S
	    $name =~ s#\b(ICQ|AIM|MP3Pro)\b##i;# we don't care
	    $name =~ s#\W\W\W\W+# #g;# excessive non-word characters
	    $name =~ s#^\W+##;# leading non-word characters
	    $genre =~ s/\s+/ /g;

	    my $full_text;
	    my @keywords = ();
	    my $original = $genre;
	    if ($munge_genres)
	    {
		$genre = "\L$genre";
		$genre =~ s/\s+/ /g;
		$genre =~ s/^ //;
		$genre =~ s/ $//;

		for (keys %genre_transform)
		{
		    $genre =~ s/$_/$genre_transform{$_}/g;
		}
		while ($genre =~ m/($genre_list)/g)
		{
		    push @keywords, "\u$1";
		}
		$genre = "\u$genre";
		$genre = 'Unknown' if ($genre eq ' ' or $genre eq '');

		$full_text= "$name | ${bitrate}kbps | $listeners online | $original | ";
	    }
	    else
	    {
		$full_text= "$name | ${bitrate}kbps | $listeners online | ";
	    }

	    my $data =
		[$url, $full_text, $name, $listeners, $bitrate, $now_playing, $original];

	    @keywords = ($genre) unless @keywords;
	    foreach my $g (@keywords)
	    {
		$stream_data{$g}{$name}{$bitrate} = $data;
		$in_genres{$name}++;
	    }
	    $stream_data{$all_name}{$name}{$bitrate} = $data;
	}

	if ($lump_singletons)
	{
	    foreach my $g (keys %stream_data)
	    {
		if ((exists $legit_genres{$g}) or
		    (keys %{ $stream_data{$g} } > 1))
		{
		    push @genres, $g;
		}
		else
		{
		    my ($n) = keys %{ $stream_data{$g} };
		    unless (exists $stream_data{$misc_genre}{$n})
		    {
			$in_genres{$n}--;
			if ($in_genres{$n} == 0)
			{
			    $stream_data{$misc_genre}{$n} = $stream_data{$g}{$n};
			}
			delete $stream_data{$g};
		    }
		}
	    }
	}
	@genres = keys %stream_data;
	@genres = sort genre_sort @genres;
	unshift @genres, $recent_name if $have_storable;

    }
    $status{$client} = 1;
    $client->update();
}

sub genre_sort
{
    my $r = 0;
    return -1 if $a eq $all_name;
    return 1  if $b eq $all_name;
    return 1  if $a eq $misc_genre;
    return -1 if $b eq $misc_genre;
    for my $criterion (@genre_criteria)
    {
	if ($criterion =~ m/^streams/i)
	{
	    $r = keys %{ $stream_data{$b} } <=> keys %{ $stream_data{$a} };
	}
	elsif ($criterion =~ m/^keyword/i)
	{
	    if ($keyword_index{lc($a)})
	    {
		if ($keyword_index{lc($b)})
		{
		    $r = $keyword_index{lc($a)} <=> $keyword_index{lc($b)};
		}
		else { $r = -1; }
	    }
	    else
	    {
		if ($keyword_index{lc($b)})
		{ $r = 1; }
		else
		{ $r = 0; }
	    }
	}
	elsif ($criterion =~ m/^name/i or $criterion =~ m/^default/i)
	{
	    $r = (lc($a) cmp lc($b));
	}
	$r = -1 * $r if $criterion =~ m/reverse$/i;
	return $r if $r;
    }
    return $r;
}

sub reload_xml
{
    my $client = shift;
    if (time() < $last_time + 60)
    {
	$status{$client} = -2;
	$client->update();
	sleep 1;
	$status{$client} = 1;
	$client->update();
    }
    else
    {
	$status{$client} = 0;
	$client->update();
	@genres = ();
	&setMode($client);
    }
}

my %functions =
    (
     'up' => sub
     {
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
     'down' => sub
     {
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
     'left' => sub
     {
	 my $client = shift;
	 $number{$client} = undef;
	 Slim::Buttons::Common::popModeRight($client);
     },
     'right' => sub
     {
	 my $client = shift;
	 $number{$client} = undef;
	 Slim::Buttons::Common::pushModeLeft($client, 'ShoutcastStreams');
     },
     'jump_rew' => sub
     {
	 my $client = shift;
	 $number{$client} = undef;
	 &reload_xml($client);
     },
     'numberScroll' => sub
     {
	 my ($client, $button, $digit) = @_;
	 if ($digit == 0 and (not $number{$client}))
	 {
	     $current_genre{$client} = 0;
	 }
	 else
	 {
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

    if ($status{$client} == 0)
    {
	$lines[0] = Slim::Utils::Strings::string('PLUGIN_SHOUTCASTBROWSER_CONNECTING');
	$lines[1] = '';
    }
    elsif ($status{$client} == -1)
    {
	$lines[0] = Slim::Utils::Strings::string('PLUGIN_SHOUTCASTBROWSER_NETWORK_ERROR');
	$lines[1] = '';
    }
    elsif ($status{$client} == -2)
    {
	$lines[0] = Slim::Utils::Strings::string('PLUGIN_SHOUTCASTBROWSER_TOO_SOON');
	$lines[1] = '';
    }
    elsif ($status{$client} == 1)
    {
	my $current_name = $genres[$current_genre{$client}];
	$lines[0] = Slim::Utils::Strings::string('PLUGIN_SHOUTCASTBROWSER_GENRES').
	    ' (' .
		($current_genre{$client} + 1) .  ' ' .
		    Slim::Utils::Strings::string('OF') .  ' ' .
			    ($#genres + 1) .  ') ' ;
	$lines[1] = $current_name;
	$lines[3] = Slim::Hardware::VFD::symbol('rightarrow');
    }

    return @lines;
}

sub getFunctions { return \%functions; }

sub setupGroup
{
    my %setupGroup =
	(
	 PrefOrder =>
	 [
	  'plugin_shoutcastbrowser_how_many_streams',
	  'plugin_shoutcastbrowser_genre_primary_criterion',
	  'plugin_shoutcastbrowser_genre_secondary_criterion',
	  'plugin_shoutcastbrowser_stream_primary_criterion',
	  'plugin_shoutcastbrowser_stream_secondary_criterion',
	  'plugin_shoutcastbrowser_min_bitrate',
	  'plugin_shoutcastbrowser_max_bitrate',
	  'plugin_shoutcastbrowser_max_recent'
	 ],
	 GroupHead => string('SETUP_GROUP_PLUGIN_SHOUTCASTBROWSER'),
	 GroupDesc => string('SETUP_GROUP_PLUGIN_SHOUTCASTBROWSER_DESC'),
	 GroupLine => 1,
	 GroupSub => 1,
	 Suppress_PrefSub => 1,
	 Suppress_PrefLine => 1
	);

    my %genre_options = (
#			 name => 'Alphabetical',
			 name_reverse => 'Alphabetical (reverse)',
			 streams => 'Number of streams',
			 streams_reverse => 'Number of streams (reverse)',
#			 keyword => 'By genre keyword',
#			 keyword_reverse => 'By genre keyword (reverse)',
			 default => 'Default (alphabetical)'
			);

    my %stream_options = (
#			  name => 'Alphabetical',
			 name_reverse => 'Alphabetical (reverse)',
			 listeners => 'Number of listeners',
			 listeners_reverse => 'Number of listeners (reverse)',
#			 bitrate => 'By bitrate',
#			 bitrate_reverse => 'By bitrate (reverse)',
			 default => 'Default (alphabetical)'
			);

    my %setupPrefs =
	(
	 plugin_shoutcastbrowser_how_many_streams =>
	 {
 	  validate => \&Slim::Web::Setup::validateInt,
 	  validateArgs => [1,2000,1,2000]
	 },
	 plugin_shoutcastbrowser_genre_primary_criterion =>
	 {
	  options => \%genre_options
	 },
	 plugin_shoutcastbrowser_genre_secondary_criterion =>
	 {
	  options => \%genre_options
	 },
	 plugin_shoutcastbrowser_stream_primary_criterion =>
	 {
	  options => \%stream_options
	 },
	 plugin_shoutcastbrowser_stream_secondary_criterion =>
	 {
	  options => \%stream_options
	 },
	 plugin_shoutcastbrowser_min_bitrate =>
	 {
 	  validate => \&Slim::Web::Setup::validateInt,
 	  validateArgs => [0, undef, 0]
	 },
	 plugin_shoutcastbrowser_max_bitrate =>
	 {
 	  validate => \&Slim::Web::Setup::validateInt,
 	  validateArgs => [0, undef, 0]
	 },
	 plugin_shoutcastbrowser_max_recent =>
	 {
 	  validate => \&Slim::Web::Setup::validateInt,
 	  validateArgs => [0, undef, 0]
	 }
	);
    &checkDefaults;
    return (\%setupGroup,\%setupPrefs);
}

sub checkDefaults
{
    if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_how_many_streams'))
    {
	Slim::Utils::Prefs::set('plugin_shoutcastbrowser_how_many_streams', 300);
    }
    if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_genre_primary_criterion'))
    {
	Slim::Utils::Prefs::set('plugin_shoutcastbrowser_genre_primary_criterion', 'default');
    }
    if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_genre_secondary_criterion'))
    {
	Slim::Utils::Prefs::set('plugin_shoutcastbrowser_genre_secondary_criterion', 'default');
    }
    if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_stream_primary_criterion'))
    {
	Slim::Utils::Prefs::set('plugin_shoutcastbrowser_stream_primary_criterion', 'default');
    }
    if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_stream_secondary_criterion'))
    {
	Slim::Utils::Prefs::set('plugin_shoutcastbrowser_stream_secondary_criterion', 'default');
    }
    if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_min_bitrate'))
    {
	Slim::Utils::Prefs::set('plugin_shoutcastbrowser_min_bitrate', 0);
    }
    if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_max_bitrate'))
    {
	Slim::Utils::Prefs::set('plugin_shoutcastbrowser_max_bitrate', 0);
    }
    if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_max_recent'))
    {
	Slim::Utils::Prefs::set('plugin_shoutcastbrowser_max_recent', 50);
    }
}


##### Sub-mode for streams #####

my $mode_sub = sub
{
    my $client = shift;
    $client->lines(\&streamsLines);
    $status{$client} = -3;
    $number{$client} = undef;
    $current_stream{$client} = 0 unless $current_stream{$client};
    $client->update();

    # Closure for the sake of $client
    my $stream_sort = sub
    {
	my $r = 0;
	for my $criterion (@stream_criteria)
	{
	    if ($criterion =~ m/^listener/i)
	    {
		my ($aa, $bb) = (0, 0);
		my $current_genre = $genres[$current_genre{$client}];
		$aa += $stream_data{$current_genre}{$a}{$_}[3]
		    foreach keys %{ $stream_data{$current_genre}{$a} };
		$bb += $stream_data{$current_genre}{$b}{$_}[3]
		    foreach keys %{ $stream_data{$current_genre}{$b} };
		$r = $bb <=> $aa;
	    }
	    elsif ($criterion =~ m/^name/i or $criterion =~ m/default/i)
	    {
		$r = lc($a) cmp lc($b);
	    }
	    $r = -1 * $r if $criterion =~ m/reverse$/i;
	    return $r if $r;
	}
	return $r;
    };

    unless(exists $streams{$current_genre{$client}})
    {
	my $current_genre = $genres[$current_genre{$client}];
	my $sorted_streams_ref;
	if ($current_genre eq $recent_name)
	{
	    my $fh = FileHandle->new();
	    $fh->open("<$recent_filename");
	    flock($fh, LOCK_EX);
	    $streams{$current_genre{$client}} = get_recent_streams($fh);
	    $fh->close;
	}
	else
	{
	    $streams{$current_genre{$client}} =
		[ sort $stream_sort keys %{ $stream_data{$current_genre} } ];
	}
    }
    $status{$client} = 1;
    $client->update();
};

my $leave_mode_sub = sub
{
    my $client = shift;
    $number{$client} = undef;
};

sub streamsLines
{
    my $client = shift;
    my (@lines);
    $current_stream{$client} ||= 0;

    if ($status{$client} == 0)
    {
	$lines[0] = Slim::Utils::Strings::string('PLUGIN_SHOUTCASTBROWSER_CONNECTING');
	$lines[1] = '';
    }
    elsif ($status{$client} == -1)
    {
	$lines[0] = Slim::Utils::Strings::string('PLUGIN_SHOUTCASTBROWSER_NETWORK_ERROR');
	$lines[1] = '';
    }
    elsif ($status{$client} == -2)
    {
	$lines[0] = Slim::Utils::Strings::string('PLUGIN_SHOUTCASTBROWSER_TOO_SOON');
	$lines[1] = '';
    }
    elsif ($status{$client} == -3)
    {
	$lines[0] =
	    Slim::Utils::Strings::string('PLUGIN_SHOUTCASTBROWSER_SORTING');
	$lines[1] = '';
    }
    elsif ($status{$client} == 1)
    {
	# print STDERR join ', ', %streams;
	my @streams = @{ $streams{$current_genre{$client}} };

	my $current_name = $streams[$current_stream{$client}];

	$lines[0] = Slim::Utils::Strings::string('PLUGIN_SHOUTCASTBROWSER_STREAMS').  ' '.
	    Slim::Utils::Strings::string('FOR') .  ' ' .
		    $genres[$current_genre{$client}] .
			' (' .
			    ($current_stream{$client} + 1) .  ' ' .
				Slim::Utils::Strings::string('OF') .  ' ' .
					($#streams + 1) .  ') ' ;
	$lines[1] = $current_name;
	}

    return @lines;
}

my %StreamsFunctions =
    (
     'up' => sub
     {
	 my $client = shift;
	 $number{$client} = undef;
	 my @streams = @{ $streams{$current_genre{$client}} };
	 $current_stream{$client} = 
	     Slim::Buttons::Common::scroll(
					   $client,
					   -1,
					   $#streams + 1,
					   $current_stream{$client} || 0,
					  );
	 $client->update();
     },
     'down' => sub
     {
	 my $client = shift;
	 $number{$client} = undef;
	 my @streams = @{ $streams{$current_genre{$client}} };
	 $current_stream{$client} =
	     Slim::Buttons::Common::scroll(
					   $client,
					   1,
					   $#streams + 1,
					   $current_stream{$client} || 0,
					  );
	 $client->update();
     },
     'left' => sub
     {
	 my $client = shift;
	 $number{$client} = undef;
	 $current_stream{$client} = 0;
	 $leave_mode_sub->($client);
	 Slim::Buttons::Common::popModeRight($client);
     },
     'right' => sub
     {
	 my $client = shift;
	 $number{$client} = undef;
	 my @streams = @{ $streams{$current_genre{$client}} };
	 if (@streams ==  1 and $streams[0] eq
	     Slim::Utils::Strings::string('PLUGIN_SHOUTCASTBROWSER_NONE'))
	 {
	     Slim::Display::Animation::bumpRight($client);
	 }
	 else
	 {
	     Slim::Buttons::Common::pushModeLeft($client, 'ShoutcastBitrates');
	 }
     },
     'play' => sub
     {
	 my $client = shift;
	 Slim::Control::Command::execute($client, ['playlist', 'clear']);
	 my $current_genre = $genres[$current_genre{$client}];
	 my @streams = @{ $streams{$current_genre{$client}} };
	 my $current_stream = $streams[$current_stream{$client}];
	 for my $b (sort bitrate_sort
		    keys %{ $stream_data{$current_genre}{$current_stream} })
         {
	     my $current_data =
		 $stream_data{$current_genre}{$current_stream}{$b};
	     my $playlist_url = $current_data->[0];
	     Slim::Control::Command::execute($client, ['playlist', 'add', $playlist_url]);
	     add_recent_stream($client, $current_stream, $b, $current_data);
	 }
	 Slim::Control::Command::execute($client, ['play']);
	 if ($current_genre{$client} == $position_of_recent)
	 {
	     # Show newly-promoted stream
	     $current_stream{$client} = 0;
	 }
     },
     'add' => sub
     {
	 my $client = shift;
	 my $current_genre = $genres[$current_genre{$client}];
	 my @streams = @{ $streams{$current_genre{$client}} };
	 my $current_stream = $streams[$current_stream{$client}];
	 for my $b (sort bitrate_sort
		    keys %{ $stream_data{$current_genre}{$current_stream} })
         {
	     my $current_data =
		 $stream_data{$current_genre}{$current_stream}{$b};
	     my $playlist_url = $current_data->[0];
	     Slim::Control::Command::execute($client, ['playlist', 'add', $playlist_url]);
	 }
     },
     'jump_rew' => sub
     {
	 my $client = shift;
	 $number{$client} = undef;
 	 Slim::Buttons::Common::popModeRight($client);
	 &reload_xml($client);
     },
      'numberScroll' => sub
     {
	 my ($client, $button, $digit) = @_;
	 if ($digit == 0 and (not $number{$client}))
	 {
	     $current_stream{$client} = 0;
	 }
	 else
	 {
	     $number{$client} .= $digit;
	     $current_stream{$client} = $number{$client} - 1;
	 }
	 $client->update();
     }
    );

##### Sub-mode for bitrates #####

my $bitrate_mode_sub = sub
{
    my $client = shift;
    unless(exists $bitrates{$current_genre{$client}}{$current_stream{$client}})
    {
	bitrate_mode_helper($client);
    }
    $client->lines(\&bitrateLines);
    $client->update();
};


sub bitrate_mode_helper
{
    my $client = shift;
    my $current_genre   = $genres[$current_genre{$client}];
    my @streams         = @{ $streams{$current_genre{$client}} };
    my $current_stream  = $streams[$current_stream{$client}];

    my @bitrates = sort bitrate_sort keys
	%{ $stream_data{$current_genre}{$current_stream} };

    $bitrates{$current_genre{$client}}{$current_stream{$client}} = [@bitrates];
}

my $leave_bitrate_mode_sub = sub
{
    my $client = shift;
};

sub bitrate_sort
{
    my $r = $b <=> $a;
    $r = -$r if $sort_bitrate_up;
    return $r;
}

sub bitrateLines
{
    my $client = shift;
    my (@lines);
    $current_bitrate{$client} ||= 0;

    my @bitrates = @{ $bitrates{$current_genre{$client}}{$current_stream{$client}} };

    my @streams = @{ $streams{$current_genre{$client}} };
    my $current_stream = $streams[$current_stream{$client}];

    if ($#bitrates == 0)
    {
	$lines[0] = Slim::Utils::Strings::string('PLUGIN_SHOUTCASTBROWSER_BITRATE');
    }
    else
    {
	$lines[0] = Slim::Utils::Strings::string('PLUGIN_SHOUTCASTBROWSER_BITRATES').
	    ' (' . ($current_bitrate{$client} + 1) .  ' ' .
		Slim::Utils::Strings::string('OF') .  ' ' .
			($#bitrates + 1) .  ') ' ;
    }
    $lines[1] = $bitrates[$current_bitrate{$client}];

    return @lines;
}

my %BitrateFunctions =
    (
     'up' => sub
     {
	 my $client = shift;
	    my @bitrates =
		@{ $bitrates{$current_genre{$client}}{$current_stream{$client}} };
	 $current_bitrate{$client} =
	     Slim::Buttons::Common::scroll(
					   $client,
					   -1,
					   $#bitrates + 1,
					   $current_bitrate{$client} || 0,
					  );
	 $client->update();
     },
     'down' => sub
     {
	 my $client = shift;
	    my @bitrates =
		@{ $bitrates{$current_genre{$client}}{$current_stream{$client}} };
	 $current_bitrate{$client} =
	     Slim::Buttons::Common::scroll(
					   $client,
					   1,
					   $#bitrates + 1,
					   $current_bitrate{$client} || 0,
					  );
	 $client->update();
     },
     'left' => sub
     {
	 my $client = shift;
	 $current_bitrate{$client} = 0;
	 $leave_bitrate_mode_sub->($client);
	 Slim::Buttons::Common::popModeRight($client);
     },
     'right' => sub
     {
	 my $client = shift;
	 Slim::Buttons::Common::pushModeLeft($client, 'ShoutcastStreamInfo');
     },
     'play' => sub
     {
	 my $client = shift;
	 my $current_genre = $genres[$current_genre{$client}];
	 my @streams = @{ $streams{$current_genre{$client}} };
	 my $current_stream = $streams[$current_stream{$client}];
	 my @bitrates = @{ $bitrates{$current_genre{$client}}{$current_stream{$client}} };
	 my $current_bitrate = $bitrates[$current_bitrate{$client}];
	 my $current_data =
	     $stream_data{$current_genre}{$current_stream}{$current_bitrate};
	 my $playlist_url = $current_data->[0];
	 Slim::Control::Command::execute($client, ['playlist', 'load', $playlist_url]);
	 add_recent_stream($client, $current_stream, $current_bitrate, $current_data);
	 if ($current_genre{$client} == $position_of_recent)
	 {
	     Slim::Buttons::Common::popModeRight($client);
	     $current_stream{$client} = 0;
	 }
     },
     'add' => sub
     {
	 my $client = shift;
	 my $current_genre = $genres[$current_genre{$client}];
	 my @streams = @{ $streams{$current_genre{$client}} };
	 my $current_stream = $streams[$current_stream{$client}];
	 my @bitrates = @{ $bitrates{$current_genre{$client}}{$current_stream{$client}} };
	 my $current_bitrate = $bitrates[$current_bitrate{$client}];
	 my $current_data =
	     $stream_data{$current_genre}{$current_stream}{$current_bitrate};
	 my $playlist_url = $current_data->[0];
	 Slim::Control::Command::execute($client, ['playlist', 'add', $playlist_url]);
     },
     'jump_rew' => sub
     {
	 my $client = shift;
	 $number{$client} = undef;
 	 Slim::Buttons::Common::popModeRight($client);
 	 Slim::Buttons::Common::popModeRight($client);
	 &reload_xml($client);
     },
    );




##### Sub-mode for stream info #####

my $info_mode_sub = sub {
    my $client = shift;
    $client->lines(\&infoLines);
    $client->update();
};

my $leave_info_mode_sub = sub
{
    my $client = shift;
};

sub infoLines
{
    my $client = shift;
    my (@lines);
    $current_stream{$client} ||= 0;

    my $current_genre = $genres[$current_genre{$client}];
    my @streams = @{ $streams{$current_genre{$client}} };
    my $current_stream = $streams[$current_stream{$client}];
    my @bitrates = @{ $bitrates{$current_genre{$client}}{$current_stream{$client}} };
    my $current_bitrate = $bitrates[$current_bitrate{$client}];

    my $current_data;
    if (defined $current_genre and defined $current_stream and defined $current_bitrate)
    {
	$current_data =
	    $stream_data{$current_genre}{$current_stream}{$current_bitrate};
    } 
    my $cur = $current_info{$client} || 0;

    if (defined $current_stream and defined $current_bitrate)
    {
	$lines[0] = $current_bitrate . 'kbps : ' .$current_stream;
    }
    my $info = $current_data->[$info_index[$cur]] ||
	Slim::Utils::Strings::string('PLUGIN_SHOUTCASTBROWSER_NONE');
    $lines[1] = $info_order[$cur] . ': ' . $info;

    return @lines;
}

my %InfoFunctions =
    (
     'up' => sub
     {
	 my $client = shift;
	 $current_info{$client} = 
	     Slim::Buttons::Common::scroll(
					   $client,
					   -1,
					   $#info_order + 1,
					   $current_info{$client} || 0,
					  );
	 $client->update();
     },
     'down' => sub
     {
	 my $client = shift;
	 $current_info{$client} =
	     Slim::Buttons::Common::scroll(
					   $client,
					   1,
					   $#info_order + 1,
					   $current_info{$client} || 0,
					  );
	 $client->update();
     },
     'left' => sub
     {
	 my $client = shift;
	 $current_info{$client} = 0;
	 $leave_info_mode_sub->($client);
	 Slim::Buttons::Common::popModeRight($client);
     },
     'right' => sub
     {
	 my $client = shift;
	 Slim::Display::Animation::bumpRight($client);
     },
     'play' => sub
     {
	 my $client = shift;
	 my $current_genre = $genres[$current_genre{$client}];
	 my @streams = @{ $streams{$current_genre{$client}} };
	 my $current_stream = $streams[$current_stream{$client}];
	 my @bitrates = @{ $bitrates{$current_genre{$client}}{$current_stream{$client}} };
	 my $current_bitrate = $bitrates[$current_bitrate{$client}];
	 my $current_data =
	     $stream_data{$current_genre}{$current_stream}{$current_bitrate};
	 my $playlist_url = $current_data->[0];
	 Slim::Control::Command::execute($client, ['playlist', 'load', $playlist_url]);
	 add_recent_stream($client, $current_stream, $current_bitrate, $current_data);
	 if ($current_genre{$client} == $position_of_recent)
	 {
	     Slim::Buttons::Common::popModeRight($client);
	     Slim::Buttons::Common::popModeRight($client);
	     $current_stream{$client} = 0;
	 }
     },
     'add' => sub
     {
	 my $client = shift;
	 my $current_genre = $genres[$current_genre{$client}];
	 my @streams = @{ $streams{$current_genre{$client}} };
	 my $current_stream = $streams[$current_stream{$client}];
	 my @bitrates = @{ $bitrates{$current_genre{$client}}{$current_stream{$client}} };
	 my $current_bitrate = $bitrates[$current_bitrate{$client}];
	 my $current_data =
	     $stream_data{$current_genre}{$current_stream}{$current_bitrate};
	 my $playlist_url = $current_data->[0];
	 Slim::Control::Command::execute($client, ['playlist', 'add', $playlist_url]);
     },
     'jump_rew' => sub
     {
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
    my $fh = shift;
    if (-f $recent_filename)
    {
	my $ref = retrieve_fd($fh);
	warn "ShoutcastBrowser: Cannot retrieve recent streams from $recent_filename"
	    unless defined $ref;
	$stream_data{$recent_name} = $ref->[0];
	my $recent_streams = $ref->[1];
	return $recent_streams;
    }
    return [ Slim::Utils::Strings::string('PLUGIN_SHOUTCASTBROWSER_NONE') ];
}

sub add_recent_stream
{
if ($have_storable) {
    my ($client, $new, $bitrate, $data_ref) = @_;

    # Another client may have changed it since our last access
    my $fh = FileHandle->new();
    $fh->open("<$recent_filename");
    flock($fh, LOCK_EX);
    my @recent = @{ get_recent_streams($fh) };

    @recent = () if (@recent == 1 and $recent[0] eq
	Slim::Utils::Strings::string('PLUGIN_SHOUTCASTBROWSER_NONE'));

    if (exists $stream_data{$recent_name}{$new})
    {
	my ($i) = grep $recent[$_] eq $new, 0..$#recent;
	splice @recent, $i, 1;
	unshift @recent, $new;
    }
    else
    {
	unshift @recent, $new;
	pop @recent if @recent > $recent_max;
    }
    $streams{$position_of_recent} = \@recent;
    $stream_data{$recent_name}{$new}{$bitrate} = $data_ref;

    ## Force reload in case this is a new bitrate of an old stream
    delete $bitrates{$position_of_recent}{0};
    bitrate_mode_helper($client);

    my $rv = store([ $stream_data{$recent_name}, \@recent ], $recent_filename);
    warn "ShoutcastBrowser: Storing recent streams failed.\n" unless $rv;
    $fh->close;
}
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
	DE	SHOUTcast Sender

PLUGIN_SHOUTCASTBROWSER_GENRES
	EN	SHOUTcast Genres
	DE	SHOUTcast Kategorien

PLUGIN_SHOUTCASTBROWSER_CONNECTING
	EN	Connecting to SHOUTcast web site ...
	DE	Verbinde mit der SHOUTcast Web-Seite ...

PLUGIN_SHOUTCASTBROWSER_NETWORK_ERROR
	EN	Error: SHOUTcast web site not available
	DE	Fehler: SHOUTcast Web-Seite nicht verfügbar

PLUGIN_SHOUTCASTBROWSER_STREAMS
	EN	Streams

PLUGIN_SHOUTCASTBROWSER_ALL_STREAMS
	EN	All Streams

PLUGIN_SHOUTCASTBROWSER_NONE
	EN	None

PLUGIN_SHOUTCASTBROWSER_BITRATE
	EN	Bitrate

PLUGIN_SHOUTCASTBROWSER_BITRATES
	EN	Bitrates

PLUGIN_SHOUTCASTBROWSER_RECENT
	EN	Favorites

PLUGIN_SHOUTCASTBROWSER_MISC
	EN	Misc. genres

PLUGIN_SHOUTCASTBROWSER_TOO_SOON
	EN	Try again in a minute

PLUGIN_SHOUTCASTBROWSER_SORTING
	EN	Sorting streams ...

SETUP_GROUP_PLUGIN_SHOUTCASTBROWSER
	EN	SHOUTcast Internet Radio

SETUP_GROUP_PLUGIN_SHOUTCASTBROWSER_DESC
	EN	Browse SHOUTcast list of Internet Radio streams.  Hit rewind after changing any settings to reload the list of streams.

SETUP_PLUGIN_SHOUTCASTBROWSER_HOW_MANY_STREAMS
	EN	Number of Streams

SETUP_PLUGIN_SHOUTCASTBROWSER_HOW_MANY_STREAMS_DESC
	EN	How many streams to get.  Default is 300, maximum is 2000.

SETUP_PLUGIN_SHOUTCASTBROWSER_GENRE_PRIMARY_CRITERION
	EN	Main Sort Criterion for Genres

SETUP_PLUGIN_SHOUTCASTBROWSER_GENRE_PRIMARY_CRITERION_DESC
	EN	Primary criterion for sorting genres.

SETUP_PLUGIN_SHOUTCASTBROWSER_GENRE_SECONDARY_CRITERION
	EN	Other Sort Criterion for Genres

SETUP_PLUGIN_SHOUTCASTBROWSER_GENRE_SECONDARY_CRITERION_DESC
	EN	Secondary criterion for sorting genres, if the primary is equal.

SETUP_PLUGIN_SHOUTCASTBROWSER_STREAM_PRIMARY_CRITERION
	EN	Main Sort Criterion for Streams

SETUP_PLUGIN_SHOUTCASTBROWSER_STREAM_PRIMARY_CRITERION_DESC
	EN	Primary criterion for sorting streams.

SETUP_PLUGIN_SHOUTCASTBROWSER_STREAM_SECONDARY_CRITERION
	EN	Other Sort Criterion for Streams

SETUP_PLUGIN_SHOUTCASTBROWSER_STREAM_SECONDARY_CRITERION_DESC
	EN	Secondary criterion for sorting streams, if the primary is equal.

SETUP_PLUGIN_SHOUTCASTBROWSER_MIN_BITRATE
	EN	Minimum Bitrate

SETUP_PLUGIN_SHOUTCASTBROWSER_MIN_BITRATE_DESC
	EN	Minimum Bitrate in which you are interested (0 for no limit).

SETUP_PLUGIN_SHOUTCASTBROWSER_MAX_BITRATE
	EN	Maximum Bitrate

SETUP_PLUGIN_SHOUTCASTBROWSER_MAX_BITRATE_DESC
	EN	Maximum Bitrate in which you are interested (0 for no limit).

SETUP_PLUGIN_SHOUTCASTBROWSER_MAX_RECENT
	EN	Recent Streams

SETUP_PLUGIN_SHOUTCASTBROWSER_MAX_RECENT_DESC
	EN	Maximum number of recently played streams to remember.
