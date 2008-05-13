#    Copyright (C) 2008 Erland Isaksson (erland_i@hotmail.com)
#    
#    This library is free software; you can redistribute it and/or
#    modify it under the terms of the GNU Lesser General Public
#    License as published by the Free Software Foundation; either
#    version 2.1 of the License, or (at your option) any later version.
#    
#    This library is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#    Lesser General Public License for more details.
#    
#    You should have received a copy of the GNU Lesser General Public
#    License along with this library; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA


package Slim::Plugin::ABTester::Plugin;

use strict;

use base qw(Slim::Plugin::Base);

use Storable;
use Slim::Utils::Prefs;
use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use File::Spec::Functions qw(:ALL);
use File::Slurp;
use File::Path;
use Scalar::Util qw(blessed);
use XML::Simple;
use Data::Dumper;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use POSIX qw(floor);
use Slim::Utils::Log;

our $PLUGINVERSION =  undef;

my $prefs = preferences('plugin.abtester');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.abtester',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_ABTESTER',
});
my $logFirmware = logger('player.firmware');

my %images;

my %choiceMapping = (
	'1' => 'selectImage_1',
	'2' => 'selectImage_2',
	'3' => 'selectImage_3',
	'4' => 'selectImage_4',
	'5' => 'selectImage_5',
	'preset_1' => 'selectImage_1',
	'preset_2' => 'selectImage_2',
	'preset_3' => 'selectImage_3',
	'preset_4' => 'selectImage_4',
	'preset_5' => 'selectImage_5',
	'arrow_left' => 'exit_left',
	'arrow_right' => 'exit_right',
	'play' => 'play',
	'add' => 'add',
	'search' => 'passback',
	'stop' => 'passback',
	'pause' => 'passback'
);

sub getDisplayName {
	return 'PLUGIN_ABTESTER';
}

sub getFunctions {
	# Functions to allow mapping of mixes to keypresses
	return {
		'loadStandardImage' => sub  {
			my $client = shift;
			my $button = shift;
			my $args = shift;

			my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
			for my $plugindir (@pluginDirs) {
				my $dir = catdir($plugindir,"ABTester","StandardImages");
				if(-e catfile($dir,$args)) {
					loadImage($client,catfile($dir,$args));
					return;
				}
			}
			$log->error("Couldn't find image: $args");
		},
	}
}

