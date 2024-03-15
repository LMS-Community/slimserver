package Slim::Plugin::Sounds::Plugin;
# Browse Sounds & Effects

use strict;
use base qw(Slim::Plugin::OPMLBased);
use File::Path qw(mkpath);
use File::Spec::Functions qw(catfile);
use HTTP::Status qw(RC_NOT_FOUND RC_OK);
use Digest::MD5 qw(md5_hex);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Player::ProtocolHandlers;
use Slim::Plugin::Sounds::ProtocolHandler;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

use constant BASE_URL => 'https://downloads.slimdevices.com/sounds';
use constant BASE_AUDIO_PATH => 'plugins/sounds/audio/';

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.sounds',
	'defaultLevel' => 'WARN',
	'description'  => getDisplayName(),
});

my $serverPrefs = preferences('server');
my $soundsCache = catfile($serverPrefs->get('cachedir'), 'Sounds');

my $menus = {
	MUSICAL => {
		BARN_FIRE      => 'musical/barn_fire.mp3',
		BLUE_HENRY     => 'musical/blue_henry.mp3',
		BLUE_ORCHID    => 'musical/blue_orchid.mp3',
		BONGO_TECH     => 'musical/bongo_tech.mp3',
		BRAINFLUID     => 'musical/brainfluid.mp3',
		BUTTERY        => 'musical/buttery.mp3',
		CAPPUCINO      => 'musical/cappucino.mp3',
		COOL_CATS      => 'musical/cool_cats.mp3',
		CORNFLOWER     => 'musical/cornflower.mp3',
		CRYSTALIZE     => 'musical/crystalize.mp3',
		EXPERIMENTAL   => 'musical/experimental.mp3',
		HIBISCUS       => 'musical/hibiscus.mp3',
		JUNK_ARMOR     => 'musical/junk_armor.mp3',
		MELANCHOLY_DAY => 'musical/melancholy_day.mp3',
		SLICKBABY      => 'musical/slickbaby.mp3',
		SLOG_IT_OUT    => 'musical/slog_it_out.mp3',
		SOFT_HORIZON   => 'musical/soft_horizon.mp3',
		SRI_LAMA       => 'musical/sri_lama.mp3',
		STARGAZER      => 'musical/stargazer.mp3',
		SUPER_CHEESE   => 'musical/super_cheese.mp3',
		TAIL_HONKER    => 'musical/tail_honker.mp3',
		TONGUE_CHEEK   => 'musical/tongue_cheek.mp3',
		TRANSLAB       => 'musical/translab.mp3',
		TWEEDLEDUM     => 'musical/tweedledum.mp3',
		TWENSA         => 'musical/twensa.mp3',
	},
	NATURAL => {
		BABBLING_BROOK    => 'natural/babbling_brook.mp3',
		BUBBLES           => 'natural/bubbles.mp3',
		CRICKETS          => 'natural/crickets.mp3',
		FIRE              => 'natural/fire.mp3',
		HARD_RAIN_THUNDER => 'natural/hard_rain_thunder.mp3',
		HEARTBEAT_FAST    => 'natural/heartbeat_fast.mp3',
		HEARTBEAT         => 'natural/heartbeat.mp3',
		HORSE_WALKING     => 'natural/horse_walking.mp3',
		HORSE_WHINNY      => 'natural/horse_whinny.mp3',
		LAPPING_WAVES     => 'natural/lapping_waves.mp3',
		MEADOWLARK        => 'natural/meadowlark.mp3',
		OCEAN_SURF        => 'natural/ocean_surf.mp3',
		RAIN_THUNDER      => 'natural/rain_thunder.mp3',
		RAIN_OUTSIDE      => 'natural/rain_outside.mp3',
		RAIN_SPLASHING    => 'natural/rain_splashing.mp3',
		RIVER             => 'natural/river.mp3',
		ROBINS            => 'natural/robins.mp3',
		ROOSTER_CROW      => 'natural/rooster_crow.mp3',
		RURAL             => 'natural/rural.mp3',
		SHORE_SEAGULLS    => 'natural/shore_seagulls.mp3',
		SPRING_PEEPERS    => 'natural/spring_peepers.mp3',
		STREAM_BIRDS      => 'natural/stream_birds.mp3',
		STREAM            => 'natural/stream.mp3',
		TROPICAL_AMBIENCE => 'natural/tropical_ambience.mp3',
		WAVES             => 'natural/waves.mp3',
		WIND_WHISTLE      => 'natural/wind_whistle.mp3',
		WIND              => 'natural/wind.mp3',
	},
	EFFECTS => {
		AMBULANCE             => 'effects/ambulance.mp3',
		BLENDER               => 'effects/blender.mp3',
		CITY                  => 'effects/city.mp3',
		COINS                 => 'effects/coins.mp3',
		CROSSING_BELLS        => 'effects/crossing_bells.mp3',
		ELECTRO_FUZZ          => 'effects/electro_fuzz.mp3',
		FOGHORN               => 'effects/foghorn.mp3',
		FREIGHT_TRAIN_PASSING => 'effects/freight_train_passing.mp3',
		FREIGHT_TRAIN         => 'effects/freight_train.mp3',
		HAIR_DRYER            => 'effects/hair_dryer.mp3',
		MAGNETO_VAPOR         => 'effects/magneto_vapor.mp3',
		MOTORCYCLES           => 'effects/motorcycles.mp3',
		SCUBA_DIVER           => 'effects/scuba_diver.mp3',
		SPOOKY_FEEDBACK       => 'effects/spooky_feedback.mp3',
		STEAM_TRAIN_WHISTLE   => 'effects/steam_train_whistle.mp3',
		SUB_ALERT             => 'effects/sub_alert.mp3',
		TEA_KETTLE            => 'effects/tea_kettle.mp3',
		TRAFFIC               => 'effects/traffic.mp3',
		WIND_CHIME_FLOURISH   => 'effects/wind_chime_flourish.mp3',
		WIND_CHIME            => 'effects/wind_chime.mp3',
		ALARM_BUZZER          => 'html/slim-backup-alarm.mp3',
	},
};

