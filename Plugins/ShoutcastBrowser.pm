# ShoutcastBrowser.pm Copyright (C) 2003 Peter Heslin
# version 3.0, 5 Apr, 2004
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
# * Make a "recently played streams" category
# * Make all singleton genres into one big genre so you can sort
#   it based on listeners

package Plugins::ShoutcastBrowser;
use strict;

################### Configuration Section ########################

### These first few preferences can only be set by editing this file
my (%genre_aka, @genre_keywords, $munge_genres);

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
	      spiritual => [qw(christian praise worship prayer inspirational bible)],
	      freeform => 'freestyle', greek => 'greece', punjabi => 'punjab',
	      breakbeat => 'breakbeats', new_age => 'newage',
	      british => [qw(english britpop)],
	      community => 'local', low_fi => [qw(lowfi lofi)],
	      anime => 'animation', electronic => [qw(electro electronica)],
	      trance => 'tranc', talk => [qw(spoken politics)], gothic => 'goth',
	      oldies => 'oldie', soundtrack => [qw(film movie)],
	      live => 'vivo'
	     );

### Warning: These preferences can (and should) be set via the web
### interface. If you set them here, they will be overriden by the
### settings in your preferences file put there by the web
### configuration interface.  If for some reason you want to specify
### these values here (eg. you really want to have a tertiary sorting
### criterion), then set $prefs_override to a true value.
my ($prefs_override, @genre_criteria, @stream_criteria, $how_many_streams);

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

my $debug = 0;
my (%current_genre, %current_stream, %old_stream, %status, %number);
my $last_time = 0;

my (@genres, %streams, %unsorted_streams);

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
use Slim::Control::Command;
use Slim::Utils::Strings qw (string);
use Slim::Display::Display;
use LWP::Simple;
use HTML::Entities;
my $have_zlib = eval 'use Compress::Zlib; 1;';

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
    # Fallback defaults if undefined in prefs or at start of this file
    $how_many_streams = 300 unless $how_many_streams;
    @genre_criteria  = qw(streams name) unless @genre_criteria;
    @stream_criteria = qw(listeners bitrate name) unless @stream_criteria;
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
	%streams = ();
	%unsorted_streams = ();
	my @all_streams = ();
	my $all = "All $how_many_streams streams";

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
	    if ($munge_genres)
	    {
		my $original = $genre;

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

	    @keywords = ($genre) unless @keywords;
	    foreach my $g (@keywords)
	    {
		unless (exists $unsorted_streams{$g})
		{
		    push @genres, $g;
		}
		push @{ $unsorted_streams{$g} },
		    [$url, $full_text, $name, $listeners, $bitrate, $now_playing];
	    }
	    push @all_streams,
		[$url, $full_text, $name, $listeners, $bitrate, $now_playing];
	}
	@genres = sort genre_sort @genres;
	$unsorted_streams{$all} = \@all_streams;
	unshift @genres, $all;
    }
    $status{$client} = 1;
    $client->update();
}

sub genre_sort
{
    my $r = 0;
    for my $criterion (@genre_criteria)
    {
	if ($criterion =~ m/^streams/i)
	{
	    $r = scalar @{ $unsorted_streams{$b} } <=> scalar @{ $unsorted_streams{$a} };
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
	elsif ($criterion =~ m/^name/i)
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
	  'plugin_shoutcastbrowser_stream_secondary_criterion'
	 ],
	 GroupHead => string('SETUP_GROUP_PLUGIN_SHOUTCASTBROWSER'),
	 GroupDesc => string('SETUP_GROUP_PLUGIN_SHOUTCASTBROWSER_DESC'),
	 GroupLine => 1,
	 GroupSub => 1,
	 Suppress_PrefSub => 1,
	 Suppress_PrefLine => 1
	);

    my %genre_options = (name => 'Alphabetical',
			 name_reverse => 'Alphabetical (reverse)',
			 streams => 'Number of streams',
			 streams_reverse => 'Number of streams (reverse)',
			 keyword => 'By genre keyword',
			 keyword_reverse => 'By genre keyword (reverse)',
			);

    my %stream_options = (name => 'Alphabetical',
			 name_reverse => 'Alphabetical (reverse)',
			 listeners => 'Number of listeners',
			 listeners_reverse => 'Number of listeners (reverse)',
			 bitrate => 'By bitrate',
			 bitrate_reverse => 'By bitrate (reverse)',
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
	  PrefName => 'foo',
	  options => \%genre_options
	 },
	 plugin_shoutcastbrowser_stream_primary_criterion =>
	 {
	  options => \%stream_options
	 },
	 plugin_shoutcastbrowser_stream_secondary_criterion =>
	 {
	  options => \%stream_options
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
	Slim::Utils::Prefs::set('plugin_shoutcastbrowser_genre_primary_criterion', 'streams');
    }
    if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_genre_secondary_criterion'))
    {
	Slim::Utils::Prefs::set('plugin_shoutcastbrowser_genre_secondary_criterion', 'name');
    }
    if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_stream_primary_criterion'))
    {
	Slim::Utils::Prefs::set('plugin_shoutcastbrowser_stream_primary_criterion', 'listeners');
    }
    if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_stream_secondary_criterion'))
    {
	Slim::Utils::Prefs::set('plugin_shoutcastbrowser_stream_secondary_criterion', 'bitrate');
    }
}