sub selectImage {
	my $client = shift;
	my $button = shift;
	my $number = shift;
			
	$log->debug("Handling button: $number");
	my $testcase = $client->modeParam('testcase');
	if($client->modeParam('modeName') =~ /.*ABX$/) {
		if($number le '3') {
			$log->debug("Executing button: $number");
			my $testcaseImages;
			if(exists $images{$client->id}->{$testcase}->{'image'}) {
				$testcaseImages = $images{$client->id}->{$testcase}->{'image'};
			}elsif(exists $images{$client->id}->{$testcase}->{'audio'}) {
				$testcaseImages = $images{$client->id}->{$testcase}->{'audio'};
			}elsif(exists $images{$client->id}->{$testcase}->{'perlfunction'}) {
				$testcaseImages = $images{$client->id}->{$testcase}->{'perlfunction'};
			}else {
				$testcaseImages = $images{$client->id}->{$testcase}->{'script'};
			}
			my @testcaseImageKeys = sort keys %$testcaseImages;
	
			my $imageKey = 'X';
	
			if($number le '2') {
				$imageKey = @testcaseImageKeys->[$number-1];
			}
	
			my $visibleImageKey = $imageKey;
			if($imageKey eq 'X') {
				my $listRef = $client->modeParam('listRef');
				if($listRef->[0]->{'value'} eq 'instruction') {
					$imageKey=$listRef->[3]->{'realId'};
				}else {
					$imageKey=$listRef->[2]->{'realId'};
				}
			}
			my $currentData = $client->modeParam('currentData');
			if(exists $images{$client->id}->{$testcase}->{'image'}) {
				if(loadImage($client,catfile(_getImageDir($testcase),$images{$client->id}->{$testcase}->{'image'}->{$imageKey}->{'content'}))) {
					$currentData->{'image'} = $visibleImageKey;
				}else {
					delete $currentData->{'image'};
				}
			}else {
				$currentData->{'image'} = $visibleImageKey;
			}
			my $showChangedData = 0;
			if(exists $images{$client->id}->{$testcase}->{'perlfunction'}) {
				_executeFunction($client,$testcase,$images{$client->id}->{$testcase}->{'perlfunction'}->{$imageKey}->{'content'});
				$showChangedData = 1;
			}
			if(exists $images{$client->id}->{$testcase}->{'script'}) {
				_executeScript($client,$testcase,$images{$client->id}->{$testcase}->{'script'}->{$imageKey}->{'content'});
				$showChangedData = 1;
			}
			if(exists $images{$client->id}->{$testcase}->{'audio'}) {
				my $url;
				if(Slim::Music::Info::isURL($images{$client->id}->{$testcase}->{'audio'}->{$imageKey}->{'content'})) {
					$url = $images{$client->id}->{$testcase}->{'audio'}->{$imageKey}->{'content'};
				}else {
					$url = Slim::Utils::Misc::fileURLFromPath(catfile(_getImageDir($testcase),$images{$client->id}->{$testcase}->{'audio'}->{$imageKey}->{'content'}));
				}
				_playAudio($client,$url,$images{$client->id}->{$testcase}->{'id'}.' '.$client->string('TRACK').' '.$visibleImageKey);
				$showChangedData = 1;
			}
			if($showChangedData) {
				$client->showBriefly({
					'line'    => [ undef, $client->string("PLUGIN_ABTESTER_LOADING_DATA")." ".$visibleImageKey],
					'overlay' => [ undef, undef ],
				});
			}
		}
	}elsif($client->modeParam('modeName') =~ /.*ABCD$/) { 
		my $testcaseImages;
		if(exists $images{$client->id}->{$testcase}->{'image'}) {
			$testcaseImages = $images{$client->id}->{$testcase}->{'image'};
		}elsif(exists $images{$client->id}->{$testcase}->{'audio'}) {
			$testcaseImages = $images{$client->id}->{$testcase}->{'audio'};
		}elsif(exists $images{$client->id}->{$testcase}->{'perlfunction'}) {
			$testcaseImages = $images{$client->id}->{$testcase}->{'perlfunction'};
		}else {
			$testcaseImages = $images{$client->id}->{$testcase}->{'script'};
		}
		my @testcaseImageKeys = sort keys %$testcaseImages;

		if($number le scalar(@testcaseImageKeys)) {
			$log->debug("Executing button: $number");
			my $currentData = $client->modeParam('currentData');
			if(exists $images{$client->id}->{$testcase}->{'image'}) {
				if(loadImage($client,catfile(_getImageDir($testcase),$images{$client->id}->{$testcase}->{'image'}->{@testcaseImageKeys->[$number-1]}->{'content'}))) {
					$currentData->{'image'} = @testcaseImageKeys->[$number-1];
				}else {
					delete $currentData->{'image'};
				}
			}else {
				$currentData->{'image'} = @testcaseImageKeys->[$number-1];
			}

			if($client->modeParam('modeName') eq 'ABTester.QuestionAnswer.ABCD') {
				my $question = $client->modeParam('question');
				my $currentRating = undef;
				if(exists($currentData->{'result'}->{$currentData->{'image'}}->{$question})) {

					$currentRating = $currentData->{'result'}->{$currentData->{'image'}}->{$question};
					$client->modeParam('listIndex',5-$currentRating);
				}
				my $listRef = $client->modeParam('listRef');
				foreach my $rating (@$listRef) {
					if(defined($currentRating) && $rating->{'value'} eq $currentRating) {
						$rating->{'name'} = $rating->{'value'}.' *';
					}else {
						$rating->{'name'} = $rating->{'value'};
					}
				}
			}
			my $showChangedData = 0;
			if(exists $images{$client->id}->{$testcase}->{'perlfunction'}) {
				_executeFunction($client,$testcase,$images{$client->id}->{$testcase}->{'perlfunction'}->{@testcaseImageKeys->[$number-1]}->{'content'});
				$showChangedData = 1;
			}
			if(exists $images{$client->id}->{$testcase}->{'script'}) {
				_executeScript($client,$testcase,$images{$client->id}->{$testcase}->{'script'}->{@testcaseImageKeys->[$number-1]}->{'content'});
				$showChangedData = 1;
			}

			if(exists $images{$client->id}->{$testcase}->{'audio'}) {
				my $url;
				if(Slim::Music::Info::isURL($images{$client->id}->{$testcase}->{'audio'}->{@testcaseImageKeys->[$number-1]}->{'content'})) {
					$url = $images{$client->id}->{$testcase}->{'audio'}->{@testcaseImageKeys->[$number-1]}->{'content'};
				}else {
					$url = Slim::Utils::Misc::fileURLFromPath(catfile(_getImageDir($testcase),$images{$client->id}->{$testcase}->{'audio'}->{@testcaseImageKeys->[$number-1]}->{'content'}));
				}
				_playAudio($client,$url,$images{$client->id}->{$testcase}->{'id'}.' '.$client->string('TRACK').' '.@testcaseImageKeys->[$number-1]);
				$showChangedData = 1;
			}
			if($showChangedData) {
				$client->showBriefly({
					'line'    => [ undef, $client->string("PLUGIN_ABTESTER_LOADING_DATA")." ".@testcaseImageKeys->[$number-1]],
					'overlay' => [ undef, undef ],
				});
			}
		}
	}
}

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};

	if(!defined($prefs->get("restrictedtohardware"))) {
		$prefs->set("restrictedtohardware",1)
	}
	if(!defined($prefs->get("autoupdate"))) {
		$prefs->set("autoupdate",1)
	}

	my %choiceFunctions = %{Slim::Buttons::Input::Choice::getFunctions()};
	$choiceFunctions{'selectImage'} = \&selectImage;
	Slim::Buttons::Common::addMode('Slim::Plugin::ABTester::Plugin.selectImage',\%choiceFunctions,\&Slim::Buttons::Input::Choice::setMode);
	for my $buttonPressMode (qw{repeat hold hold_release single double}) {
		$choiceMapping{'play.' . $buttonPressMode} = 'dead';
		$choiceMapping{'add.' . $buttonPressMode} = 'dead';
		$choiceMapping{'search.' . $buttonPressMode} = 'passback';
		$choiceMapping{'stop.' . $buttonPressMode} = 'passback';
		$choiceMapping{'pause.' . $buttonPressMode} = 'passback';
	}
	Slim::Hardware::IR::addModeDefaultMapping('Slim::Plugin::ABTester::Plugin.selectImage',\%choiceMapping);
	Slim::Control::Request::subscribe(\&loadDefaultDACImage,[['client','reconnect']]);
}

sub exitPlugin {
	Slim::Control::Request::unsubscribe(\&loadDefaultDACImage);
}

sub getDisplayText {
	my ($client,$item) = @_;

	if(exists $images{$client->id}->{$item}) {
		return $images{$client->id}->{$item}->{'id'};
	}else {
		return string($item);
	}
}

sub loadDefaultDACImage {
	# These are the two passed parameters
	my $request=shift;
	my $client = $request->client();

	if(!$prefs->get("autoupdate")) {
		return;
	}
	if ( defined($client) && $request->isCommand([['client','reconnect']]) ) {
		if($client->model eq 'boom' || !$prefs->get("restrictedtohardware")) {
			my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
			for my $plugindir (@pluginDirs) {
				my $dir = catdir($plugindir,"ABTester","StandardImages");
				if(!$prefs->get("defaultimage")) {
					if(-e catfile($dir,'default.i2c')) {
						loadImage($client,catfile($dir,'default.i2c'));
						last;
					}
				}elsif(-e $prefs->get("defaultimage")) {
					loadImage($client,$prefs->get("defaultimage"));
					last;
				}elsif(-e catfile($dir,$prefs->get("defaultimage"))) {
					loadImage($client,catfile($dir,$prefs->get("defaultimage")));
					last;
				}
			}
		}
	}
}

