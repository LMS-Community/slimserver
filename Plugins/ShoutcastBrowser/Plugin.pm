# ShoutcastBrowser.pm Copyright (C) 2003 Peter Heslin
# version 3.0, 5 Apr, 2004
#$Id: ShoutcastBrowser.pm 2620 2005-03-21 08:40:35Z mherger $
#
# A Slim plugin for browsing the Shoutcast directory of mp3
# streams.  Inspired by streamtuner.
#
# With contributions from Okko, Kevin Walsh, Michael Herger and Rob Funk.
#
# This code is derived from code with the following copyright message:
#
# Slim Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Plugins::ShoutcastBrowser::Plugin;

use strict;
use File::Spec::Functions qw(catdir catfile);
use Slim::Control::Command;
use Slim::Utils::Strings qw (string);
use Slim::Utils::Misc qw( msg );
use HTML::Entities qw(decode_entities);
use XML::Simple;

################### Configuration Section ########################

### These first few preferences can only be set by editing this file
my (%genre_aka, @genre_keywords, @legit_genres);

# If you choose to munge the genres, here is the list of keywords that
# define various genres.  If any of these words or phrases is found in
# the genre of a stream, then the stream is allocated to the genre
# indicated by those word(s) or phrase(s).  In phrases, indicate a
# space by means of an underscore.  

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
	drum_&_bass r_&_b
};

# Here are keywords defined in terms of other, variant keywords.  The
# form on the right is the canonical form, and on the left is the
# variant or list of variants which should be transformed into that
# canonical form.

%genre_aka = (
	'50s' => '50', 
	'60s' => '60',
	'70s' => '70',  
	'80s' => '80',  
	'90s' => '90', 
	'african' => 'africa',
	'anime' => 'animation', 
	'breakbeat' => 'breakbeats', 
	'british' => 'britpop',
	'classical' => 'symphonic',
	'comedy' => 'humor|humour', 
	'community' => 'local', 
	'drum & bass' => 'dnb|d&b|d & b|drum and bass|drum|bass', 
	'dutch' => 'holland|netherla|nederla', 
	'electronic' => 'electro|electronica',
	'freeform' => 'freestyle', 
	'gothic' => 'goth',
	'greek' => 'greece', 
	'hungarian' => 'hungar', 
	'live' => 'vivo',
	'low fi' => 'lowfi|lofi',
	'new age' => 'newage',
	'old school' => 'oldskool|old skool|oldschool', 
	'oldies' => 'oldie|old time radio', 
	'psychedelic' => 'psych',
	'punjabi' => 'punjab',
	'r & b' => 'rnb|r n b|r&b',  
	'reggae' => 'ragga|dancehall|dance hall', 
	'rap' => 'hiphop|hip hop', 
	'soundtrack' => 'film|movie',
	'spiritual' => 'christian|praise|worship|prayer|inspirational|bible|religious',
	'talk' => 'spoken|politics', 
	'top 40' => 'top40|chart|top hits', 
	'trance' => 'tranc', 
	'turkish' => 'turk|turkce',
	'various' => 'all|any|every|mixed|eclectic|mix|variety|varied|random|misc|unknown',
	'video_game' => 'videogame|gaming'
);

# These are useful, descriptive genres, which should not be removed
# from the list, even when they only have one stream and we are
# lumping singletons together.  So we eliminate the more obscure and
# regional genres from this list.

@legit_genres = qw(
	rock pop trance dance techno various house alternative 80s metal
	college jazz talk world rap ambient oldies blues country punk reggae
	70s classical live latin indie downtempo gospel industrial scanner 90s
	folk comedy urban funk progressive ska 60s news soul lounge soundtrack
	bluegrass salsa swing sports disco 50s merengue opera top_40 hard_rock
	hard_core video_game big_band classic_rock easy_listening new_age
);

################### End Configuration Section ####################

# rather constants than variables (never changed in the code)
use constant SORT_BITRATE_UP => 0;
use constant RECENT_DIRNAME => 'ShoutcastBrowser_Recently_Played';
use constant UPDATEINTERVAL => 86400;
use constant ERRORINTERVAL => 60;

# keep track of client status
my (%status, %genreStreams, %streamList, @genresList, @mostPopularStreams);

# http status: 0 = ok, -1 = loading, >0 = error, undef = not loaded
my $httpError;

# time of last list refresh
my $last_time = 0;

sub initPlugin {
	checkDefaults();

	if (defined @genre_keywords) {
		foreach my $genre (keys %genre_aka) {
			foreach (split /\|/, $genre_aka{$genre}) {
				$genre_aka{$_} = $genre;
			}
			delete $genre_aka{$genre};
		}

		# store the keywords in the %genre_aka hash for faster access
		foreach (@genre_keywords) {
			s/_/ /g; 
			$genre_aka{$_} = $_;
		}
		undef @genre_keywords;
	}
	@legit_genres = map { s/_/ /g; $_; } @legit_genres;
	
	return 1;	
}

sub enabled {	
	return ($::VERSION ge '6.1');
}

sub getDisplayName {
	return 'PLUGIN_SHOUTCASTBROWSER_MODULE_NAME';
}

