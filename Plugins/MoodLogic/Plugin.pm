package Plugins::MoodLogic::Plugin;

# $Id$

use strict;
use Scalar::Util qw(blessed);

use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

use Plugins::MoodLogic::VarietyCombo;
use Plugins::MoodLogic::InstantMix;
use Plugins::MoodLogic::MoodWheel;
use Plugins::MoodLogic::Common;
use Plugins::MoodLogic::Settings;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.moodlogic',
	'defaultLevel' => 'WARN',
});

my $mixer;
my $isScanning = 0;

my $initialized = 0;
my $browser;

our @mood_names = ();
our %mood_hash  = ();
my $last_error  = 0;

sub getFunctions {
	return '';
}

sub getDisplayName {
	return 'MOODLOGIC';
}

sub enabled {
	return ($::VERSION ge '6.1') && Slim::Utils::OSDetect::OS() eq 'win' && __PACKAGE__->initPlugin();
}

sub canUseMoodLogic {
	my $class = shift;

	return (Slim::Utils::OSDetect::OS() eq 'win' && __PACKAGE__->initPlugin());
}

sub shutdownPlugin {

	# turn off checker
	Slim::Utils::Timers::killTimers(0, \&checker);

	# disable protocol handler
	Slim::Player::ProtocolHandlers->registerHandler('moodlogicplaylist', 0);

	$initialized = 0;

	# set importer to not use
	Slim::Music::Import->useImporter('Plugins::MoodLogic::Plugin', 0);
}

sub prefName {
	my $class = shift;

	return lc($class->title);
}

sub title {
	my $class = shift;

	return 'MOODLOGIC';
}

sub mixable {
	my $class = shift;
	my $item  = shift;
	
	if (blessed($item) && $item->can('moodlogic_mixable')) {

		return $item->moodlogic_mixable;
	}
}

sub initPlugin {
	my $class = shift;

	return 1 if $initialized; 
	return 0 if Slim::Utils::OSDetect::OS() ne 'win';
	
	Plugins::MoodLogic::Common::checkDefaults();
	
	require Win32::OLE;
	import Win32::OLE qw(EVENTS);
	
	Win32::OLE->Option(Warn => \&Plugins::MoodLogic::Common::OLEError);
	my $name = "mL_MixerCenter";
	
	$mixer = Win32::OLE->new("$name.MlMixerComponent");
	
	if (!defined $mixer) {
		$name = "mL_Mixer";
		$mixer = Win32::OLE->new("$name.MlMixerComponent");
	}
	
	if (!defined $mixer) {

		logError("Could not find MoodLogic mixer component.");
		return 0;
	}
	
	$browser = Win32::OLE->new("$name.MlMixerFilter");
	
	if (!defined $browser) {

		logError("Could not find MoodLogic filter component.");
		return 0;
	}

	Win32::OLE->WithEvents($mixer, \&Plugins::MoodLogic::Common::event_hook);

	# What are these constants from?
	$mixer->{JetPwdMixer}   = 'C393558B6B794D';
	$mixer->{JetPwdPublic}  = 'F8F4E734E2CAE6B';
	$mixer->{JetPwdPrivate} = '5B1F074097AA49F5B9';
	$mixer->{UseStrings}    = 1;
	$mixer->{MixMode}       = 0;
	$mixer->Initialize();
	
	if ($last_error != 0) {

		$log->info("Rebuilding mixer database.");

		$mixer->MixerDb_Create();
		$last_error = 0;
		$mixer->Initialize();

		if ($last_error != 0) {
			return 0;
		}
	}
	
	for (my $i = 0; $i < 7; $i++) {

		push @mood_names, string("MOODLOGIC_MOOD_$i");

		$mood_hash{$mood_names[$i]} = $i;
	}

	#Slim::Utils::Strings::addStrings($strings);
	Slim::Player::ProtocolHandlers->registerHandler("moodlogicplaylist", "0");

	# addImporter for Plugins, may include mixer function, setup function, mixerlink reference and use on/off.
	Slim::Music::Import->addImporter($class, {
		'mixer'     => \&mixerFunction,
		'setup'     => \&addGroups,
		'mixerlink' => \&mixerlink,
		'use'       => Slim::Utils::Prefs::get($class->prefName),
	});

	Plugins::MoodLogic::Settings->new;

	Plugins::MoodLogic::InstantMix::init();
	Plugins::MoodLogic::MoodWheel::init();
	Plugins::MoodLogic::VarietyCombo::init();

	$initialized = 1;

	checker($initialized);

	return $initialized;
}