sub setMode {
	my $class  = shift;
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# Read the configuration files
	_extractConfigurationFiles();
	$images{$client->id} = _readTestImages($client);

	my @listRef = ();
	my $currentImages = $images{$client->id};
	push @listRef, keys %$currentImages;

	push @listRef,'PLUGIN_ABTESTER_DELETE_AUDIO';
	if($client->model eq 'boom' || !$prefs->get("restrictedtohardware")) {
		push @listRef,'PLUGIN_ABTESTER_DEFAULT_IMAGES';
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header     => '{PLUGIN_ABTESTER} {count}',
		listRef    => \@listRef,
		overlayRef => sub {
			return [undef, $client->symbols('rightarrow')];
		},
		name       => \&getDisplayText,
		modeName   => 'ABTester',
		onPlay     => sub {
			my ($client, $item) = @_;
			$client->execute(["pause","0"]);
		},
		onRight    => sub {
			my ($client, $item) = @_;

			if($item eq 'PLUGIN_ABTESTER_DEFAULT_IMAGES') {
				setModeDefaultImages($client);
			}elsif($item eq 'PLUGIN_ABTESTER_DELETE_AUDIO') {
				$client->showBriefly({
					'line'    => [ undef, $client->string("PLUGIN_ABTESTER_DELETE_AUDIO_FILES") ],
					'overlay' => [ undef, undef ],
				});
				_deleteFiles($client);
			}else {
				my $testcase = $item;
				if($images{$client->id}->{$testcase}->{'type'} eq 'abx') {
					setModeABXTest($client,$testcase);
				}else {
					setModeABCDTest($client,$testcase);
				}
				disableScreenSaver($client);
			}
		},
	);
	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub setModeDefaultImages {
	my ($client) = @_;
	
	my @listRef = ();

	my %default = (
		'name' => $client->string('PLUGIN_ABTESTER_RESTORE_DEFAULT_IMAGE'),
		'value' => undef,
	);
	push @listRef, \%default;

	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		my $dir = catdir($plugindir,"ABTester","StandardImages");
		$log->debug("Checking for directory: $dir");
		next unless -d $dir;
		
		my @dircontents = Slim::Utils::Misc::readDirectory($dir,"i2c");
		my $extensionRegexp = "\\.i2c\$";

		# Iterate through all files in the specified directory
		for my $item (@dircontents) {
			next unless $item =~ /$extensionRegexp/;
			next if -d catdir($dir, $item);

			my $name = $item;
			$name =~ s/$extensionRegexp//;
			
			my %item = (
				'name' => $name,
				'value' => catfile($dir,$item),
			);
			push @listRef, \%item;
		}
	}
	
	# use INPUT.Choice to display the list of feeds
	my %params = (
		header     => '{PLUGIN_ABTESTER} {count}',
		listRef    => \@listRef,
		overlayRef => sub {
			return [undef, $client->symbols('rightarrow')];
		},
		name       => sub {
			my ($client, $item) = @_;
			return  $item->{'name'};
		},
		modeName   => 'ABTester.StandardImages',
		onPlay     => sub {
			my ($client, $item) = @_;
			$client->execute(["pause","0"]);
		},
		onRight    => sub {
			my ($client, $item) = @_;

			loadImage($client,$item->{'value'});
			if(!defined($item->{'value'})) {
				$client->showBriefly({
					'line'    => [ undef, $client->string("PLUGIN_ABTESTER_LOADING_DEFAULT_IMAGE") ],
					'overlay' => [ undef, undef ],
				});
			}
		},
	);
	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);
}