my %modes;
sub getModes {
	my $client = shift;
	
	# creation of this hash is rather expensive - let's do it only once 
	if (not defined %modes or ($status{'language'} ne Slim::Utils::Strings::getLanguage())) {
		%modes = (
			'PLUGIN_SHOUTCASTBROWSER_RECENT' => {
					'valuesFunc' => sub { return readRecentStreamList($client); },
					'callback' => \&browseStreamsExitHandler,
					'valueRef' => \$status{$client}{'stream'},
					'overlay' => 'notesymbol',
				},
			'PLUGIN_SHOUTCASTBROWSER_MOST_POPULAR' => {
					'values' => \@mostPopularStreams,
					'callback' => \&browseStreamsExitHandler,
					'valueRef' => \$status{$client}{'stream'},
					'overlay' => 'notesymbol',
				},
			'BROWSE_BY_GENRE' => {
					'values' => \@genresList,
					'header' => 'GENRE',
					'dontSetGenre' => 1,
					'valueRef' => \$status{$client}{'genre'},
					'overlay' => 'rightarrow',
					'isSorted' => ((Slim::Utils::Prefs::getArray('plugin_shoutcastbrowser_genre_criterion'))[0] =~ m/^(name|default)/i ? 'I' : ''),
					'callback' => sub {
							my $client = shift;
							my $method = shift;
							if ($method eq 'left') {
								Slim::Buttons::Common::popModeRight($client);
							}
							elsif ($method eq 'right') {
								my $item = ${$client->param('valueRef')};
								my %params = (
									header => $client->string('PLUGIN_SHOUTCASTBROWSER_SHOUTCAST') . ' - ' . $item,
									headerAddCount => 1,
									listRef => [sort { &stream_sort } @{$genreStreams{$item}}],
									valueRef => \$status{$client}{'stream'},
									overlayRef => sub {return (undef, $client->symbols('notesymbol'));},
									isSorted => ((Slim::Utils::Prefs::getArray('plugin_shoutcastbrowser_stream_criterion'))[0] =~ m/(^name|default)/i ? 'I' : ''),
									callback => \&browseStreamsExitHandler
								);
								Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', \%params);
							}
						}
				},
			'PLUGIN_SHOUTCASTBROWSER_ALL_STREAMS' => {
					'values' => [sort { &stream_sort } keys %streamList],
					'valueRef' => \$status{$client}{'stream'},
					'overlay' => 'notesymbol',
					'isSorted' => ((Slim::Utils::Prefs::getArray('plugin_shoutcastbrowser_stream_criterion'))[0] =~ m/(^name|default)/i ? 'I' : ''),
					'callback' => \&browseStreamsExitHandler
				},
			'PLUGIN_SHOUTCASTBROWSER_REFRESH_STREAMLIST' => {
					'values' => [ $client->string('PLUGIN_SHOUTCASTBROWSER_REFRESH_NOW') ],
					'header' => 'PLUGIN_SHOUTCASTBROWSER_REFRESH',
					'overlay' => 'rightarrow',
					'headerAddCount' => 0,
					'callback' => sub {
							my $client = shift;
							my $method = shift;
							# only allow reload every other minute
							if (($method eq 'right') && (time() > $last_time + 60)) {
								$httpError = undef;
								Slim::Buttons::Common::popModeRight($client);
								$client->block({'line1' => $client->string('PLUGIN_SHOUTCASTBROWSER_CONNECTING')});
								loadStreamList($client);
							}
							elsif ($method eq 'right') {
								$client->bumpRight();
							} 
							elsif ($method eq 'left') {
								Slim::Buttons::Common::popModeRight($client);
							}
						}
				},
				'PLUGIN_SHOUTCASTBROWSER_RANDOM_STREAM' => {
					'valuesFunc' => sub {
							my $streamList = [sort { &stream_sort } keys %streamList];
							$status{$client}{'stream'} = $$streamList[int(rand(scalar @{$streamList}))];
							playOrAddStream($client, 'play');
							return $streamList;							
						},
					'header' => 'PLUGIN_SHOUTCASTBROWSER_ALL_STREAMS',
					'valueRef' => \$status{$client}{'stream'},
					'overlay' => 'notesymbol',
					'isSorted' => ((Slim::Utils::Prefs::getArray('plugin_shoutcastbrowser_stream_criterion'))[0] =~ m/(^name|default)/i ? 'I' : ''),
					'callback' => \&browseStreamsExitHandler
					
				}
		);

		# keep track of the current language so we can update if the language changes
		$status{'language'} = Slim::Utils::Strings::getLanguage();
	}
	return \%modes;
}

sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop' && not $status{'getStreams'}) {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	elsif ($method eq 'pop' && $status{'getStreams'}) {
		$status{'getStreams'} = 0;
	}

	$status{$client}{status} = 0;

	check4Update();

	if (not defined $httpError) {
		$client->block({'line1' => $client->string('PLUGIN_SHOUTCASTBROWSER_CONNECTING')});
		loadStreamList($client);
		$status{'getStreams'} = 1;
	}
	# tell the user if we're loading the strings
	elsif ($httpError < 0) {
		Slim::Buttons::Common::popModeRight($client);
	}
	elsif ($httpError) {
		my %params = (
			header => '{PLUGIN_SHOUTCASTBROWSER_MODULE_NAME}',
			listRef => [ "{PLUGIN_SHOUTCASTBROWSER_NETWORK_ERROR}" ],
		);
		Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);
	}
	else {
		$status{$client}{status} = 1;
		getModes($client);

		my @modeOrder = map { "{$_}" } ('PLUGIN_SHOUTCASTBROWSER_RECENT', 
										'PLUGIN_SHOUTCASTBROWSER_MOST_POPULAR', 
										'BROWSE_BY_GENRE', 
										'PLUGIN_SHOUTCASTBROWSER_ALL_STREAMS',
										'PLUGIN_SHOUTCASTBROWSER_RANDOM_STREAM',
										'PLUGIN_SHOUTCASTBROWSER_REFRESH_STREAMLIST');

		my %params = (
			header => '{PLUGIN_SHOUTCASTBROWSER_MODULE_NAME} {count}',
			listRef => \@modeOrder,
			modeName => 'ShoutcastBrowser Plugin',
			overlayRef => [undef, Slim::Display::Display::symbol('rightarrow')],
			onRight => sub {
					my $client = shift;
					my $item = shift;
					$item =~ s/\{(.*)\}/$1/i;
					
					if (not $modes{$item}->{'dontSetGenre'}) {
						$status{$client}{'genre'} = $item;
					}

					my $values;
					if (not (defined $modes{$item}->{'valuesFunc'} && ($values = &{$modes{$item}->{'valuesFunc'}}))) {
						$values = $modes{$item}->{'values'};
					}

					my %params = (
						header => $client->string('PLUGIN_SHOUTCASTBROWSER_SHOUTCAST') . ' - ' . $client->string((defined($modes{$item}->{'header'}) ? $modes{$item}->{'header'} : $item)),
						headerAddCount => (defined($modes{$item}->{'headerAddCount'}) ? $modes{$item}->{'headerAddCount'} : 1),
						listRef => $values || [ $client->string('PLUGIN_SHOUTCASTBROWSER_NONE') ],
						overlayRef => sub {return (undef, $client->symbols($modes{$item}->{'overlay'}));},
						isSorted => $modes{$item}->{'isSorted'},
						callback => $modes{$item}->{'callback'},
						valueRef => $modes{$item}->{'valueRef'}
					);
					Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', \%params);
				}
		);
		Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);
	}
}

sub browseStreamsExitHandler {
	my $client = shift;
	my $method = shift;

	if ($method eq 'left') {
		$status{$client}{'bitrate'} = 0;
		Slim::Buttons::Common::popModeRight($client);
	}
	elsif ($method eq 'right') {
		my $item = ${$client->param('valueRef')};
		$item =~ s/^$client->string('PLUGIN_SHOUTCASTBROWSER_SHOUTCAST')- - (.*)$/$1/;

		my @bitrates = keys %{ $streamList{$item} };

		if ($status{$client}{'genre'} eq 'PLUGIN_SHOUTCASTBROWSER_RECENT' && $status{$client}{stream} =~ /(\d+) kbps: (.*)/i) {
			$status{$client}{'bitrate'} = $1;
			showStreamInfo($client);
		}
		elsif ((not keys %{$streamList{$item}}) && ($item =~ /:\s+(\d+)\s+/i)) {
			$status{$client}{'bitrate'} = $1;
			showStreamInfo($client);
		}
		elsif ($#bitrates == 0) {
			$status{$client}{'bitrate'} = $bitrates[0];
			showStreamInfo($client);
		} else {
			@bitrates = map {$client->string('PLUGIN_SHOUTCASTBROWSER_BITRATE') . $client->string('COLON') . " $_ " . $client->string('PLUGIN_SHOUTCASTBROWSER_KBPS')} @bitrates;
			my %params = (
				header => $item,
				valueRef => \$status{$client}{'bitrate'},
				headerAddCount => 1,
				listRef => \@bitrates,
				callback => \&browseStreamsExitHandler
			);
			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', \%params);
		}
	}
}