sub checker {
	my $firstTime = shift || 0;

	if (!Slim::Utils::Prefs::get('moodlogic')) {
		return;
	}
	
	if (!$firstTime && !Slim::Music::Import->stillScanning && isMusicLibraryFileChanged()) {

		Slim::Control::Request::executeRequest(undef, ['rescan']);
	}

	# make sure we aren't doing this more than once...
	Slim::Utils::Timers::killTimers(0, \&checker);

	# Call ourselves again after 5 seconds
	Slim::Utils::Timers::setTimer(0, (Time::HiRes::time() + 5.0), \&checker);
}

sub isMusicLibraryFileChanged {

	my $file      = $mixer->{'JetFilePublic'} || return 0;
	my $fileMTime = (stat $file)[9];

	$log->debug("Read library status of $fileMTime");

	# Only say "yes" if it has been more than one minute since we last finished scanning
	# and the file mod time has changed since we last scanned. Note that if we are
	# just starting, $lastMLChange is undef, so both $fileMTime
	# will be greater than 0 and time()-0 will be greater than 180 :-)
	my $lastScanTime = Slim::Music::Import->lastScanTime;
	my $lastMLChange = Slim::Music::Import->lastScanTime('MLLastLibraryChange');

	if ($fileMTime > $lastMLChange) {

		$log->info("Music library has changed!");

		my $scanInterval = Slim::Utils::Prefs::get('moodlogicscaninterval');

		if (!$scanInterval) {

			# only scan if moodlogicscaninterval is non-zero.
			$log->info("Scan interval set to 0, rescanning disabled.");

			return 0;
		}

		if (!$lastScanTime) {
			return 1;
		}

		if ((time - $lastScanTime) > $scanInterval) {
			return 1;
		}

		$log->info("Waiting for $scanInterval seconds to pass before rescanning.");
	}
	
	return 0;
}

sub getMoodWheel {
	my ($id, $for) = @_;

	my @enabled_moods = ();
	
	if ($for eq "genre") {

		$mixer->{Seed_MGID} = $id;
		$mixer->{MixMode} = 3;

	} elsif ($for eq "artist") {

		$mixer->{Seed_AID} = $id;
		$mixer->{MixMode} = 2;

	} else {

		$log->warn('Warning: no/unknown type specified for mood wheel.');
		return undef;
	}

	push @enabled_moods, $mood_names[1] if ($mixer->{MF_1_Enabled});
	push @enabled_moods, $mood_names[3] if ($mixer->{MF_3_Enabled});
	push @enabled_moods, $mood_names[4] if ($mixer->{MF_4_Enabled});
	push @enabled_moods, $mood_names[6] if ($mixer->{MF_6_Enabled});
	push @enabled_moods, $mood_names[0] if ($mixer->{MF_0_Enabled});

	return \@enabled_moods;
}