sub setModeABXTest {
	my ($client, $testcase) = @_;

	_executeInitCommands($client,$testcase);

	my $initialValue = 'A';
	my $startIndex = 0;

	my @listRef = ();
	if(exists $images{$client->id}->{$testcase}->{'instructions'}) {
		my %instruction = (
			'value' => 'instruction',
			'name' => ($images{$client->id}->{$testcase}->{'instructions'} || ''),
		);
		push @listRef,\%instruction;
		$initialValue = $instruction{'value'};
		$startIndex = 1;
	}

	my $testImages;
	if(exists $images{$client->id}->{$testcase}->{'image'}) {
		$testImages = $images{$client->id}->{$testcase}->{'image'};
	}elsif(exists $images{$client->id}->{$testcase}->{'audio'}) {
		$testImages = $images{$client->id}->{$testcase}->{'audio'};
	}elsif(exists $images{$client->id}->{$testcase}->{'perlfunction'}) {
		$testImages = $images{$client->id}->{$testcase}->{'perlfunction'};
	}else {
		$testImages = $images{$client->id}->{$testcase}->{'script'};
	}

	foreach my $img (qw(A B)) {
		if(exists($testImages->{$img})) {
			my %data = (
				'value' => $img,
				'name' => $client->string("PLUGIN_ABTESTER_LOAD_DATA").' '.$img,
			);
			if(exists $images{$client->id}->{$testcase}->{'image'}) {
				$data{'image'} = $images{$client->id}->{$testcase}->{'image'}->{$img}->{'content'};
			}
			if(exists $images{$client->id}->{$testcase}->{'audio'}) {
				$data{'audio'} = $images{$client->id}->{$testcase}->{'audio'}->{$img}->{'content'};
			}
			if(exists $images{$client->id}->{$testcase}->{'perlfunction'}) {
				$data{'perlfunction'} = $images{$client->id}->{$testcase}->{'perlfunction'}->{$img}->{'content'};
			}
			if(exists $images{$client->id}->{$testcase}->{'script'}) {
				$data{'script'} = $images{$client->id}->{$testcase}->{'script'}->{$img}->{'content'};
			}
			push @listRef,\%data;
		}else {
			$log->error("Can't find '.$img.' image for ABX test of $testcase");
			$client->bumpRight();
			return;
		}
	}
	my $imageXPos = floor(rand(2))+$startIndex;
	my %dataX = (
		'value' => 'X',
		'realId' => @listRef->[$imageXPos]->{'value'},
		'name' => $client->string('PLUGIN_ABTESTER_LOAD_DATA').' X',
	);
	if(exists(@listRef->[$imageXPos]->{'image'})) {
		$dataX{'image'} = @listRef->[$imageXPos]->{'image'};
	}
	if(exists(@listRef->[$imageXPos]->{'audio'})) {
		$dataX{'audio'} = @listRef->[$imageXPos]->{'audio'};
	}
	if(exists(@listRef->[$imageXPos]->{'perlfunction'})) {
		$dataX{'perlfunction'} = @listRef->[$imageXPos]->{'perlfunction'};
	}
	if(exists(@listRef->[$imageXPos]->{'script'})) {
		$dataX{'script'} = @listRef->[$imageXPos]->{'script'};
	}
	push @listRef,\%dataX;

	foreach my $img (qw(A B)) {
		my %dataPublish = (
			'value' => 'publish'.$img,
			'realId' => @listRef->[$imageXPos]->{'value'},
			'name' => 'Publish X='.$img,
		);
		push @listRef,\%dataPublish;
	}
	my %dataCheck = (
		'value' => 'checkanswer',
		'realId' => @listRef->[$imageXPos]->{'value'},
		'name' => $client->string("PLUGIN_ABTESTER_CHECK_ANSWER"),
	);
	push @listRef,\%dataCheck;

	my %currentData = ();
	# use INPUT.Choice to display the list of feeds
	my %params = (
		header     => 
			sub {
				my $client = shift;
				my $item = shift;
				return getHeaderText($client,$item);
			},
		testcase   => $testcase,
		currentData => \%currentData,
		initialValue => $initialValue,
		listRef    => \@listRef,
		overlayRef => sub {
			my ($client, $item) = @_;
			if($item->{'value'} eq 'instruction') {
				return [undef, undef];
			}else {
				return [undef, $client->symbols('rightarrow')];
			}
		},
		modeName   => 'ABTester.ABX',
		onPlay     => sub {
			my ($client, $item) = @_;
			$client->execute(["pause","0"]);
		},
		onRight    => sub {
			my ($client, $item) = @_;

			if($item->{'value'} =~ /^publish(.*)$/) {
				my $selected = $1;
				$client->showBriefly({
					'line'    => [ undef, $client->string("PLUGIN_ABTESTER_PUBLISH_RESULT") ],
					'overlay' => [ undef, undef ],
				});
				my %result = (
					'selected' => $selected,
					'real' => $item->{'realId'},
				);
				publishResult($client,$testcase,\%result);
				Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 1,\&Slim::Buttons::Common::popModeRight);
			}elsif($item->{'value'} eq 'instruction') {
				$client->bumpRight();
			}elsif($item->{'value'} eq "checkanswer") {
				my $listRef = $client->modeParam('listRef');
				if(scalar(@$listRef)>5) {
					splice(@$listRef,$startIndex+3,2);
					$client->modeParam('listIndex',$client->modeParam('listIndex')-2);
				}
				$client->showBriefly({
					'line'    => [ undef, "X=".$item->{'realId'} ],
					'overlay' => [ undef, undef ],
				});
			}else {
				my $currentData = $client->modeParam('currentData');
				if(exists $item->{'image'}) {
					if(loadImage($client,catfile(_getImageDir($testcase),$item->{'image'}))) {
						$currentData->{'image'} = $item->{'value'};
					}else {
						delete $currentData->{'image'};
					}
				}else {
					$currentData->{'image'} = $item->{'value'};
				}
				my $showChangedData = 0;
				if(exists $item->{'perlfunction'}) {
					_executeFunction($client,$testcase,$item->{'perlfunction'});
					$showChangedData = 1;
				}
				if(exists $item->{'script'}) {
					_executeScript($client,$testcase,$item->{'script'});
					$showChangedData = 1;
				}
				if(exists $item->{'audio'}) {
					my $url;
					if(Slim::Music::Info::isURL($item->{'audio'})) {
						$url = $item->{'audio'};
					}else {
						$url = Slim::Utils::Misc::fileURLFromPath(catfile(_getImageDir($testcase),$item->{'audio'}));
					}
					_playAudio($client,$url,$images{$client->id}->{$testcase}->{'id'}.' '.$client->string('TRACK').' '.$item->{'value'});
					$showChangedData = 1;
				}
				if($showChangedData) {
					$client->showBriefly({
						'line'    => [ undef, $client->string("PLUGIN_ABTESTER_LOADING_DATA")." ".$item->{'value'} ],
						'overlay' => [ undef, undef ],
					});
				}
			}
		},
	);
	Slim::Buttons::Common::pushModeLeft($client, 'Slim::Plugin::ABTester::Plugin.selectImage', \%params);
}