sub loadStreamList {
	my ($client, $params, $callback, $httpClient, $response) = @_;
	
	# only start if it's not been launched by another client
	if (not defined $httpError) {
		# reset the modes
		undef %modes;
		$last_time = time();
		$::d_plugins && msg("Shoutcast: next update " . localtime($last_time + UPDATEINTERVAL) . "\n");
		
		$httpError = -1;
		my $http = Slim::Networking::SimpleAsyncHTTP->new(\&gotViaHTTP, \&gotErrorViaHTTP, {client => $client, params => $params, callback => $callback, httpClient => $httpClient, response => $response});
	
		my $url = unpack 'u', q{M:'1T<#HO+W-H;W5T8V%S="YC;VTO<V)I;B]X;6QL:7-T97(N<&AT;6P_<V5R+=FEC93U3;&E-4#,`};
		$url .= '&limit=' . Slim::Utils::Prefs::get('plugin_shoutcastbrowser_how_many_streams') if Slim::Utils::Prefs::get('plugin_shoutcastbrowser_how_many_streams');
		eval { require Compress::Zlib };
		$url .= '&no_compress=1' if $@;

		$::d_plugins && msg("Shoutcast: async request\n");
		$http->get($url);
	}
}

sub gotViaHTTP {
	my $http = shift;
	my $params = $http->params();
	my $data;

	$::d_plugins && msg("Shoutcast: get XML content\n");
	$httpError = 1 if not ($data = $http->content());

	$::d_plugins && msg("Shoutcast: parse XML \n");
	$httpError = 2 if not ($data = extractStreamInfoXML($data));

	if ((not defined $httpError) || ($httpError < 1)) {
		undef %genreStreams;
		undef %streamList;
		undef @mostPopularStreams;
		undef @genresList;

		$::d_plugins && msg("Shoutcast: extract streams\n");
		extractStreamInfo($params->{'client'}, $data);

		$::d_plugins && msg("Shoutcast: remove singletons\n");
		removeSingletons($params->{'client'});

		$::d_plugins && msg("Shoutcast: sort genres\n");
		sortGenres();
		$httpError = 0;
	}
	undef $data;
	
	$::d_plugins && msg("Shoutcast: create page\n");
	createAsyncWebPage($params);
	$::d_plugins && msg("Shoutcast: that's it\n");
	if (defined $params->{'client'}) {
		$params->{'client'}->unblock();
		$params->{'client'}->update();
	}
}

sub gotErrorViaHTTP {
	my $http = shift;
	my $params = $http->params();

	$httpError = 99;
	createAsyncWebPage($params);
	if (defined $params->{'client'}) {
		$params->{'client'}->unblock();
		$params->{'client'}->update();
	}
}

sub createAsyncWebPage {
	my $params = shift;
	# create webpage if we were called by the web interface
	if ($params->{httpClient}) {
		my $output = handleWebIndex($params->{client}, $params->{params}, $params->{callback}, $params->{httpClient}, $params->{response});
		my $current_player;
		if (defined($params->{client})) {
			$current_player = $params->{client}->id();
		}
		
		$params->{callback}->($current_player, $params->{params}, $output, $params->{httpClient}, $params->{response});
	}
}

sub extractStreamInfoXML {
	my $data = shift;
	return 0 unless ($data);

	eval { require Compress::Zlib };
	$data = Compress::Zlib::uncompress($data) unless ($@);
	$data = eval { XML::Simple::XMLin($data, SuppressEmpty => ''); };

	if ($@ || !exists $data->{'playlist'} || 
	    ref($data->{'playlist'}->{'entry'}) ne 'ARRAY') {
		$::d_plugins && msg("Shoutcast: problem reading XML: $@\n");
		return 0;
	}
	else {
		return $data;
	}
}

sub extractStreamInfo {
	my $client = shift;
	my $data = shift;

	my $munge_genres = Slim::Utils::Prefs::get('plugin_shoutcastbrowser_munge_genre');
	my $min_bitrate = Slim::Utils::Prefs::get('plugin_shoutcastbrowser_min_bitrate');
	my $max_bitrate = Slim::Utils::Prefs::get('plugin_shoutcastbrowser_max_bitrate');
	my $miscName = (defined($client) ? $client->string('PLUGIN_SHOUTCASTBROWSER_MISC') : string('PLUGIN_SHOUTCASTBROWSER_MISC'));

	for my $entry (@{$data->{'playlist'}->{'entry'}}) {
		my $bitrate	 = $entry->{'Bitrate'};
		next if ($min_bitrate and $bitrate < $min_bitrate);
		next if ($max_bitrate and $bitrate > $max_bitrate);

		my $name = cleanStreamInfo($entry->{'Name'});
		my $genre = my $original = cleanStreamInfo($entry->{'Genre'});
		$genre = "\L$genre";
		$genre =~ s/\s+/ /g;
		$genre =~ s/^ //;
		$genre =~ s/ $//;

		my @keywords = ();

		if ($munge_genres) {
			my %new_genre;
			for my $old_genre (split / /, $genre) {
				if (my $new_genre = $genre_aka{$old_genre}) {
					$new_genre{"\u$new_genre"}++;
				}
			}

			if (not (@keywords = keys %new_genre)) {
				@keywords = ($genre ? ("\u$genre") : ($miscName));			
			}
	
		} else {
			@keywords = ($original);
		}

		foreach (@keywords) {
			push @{$genreStreams{$_}}, $name;
		}

		$streamList{$name}{$bitrate} = [$entry->{'Playstring'}, 
										$entry->{'Listeners'},
										$bitrate,
										cleanStreamInfo($entry->{'Nowplaying'}), 
										$original];
	}
}

sub removeSingletons {
	my $client = shift;
	my @criterions = Slim::Utils::Prefs::getArray('plugin_shoutcastbrowser_genre_criterion');
	my $miscName = (defined($client) ? $client->string('PLUGIN_SHOUTCASTBROWSER_MISC') : string('PLUGIN_SHOUTCASTBROWSER_MISC'));
	
	if (($criterions[0] =~ /default/i) and Slim::Utils::Prefs::get('plugin_shoutcastbrowser_munge_genre')) {
		foreach my $g (keys %genreStreams) {
			my @n = @{ $genreStreams{$g} };

			if (not (grep(/$g/i, @legit_genres) or ($#n > 0))) {
				unless (grep {$_ eq $n[0]} @{$genreStreams{$miscName}}) {
					push @{$genreStreams{$miscName}}, $n[0];
				}
				delete $genreStreams{$g};
			}
		}
	}
}

sub sortGenres {
	my @criterions = Slim::Utils::Prefs::getArray('plugin_shoutcastbrowser_genre_criterion');
	
	my $genre_sort = sub {
		my $r = 0;
		for my $criterion (@criterions) {
			
			if ($criterion =~ m/^streams/i)	{
				$r = @{ $genreStreams{$b} } <=> @{ $genreStreams{$a} };
			} else {
				$r = (lc($a) cmp lc($b));
			}
			
			$r = -1 * $r if $criterion =~ m/reverse$/i;
			return $r if $r;
		}
		return $r;
	};
	
	@genresList = sort $genre_sort keys %genreStreams;

	my %topHelper;
	foreach my $stream (keys %streamList) {
		foreach (keys %{ $streamList{$stream} }) {
			$topHelper{$stream} += $streamList{$stream}{$_}[1];
		}
	}
	@mostPopularStreams = sort { $topHelper{$b} <=> $topHelper{$a} } keys %topHelper;

	if (Slim::Utils::Prefs::get('plugin_shoutcastbrowser_max_popular') < $#mostPopularStreams) {
		splice @mostPopularStreams, Slim::Utils::Prefs::get('plugin_shoutcastbrowser_max_popular');
	}
}

sub cleanStreamInfo {
	my $arg = shift;
	$arg =~ s/%([\dA-F][\dA-F])/chr hex $1/gei;	# encoded chars
	$arg = decode_entities($arg);
	$arg =~ s#\b([\w-]) ([\w-]) #$1$2#g;		# S P A C E D  W O R D S
	$arg =~ s#\b(ICQ|AIM|MP3Pro)\b##i;			# we don't care
	$arg =~ s#\W\W\W\W+# #g;					# excessive non-word characters
	$arg =~ s#^\W+##;							# leading non-word characters
	$arg =~ s/\s+/ /g;
	return $arg;
}

my %functions = (
	'play' => sub {
		my $client = shift;
		playOrAddStream($client, 'play');
	},

	'add' => sub {
		my $client = shift;
		playOrAddStream($client, 'add');
	},
);	

sub getFunctions { 
	return \%functions;
}

sub addMenu { 
	return 'RADIO'; 
}

sub setupGroup {
	my %setupGroup = (
		PrefOrder => [
			'plugin_shoutcastbrowser_how_many_streams',
			'plugin_shoutcastbrowser_genre_criterion',
			'plugin_shoutcastbrowser_stream_criterion',
			'plugin_shoutcastbrowser_min_bitrate',
			'plugin_shoutcastbrowser_max_bitrate',
			'plugin_shoutcastbrowser_max_recent',
			'plugin_shoutcastbrowser_max_popular',
			'plugin_shoutcastbrowser_munge_genre'
		],
		GroupHead => Slim::Utils::Strings::string('SETUP_GROUP_PLUGIN_SHOUTCASTBROWSER'),
		GroupDesc => Slim::Utils::Strings::string('SETUP_GROUP_PLUGIN_SHOUTCASTBROWSER_DESC'),
		GroupLine => 1,
		GroupSub => 1,
		Suppress_PrefSub => 1,
		Suppress_PrefLine => 1
	);

	my %genre_options = (
		'' => '',
		name_reverse => Slim::Utils::Strings::string('SETUP_PLUGIN_SHOUTCASTBROWSER_ALPHA_REVERSE'),
		streams => Slim::Utils::Strings::string('SETUP_PLUGIN_SHOUTCASTBROWSER_NUMBEROFSTREAMS'),
		streams_reverse => Slim::Utils::Strings::string('SETUP_PLUGIN_SHOUTCASTBROWSER_NUMBEROFSTREAMS_REVERSE'),
		default => Slim::Utils::Strings::string('SETUP_PLUGIN_SHOUTCASTBROWSER_DEFAULT_ALPHA'),
	);

	my %stream_options = (
		'' => '',
		name_reverse => Slim::Utils::Strings::string('SETUP_PLUGIN_SHOUTCASTBROWSER_ALPHA_REVERSE'),
		listeners => Slim::Utils::Strings::string('SETUP_PLUGIN_SHOUTCASTBROWSER_NUMBEROFLISTENERS'),
		listeners_reverse => Slim::Utils::Strings::string('SETUP_PLUGIN_SHOUTCASTBROWSER_NUMBEROFLISTENERS_REVERSE'),
		default => Slim::Utils::Strings::string('SETUP_PLUGIN_SHOUTCASTBROWSER_DEFAULT_ALPHA'),
	);

	my %setupPrefs = (
		plugin_shoutcastbrowser_how_many_streams => {
 			validate => \&Slim::Web::Setup::validateInt,
 			validateArgs => [1,2000,1,2000],
			onChange => sub { $httpError = undef; }
		},
		
		plugin_shoutcastbrowser_genre_criterion => {
			isArray => 1,
			arrayAddExtra => 1,
			arrayDeleteNull => 1,
			arrayDeleteValue => '',
			options => \%genre_options,
			onChange => sub {
				my ($client,$changeref,$paramref,$pageref) = @_;
				if (exists($changeref->{'plugin_shoutcastbrowser_genre_criterion'}{'Processed'})) {
					return;
				}
				Slim::Web::Setup::processArrayChange($client, 'plugin_shoutcastbrowser_genre_criterion', $paramref, $pageref);
				$httpError = undef;
				$changeref->{'plugin_shoutcastbrowser_genre_criterion'}{'Processed'} = 1;
			},
			
		},
	
		plugin_shoutcastbrowser_stream_criterion => {
			isArray => 1,
			arrayAddExtra => 1,
			arrayDeleteNull => 1,
			arrayDeleteValue => '',
			options => \%stream_options,
			onChange => sub {
				my ($client,$changeref,$paramref,$pageref) = @_;
				if (exists($changeref->{'plugin_shoutcastbrowser_stream_criterion'}{'Processed'})) {
					return;
				}
				Slim::Web::Setup::processArrayChange($client, 'plugin_shoutcastbrowser_stream_criterion', $paramref, $pageref);
				$httpError = undef;
				$changeref->{'plugin_shoutcastbrowser_stream_criterion'}{'Processed'} = 1;
			},
			
		},

		plugin_shoutcastbrowser_min_bitrate => {
			validate => \&Slim::Web::Setup::validateInt,
			validateArgs => [0, undef, 0],
			onChange => sub { $httpError = undef; }
		},
		
		plugin_shoutcastbrowser_max_bitrate => {
			validate => \&Slim::Web::Setup::validateInt,
			validateArgs => [0, undef, 0],
			onChange => sub { $httpError = undef; }
		},
		
		plugin_shoutcastbrowser_max_recent => {
			validate => \&Slim::Web::Setup::validateInt,
			validateArgs => [0, undef, 0]
		},
		
		plugin_shoutcastbrowser_max_popular => {
			validate => \&Slim::Web::Setup::validateInt,
			validateArgs => [0, undef, 0]
		},
		
		plugin_shoutcastbrowser_munge_genre => {
			validate => \&Slim::Web::Setup::validateTrueFalse,
			options  => {
				1 => string('ON'),
				0 => string('OFF')
			},
			'PrefChoose' => string('SETUP_PLUGIN_SHOUTCASTBROWSER_MUNGE_GENRE')
		}
	);
	
	return (\%setupGroup,\%setupPrefs);
}

sub checkDefaults {
	if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_how_many_streams')) {
		Slim::Utils::Prefs::set('plugin_shoutcastbrowser_how_many_streams', 300);
	}
	
	if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_genre_criterion', 0)) {
		Slim::Utils::Prefs::set('plugin_shoutcastbrowser_genre_criterion', 'default', 0);
	}
	
	if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_stream_criterion', 0)) {
		Slim::Utils::Prefs::set('plugin_shoutcastbrowser_stream_criterion', 'default', 0);
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
	
	if (!Slim::Utils::Prefs::isDefined('plugin_shoutcastbrowser_munge_genre')) {
		Slim::Utils::Prefs::set('plugin_shoutcastbrowser_munge_genre', 1);
	}
}


sub stream_sort {
	my $r = 0;

	for my $criterion (Slim::Utils::Prefs::getArray('plugin_shoutcastbrowser_stream_criterion')) {
		if ($criterion =~ m/^listener/i) {
			my ($aa, $bb) = (0, 0);
			
			$aa += $streamList{$a}{$_}[1]
				foreach keys %{ $streamList{$a} };

			$bb += $streamList{$b}{$_}[1]
				foreach keys %{ $streamList{$b} };
			
			$r = $bb <=> $aa;
		} elsif ($criterion =~ m/^name/i or $criterion =~ m/default/i) {
			$r = lc($a) cmp lc($b);
		}
		
		$r = -1 * $r if $criterion =~ m/reverse$/i;
		
		return $r if $r;
	}
	
	return $r;
};
	

##### Sub-mode for stream info #####
sub showStreamInfo {
	my $client = shift;
	my @details;
	my %params;

	if ($status{$client}{'genre'} eq 'PLUGIN_SHOUTCASTBROWSER_RECENT') {
		$status{$client}{stream} =~ /(\d+) kbps: (.*)/i;
		my ($bitrate, $stream) = ($1, $2);
		@details = (
			$client->string('BITRATE') . $client->string('COLON') . ' ' . $bitrate || $client->string('PLUGIN_SHOUTCASTBROWSER_NONE'),
		);

		%params = (
			url => $status{$client}{recent_data}{$status{$client}{'stream'}},
			title => $stream,
			details => \@details
		);
	}
	else {
		my $current_data = $streamList{$status{$client}{stream}}{$status{$client}{bitrate}};

		@details = (
			$client->string('BITRATE') . $client->string('COLON') . ' ' . $current_data->[2] || $client->string('PLUGIN_SHOUTCASTBROWSER_NONE'),
			$client->string('SETUP_PLUGIN_SHOUTCASTBROWSER_NUMBEROFLISTENERS') . ': ' . $current_data->[1] || $client->string('PLUGIN_SHOUTCASTBROWSER_NONE'),
			$client->string('GENRE') . ': ' . $current_data->[4] || $client->string('PLUGIN_SHOUTCASTBROWSER_NONE'),
			$client->string('PLUGIN_SHOUTCASTBROWSER_WAS_PLAYING') . ': ' . $current_data->[3] || $client->string('PLUGIN_SHOUTCASTBROWSER_NONE')
		);

		%params = (
			url => $current_data->[0],
			title => $status{$client}{stream},
			details => \@details
		);
	}

	Slim::Buttons::Common::pushModeLeft($client, 'remotetrackinfo', \%params);
}


sub playOrAddStream {
	my ($client, $method) = @_;

	if ($status{$client}{'bitrate'} =~ /: (\d+) /i) {
		$status{$client}{'bitrate'} = $1;
	}

	$client->showBriefly({
		'line1' => $client->string((lc($method) eq 'play' ? 'CONNECTING_FOR' : 'ADDING_TO_PLAYLIST')),
		'line2' => $status{$client}{'stream'}
	});

	if ($status{$client}{'genre'} eq 'PLUGIN_SHOUTCASTBROWSER_RECENT') {
		playRecentStream($client, $status{$client}{recent_data}{$status{$client}{'stream'}}, $status{$client}{'stream'}, $method);
	}
	else {
		# Add all bitrates to current playlist, but only the first one to the recently played list
		my @bitrates;
		if (not $status{$client}{'bitrate'}) {
			@bitrates = keys %{ $streamList{$status{$client}{'stream'}} };
		}
		else {
			@bitrates = ($status{$client}{'bitrate'});
		}

		playStream($client, $status{$client}{'stream'}, shift @bitrates, $method);
		for my $b (@bitrates) {
			playStream($client, $status{$client}{'stream'}, $b, 'add', 0);
		}
	}
}


sub playStream {
	my ($client, $currentStream, $currentBitrate, $method, $addToRecent) = @_;
	my $current_data = $streamList{$currentStream}{$currentBitrate};

	$client->execute(['playlist', 'clear']) if (lc($method) eq 'play');
	$client->execute(['playlist', $method, $current_data->[0], $currentStream]);
	unless (defined $addToRecent && not $addToRecent) {
		writeRecentStreamList($client, $currentStream, $currentBitrate, $current_data);
	}
}


sub playRecentStream {
	my ($client, $url, $currentStream, $method) = @_;
	writeRecentStreamList($client, $currentStream, undef, [ $url ]);
	if ($currentStream =~ /\d+ \w+?: (.*)/i) {
		$currentStream = $1;
	}
	$client->execute(['playlist', $method, $url, $currentStream]);
	$status{$client}{streams} = readRecentStreamList($client) || [ $client->string('PLUGIN_SHOUTCASTBROWSER_NONE') ];
	$status{$client}{stream} = 0;
}

sub getRecentFilename {
	my $client = shift;
	
	unless ($status{$client}{recent_filename}) {
		my $recentDir;
		if (Slim::Utils::Prefs::get('playlistdir')) {
			$recentDir = catdir(Slim::Utils::Prefs::get('playlistdir'), RECENT_DIRNAME);
			mkdir $recentDir unless (-d $recentDir);
		}
		$status{$client}{recent_filename} = catfile($recentDir, $client->name() . '.m3u') if defined $recentDir;
	}
	
	return $status{$client}{recent_filename};
}

sub readRecentStreamList {
	my $client = shift;

	my @recent = ();
	unless (defined $client && open(FH, getRecentFilename($client))) {
		# if there's no client, we can't display a client specific list...
		return undef;
	};

	# Using Slim::Formats::Parse::M3U is unreliable, since it
	# forces us to use Slim::Music::Info::title to get the
	# title, but Info.pm may refuse to give it to us if it
	# thinks the data is "invalid" or something.  Also, we
	# want a list of titles with URLs attached, not vice
	# versa.
	my $title;
	
	while (my $entry = <FH>) {
		chomp($entry);
		$entry =~ s/^\s*(\S.*\S)\s*$/$1/sg;

		if ($entry =~ /^#EXTINF:.*?,(.*)$/) {
			$title = $1;
		}

		next if ($entry =~ /^#/ || not $entry);

		if (defined($title)) {
			$status{$client}{recent_data}{$title} = $entry;
			push @recent, $title;
			$title = undef;
		}
	}

	close FH;
	return [ @recent ];
}

sub writeRecentStreamList {
	my ($client, $streamname, $bitrate, $data) = @_;
	
	return if not defined $client;
	
	$streamname = "$bitrate kbps: $streamname" if (defined $bitrate);
	$status{$client}{recent_data}{$streamname} = $data->[0];

	my @recent;
	if (exists $status{$client}{recent_data}) {
		@recent = keys %{ $status{$client}{recent_data} };
	} else {
		@recent = @{ readRecentStreamList($client) };
	}

	# put current stream at the top of the list if already in the list	
	my ($i) = grep $recent[$_] eq $streamname, 0..$#recent;
	
	if (defined $i) {
		splice @recent, $i, 1;
		unshift @recent, $streamname;
	} else {
		unshift @recent, $streamname;
		pop @recent if @recent > Slim::Utils::Prefs::get('plugin_shoutcastbrowser_max_recent');
	}

	if (defined getRecentFilename($client)) {
		open(FH, ">" . getRecentFilename($client)) or do {
			return;
		};
	
		print FH "#EXTM3U\n";
		foreach my $name (@recent) {
			print FH "#EXTINF:-1,$name\n";
			print FH $status{$client}{recent_data}{$name} . "\n";
		}
		close FH;
	}
}


# Web pages
sub webPages {
	my %pages = ("index\.htm" => \&handleWebIndex);

	if (grep {$_ eq 'ShoutcastBrowser::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins')) {
		Slim::Web::Pages->addPageLinks("radio", { 'PLUGIN_SHOUTCASTBROWSER_MODULE_NAME' => undef });
	} else {
		Slim::Web::Pages->addPageLinks("radio", { 'PLUGIN_SHOUTCASTBROWSER_MODULE_NAME' => "plugins/ShoutcastBrowser/index.html" });
	}

	return (\%pages);
}

sub handleWebIndex {
	my ($client, $params, $callback, $httpClient, $response) = @_;
	
	my %genericGenres = (
		'-1' => {
			token => 'PLUGIN_SHOUTCASTBROWSER_RECENT',
			listRef => readRecentStreamList($client)
		},
		'-2' => {
			token => 'PLUGIN_SHOUTCASTBROWSER_MOST_POPULAR',
			listRef => \@mostPopularStreams
		},
		'-3' => {
			token => 'PLUGIN_SHOUTCASTBROWSER_ALL_STREAMS',
			listRef => [ sort { &stream_sort } keys %streamList ]
		}
	);

	if (defined $params->{'action'} && ($params->{'action'} eq 'refresh')) {
		$params->{'action'} = undef;
		$httpError = undef;
	}
		
	check4Update();
		
	if (not defined $httpError) {
		loadStreamList($client, $params, $callback, $httpClient, $response);
		return undef;
	}
	
	if ($httpError == 0) {
		if (defined $params->{'genreID'}) {
			my $myStreams;
			if ($params->{'genreID'} < 0) {
				$myStreams = $genericGenres{$params->{'genreID'}}->{'listRef'};
				$params->{'genre'} = string($genericGenres{$params->{'genreID'}}->{'token'});
			}
			else {
				$params->{'genre'} = $genresList[$params->{'genreID'}];
				$myStreams = [ sort { &stream_sort } @{ $genreStreams{$params->{'genre'}} } ];
			}

			# play/add stream
			if (defined $params->{'action'} && ($params->{'action'} =~ /(add|play|insert|delete)/i)) {
				my $myStream = @{$myStreams}[$params->{'streamID'}];
				
				if (!defined $client) {
					$params->{'msg'} = string('SETUP_PLUGIN_SHOUTCASTBROWSER_CLIENT_ERROR');
				}
				elsif ($params->{'genre'} eq string('PLUGIN_SHOUTCASTBROWSER_RECENT')) {
					playRecentStream($client, $status{$client}{recent_data}{$myStream}, $myStream, $params->{'action'});
				}
				else {
					playStream($client, $myStream, $params->{'bitrate'}, $params->{'action'});
				}
			}
	
			# show stream information
			if (defined $params->{'action'} && ($params->{'action'} eq 'info')) {
				$params->{'stream'} = @{$myStreams}[$params->{'streamID'}];
				$params->{'streaminfo'} = $streamList{$params->{'stream'}}{$params->{'bitrate'}};
			} 
			# show streams of the wanted genre
			else {
				$params->{'mystreams'} = $myStreams;
				# we don't have any information about recent streams -> fill in some fake values
				if ($params->{'genre'} eq string('PLUGIN_SHOUTCASTBROWSER_RECENT')) {
					if (defined @{$params->{'mystreams'}}) {
						foreach (@{$params->{'mystreams'}}) {
							$params->{'streams'}->{$_}->{'0'} = ();
						}
					}
					else {
						$params->{'streams'} = 1;
						$params->{'msg'} = string('PLUGIN_SHOUTCASTBROWSER_NONE');
					}
				}
				else {
					$params->{'streams'} = \%streamList;
					$params->{'mystreams'} = $myStreams;
				}
			}
		}
		# show genre list
		else {
			$params->{'genericGenres'} = \%genericGenres;
			$params->{'genres'} = \@genresList;
		}
	}
	# data has not been loaded yet
	elsif ($httpError < 0) {
		$params->{'redirect'}{delay} = 3;
		$params->{'redirect'}{url} = "index.html?$params->{'url_query'}";
	}
	elsif ($httpError == 2) {
		# there was a problem parsing XML
		$params->{'msg'} = string('PLUGIN_SHOUTCASTBROWSER_PARSE_ERROR') . " ($httpError)";
		$httpError = undef;	
	}
	else {
		$params->{'msg'} = string('PLUGIN_SHOUTCASTBROWSER_NETWORK_ERROR') . " ($httpError)";
		$httpError = undef;
	}

	return Slim::Web::HTTP::filltemplatefile('plugins/ShoutcastBrowser/index.html', $params);
}

sub check4Update {
	$httpError = undef if (defined($httpError) && ($httpError > 0) && (time() - $last_time > ERRORINTERVAL)) || (time() - $last_time > UPDATEINTERVAL);
}

sub strings {
	return q^PLUGIN_SHOUTCASTBROWSER_MODULE_NAME
	EN	SHOUTcast Internet Radio
	ES	Radio por Internet SHOUTcast
	NL	SHOUTcast Internet radio

PLUGIN_SHOUTCASTBROWSER_CONNECTING
	DE	Verbinde mit SHOUTcast...
	EN	Connecting to SHOUTcast...
	ES	Conectando a SHOUTcast...
	NL	Connectie maken naar SHOUTcast...

PLUGIN_SHOUTCASTBROWSER_REDIRECT
	DE	Bitte haben Sie etwas Geduld, während die Stream-Informationen von der SHOUTcast Website geladen werden...
	EN	Please stay tuned while I'm looking up stream information on the SHOUTcast web site...
	ES	Por favor, permanezca conectado mientras busco información de streams en el sitio web de SHOUTcast...
	NL	Wacht even terwijl naar de streaminformatie wordt gekeken op de SHOUTcast website...

PLUGIN_SHOUTCASTBROWSER_CLICK_REDIRECT
	DE	Klicken Sie hier, falls die Seite nicht automatisch aktualisiert wird
	EN	Click here if this page isn't updated automatically
	ES	Presionar aqui si  esta página no se actualiza automáticamente
	NL	Klik hier als deze pagina niet automatisch wijzigt

PLUGIN_SHOUTCASTBROWSER_REFRESH
	DE	Aktualisieren
	EN	Refresh
	ES	Refrescar
	NL	Vernieuwen

PLUGIN_SHOUTCASTBROWSER_REFRESH_NOW
	DE	RECHTS drücken zum Aktualisieren
	EN	Press RIGHT to refresh the list
	ES	Presionar DERECHA para refrescar la lista
	NL	Druk -> om de lijst te vernieuwen

PLUGIN_SHOUTCASTBROWSER_REFRESH_STREAMLIST
	DE	Liste der Streams aktualisieren
	EN	Refresh stream list
	ES	Refrescar la lista de streams
	NL	Vernieuw stream lijst

PLUGIN_SHOUTCASTBROWSER_NETWORK_ERROR
	CZ	CHYBA: web SHOUTcast je nedostupný
	DE	Fehler: SHOUTcast ist nicht verfügbar
	EN	Error: SHOUTcast web site not available
	ES	Error: el sitio web de SHOUTcast no está disponible
	NL	Fout: SHOUTcast website niet beschikbaar

PLUGIN_SHOUTCASTBROWSER_PARSE_ERROR
	DE	Beim Auswerten der Stream-Informationen ist ein Fehler aufgetreten. Reduzieren Sie allenfalls die Anzahl Streams, falls Sie eine grosse Zahl anfordern wollten.
	EN	There was an error parsing the stream information. Try reducing the number of streams if you've set a great number.
	ES	Hubo un error al analizar la información del stream. Intente reducir el numero de streams si se estableció un número  muy grande.
	NL	Er was een fout bij het analyseren van de streaminformatie. Probeer het aantal streams verminderen als je een groot aantal hebt ingesteld.

SETUP_PLUGIN_SHOUTCASTBROWSER_CLIENT_ERROR
	DE	Kein Player verfügbar.
	EN	Sorry, valid player not found.
	NL	Sorry, geen geldige speler was gevonden.

PLUGIN_SHOUTCASTBROWSER_SHOUTCAST
	EN	SHOUTcast

PLUGIN_SHOUTCASTBROWSER_ALL_STREAMS
	DE	Alle Streams
	EN	All Streams
	ES	Todos los streams
	NL	Alle streams

PLUGIN_SHOUTCASTBROWSER_NONE
	DE	Keine
	EN	None
	ES	Ninguno
	NL	Geen

PLUGIN_SHOUTCASTBROWSER_BITRATE
	EN	Bitrate
	ES	Tasa de bits

PLUGIN_SHOUTCASTBROWSER_KBPS
	EN	kbps

PLUGIN_SHOUTCASTBROWSER_RECENT
	DE	Kürzlich gehört
	EN	Recently played
	ES	Recientemente escuchado
	NL	Recent afgespeeld

PLUGIN_SHOUTCASTBROWSER_MOST_POPULAR
	CZ	Nejpopulárnější
	DE	Populäre Streams
	EN	Most Popular
	ES	Más Popular
	NL	Meest populair

PLUGIN_SHOUTCASTBROWSER_MISC
	DE	Diverse Stile
	EN	Misc. genres
	ES	Géneros misceláneos
	NL	Diverse genres

PLUGIN_SHOUTCASTBROWSER_RANDOM_STREAM
	DE	Zufälligen Stream spielen
	EN	Play random stream
	ES	Reproducir stream al azar
	NL	Speel willekeurige stream

PLUGIN_SHOUTCASTBROWSER_WAS_PLAYING
	DE	Spielte zuletzt
	EN	Was playing
	ES	Se estaba escuchando
	NL	Speelde af

SETUP_GROUP_PLUGIN_SHOUTCASTBROWSER
	EN	SHOUTcast Internet Radio
	ES	Radio por Internet SHOUTcast
	NL	SHOUTcast Internet radio

SETUP_GROUP_PLUGIN_SHOUTCASTBROWSER_DESC
	DE	Blättere durch die Liste der SHOUTcast Internet Radiostationen.
	EN	Browse SHOUTcast list of Internet Radio streams.
	ES	Recorrer la lista de streams de Radio por Internet de  SHOUTcast.
	NL	Bekijk SHOUTcast lijst van Internet radio streams.

SETUP_PLUGIN_SHOUTCASTBROWSER_HOW_MANY_STREAMS
	DE	Anzahl Streams
	EN	Number of Streams
	ES	Número de Streams
	NL	Aantal streams

SETUP_PLUGIN_SHOUTCASTBROWSER_HOW_MANY_STREAMS_DESC
	DE	Anzahl aufzulistender Streams (Radiostationen). Voreinstellung ist 300, das Maximum 2000.
	EN	How many streams to get.  Default is 300, maximum is 2000.
	ES	Cuántos streams traer. Por defecto es 300, máximo es 2000.
	NL	Hoeveel streams ophalen. Standaard is 300, maximum is 2000.

SETUP_PLUGIN_SHOUTCASTBROWSER_GENRE_CRITERION
	DE	Sortierkriterium für Musikstile
	EN	Sort Criterion for Genres
	ES	Criterio para Ordenar por Géneros
	NL	Sorteercriteria voor genres

SETUP_PLUGIN_SHOUTCASTBROWSER_GENRE_CRITERION_DESC
	DE	Kriterium für die Sortierung der Musikstile
	EN	Criterion for sorting genres.
	ES	Criterio para Ordenar por Géneros
	NL	Criterium voor sorteren genres.

SETUP_PLUGIN_SHOUTCASTBROWSER_STREAM_CRITERION
	DE	Sortierkriterium für Streams
	EN	Sort Criterion for Streams
	ES	Criterio para ordenar streams.
	NL	Sorteer criteria voor streams

SETUP_PLUGIN_SHOUTCASTBROWSER_STREAM_CRITERION_DESC
	DE	Kriterium für die Sortierung der Streams (Radiostationen)
	EN	Criterion for sorting streams.
	ES	Criterio para ordenar streams.
	NL	Criterium voor sorteren streams.

SETUP_PLUGIN_SHOUTCASTBROWSER_MIN_BITRATE
	DE	Minimale Bitrate
	EN	Minimum Bitrate
	ES	Mínima Tasa de Bits
	NL	Minimum bitrate

SETUP_PLUGIN_SHOUTCASTBROWSER_MIN_BITRATE_DESC
	DE	Minimal erwünschte Bitrate (0 für unbeschränkt).
	EN	Minimum Bitrate in which you are interested (0 for no limit).
	ES	Mínima Tasa de Bits que nos interesa (0 para no tener límite).
	NL	Minimum bitrate waarin je ge&iuml;nteresseerd bent (0 voor geen limiet).

SETUP_PLUGIN_SHOUTCASTBROWSER_MAX_BITRATE
	DE	Maximale Bitrate
	EN	Maximum Bitrate
	ES	Máxima Tasa de Bits
	NL	Maximum bitrate

SETUP_PLUGIN_SHOUTCASTBROWSER_MAX_BITRATE_DESC
	DE	Maximal erwünschte Bitrate (0 für unbeschränkt).
	EN	Maximum Bitrate in which you are interested (0 for no limit).
	ES	Máxima Tasa de Bits que nos interesa (0 para no tener límite).
	NL	Maximum bitrate waarin je geïnteresseerd bent (0 voor geen limiet).

SETUP_PLUGIN_SHOUTCASTBROWSER_MAX_RECENT
	DE	Zuletzt gehörte Streams
	EN	Recent Streams
	ES	Streams recientes
	NL	Recente streams

SETUP_PLUGIN_SHOUTCASTBROWSER_MAX_RECENT_DESC
	DE	Anzahl zu merkender Streams (Radiostationen)
	EN	Maximum number of recently played streams to remember.
	ES	Máximo número a recordar de streams escuchados recientemente.
	NL	Maximum te onthouden recent afgespeelde streams

SETUP_PLUGIN_SHOUTCASTBROWSER_MAX_POPULAR
	CZ	Nejpopulárnější
	DE	Populäre Streams
	EN	Most Popular
	ES	Más Popular
	NL	Meest populair

SETUP_PLUGIN_SHOUTCASTBROWSER_MAX_POPULAR_DESC
	DE	Die Anzahl Streams, die unter "Populäre Streams" aufgeführt werden sollen. Die Beliebtheit misst sich an der Anzahl Hörer aller Bitraten.
	EN	Number of streams to include in the category of most popular streams, measured by the total of all listeners at all bitrates.
	ES	Número de streams a incluir en la categoría de streams más populares, medida por el total de oyentes en todas las tasas de bits.
	NL	Aantal streams dat in de 'Meest populair' categorie komt, wordt gemeten naar het aantal luisteraars op alle bitrates.

SETUP_PLUGIN_SHOUTCASTBROWSER_ALPHA_REVERSE
	DE	Alphabetisch (umgekehrte Reihenfolge)
	EN	Alphabetical (reverse)
	ES	Alfabético (reverso)
	NL	Alfabetisch (omgekeerd)

SETUP_PLUGIN_SHOUTCASTBROWSER_NUMBEROFSTREAMS
	DE	Anzahl Streams
	EN	Number of streams
	ES	Número de streams
	NL	Aantal streams

SETUP_PLUGIN_SHOUTCASTBROWSER_NUMBEROFSTREAMS_REVERSE
	DE	Anzahl Streams (umgekehrte Reihenfolge)
	EN	Number of streams (reverse)
	ES	Número de Streams (reverso)
	NL	Aantal streams (omgekeerd)

SETUP_PLUGIN_SHOUTCASTBROWSER_DEFAULT_ALPHA
	DE	Alphabetisch (Standard)
	EN	Alphabetical (Default)
	ES	Alfabético (Por Defecto)
	NL	Alfabetisch (standaard)

SETUP_PLUGIN_SHOUTCASTBROWSER_NUMBEROFLISTENERS
	DE	Anzahl Hörer
	EN	Number of listeners
	ES	Número de oyentes
	NL	Aantal luisteraars

SETUP_PLUGIN_SHOUTCASTBROWSER_LISTENERS
	DE	Hörer
	EN	Listeners
	ES	Oyentes
	NL	Luisteraars

SETUP_PLUGIN_SHOUTCASTBROWSER_NUMBEROFLISTENERS_REVERSE
	DE	Anzahl Hörer (umgekehrte Reihenfolge)
	EN	Number of listeners (reverse)
	ES	Número de oyentes (reverso)
	NL	Aantal luisteraars (omgekeerd)

SETUP_PLUGIN_SHOUTCASTBROWSER_MUNGE_GENRE
	DE	Musikstile normalisieren
	EN	Normalise genres
	ES	Normalizar géneros
	NL	Normaliseer genres

SETUP_PLUGIN_SHOUTCASTBROWSER_MUNGE_GENRE_DESC
	DE	Standardmässig wird versucht, die Musikstile zu normalisieren, weil sonst beinahe so viele Stile wie Streams aufgeführt werden. Falls Sie alle Stile unverändert aufführen wollen, so deaktivieren Sie diese Option.
	EN	By default, genres are normalised based on keywords, because otherwise there are nearly as many genres as there are streams. If you would like to see the genre listing as defined by each stream, turn off this parameter.
	ES	Por defecto, los géneros se normalizan en base a palabras clave, ya que de lo contrario existen casi tantos géneros como streams. Si se quiere ver la lista de géneros tal cual se la define en cada stream,   desactivar este parámetro.
	NL	Standaard zijn genres genormaliseerd op sleutelwoorden omdat er anders vrijwel net zoveel genres zouden zijn als streams. Zet deze optie uit als je de genre lijst wilt zien zoals gedefinieerd door elke stream
^;
}

1;