my $soundsMenus;
my %validPaths;
# Flat list of sounds to use for alarms
my $alarmPlaylists;

sub initPlugin {
	my $class = shift;

	Slim::Player::ProtocolHandlers->registerHandler(
		loop => 'Slim::Plugin::Sounds::ProtocolHandler'
	);

	# localize list of sounds
	getSortedSounds();
	$serverPrefs->setChange(\&getSortedSounds, 'language');
	mkpath($soundsCache);

	# register a handler to proxy the sounds files - it might be a https source which the players can't handle
	Slim::Web::Pages->addRawFunction(BASE_AUDIO_PATH, \&proxyRequest);

	$class->SUPER::initPlugin(
		feed   => sub {
			my ($client, $cb, $args) = @_;
			$cb->($soundsMenus);
		},
		tag    => 'sounds',
		menu   => 'music_services',
		weight => 90,
		is_app => 1,
	);
}

sub getDisplayName {
	return 'PLUGIN_SOUNDS_MODULE_NAME';
}

# Don't add this item to any menu
sub playerMenu { }

# Called by Slim::Utils::Alarm to get the playlists that should be presented as options
# for an alarm playlist.
sub getAlarmPlaylists {
	$alarmPlaylists || getSortedSounds();
	return $alarmPlaylists;
}

sub getSortedSounds {
	main::INFOLOG && $log->is_info && $log->info("Sorting Sounds list alphabetically");
	my @items = sort {
		$a->{name} cmp $b->{name};
	} map {
		{
			name  => string("PLUGIN_SOUNDS_$_"),
			id    => $_,
			items => [],
		}
	} keys %{$menus};

	my @playlistItems;

	for my $menu ( @items ) {
		# Sort each submenu after localizing
		my @subsorted = sort {
			$a->{name} cmp $b->{name}
		} map {
			my $path = $menus->{$menu->{id}}->{$_};
			$validPaths{$path} = string("PLUGIN_SOUNDS_$_");
			{
				name    => string("PLUGIN_SOUNDS_$_"),
				bitrate => 128,
				type    => 'audio',
				url     => 'loop://' . $path,
			};
		} keys %{ $menus->{$menu->{id}} };

		$menu->{items} = \@subsorted;

		push @playlistItems, {
			type  => $menu->{name},
			items => [ map {
				{
					title => $_->{name},
					url   => $_->{url},
				}
			} @subsorted ]
		};

		delete $menu->{id};
	}

	main::DEBUGLOG && $log->is_debug && $log->debug(Data::Dump::dump(\@items, \%validPaths));

	$alarmPlaylists = \@playlistItems;
	return $soundsMenus = {
		title => string('PLUGIN_SOUNDS_MODULE_NAME'),
		type  => 'opml',
		items => \@items
	};
}

sub getSoundName {
	my ($class, $path) = @_;
	return $validPaths{$path =~ s/^loop:\/\///r};
}

sub getStreamUrl {
	my ($class, $client, $url) = @_;

	my $auth = '';
	if ( $serverPrefs->get('authorize') ) {
		my $password = Slim::Player::Squeezebox::generate_random_string(10);
		$client->password($password);
		$auth = "squeezeboxXXX:$password@";
	}

	my $serverURL = "http://$auth" . Slim::Utils::Network::serverAddr() . ':' . $serverPrefs->get('httpport');

	return "$serverURL/$url" if $url =~ /^html/;

	return "$serverURL/" . BASE_AUDIO_PATH . $url;
}

sub proxyRequest {
	my ($httpClient, $response) = @_;

	my ($path) = $response->request->uri->path =~ m|/${\BASE_AUDIO_PATH}(.*)|;

	main::INFOLOG && $log->is_info && $log->info("Sounds file to fetch: $path");

	return _notFound(@_) unless $validPaths{$path};

	my $soundsFile = catfile($soundsCache, md5_hex($path));

	my $sendFile = sub {
		$response->code(HTTP::Status::RC_OK);
		Slim::Web::HTTP::sendStreamingFile($httpClient, $response, 'audio/mpeg', $soundsFile);
	};

	if (-f $soundsFile) {
		main::INFOLOG && $log->is_info && $log->info("Serving from local cache ($soundsFile).");
		return $sendFile->();
	}

	my $originUrl = BASE_URL . "/$path";

	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			return _notFound($httpClient, $response) unless -f $soundsFile;

			main::INFOLOG && $log->is_info && $log->info("Downloaded $originUrl as $soundsFile");

			$sendFile->();
		},
		sub {
			my ($http, $error) = @_;

			$log->error("Failed to fetch $originUrl: $error");
			_notFound($httpClient, $response);
		},
		{
			saveAs => $soundsFile
		}
	)->get($originUrl);

	return;
}

sub _notFound {
	my ($httpClient, $response) = @_;

	$log->warn("Failed to fetch Sounds file: " . $response->request->uri->path);

	$response->code(RC_NOT_FOUND);
	$response->content_type('text/html');
	$response->header('Connection' => 'close');
	Slim::Web::HTTP::addHTTPResponse($httpClient, $response,
		Slim::Web::HTTP::filltemplatefile('html/errors/404.html', { path => $response->request->uri->path }
	));
}

1;