sub setModeABCDTest {
	my ($client, $testcase) = @_;

	_executeInitCommands($client,$testcase);

	my @listRef = ();
	my $initialValue = undef;
	if(exists $images{$client->id}->{$testcase}->{'instructions'}) {
		my %instruction = (
			'value' => 'instruction',
			'name' => ($images{$client->id}->{$testcase}->{'instructions'} || ''),
		);
		push @listRef,\%instruction;
		$initialValue = $instruction{'value'};
	}

	my $testImages;
	if(exists $images{$client->id}->{$testcase}->{'image'}) {
		$testImages = $images{$client->id}->{$testcase}->{'image'};
	}elsif(exists $images{$client->id}->{$testcase}->{'audio'}) {
		$testImages = $images{$client->id}->{$testcase}->{'audio'};
	}elsif(exists $images{$client->id}->{$testcase}->{'perlfunction'}) {
		$testImages = $images{$client->id}->{$testcase}->{'perlfunction'};
	}else {
		$testImages = $images{$client->id}->{$testcase}->{'script'};
	}

	foreach my $img (sort keys %$testImages) {
		if(!defined($initialValue)) {
			$initialValue = $img;
		}
		if(exists($testImages->{$img})) {
			my %data = (
				'value' => $img,
				'name' => $client->string('PLUGIN_ABTESTER_LOAD_DATA').' '.$img,
			);
			if(exists $images{$client->id}->{$testcase}->{'image'}) {
				$data{'image'} = $images{$client->id}->{$testcase}->{'image'}->{$img}->{'content'};
			}
			if(exists $images{$client->id}->{$testcase}->{'audio'}) {
				$data{'audio'} = $images{$client->id}->{$testcase}->{'audio'}->{$img}->{'content'};
			}
			if(exists $images{$client->id}->{$testcase}->{'perlfunction'}) {
				$data{'perlfunction'} = $images{$client->id}->{$testcase}->{'perlfunction'}->{$img}->{'content'};
			}
			if(exists $images{$client->id}->{$testcase}->{'script'}) {
				$data{'script'} = $images{$client->id}->{$testcase}->{'script'}->{$img}->{'content'};
			}
			push @listRef,\%data;
		}else {
			$log->error("Can't find '.$img.' image for ABCD test of $testcase");
			$client->bumpRight();
			return;
		}
	}

	my @questions = ();
	my $testQuestions = $images{$client->id}->{$testcase}->{'question'};
	foreach my $question (keys %$testQuestions) {
		my %dataQuestion = (
			'value' => 'question'.$question,
			'name' => $testQuestions->{$question}->{'content'},
		);
		push @questions,\%dataQuestion;
	}

	my %dataResult = (
		'value' => 'question',
		'name' => $client->string("PLUGIN_ABTESTER_TEST_RESULT"),
	);
	push @listRef,\%dataResult;

	my %dataPublish = (
		'value' => 'publish',
		'name' => $client->string("PLUGIN_ABTESTER_PUBLISH"),
	);
	push @listRef,\%dataPublish;

	my %result = ();

	my %empty = ();
	my %currentData = (
		'result' => \%empty,
	);
	# use INPUT.Choice to display the list of feeds
	my %params = (
		header     => 
			sub {
				my $client = shift;
				my $item = shift;
				return getHeaderText($client,$item);
			},
		listRef    => \@listRef,
		overlayRef => sub {
			my ($client, $item) = @_;
			if($item->{'value'} eq 'instruction') {
				return [undef, undef];
			}else {
				return [undef, $client->symbols('rightarrow')];
			}
		},
		modeName   => 'ABTester.ABCD',
		testcase   => $testcase,
		currentData => \%currentData,
		initialValue => $initialValue,
		onPlay     => sub {
			my ($client, $item) = @_;
			$client->execute(["pause","0"]);
		},
		onRight    => sub {
			my ($client, $item) = @_;

			if($item->{'value'} =~ /^publish$/) {
				my $result = $client->modeParam('currentData')->{'result'};
				my $completeResult = 1;
				foreach my $img (sort keys %$testImages) {
					my $testQuestions = $images{$client->id}->{$testcase}->{'question'};
					foreach my $question (keys %$testQuestions) {
						if(!defined($result->{$img}->{$question})) {
							$completeResult = 0;
						}
					}
				}
				if($completeResult) {
					$client->showBriefly({
						'line'    => [ undef, $client->string("PLUGIN_ABTESTER_PUBLISH_RESULT") ],
						'overlay' => [ undef, undef ],
					});
					publishResult($client,$testcase,$result);
					Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 1,\&Slim::Buttons::Common::popModeRight);
				}else {
					$client->showBriefly({
						'line'    => [ undef, $client->string("PLUGIN_ABTESTER_TEST_RESULT_MISSING") ],
						'overlay' => [ undef, undef ],
					});
				}
			}elsif($item->{'value'} eq 'instruction') {
				$client->bumpRight();
			}elsif($item->{'value'} =~ /^question(.*)$/) {
				if(defined($client->modeParam('currentData')->{'image'})) {
					setModeQuestions($client,$testcase,$client->modeParam('currentData'));
				}else {
					$client->showBriefly({
						'line'    => [ undef, $client->string("PLUGIN_ABTESTER_SELECT_DATA_FIRST") ],
						'overlay' => [ undef, undef ],
					});
				}
			}else {
				my $currentData = $client->modeParam('currentData');
				if(exists $item->{'image'}) {
					if(loadImage($client,catfile(_getImageDir($testcase),$item->{'image'}))) {
						$currentData->{'image'} = $item->{'value'};
					}else {
						delete $currentData->{'image'};
					}
				}else {
					$currentData->{'image'} = $item->{'value'};
				}
				my $showChangedData = 0;
				if(exists $item->{'perlfunction'}) {
					_executeFunction($client,$testcase,$item->{'perlfunction'});
					$showChangedData = 1;
				}
				if(exists $item->{'script'}) {
					_executeScript($client,$testcase,$item->{'script'});
					$showChangedData = 1;
				}
				if(exists $item->{'audio'}) {
					my $url;
					if(Slim::Music::Info::isURL($item->{'audio'})) {
						$url = $item->{'audio'};
					}else {
						$url = Slim::Utils::Misc::fileURLFromPath(catfile(_getImageDir($testcase),$item->{'audio'}));
					}
					_playAudio($client,$url,$images{$client->id}->{$testcase}->{'id'}.' '.$client->string('TRACK').' '.$item->{'value'});
					$showChangedData = 1;
				}
				if($showChangedData) {
					$client->showBriefly({
						'line'    => [ undef, $client->string("PLUGIN_ABTESTER_LOADING_DATA")." ".$item->{'value'} ],
						'overlay' => [ undef, undef ],
					});
				}
			}
		},
	);
	Slim::Buttons::Common::pushModeLeft($client, 'Slim::Plugin::ABTester::Plugin.selectImage', \%params);
}