sub mixerFunction {
	my $client = shift;
	
	# look for parentParams (needed when multiple mixers have been used)
	my $paramref  = defined $client->modeParam('parentParams') ? $client->modeParam('parentParams') : $client->modeParameterStack(-1);
	my $listIndex = $paramref->{'listIndex'};

	my $items     = $paramref->{'listRef'};
	my $hierarchy = $paramref->{'hierarchy'};
	my $level     = $paramref->{'level'} || 0;
	my $descend   = $paramref->{'descend'};

	my $currentItem = $items->[$listIndex];
	my $all         = !ref($currentItem);

	my @levels = split(",", $hierarchy);
	my $mix;

	# if we've chosen a particular song
	if ($levels[$level] eq 'track' && $currentItem && $currentItem->moodlogic_mixable()) {

		Slim::Buttons::Common::pushMode($client, 'moodlogic_variety_combo', {'song' => $currentItem});
		$client->pushLeft();

	} elsif ($levels[$level] eq 'contributor' && $currentItem && $currentItem->moodlogic_mixable()) {

		# if we've picked an artist 
		Slim::Buttons::Common::pushMode($client, 'moodlogic_mood_wheel', {'artist' => $currentItem});
		$client->pushLeft();

	} elsif ($levels[$level] eq 'genre' && $currentItem && $currentItem->moodlogic_mixable()) {

		# if we've picked a genre 
		Slim::Buttons::Common::pushMode($client, 'moodlogic_mood_wheel', {'genre' => $currentItem});
		$client->pushLeft();

	} else {

		# don't do anything if nothing is mixable
		$client->bumpRight();
	}
}

sub mixerlink {
	my ($item, $form, $descend) = @_;

	if ($descend) {
		$form->{'mixable_descend'} = 1;
	} else {
		$form->{'mixable_not_descend'} = 1;
	}

	# only add link if enabled and usable.  moodlogic doensn't do albums
	if (canUseMoodLogic() && Slim::Utils::Prefs::get('moodlogic') && $form->{'levelName'} ne 'album') {
		
		#set up a moodlogic link
		$form->{'mixerlinks'}{Plugins::MoodLogic::Plugin->title()} = "plugins/MoodLogic/mixerlink.html";

		#flag if mixable
		if ($item->can('moodlogic_mixable') && $item->moodlogic_mixable) {
			$form->{'moodlogic_mixable'} = 1;
		}
	}
	
	return $form;
}

sub getMix {
	my ($id, $mood, $for) = @_;

	my @instant_mix = ();
	
	$mixer->{VarietyCombo} = 0; # resets mixer

	if (defined $mood) {

		$log->info("Create $mood mix for $for $id")
	}
	
	if ($for eq "song") {

		$mixer->{Seed_SID} = $id;
		$mixer->{MixMode} = 0;

	} elsif (defined $mood && defined $mood_hash{$mood}) {

		$mixer->{MoodField} = $mood_hash{$mood};

		if ($for eq "artist") {

			$mixer->{Seed_AID} = $id;
			$mixer->{MixMode} = 2;

		} elsif ($for eq "genre") {

			$mixer->{Seed_MGID} = $id;
			$mixer->{MixMode} = 3;

		} else {

			$log->warn("Warning: No valid type specified for instant mix.");
			return undef;
		}

	} else {

		$log->warn("Warning: No valid mood specified for instant mix.");
		return undef;
	}

	# the VarietyCombo property can only be set
	# after an initial mix has been created
	$mixer->Process;

	my $count   = Slim::Utils::Prefs::get('instantMixMax');
	my $variety = Slim::Utils::Prefs::get('varietyCombo');

	while ($mixer->Mix_PlaylistSongCount() < $count && $mixer->{VarietyCombo} > $variety) {

		# $mixer->{VarietyCombo} = 0 causes a mixer reset, so we have to avoid it.
		$mixer->{VarietyCombo} = $mixer->{VarietyCombo} == 10 ? $mixer->{VarietyCombo} - 9 : $mixer->{VarietyCombo} - 10;
		$mixer->Process(); # recreate mix
	}

	$count = $mixer->Mix_PlaylistSongCount();

	for (my $i = 1; $i <= $count; $i++) {

		push @instant_mix, Slim::Utils::Misc::fileURLFromPath($mixer->Mix_SongFile($i));
	}

	return \@instant_mix;
}

sub webPages {
	my %pages = (
		"instant_mix\.(?:htm|xml)" => \&instant_mix,
		"mood_wheel\.(?:htm|xml)"  => \&mood_wheel,
	);

	return (\%pages);
}

