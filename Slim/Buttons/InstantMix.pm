package Slim::Buttons::InstantMix;

# license bla

use strict;
use Slim::Buttons::Common;
use Slim::Music::MoodLogic;
use Slim::Utils::Strings qw (string);
use Slim::Utils::Timers;
use Slim::Hardware::VFD;

# button functions for browse directory
my @instantMix = ();

my %functions = (
	
	'up' => sub  {
		my $client = shift;
                my $count = scalar @instantMix;
                
		if ($count < 2) {
			Slim::Display::Animation::bumpUp($client);
		} else {
                    my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#instantMix + 1), selection($client, 'instant_mix_index'));
                    setSelection($client, 'instant_mix_index', $newposition);
                    $client->update();
		}
	},
	
	'down' => sub  {
		my $client = shift;
		my $count = scalar @instantMix;

		if ($count < 2) {
			Slim::Display::Animation::bumpDown($client);
		} else {
                    my $newposition = Slim::Buttons::Common::scroll($client, +1, ($#instantMix + 1), selection($client, 'instant_mix_index'));
                    setSelection($client, 'instant_mix_index', $newposition);
                    $client->update();
		}
	},
	
	'left' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	
	'right' => sub  {
                my $client = shift;
                
                my @oldlines = Slim::Display::Display::curLines($client);
		Slim::Buttons::Common::pushMode($client, 'trackinfo', {'track' => $instantMix[selection($client, 'instant_mix_index')]});
		Slim::Display::Animation::pushLeft($client, @oldlines, Slim::Display::Display::curLines($client));
	},
	'play' => sub  {
		my $client = shift;
		my $button = shift;
		my $append = shift;
		my $line1;
		my $line2;
		
		if ($append) {
			$line1 = string('ADDING_TO_PLAYLIST')
		} elsif (Slim::Player::Playlist::shuffle($client)) {
			$line1 = string('PLAYING_RANDOMLY_FROM');
		} else {
			$line1 = string('NOW_PLAYING_FROM')
		}
	 	$line2 = string('MOODLOGIC_INSTANT_MIX');

		Slim::Display::Animation::showBriefly($client, Slim::Display::Display::renderOverlay($line1, $line2, undef, Slim::Hardware::VFD::symbol('notesymbol')));
		
		Slim::Control::Command::execute($client, ["playlist", $append ? "append" : "play", $instantMix[0]]);
		
		for (my $i=1; $i<=$#instantMix; $i++) {
                        Slim::Control::Command::execute($client, ["playlist", "append", $instantMix[$i]]);		    
		}
	},
);

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	my $push = shift;

        if ($push eq "push") {
            setSelection($client, 'instant_mix_index', 0);
            
            if (defined Slim::Buttons::Common::param($client, 'song')) {
                @instantMix = Slim::Music::MoodLogic::getMix(Slim::Music::Info::moodLogicSongId(Slim::Buttons::Common::param($client, 'song')), undef, 'song');
            } elsif (defined Slim::Buttons::Common::param($client, 'artist') && defined Slim::Buttons::Common::param($client, 'mood')) {
                @instantMix = Slim::Music::MoodLogic::getMix(Slim::Music::Info::moodLogicArtistId(Slim::Buttons::Common::param($client, 'artist')), Slim::Buttons::Common::param($client, 'mood'), 'artist');
            } elsif (defined Slim::Buttons::Common::param($client, 'genre') && defined Slim::Buttons::Common::param($client, 'mood')) {
                @instantMix = Slim::Music::MoodLogic::getMix(Slim::Music::Info::moodLogicGenreId(Slim::Buttons::Common::param($client, 'genre')), Slim::Buttons::Common::param($client, 'mood'), 'genre');
            } else {
                die 'no/unknown type specified for instant mix';
            }
        } 
	
	$client->lines(\&lines);
}

#
# figure out the lines to be put up to display
#
sub lines {
	my $client = shift;
	my ($line1, $line2);

	$line1 = string('MOODLOGIC_INSTANT_MIX');
	$line1 .= sprintf(" (%d ".string('OUT_OF')." %s)", selection($client, 'instant_mix_index') + 1, scalar @instantMix);	
	$line2 = Slim::Music::Info::infoFormat($instantMix[selection($client, 'instant_mix_index')], 'TITLE (ARTIST)', 'TITLE');

	return ($line1, $line2, undef, Slim::Hardware::VFD::symbol('rightarrow'));
}

#	get the current selection parameter from the parameter stack
sub selection {
	my $client = shift;
	my $index = shift;

	my $value = Slim::Buttons::Common::param($client, $index);

	if (defined $value  && $value eq '__undefined') {
		undef $value;
	}

	return $value;
}

#	set the current selection parameter from the parameter stack
sub setSelection {
	my $client = shift;
	my $index = shift;
	my $value = shift;

	if (!defined $value) {
		$value = '__undefined';
	}

	Slim::Buttons::Common::param($client, $index, $value);
}

sub specialPushLeft {
        my $client = shift @_;
        my $step = shift @_;
        my @oldlines = @_;

	my $now = Time::HiRes::time();
	my $when = $now + 0.5;
	
        if ($step == 0) {
            Slim::Buttons::Common::pushMode($client, 'block');
            Slim::Display::Animation::pushLeft($client, @oldlines, string('MOODLOGIC_MIXING'));
            Slim::Utils::Timers::setTimer($client,$when,\&specialPushLeft,$step+1);
        } elsif ($step == 3) {
            Slim::Buttons::Common::popMode($client);            
            Slim::Display::Animation::pushLeft($client, string('MOODLOGIC_MIXING')."...", "", Slim::Display::Display::curLines($client));
        } else {
            Slim::Hardware::VFD::vfdUpdate($client, Slim::Display::Display::renderOverlay(string('MOODLOGIC_MIXING').("." x $step), undef, undef, undef));
            Slim::Utils::Timers::setTimer($client,$when,\&specialPushLeft,$step+1);
        }
}


1;

__END__