sub setModeQuestions {
	my ($client, $testcase, $currentData) = @_;

	my @listRef = ();
	my $testQuestions = $images{$client->id}->{$testcase}->{'question'};
	my $initialValue = undef;
	foreach my $question (sort keys %$testQuestions) {
		if(!defined($initialValue)) {
			$initialValue = $question;
		}
		my %dataQuestion = (
			'value' => $question,
			'name' => $testQuestions->{$question}->{'content'},
		);
		push @listRef,\%dataQuestion;
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header     => 
			sub {
				my $client = shift;
				my $item = shift;
				return getHeaderText($client,$item);
			},
		listRef    => \@listRef,
		overlayRef => sub {
			return [undef, $client->symbols('rightarrow')];
		},
		modeName   => 'ABTester.Questions.ABCD',
		testcase   => $testcase,
		currentData => $currentData,
		initialValue => $initialValue,
		onPlay     => sub {
			my ($client, $item) = @_;
			$client->execute(["pause","0"]);
		},
		onRight    => sub {
			my ($client, $item) = @_;

			setModeRequestQuestionAnswer($client,$testcase,$item->{'value'},$client->modeParam('currentData'));
		},
	);
	Slim::Buttons::Common::pushModeLeft($client, 'Slim::Plugin::ABTester::Plugin.selectImage', \%params);
}

sub setModeRequestQuestionAnswer {
	my ($client, $testcase, $question, $currentData) = @_;

	my $listIndex = 0;
	my $currentRating = undef;
	my @listRef = ();
	foreach my $rating (qw(5 4 3 2 1)) {
		my %ratingItem = (
			'value' => $rating,
			'name' => $rating,
		);
		if(exists($currentData->{'result'}->{$currentData->{'image'}}->{$question}) && $currentData->{'result'}->{$currentData->{'image'}}->{$question} eq $rating) {
			$ratingItem{'name'} .= ' *';
			$currentRating = $ratingItem{'value'};
			$listIndex = 5-$ratingItem{'value'};
		}
		push @listRef,\%ratingItem;
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header     => 
			sub {
				my $client = shift;
				my $item = shift;
				return getHeaderText($client,$item);
			},
		listRef    => \@listRef,
		initialValue => $currentRating,
		overlayRef => sub {
			return [undef, $client->symbols('rightarrow')];
		},
		modeName   => 'ABTester.QuestionAnswer.ABCD',
		testcase   => $testcase,
		currentData => $currentData,
		question => $question,
		onPlay     => sub {
			my ($client, $item) = @_;
			$client->execute(["pause","0"]);
		},
		onRight    => sub {
			my ($client, $item) = @_;

			my $currentData = $client->modeParam('currentData');
			$currentData->{'result'}->{$currentData->{'image'}}->{$question} = $item->{'value'};
			foreach my $rating (@listRef) {
				if($rating eq $item) {
					$rating->{'name'} = $rating->{'value'}.' *';
				}else {
					$rating->{'name'} = $rating->{'value'};
				}
			}
			$client->update();
		},
	);

	Slim::Buttons::Common::pushModeLeft($client, 'Slim::Plugin::ABTester::Plugin.selectImage', \%params);
}

sub getHeaderText {
	my $client = shift;
	my $item = shift;

	my $currentData = $client->modeParam('currentData');
	if(defined($currentData->{'image'})) {
		return uc($images{$client->id}->{$client->modeParam('testcase')}->{'id'}).' {PLUGIN_ABTESTER_DATA} '.$currentData->{'image'}.' {count}';
	}else {
		return uc($images{$client->id}->{$client->modeParam('testcase')}->{'id'}).' {PLUGIN_ABTESTER_NONE} {count}';
	}
}

sub _executeInitCommands {
	my $client = shift;
	my $testcase = shift;

	if(exists $images{$client->id}->{$testcase}->{'init'}) {
		my $initCommands = $images{$client->id}->{$testcase}->{'init'};
		foreach my $key (sort keys %$initCommands) {
			my $cmd = $initCommands->{$key};
			if($cmd->{'type'} eq 'cli') {
				my $execString = $cmd->{'content'};
				my $playername = $client->name;
				$execString =~ s/\$PLAYERNAME/$playername/;
				my @cmdParts = split(/ /,$execString);
				if(scalar(@cmdParts)>0) {
					$log->debug("Executing CLI: $execString");
					$client->execute(\@cmdParts);
				}else {
					$log->error("Empty CLI command found, not executing");
				}
			}else {
				$log->error("Unknown command type found, not executing");
			}
		}
	}
}
sub _deleteFiles {
	my $client = shift;

	my $currentImages = $images{$client->id};
	foreach my $testcase (keys %$currentImages) {
		if(exists $images{$client->id}->{$testcase}->{'audio'}) {
			my $audioHash = $images{$client->id}->{$testcase}->{'audio'};
			foreach my $key (keys %$audioHash) {
				my $url;
				if(Slim::Music::Info::isURL($audioHash->{$key}->{'content'})) {
					$url = $audioHash->{$key}->{'content'};
				}else {
					$url = Slim::Utils::Misc::fileURLFromPath(catfile(_getImageDir($testcase),$audioHash->{$key}->{'content'}));
				}
				my $track = Slim::Schema->resultset('Track')->single({ 'url' => $url });
				if(defined($track)) {
					$log->info("Removing ".$track->title.": ".$track->url." from database");
					$client->execute(["playlist","deleteitem",$track]);
					$track->delete;
				}
			}
		}
	}
}
sub _playAudio {
	my $client = shift;
	my $url = shift;
	my $fileId = shift;
	my %attributeHash = %{Slim::Formats->readTags($url)};
	my @removeAttributes =('ALBUMSORT',
				'ARTISTSORT',
				'TITLESORT',
				'ARTIST',
				'COMPOSER',
				'BAND',
				'CONDUCTOR',
				'SET',
				'ALBUMARTIST',
				'TRACKARTIST',
				'COMPILATION',
				'PIC',
				'YEAR',
				'ALBUM',
				'GENRE',
				'COMMENT',
				'TRACKNUM',
			);
	foreach my $attr (@removeAttributes) {
		delete $attributeHash{$attr};
	}
	$attributeHash{'TITLE'} = $fileId;
	$attributeHash{'TRACKNUM'} = 1;
	my $track = Slim::Schema->updateOrCreate({
		'url' => $url,
		'readTags' => 0,
		'checkMTime' => 0,
		'attributes' => \%attributeHash,
	});
	my @tracks = ();
	push @tracks,$track;
	$client->execute(['playlist','loadtracks','listRef',\@tracks]);
}