sub mood_wheel {
	my ($client, $params) = @_;

	my $items = "";

	my $song   = $params->{'song'}   || $params->{'track'};
	my $artist = $params->{'artist'} || $params->{'contributor'};
	my $album  = $params->{'album'};
	my $genre  = $params->{'genre'};
	my $player = $params->{'player'};

	my $itemnumber = 0;

	if (defined $artist && $artist ne "") {

		$items = getMoodWheel(Slim::Schema->find('Contributor', $artist)->moodlogic_id, 'artist');

	} elsif (defined $genre && $genre ne "" && $genre ne "*") {

		$items = getMoodWheel(Slim::Schema->find('Genre', $genre)->moodlogic_id, 'genre');

	} else {

		$log->warn('Warning: no/unknown type specified for mood wheel');
		return undef;
	}

	$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("plugins/MoodLogic/mood_wheel_pwdlist.html", $params)};
	$params->{'mood_list'} = $items;

	return Slim::Web::HTTP::filltemplatefile("plugins/MoodLogic/mood_wheel.html", $params);
}

sub instant_mix {
	my ($client, $params) = @_;

	my $output = "";
	my $items  = "";

	my $song   = $params->{'song'}   || $params->{'track'};
	my $artist = $params->{'artist'} || $params->{'contributor'};
	my $album  = $params->{'album'};
	my $genre  = $params->{'genre'};
	my $player = $params->{'player'};
	my $mood   = $params->{'mood'};
	my $p0     = $params->{'p0'};

	my $itemnumber = 0;
	my $track      = Slim::Schema->find('Track', $song);

	$params->{'browse_items'} = [];
	$params->{'levelName'} = "track";

	if (defined $mood && $mood ne "") {

		$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("plugins/MoodLogic/mood_wheel_pwdlist.html", $params)};
	}

	if (defined $song && $song ne "") {
		$params->{'src_mix'} = Slim::Music::Info::standardTitle(undef, $track);
	} elsif (defined $mood && $mood ne "") {
		$params->{'src_mix'} = $mood;
	}

	$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("plugins/MoodLogic/instant_mix_pwdlist.html", $params)};

	if (defined $song && $song ne "") {

		$items = getMix($track->moodlogic_id, undef, 'song');

	} elsif (defined $artist && $artist ne "" && $artist ne "*" && $mood ne "") {

		$items = getMix(Slim::Schema->find('Contributor', $artist)->moodlogic_id, $mood, 'artist');

	} elsif (defined $genre && $genre ne "" && $genre ne "*" && $mood ne "") {

		$items = getMix(Slim::Schema->find('Genre', $genre)->moodlogic_id, $mood, 'genre');

	} else {

		$log->warn('Warning: no/unknown type specified for instant mix.');

		return undef;
	}

	if (defined $items && ref $items eq "ARRAY" && defined $client) {
		# We'll be using this to play the entire mix using 
		# playlist (add|play|load|insert)tracks listref=moodlogic_mix
		$client->modeParam('moodlogic_mix',$items);
	} else {
		$items = [];
	}

	if (scalar @$items) {

		push @{$params->{'browse_items'}}, {

			'text'         => Slim::Utils::Strings::string('THIS_ENTIRE_PLAYLIST'),
			'attributes'   => "&listRef=moodlogic_mix",
			'odd'          => ($itemnumber + 1) % 2,
			'webroot'      => $params->{'webroot'},
			'skinOverride' => $params->{'skinOverride'},
			'player'       => $params->{'player'},
		};

		$itemnumber++;
	}

	for my $item (@$items) {

		my %form = ();

		# If we can't get an object for this url, skip it, as the
		# user's database is likely out of date. Bug 863
		my $trackObj  = Slim::Schema->rs('Track')->objectForUrl($item) || next;

		$trackObj->displayAsHTML(\%form, 0);

		$form{'attributes'} = join('=', '&track.id', $trackObj->id);

		$itemnumber++;

		push @{$params->{'browse_items'}}, \%form;
		
	}

	if (defined $p0 && defined $client) {

		$client->execute(["playlist", $p0 eq "append" ? "addtracks" : "playtracks", "listref=moodlogic_mix"]);
	}

	return Slim::Web::HTTP::filltemplatefile("plugins/MoodLogic/instant_mix.html", $params);
}

1;

__END__