##### Sub-mode for streams #####

my $mode_sub = sub {
    my $client = shift;
    $client->lines(\&streamsLines);
    $status{$client} = 0;
    $number{$client} = undef;
    $current_stream{$client} = $old_stream{$current_genre{$client}}{$client} || 0;
    $client->update();

    unless(exists $streams{$current_genre{$client}})
    {
	my $genre = $genres[$current_genre{$client}];
	my @sorted_streams = sort stream_sort @{ $unsorted_streams{$genre} };
	$streams{$current_genre{$client}} = [@sorted_streams];

	$debug && print "\n\nStreams: ".scalar @sorted_streams."\n";
	$debug && print $_->[1]."\n" for @sorted_streams;
    }
    $status{$client} = 1;
    $client->update();

};

my $leave_mode_sub = sub
{
    my $client = shift;
    $number{$client} = undef;
    $old_stream{$current_genre{$client}}{$client} =
	$current_stream{$client};
};

sub stream_sort
{
    my $r = 0;
    for my $criterion (@stream_criteria)
    {
	if ($criterion =~ m/^bitrate/i)
	{
	    $r = $b->[4] <=> $a->[4];
	}
	elsif ($criterion =~ m/^listener/i)
	{
	    $r = $b->[3] <=> $a->[3];
	}
	elsif ($criterion =~ m/^name/i)
	{
	    $r = lc($a->[2]) cmp lc($b->[2]);
	}
	$r = -1 * $r if $criterion =~ m/reverse$/i;
	return $r if $r;
    }
    return $r;
}

sub streamsLines
{
    my $client = shift;
    my (@lines);
    $current_stream{$client} ||= 0;

    if ($status{$client} == 0)
    {
	$lines[0] =
	    Slim::Utils::Strings::string('PLUGIN_SHOUTCASTBROWSER_SORTING');
	$lines[1] = '';
    }
    elsif ($status{$client} == -1)
    {
	$lines[0] = Slim::Utils::Strings::string('PLUGIN_SHOUTCASTBROWSER_NETWORK_ERROR');
	$lines[1] = '';
    }
    elsif ($status{$client} == 1)
    {
	# print STDERR join ', ', %streams;
	my @streams = @{ $streams{$current_genre{$client}} };

	my $current_array = $streams[$current_stream{$client}];
	my $current_name = $current_array->[1];

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
	 $leave_mode_sub->($client);
	 Slim::Buttons::Common::popModeRight($client);
     },
     'right' => sub
     {
	 my $client = shift;
	 $number{$client} = undef;
	 Slim::Display::Animation::bumpRight($client);
     },
     'play' => sub
     {
	 my $client = shift;
	 $number{$client} = undef;
	 my @streams = @{ $streams{$current_genre{$client}} };
	 my $current_array = $streams[$current_stream{$client}];
	 my $playlist_url = $current_array->[0];
	 Slim::Control::Command::execute($client, ['playlist', 'load', $playlist_url]);
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



# Add extra mode
Slim::Buttons::Common::addMode('ShoutcastStreams', \%StreamsFunctions,
			       $mode_sub, $leave_mode_sub);

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
	DE	Sender

PLUGIN_SHOUTCASTBROWSER_TOO_SOON
	EN	Try again in a minute

PLUGIN_SHOUTCASTBROWSER_SORTING
	EN	Sorting streams ...

SETUP_GROUP_PLUGIN_SHOUTCASTBROWSER
	EN	SHOUTcast Internet Radio

SETUP_GROUP_PLUGIN_SHOUTCASTBROWSER_DESC
	EN	Browse SHOUTcast list of Internet Radio streams.

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