sub _getImageDir {
	my $testcase = shift;

	# Iterate through all files in plugin image directories
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		my $dir = catdir($plugindir,"ABTester","Images",$testcase);
		return $dir if -d $dir;
	}
	
	my $imageDir = $serverPrefs->get('cachedir');
	$imageDir = catdir($imageDir,'ABTesterImages');
	$imageDir = catdir($imageDir,$testcase);
	return $imageDir;
}

sub loadImage {
	my ($client, $image) = @_;
	
	if(defined($image)) {
		$log->warn("Loading ".$image);
		return $client->upgradeDAC($image);
	}else {
		$log->warn("Loading default image");
		$client->sendBDACFrame("DACDEFAULT");
		return 1;
	}
}

sub _executeScript {
	my ($client, $testcase, $script) = @_;

	my $playername = $client->name;
	$script =~ s/\$PLAYERNAME/$playername/;
	
	my $testdir = _getImageDir($testcase);
	$script =~ s/\$TESTDIR/$testdir/;

	$log->debug("Executing: $script");
	my $result = system($script);
	if($result) {
		$result = $result / 256;
		$log->error("Error ($result) when executing script: $script");
	}
	return $result;
}

sub _executeFunction {
	my ($client, $testcase, $script) = @_;

	my $playername = $client->name;
	$script =~ s/\$PLAYERNAME/$playername/;
	
	my $testdir = _getImageDir($testcase);
	$script =~ s/\$TESTDIR/$testdir/;

	my @args = split(/ /,$script);
	
	my $found = 0;
	foreach my $dir (@INC) {
		if($dir eq $testdir) {
			$found = 1;
			last;
		}
	}
	if(!$found) {
		push @INC,$testdir;
	}

	my $function = shift @args;

	my $package = $function;
	if($package =~ /^(.*)::([^:]+)$/) {
		no strict 'refs';
		$package = $1;
		my $func = $2;
		$log->debug("Loading: $package");
		eval "use $package";
		if(UNIVERSAL::can($package,$func)) {
			$log->debug("Calling: \"$function\"");
			eval {&{$function}(@args)};
			if ($@) {
				$log->error("Failed to call function:$@");
			}
		}else {
			$log->error("Can't find function: \"$function\"");
		}
		eval "no $package";
		use strict 'refs';
	}
	my $i = 0;
	foreach my $dir (@INC) {
		if($dir eq $testdir) {
			splice(@INC,$i,1);
			last;
		}
		$i++;
	}
	return 0;
}

sub disableScreenSaver {
	my $client = shift;
	Slim::Hardware::IR::setLastIRTime($client, Time::HiRes::time());
	if($client->modeParam('modeName') =~ /ABTester.*/) {
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 4,\&disableScreenSaver);
	}
}

sub publishResult {
	my ($client, $testcase, $result) = @_;

	$log->warn("Publish result for testcase ".$images{$client->id}->{$testcase}->{'id'}.": ".Dumper($result));
}

sub _extractConfigurationFiles {
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	my $cacheDir = $serverPrefs->get('cachedir');
	$cacheDir = catdir($cacheDir,'ABTesterImages');
	if(-d $cacheDir) {
		$log->debug("Deleting dir: ".$cacheDir."\n");
		rmtree($cacheDir) or do {
			$log->error("Unable to delete directory: $cacheDir");
		};
	}
	mkdir($cacheDir);

	for my $plugindir (@pluginDirs) {
		my $dir = catdir($plugindir,"ABTester","Images");
		$log->debug("Checking for directory: $dir");
		next unless -d $dir;
		
		my @dircontents = Slim::Utils::Misc::readDirectory($dir,"zip");
		my $extensionRegexp = "\\.zip\$";

		# Iterate through all files in the specified directory
		for my $item (@dircontents) {
			next unless $item =~ /$extensionRegexp/;
			next if -d catdir($dir, $item);

			my $file = catfile($dir, $item);
			my $zip = Archive::Zip->new();
			unless ( $zip->read( $file ) == AZ_OK ) {
				$log->error("Unable to read zip file: $item");
				next;
			}
			my $itemDir = $item;
			$itemDir =~ s/$extensionRegexp//;
			my $extractDir = catdir($cacheDir,$itemDir);
			if(-d $extractDir) {
				$log->debug("Deleting dir: ".$extractDir."\n");
				rmtree($extractDir) or do {
					$log->error("Unable to delete directory: $extractDir");
				};
			}
			mkdir($extractDir);
			$log->debug("Extracting $item to $extractDir");
			$zip->extractTree(undef,$extractDir."/");
		}
	}
}

sub _readTestImages {
	my $client = shift;
	my %images = ();

	# Iterate through all files in plugin image directories
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		my $dir = catdir($plugindir,"ABTester","Images");
		next unless -d $dir;

		my @imageDirs = Slim::Utils::Misc::readDirectory($dir);
		for my $imageDir (@imageDirs) {
			next unless -d catdir($dir, $imageDir);

			_readTestFiles($client,$dir,$imageDir,\%images);
		}
	}
	
	my $cacheDir = $serverPrefs->get('cachedir');
	my $cacheDir = catdir($cacheDir,'ABTesterImages');

	return \%images unless -d $cacheDir;

	my @imageDirs = Slim::Utils::Misc::readDirectory($cacheDir);
	# Iterate through all files in the specified directory
	for my $imageDir (@imageDirs) {
		next unless -d catdir($cacheDir, $imageDir);
		next if exists $images{$imageDir};
		_readTestFiles($client,$cacheDir,$imageDir,\%images);
	}
	return \%images;
}

sub _readTestFiles {
	my $client = shift;
	my $cacheDir = shift;
	my $imageDir = shift;
	my $images = shift;

	my $specFile = catfile(catdir($cacheDir,$imageDir),"test.xml");
	if(! -f $specFile) {
		$log->error("No test.xml file found for image $imageDir");
		return;
	}
	my $content = eval { read_file($specFile) };
	if ( $content ) {
	       	$log->debug("Parsing file: $specFile\n");
		my $xml = eval { XMLin($content,forcearray => ["question","image","script","init"]) };
		if ($@) {
			$log->error("Failed to parse configuration ($imageDir) because:\n$@\n");
			return;
		}
		if(!exists($xml->{'id'})) {
			$xml->{'id'} = $imageDir;
		}
		if(!exists($xml->{'type'})) {
			$log->error("Failed to parse configuration ($imageDir) because: 'type' not defined");
			return;
		}
		if(!exists($xml->{'image'}) && !exists($xml->{'audio'}) && !exists($xml->{'script'}) && !exists($xml->{'perlfunction'})) {
			$log->error("Failed to parse configuration ($imageDir) because: No 'image' or 'audio' or 'script' or 'perlfunction' elements defined");
			return;
		}
		if(exists($xml->{'image'}))  {
			my $imageElements = $xml->{'image'};
			if(scalar(keys %$imageElements) lt 2) {
				$log->error("Failed to parse configuration ($imageDir) because: At least two 'image' elements is required");
				return;
			}
		}elsif(exists($xml->{'audio'})) {
			my $audioElements = $xml->{'audio'};
			if(scalar(keys %$audioElements) lt 2) {
				$log->error("Failed to parse configuration ($imageDir) because: At least two 'audio' elements is required");
				return;
			}
		}elsif(exists($xml->{'perlfunction'})) {
			my $functionElements = $xml->{'perlfunction'};
			if(scalar(keys %$functionElements) lt 2) {
				$log->error("Failed to parse configuration ($imageDir) because: At least two 'perlfunction' elements is required");
				return;
			}
		}else {
			my $scriptElements = $xml->{'script'};
			if(scalar(keys %$scriptElements) lt 2) {
				$log->error("Failed to parse configuration ($imageDir) because: At least two 'script' elements is required");
				return;
			}
		}
		if($xml->{'type'} eq 'abcd' && !exists($xml->{'question'})) {
			$log->error("Failed to parse configuration ($imageDir) because: No 'question' elements defined");
			return;
		}

		if(exists $xml->{'requiredplugins'} && !_isPluginsInstalled($client,$xml->{'requiredplugins'})) {
			$log->info("Testcase \"".$xml->{'id'}."\" not available, needs plugins: ".$xml->{'requiredplugins'});
			return;
		}
		if($prefs->get("restrictedtohardware")) {
			if(exists $xml->{'requiredmodels'} && !_isPlayerModels($client,$xml->{'requiredmodels'})) {
				$log->info("Testcase \"".$xml->{'id'}."\" not available, needs player model: ".$xml->{'requiredmodels'});
				return;
			}
			if(exists $xml->{'minfirmware'} && !$client->revision >= $xml->{'minfirmware'}) {
				$log->info("Testcase \"".$xml->{'id'}."\" not available, needs at least firmware: ".$xml->{'minfirmware'});
				return;
			}
			if(exists $xml->{'maxfirmware'} && !$client->revision >= $xml->{'maxfirmware'}) {
				$log->info("Testcase \"".$xml->{'id'}."\" not available, only works with firmware equal or before: ".$xml->{'maxfirmware'});
				return;
			}
		}
		if(exists $xml->{'requiredos'} && !_isOperatingSystem($client,$xml->{'requiredos'})) {
			$log->info("Testcase \"".$xml->{'id'}."\" not available, needs operating system: ".$xml->{'requiredos'});
			return;
		}
		$images->{$imageDir} = $xml;
	}
}

sub _isPluginsInstalled {
	my $client = shift;
	my $pluginList = shift;
	my $enabledPlugin = 1;
	foreach my $plugin (split /,/, $pluginList) {
		if($enabledPlugin) {
			$enabledPlugin = grep(/$plugin/, Slim::Utils::PluginManager->enabledPlugins($client));
		}
	}
	return $enabledPlugin;
}

sub _isOperatingSystem {
	my $client = shift;
	my $osList = shift;
	foreach my $os (split /,/, $osList) {
		if($os eq Slim::Utils::OSDetect::OS()) {
			return 1;
		}
	}
	$log->debug("Not allowed, os is: ".Slim::Utils::OSDetect::OS());
	return 0;
}

sub _isPlayerModels {
	my $client = shift;
	my $modelList = shift;
	foreach my $model (split /,/, $modelList) {
		if($model eq $client->model) {
			return 1;
		}
	}
	$log->debug("Not allowed, model is: ".$client->model);
	return 0;
}

1;

__END__
