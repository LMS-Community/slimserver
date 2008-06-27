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
use POSIX qw(floor strftime);
use Slim::Utils::Log;
use Slim::Plugin::ABTester::Settings;

our $PLUGINVERSION =  undef;

my $prefs = preferences('plugin.abtester');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.abtester',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_ABTESTER',
});
my %testcases;
my %recordedData;

# This mapping must be a copy of the INPUT.Choice mapping with the addition of the association of the selectImage function
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

# Mode function to handle the shortcut buttons when the users uses number buttons during the execution of a test case
sub selectImage {
	my $client = shift;
	my $button = shift;
	my $number = shift;
			
	$log->debug("Handling button: $number");

	# Check if a test case is active and in that case execute the "Load data" menu associated with the button
	my $testcase = $client->modeParam('testcase');
	if($client->modeParam('modeName') =~ /.*ABX$/) {
		if($number le '3') {
			$log->debug("Executing button: $number");

			# Find all available test case data entries
			my $testData;
			if(exists $testcases{$client->id}->{$testcase}->{'image'}) {
				$testData = $testcases{$client->id}->{$testcase}->{'image'};
			}elsif(exists $testcases{$client->id}->{$testcase}->{'commands'}) {
				$testData = $testcases{$client->id}->{$testcase}->{'commands'};
			}elsif(exists $testcases{$client->id}->{$testcase}->{'audio'}) {
				$testData = $testcases{$client->id}->{$testcase}->{'audio'};
			}elsif(exists $testcases{$client->id}->{$testcase}->{'perlfunction'}) {
				$testData = $testcases{$client->id}->{$testcase}->{'perlfunction'};
			}else {
				$testData = $testcases{$client->id}->{$testcase}->{'script'};
			}
			my @testcaseDataKeys = sort keys %$testData;
	
			# Find the test case data entry associated with the button
			my $testdataKey = 'X';
			if($number le '2') {
				$testdataKey = @testcaseDataKeys->[$number-1];
			}
	
			# Find the test case data text that should be shown to the user
			# We don't want to show the real value behind X if the 3 button is used
			my $visibleTestdataKey = $testdataKey;
			if($testdataKey eq 'X') {
				my $listRef = $client->modeParam('listRef');
				if($listRef->[0]->{'value'} eq 'instruction') {
					$testdataKey=$listRef->[3]->{'realId'};
				}else {
					$testdataKey=$listRef->[2]->{'realId'};
				}
			}

			# Load the image if there is a image associated with the selected test data entry
			my $currentData = $client->modeParam('currentData');
			if(exists $testcases{$client->id}->{$testcase}->{'image'}) {
				if(loadImage($client,catfile(_getImageDir($testcase),$testcases{$client->id}->{$testcase}->{'image'}->{$testdataKey}->{'content'}))) {
					$currentData->{'image'} = $visibleTestdataKey;
				}else {
					delete $currentData->{'image'};
				}
			}else {
				$currentData->{'image'} = $visibleTestdataKey;
			}
			
			# Execute additional actions associated with the selected test data entry
			my $showChangedData = 0;
			if(exists $testcases{$client->id}->{$testcase}->{'commands'}) {
				_executeCommands($client,$testcase,$testcases{$client->id}->{$testcase}->{'commands'}->{$testdataKey}->{'command'});
				$showChangedData = 1;
			}
			if(exists $testcases{$client->id}->{$testcase}->{'perlfunction'}) {
				_executeFunction($client,$testcase,$testcases{$client->id}->{$testcase}->{'perlfunction'}->{$testdataKey}->{'content'});
				$showChangedData = 1;
			}
			if(exists $testcases{$client->id}->{$testcase}->{'script'}) {
				_executeScript($client,$testcase,$testcases{$client->id}->{$testcase}->{'script'}->{$testdataKey}->{'content'});
				$showChangedData = 1;
			}
			if(exists $testcases{$client->id}->{$testcase}->{'audio'}) {
				my $url;
				if(Slim::Music::Info::isURL($testcases{$client->id}->{$testcase}->{'audio'}->{$testdataKey}->{'content'})) {
					$url = $testcases{$client->id}->{$testcase}->{'audio'}->{$testdataKey}->{'content'};
				}else {
					$url = Slim::Utils::Misc::fileURLFromPath(catfile(_getImageDir($testcase),$testcases{$client->id}->{$testcase}->{'audio'}->{$testdataKey}->{'content'}));
				}
				_playAudio($client,$url,$testcases{$client->id}->{$testcase}->{'id'}.' '.$client->string('TRACK').' '.$visibleTestdataKey);
				$showChangedData = 1;
			}
			if($showChangedData) {
				$client->showBriefly({
					'line'    => [ undef, $client->string("PLUGIN_ABTESTER_LOADING_DATA")." ".$visibleTestdataKey],
					'overlay' => [ undef, undef ],
				});
			}
		}
	}elsif($client->modeParam('modeName') =~ /.*ABCD$/) { 

		# Find all available test case data entries
		my $testData;
		if(exists $testcases{$client->id}->{$testcase}->{'image'}) {
			$testData = $testcases{$client->id}->{$testcase}->{'image'};
		}elsif(exists $testcases{$client->id}->{$testcase}->{'commands'}) {
			$testData = $testcases{$client->id}->{$testcase}->{'commands'};
		}elsif(exists $testcases{$client->id}->{$testcase}->{'audio'}) {
			$testData = $testcases{$client->id}->{$testcase}->{'audio'};
		}elsif(exists $testcases{$client->id}->{$testcase}->{'perlfunction'}) {
			$testData = $testcases{$client->id}->{$testcase}->{'perlfunction'};
		}else {
			$testData = $testcases{$client->id}->{$testcase}->{'script'};
		}
		my @testcaseDataKeys = sort keys %$testData;

		# Ignore buttons above the number of available test case data entries
		if($number le scalar(@testcaseDataKeys)) {
			$log->debug("Executing button: $number");
			# Load the image if there is a image associated with the selected test data entry
			my $currentData = $client->modeParam('currentData');
			if(exists $testcases{$client->id}->{$testcase}->{'image'}) {
				if(loadImage($client,catfile(_getImageDir($testcase),$testcases{$client->id}->{$testcase}->{'image'}->{@testcaseDataKeys->[$number-1]}->{'content'}))) {
					$currentData->{'image'} = @testcaseDataKeys->[$number-1];
				}else {
					delete $currentData->{'image'};
				}
			}else {
				$currentData->{'image'} = @testcaseDataKeys->[$number-1];
			}

			# If the user stands in one of the "Test result" menus, change the * marking to the rating previously selected for the specified question
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

			# Execute additional actions associated with the selected test data entry
			my $showChangedData = 0;
			if(exists $testcases{$client->id}->{$testcase}->{'commands'}) {
				_executeCommands($client,$testcase,$testcases{$client->id}->{$testcase}->{'commands'}->{@testcaseDataKeys->[$number-1]}->{'command'});
				$showChangedData = 1;
			}
			if(exists $testcases{$client->id}->{$testcase}->{'perlfunction'}) {
				_executeFunction($client,$testcase,$testcases{$client->id}->{$testcase}->{'perlfunction'}->{@testcaseDataKeys->[$number-1]}->{'content'});
				$showChangedData = 1;
			}
			if(exists $testcases{$client->id}->{$testcase}->{'script'}) {
				_executeScript($client,$testcase,$testcases{$client->id}->{$testcase}->{'script'}->{@testcaseDataKeys->[$number-1]}->{'content'});
				$showChangedData = 1;
			}

			if(exists $testcases{$client->id}->{$testcase}->{'audio'}) {
				my $url;
				if(Slim::Music::Info::isURL($testcases{$client->id}->{$testcase}->{'audio'}->{@testcaseDataKeys->[$number-1]}->{'content'})) {
					$url = $testcases{$client->id}->{$testcase}->{'audio'}->{@testcaseDataKeys->[$number-1]}->{'content'};
				}else {
					$url = Slim::Utils::Misc::fileURLFromPath(catfile(_getImageDir($testcase),$testcases{$client->id}->{$testcase}->{'audio'}->{@testcaseDataKeys->[$number-1]}->{'content'}));
				}
				_playAudio($client,$url,$testcases{$client->id}->{$testcase}->{'id'}.' '.$client->string('TRACK').' '.@testcaseDataKeys->[$number-1]);
				$showChangedData = 1;
			}
			if($showChangedData) {
				$client->showBriefly({
					'line'    => [ undef, $client->string("PLUGIN_ABTESTER_LOADING_DATA")." ".@testcaseDataKeys->[$number-1]],
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
	Slim::Plugin::ABTester::Settings->new($class);

	# Set default values of plugin settings
	if(!defined($prefs->get("restrictedtohardware"))) {
		$prefs->set("restrictedtohardware",1)
	}
	if(!defined($prefs->get("autoupdate"))) {
		$prefs->set("autoupdate",1)
	}

	# Register a custom mode which is based on the INPUT.Choice mode but adds a selectImage function
	# This is required to make it possible to use the number buttons as shortcuts to load different data in the test cases
	my %choiceFunctions = %{Slim::Buttons::Input::Choice::getFunctions()};
	$choiceFunctions{'selectImage'} = \&selectImage;
	Slim::Buttons::Common::addMode('Slim::Plugin::ABTester::Plugin.recordTestcase',$class->getFunctions(),\&setModeRecordTestcase);
	Slim::Buttons::Common::addMode('Slim::Plugin::ABTester::Plugin.selectImage',\%choiceFunctions,\&Slim::Buttons::Input::Choice::setMode);
	for my $buttonPressMode (qw{repeat hold hold_release single double}) {
		$choiceMapping{'play.' . $buttonPressMode} = 'dead';
		$choiceMapping{'add.' . $buttonPressMode} = 'dead';
		$choiceMapping{'search.' . $buttonPressMode} = 'passback';
		$choiceMapping{'stop.' . $buttonPressMode} = 'passback';
		$choiceMapping{'pause.' . $buttonPressMode} = 'passback';
	}
	Slim::Hardware::IR::addModeDefaultMapping('Slim::Plugin::ABTester::Plugin.selectImage',\%choiceMapping);

	# Subscribe to event to automatically load DSP images when player reconnects
	Slim::Control::Request::subscribe(\&loadDefaultDSPImage,[['client','reconnect']]);
	Slim::Control::Request::subscribe(\&recordBoomDacCommands,[['boomdac']]);

	# Add CLI commands
	Slim::Control::Request::addDispatch(['abtester','images'], [0, 1, 0, \&cliListImages]);
	Slim::Control::Request::addDispatch(['abtester','image','_image'], [1, 0, 0, \&cliLoadImage]);
}

sub recordBoomDacCommands {
	my $request = shift;
	my $client = $request->client();

	my $mode = $client->modeParam('modeName');

	if ($request->isCommand([['boomdac']]) && $mode =~ /^ABTester\.Recording\.(.*)$/) {
		my $recordingKey = $1;

		my $data = $request->getParam('_command');
		$log->debug("Recording $recordingKey: boomdac ".URI::Escape::uri_escape($data,'\x00-\xff'));
		
		my @empty = ();
		my $current = $recordedData{$client->id}->{$recordingKey} || \@empty;
		push @$current,"boomdac ".URI::Escape::uri_escape($data,'\x00-\xff');
	}
	return;
}

sub exitPlugin {
	Slim::Control::Request::unsubscribe(\&loadDefaultDSPImage);
	Slim::Control::Request::unsubscribe(\&recordBoomDacCommands);
}

sub getDisplayText {
	my ($client,$item) = @_;

	if(exists $testcases{$client->id}->{$item}) {
		return $testcases{$client->id}->{$item}->{'id'};
	}else {
		return string($item);
	}
}

# Function to automatically load DSP image at player reconnect
sub loadDefaultDSPImage {
	my $request=shift;
	my $client = $request->client();

	# Exit if automatic update of DSP image has been disabled
	if(!$prefs->get("autoupdate")) {
		return;
	}

	# Verify that this is a Boom player that is reconnecting and find and load the bundled default image
	if ( defined($client) && $request->isCommand([['client','reconnect']]) ) {
		if($client->model eq 'boom' || !$prefs->get("restrictedtohardware")) {

			# Search for default DSP image bundled with plugin
			my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
			for my $plugindir (@pluginDirs) {
				my $dir = catdir($plugindir,"ABTester","StandardImages");
				
				# Use default.i2c unless the user has specified another default image file
				if(!$prefs->get("defaultimage")) {
					if(-e catfile($dir,'default.i2c')) {
						loadImage($client,catfile($dir,'default.i2c'));
						last;
					}else {
						loadImage($client);
						last;
					}

				# A default image file has been specified with full path
				}elsif(-e $prefs->get("defaultimage")) {
					loadImage($client,$prefs->get("defaultimage"));
					last;

				# A default image file has been specified without path, load it from the StandardImages directory
				}elsif(-e catfile($dir,$prefs->get("defaultimage"))) {
					loadImage($client,catfile($dir,$prefs->get("defaultimage")));
					last;
				}else {
					loadImage($client);
					last;
				}
			}
		}
	}
}

# Function to re-read the testcases after a new test case has been extracted, 
# this is for example used when a test case has been downloaded from internet
# or when the user enters the ABTester plugin menu
sub refreshTestdata {
	my $client = shift;
	$testcases{$client->id} = _readTestcases($client);
}

# Mode to record boomdac commands
sub setModeRecordTestcase {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	$recordedData{$client->id} = ();

	my $dirname = "rec_".strftime("%Y%m%d_%H%M%S", localtime(time()));

	my @listRef = ();
	foreach my $dataKey (qw(A B)) {
		my %dataEntry = (
			'value' => $dataKey,
			'name' => $client->string('PLUGIN_ABTESTER_RECORD_DATA')." ".$dataKey,
		);
		push @listRef,\%dataEntry;
	}
	my %saveEntry = (
		'value' => 'save',
		'name' => $client->string('PLUGIN_ABTESTER_RECORD_SAVE'),
	);
	push @listRef,\%saveEntry;
	
	my %params = (
		header     => '{PLUGIN_ABTESTER} {count}',
		listRef    => \@listRef,
		name       => sub {
			my ($client, $item) = @_;
			return  $item->{'name'};
		},
		overlayRef => sub {
			return [undef, $client->symbols('rightarrow')];
		},
		modeName   => 'ABTester.RecordTestcase',
		onPlay     => sub {
			my ($client, $item) = @_;
			$client->execute(["pause","0"]);
		},
		onRight    => sub {
			my ($client, $item) = @_;
			
			if($item->{'value'} eq 'save') {
				# Saving recorded data
				my $datas = $recordedData{$client->id};

				# We need both A and B data to make a working test case
				if(scalar(keys %$datas)<2) {
					$client->showBriefly({
						'line'    => [ undef, $client->string("PLUGIN_ABTESTER_RECORD_SAVING_NOT_ENOUGH_DATA") ],
						'overlay' => [ undef, undef ],
					});
					return;
				}

				# Create test case directory
				my $cacheDir = $serverPrefs->get('cachedir');
				$cacheDir = catdir($cacheDir,'ABTester','Recorded');
				mkdir($cacheDir) unless -d catdir($cacheDir);
				$cacheDir = catdir($cacheDir,$dirname);				
				mkdir($cacheDir);

				# Generate test case text and save the test case
				$log->debug("Saving: ".Dumper($recordedData{$client->id}));
				my $file = catfile($cacheDir,"test.xml");
				my $fh;
				open($fh,"> $file") or do {
					$log->error("Unable to save to: ".$file);
					$client->showBriefly({
						'line'    => [ undef, $client->string("PLUGIN_ABTESTER_RECORD_SAVING_FAILED") ],
						'overlay' => [ undef, undef ],
					});
					return;
				};
				print $fh "<test type=\"abx\">\n";
				print $fh "\t<requiredmodels>boom</requiredmodels>\n";
				print $fh "\t<minfirmware>7</minfirmware>\n";
				foreach my $key (keys %$datas) {
					my $commands = $datas->{$key};
					if(defined($commands) && scalar(@$commands)>0) {
						print $fh "\t<commands id=\"$key\">\n";
						my $i=1;
						foreach my $command (@$commands) {
							print $fh "\t\t<command id=\"$i\" type=\"cli\">$command</command>\n";
							$i++;
						}
						print $fh "\t</commands>\n";
					}else {
						$client->showBriefly({
							'line'    => [ undef, $client->string("PLUGIN_ABTESTER_RECORD_SAVING_NOT_ENOUGH_DATA") ],
							'overlay' => [ undef, undef ],
						});
						return;
					}
				}
				print $fh "</test>";
				close $fh;
				$log->warn("Saved recorded testcase as: ".catfile($cacheDir,"test.xml"));
				refreshTestdata($client);

				$client->showBriefly({
					'line'    => [ $client->string("PLUGIN_ABTESTER_RECORD_SAVING"), $dirname ],
					'overlay' => [ undef, undef ],
				},
				{
					'duration' => 3,
				});
			}else {
				# Initiate recording mode
				my @recording = ($client->string('PLUGIN_ABTESTER_RECORDING')." ".$item->{'value'}."...");
				my @empty = ();
				$recordedData{$client->id}->{$item->{'value'}} = \@empty;
				my %params = (
					header     => '{PLUGIN_ABTESTER} {count}',
					listRef    => \@recording,
					modeName   => 'ABTester.Recording.'.$item->{'value'},
					onPlay     => sub {
						my ($client, $item) = @_;
						$client->execute(["pause","0"]);
					},
				);
				Slim::Buttons::Common::pushModeLeft($client,'INPUT.Choice',\%params);
			}
		}
	);

	Slim::Buttons::Common::pushModeLeft($client,'INPUT.Choice',\%params);
	disableScreenSaver($client);
}

# Mode to represent the main ABTester plugin menu
sub setMode {
	my $class  = shift;
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# Read the configuration files
	_extractTestcaseAndImageFiles();
	refreshTestdata($client);
	
	my @listRef = ();

	# Prepare top level menu entries under the plugin menu
	if($client->model eq 'boom' || !$prefs->get("restrictedtohardware")) {
		push @listRef,'PLUGIN_ABTESTER_IMAGES';
	}
	push @listRef,'PLUGIN_ABTESTER_TESTCASES';
	push @listRef,'PLUGIN_ABTESTER_FROM_INTERNET';
	push @listRef,'PLUGIN_ABTESTER_DELETE_TEST_FILES';
	if($client->model eq 'boom' || !$prefs->get("restrictedtohardware")) {
		push @listRef,'PLUGIN_ABTESTER_RECORD';
	}

	# Prepare mode parameters and move player into the new mode
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

			if($item eq 'PLUGIN_ABTESTER_IMAGES') {
				# Show "Images" menu
				setModeDefaultImages($client);
			}elsif($item eq 'PLUGIN_ABTESTER_DELETE_TEST_FILES') {
				# Clean up after test cases
				$client->showBriefly({
					'line'    => [ undef, $client->string("PLUGIN_ABTESTER_DELETING_TEST_FILES") ],
					'overlay' => [ undef, undef ],
				});
				_deleteFiles($client);
			}elsif($item eq 'PLUGIN_ABTESTER_RECORD') {
				Slim::Buttons::Common::pushModeLeft($client, 'Slim::Plugin::ABTester::Plugin.recordTestcase');
			}elsif($item eq 'PLUGIN_ABTESTER_FROM_INTERNET') {
				# Show "From Internet" menu
				setModeFromInternet($client);
			}elsif($item eq 'PLUGIN_ABTESTER_TESTCASES') {
				# Create a sub menu for each test case in the "Test cases" menu and let the user select one to run
				my @testCases = ();
				my $currentTestcases = $testcases{$client->id};
				push @testCases, sort keys %$currentTestcases;
				my %params = (
					header     => '{PLUGIN_ABTESTER} {count}',
					listRef    => \@testCases,
					overlayRef => sub {
						return [undef, $client->symbols('rightarrow')];
					},
					modeName   => 'ABTester.Testcases',
					onPlay     => sub {
						my ($client, $item) = @_;
						$client->execute(["pause","0"]);
					},
					onRight    => sub {
						my ($client, $item) = @_;
						runTestcase($client,$item);
					},
				);
				Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);
			}
		},
	);
	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

# Function that executes a testcase
sub runTestcase {
	my $client = shift;
	my $testcase = shift;

	if($testcases{$client->id}->{$testcase}->{'type'} eq 'abx') {
		setModeABXTest($client,$testcase);
	}else {
		setModeABCDTest($client,$testcase);
	}
	# Disable screen saver during the time the test case is run
	disableScreenSaver($client);
}

# Mode that represents the "ABTester/From Internet" menu
sub setModeFromInternet {
	my ($client) = @_;

	# Add sub menus under "From Internet" menu
	my @listRef = ();
	push @listRef,'PLUGIN_ABTESTER_TESTCASES';
	if($client->model eq 'boom' || !$prefs->get("restrictedtohardware")) {
		push @listRef,'PLUGIN_ABTESTER_IMAGES';
	}

	# Prepare mode parameters and move player into the new mode
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
			if($item eq 'PLUGIN_ABTESTER_TESTCASES') {
				# Use Slim::Buttons::XMLBrowser based mode for the "From Internet/Test cases" menu
				# TODO: Verify the url below when Logitech has put up the opml files
				my %params = (
					url => 'http://eng.slimdevices.com/abtester/testcases.opml',
					title => $client->string($item),
					expires => 10,
					parser => "Slim::Plugin::ABTester::TestcaseZipParser",
				);
				Slim::Buttons::Common::pushMode($client,'xmlbrowser',\%params);
			}elsif($item eq 'PLUGIN_ABTESTER_IMAGES') {
				# Use Slim::Buttons::XMLBrowser based mode for the "From Internet/Images" menu
				# TODO: Verify the url below when Logitech has put up the opml files
				my %params = (
					url => 'http://eng.slimdevices.com/abtester/images.opml',
					title => $client->string($item),
					expires => 10,
					parser => "Slim::Plugin::ABTester::ImageZipParser",
				);
				Slim::Buttons::Common::pushMode($client,'xmlbrowser',\%params);
			}
		},
	);
	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);

}

# Retreive available images as array
sub _getAvailableImages {
	my @availableImages = ();

	# Add all images bundled with the plugin as directories to the "Images" menu
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		my $dir = catdir($plugindir,"ABTester","StandardImages");
		$log->debug("Checking for directory: $dir");
		next unless -d $dir;
		
		_readImageDir($dir,\@availableImages);
	}

	# Add all images extracted to the "Images" menu 
	# (this can be both extracted .zip files bundled with plugin and downloaded from internet)
	my $cacheDir = $serverPrefs->get('cachedir');
	$cacheDir = catdir($cacheDir,'ABTester','Images');
	return unless -d $cacheDir;
	if(-d $cacheDir) {
		_readImageDir($cacheDir,\@availableImages);
	}
	return \@availableImages;
}

# Mode that represents the "ABTester/Images" menu
sub setModeDefaultImages {
	my ($client) = @_;
	
	my @listRef = ();

	# Add the "From Firmware" entry to the "Images" menu
	my %default = (
		'name' => $client->string('PLUGIN_ABTESTER_RESTORE_DEFAULT_IMAGE'),
		'value' => 0,
	);
	push @listRef, \%default;
	
	my $availableImages = _getAvailableImages();
	if(scalar(@$availableImages)>0) {
		push @listRef, @$availableImages;
	}

	# Prepare mode parameters and move player into the new mode
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

sub _readImageDir {
	my $dir = shift;
	my $result = shift;

	opendir(DIR, $dir) || do {
                $log->error("opendir on [$dir] failed: $!");
		return;
        };

	my $extensionRegexp = "\\.i2c\$";

	# Find all *.i2c files in the specified directory and the sub directories one level down
	for my $item (readdir(DIR)) {

		# Enter sub directories that doesn't start with a .
		if(-d catdir($dir, $item) && $item !~ /^\./) {
			my @subdircontents = Slim::Utils::Misc::readDirectory(catdir($dir,$item),"i2c");

			# Find all .i2c files in the sub directory and add them to the result
			for my $subitem (@subdircontents) {
				next unless $subitem =~ /$extensionRegexp/;
				next if -d catdir($dir, $item, $subitem);
				my %item = (
					'name' => $item,
					'value' => catfile($dir,$item,$subitem),
				);
				push @$result, \%item;
			}

		# If this is a .i2c file, add it to the result
		}else {
			next unless $item =~ /$extensionRegexp/;
			next if -d catdir($dir, $item);
			my $name = $item;
			$name =~ s/$extensionRegexp//;
			my %item = (
				'name' => $name,
				'value' => catfile($dir,$item),
			);
			push @$result, \%item;
		}
	}
	closedir(DIR);
}

# Mode that represents the menu shown when a ABX test case is selected
sub setModeABXTest {
	my ($client, $testcase) = @_;

	# Execute the init elements in the test case to prepare the player for the test case
	_executeInitCommands($client,$testcase);

	my $initialValue = 'A';
	my $startIndex = 0;

	# Add optional "instructions" element to the test case menu
	my @listRef = ();
	if(exists $testcases{$client->id}->{$testcase}->{'instructions'}) {
		my %instruction = (
			'value' => 'instruction',
			'name' => ($testcases{$client->id}->{$testcase}->{'instructions'} || ''),
		);
		push @listRef,\%instruction;
		$initialValue = $instruction{'value'};
		$startIndex = 1;
	}

	# Create a test data structure that contains the available data entries which the user should be able to select to load
	my $testData;
	if(exists $testcases{$client->id}->{$testcase}->{'image'}) {
		$testData = $testcases{$client->id}->{$testcase}->{'image'};
	}elsif(exists $testcases{$client->id}->{$testcase}->{'commands'}) {
		$testData = $testcases{$client->id}->{$testcase}->{'commands'};
	}elsif(exists $testcases{$client->id}->{$testcase}->{'audio'}) {
		$testData = $testcases{$client->id}->{$testcase}->{'audio'};
	}elsif(exists $testcases{$client->id}->{$testcase}->{'perlfunction'}) {
		$testData = $testcases{$client->id}->{$testcase}->{'perlfunction'};
	}else {
		$testData = $testcases{$client->id}->{$testcase}->{'script'};
	}

	# Add the "Load data A/B" menus to the test case menu
	foreach my $data (qw(A B)) {
		if(exists($testData->{$data})) {
			my %data = (
				'value' => $data,
				'name' => $client->string("PLUGIN_ABTESTER_LOAD_DATA").' '.$data,
			);
			if(exists $testcases{$client->id}->{$testcase}->{'image'}) {
				$data{'image'} = $testcases{$client->id}->{$testcase}->{'image'}->{$data}->{'content'};
			}
			if(exists $testcases{$client->id}->{$testcase}->{'commands'}) {
				$data{'commands'} = $testcases{$client->id}->{$testcase}->{'commands'}->{$data}->{'command'};
			}
			if(exists $testcases{$client->id}->{$testcase}->{'audio'}) {
				$data{'audio'} = $testcases{$client->id}->{$testcase}->{'audio'}->{$data}->{'content'};
			}
			if(exists $testcases{$client->id}->{$testcase}->{'perlfunction'}) {
				$data{'perlfunction'} = $testcases{$client->id}->{$testcase}->{'perlfunction'}->{$data}->{'content'};
			}
			if(exists $testcases{$client->id}->{$testcase}->{'script'}) {
				$data{'script'} = $testcases{$client->id}->{$testcase}->{'script'}->{$data}->{'content'};
			}
			push @listRef,\%data;
		}else {
			$log->error("Can't find '.$data.' image for ABX test of $testcase");
			$client->bumpRight();
			return;
		}
	}

	# Add the "Load data X" menu to the test case menu
	my $imageXPos = floor(rand(2))+$startIndex;
	my %dataX = (
		'value' => 'X',
		'realId' => @listRef->[$imageXPos]->{'value'},
		'name' => $client->string('PLUGIN_ABTESTER_LOAD_DATA').' X',
	);
	if(exists(@listRef->[$imageXPos]->{'image'})) {
		$dataX{'image'} = @listRef->[$imageXPos]->{'image'};
	}
	if(exists(@listRef->[$imageXPos]->{'commands'})) {
		$dataX{'commands'} = @listRef->[$imageXPos]->{'commands'};
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

	# Add the "Publish ..." menus to the test case menu
	foreach my $data (qw(A B)) {
		my %dataPublish = (
			'value' => 'publish'.$data,
			'realId' => @listRef->[$imageXPos]->{'value'},
			'name' => 'Publish X='.$data,
		);
		push @listRef,\%dataPublish;
	}
	
	# Add a "Check Answer" menu to the test case menu
	my %dataCheck = (
		'value' => 'checkanswer',
		'realId' => @listRef->[$imageXPos]->{'value'},
		'name' => $client->string("PLUGIN_ABTESTER_CHECK_ANSWER"),
	);
	push @listRef,\%dataCheck;

	# The test result will be stored in this hash when the user navigates around between the menus inside the test case
	my %currentData = ();

	# Prepare mode parameters and move player into the new mode
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
				if(exists $item->{'commands'}) {
					_executeCommands($client,$testcase,$item->{'commands'});
					$showChangedData = 1;
				}
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
					_playAudio($client,$url,$testcases{$client->id}->{$testcase}->{'id'}.' '.$client->string('TRACK').' '.$item->{'value'});
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

# Mode that represents the menu shown when a ABCD test case is selected
sub setModeABCDTest {
	my ($client, $testcase) = @_;

	# Execute the init elements in the test case to prepare the player for the test case
	_executeInitCommands($client,$testcase);

	my @listRef = ();

	# Add optional "instructions" element to the test case menu
	my $initialValue = undef;
	if(exists $testcases{$client->id}->{$testcase}->{'instructions'}) {
		my %instruction = (
			'value' => 'instruction',
			'name' => ($testcases{$client->id}->{$testcase}->{'instructions'} || ''),
		);
		push @listRef,\%instruction;
		$initialValue = $instruction{'value'};
	}

	# Create a test data structure that contains the available data entries which the user should be able to select to load
	my $testData;
	if(exists $testcases{$client->id}->{$testcase}->{'image'}) {
		$testData = $testcases{$client->id}->{$testcase}->{'image'};
	}elsif(exists $testcases{$client->id}->{$testcase}->{'commands'}) {
		$testData = $testcases{$client->id}->{$testcase}->{'commands'};
	}elsif(exists $testcases{$client->id}->{$testcase}->{'audio'}) {
		$testData = $testcases{$client->id}->{$testcase}->{'audio'};
	}elsif(exists $testcases{$client->id}->{$testcase}->{'perlfunction'}) {
		$testData = $testcases{$client->id}->{$testcase}->{'perlfunction'};
	}else {
		$testData = $testcases{$client->id}->{$testcase}->{'script'};
	}

	# Add all the Load menus that should be available in the test case menu
	foreach my $data (sort keys %$testData) {
		if(!defined($initialValue)) {
			$initialValue = $data;
		}
		if(exists($testData->{$data})) {
			my %data = (
				'value' => $data,
				'name' => $client->string('PLUGIN_ABTESTER_LOAD_DATA').' '.$data,
			);
			if(exists $testcases{$client->id}->{$testcase}->{'image'}) {
				$data{'image'} = $testcases{$client->id}->{$testcase}->{'image'}->{$data}->{'content'};
			}
			if(exists $testcases{$client->id}->{$testcase}->{'commands'}) {
				$data{'commands'} = $testcases{$client->id}->{$testcase}->{'commands'}->{$data}->{'command'};
			}
			if(exists $testcases{$client->id}->{$testcase}->{'audio'}) {
				$data{'audio'} = $testcases{$client->id}->{$testcase}->{'audio'}->{$data}->{'content'};
			}
			if(exists $testcases{$client->id}->{$testcase}->{'perlfunction'}) {
				$data{'perlfunction'} = $testcases{$client->id}->{$testcase}->{'perlfunction'}->{$data}->{'content'};
			}
			if(exists $testcases{$client->id}->{$testcase}->{'script'}) {
				$data{'script'} = $testcases{$client->id}->{$testcase}->{'script'}->{$data}->{'content'};
			}
			push @listRef,\%data;
		}else {
			$log->error("Can't find '.$data.' image for ABCD test of $testcase");
			$client->bumpRight();
			return;
		}
	}

	# Add the "Test result" menu to the test case menu
	my %dataResult = (
		'value' => 'question',
		'name' => $client->string("PLUGIN_ABTESTER_TEST_RESULT"),
	);
	push @listRef,\%dataResult;

	# Add the "Publish" menu to the test case menu
	my %dataPublish = (
		'value' => 'publish',
		'name' => $client->string("PLUGIN_ABTESTER_PUBLISH"),
	);
	push @listRef,\%dataPublish;

	my %result = ();

	# The test result will be stored in this hash when the user navigates around between the menus inside the test case
	my %empty = ();
	my %currentData = (
		'result' => \%empty,
	);

	# Prepare mode parameters and move player into the new mode
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
				foreach my $data (sort keys %$testData) {
					my $testQuestions = $testcases{$client->id}->{$testcase}->{'question'};
					foreach my $question (keys %$testQuestions) {
						if(!defined($result->{$data}->{$question})) {
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
				if(exists $item->{'commands'}) {
					_executeCommands($client,$testcase,$item->{'commands'});
					$showChangedData = 1;
				}
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
					_playAudio($client,$url,$testcases{$client->id}->{$testcase}->{'id'}.' '.$client->string('TRACK').' '.$item->{'value'});
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

# Mode that represents the menu shown when the "Test result" menu is selected within a ABCD test case
sub setModeQuestions {
	my ($client, $testcase, $currentData) = @_;

	my @listRef = ();

	# Prepare the questions for a ABCD test case, all question elements in the test case should be shown
	my $testQuestions = $testcases{$client->id}->{$testcase}->{'question'};
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

	# Prepare mode parameters and move player into the new mode
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

# Mode that represents the menu shown when a specific question is selected within the "Test result" menu in a ABCD test case
sub setModeRequestQuestionAnswer {
	my ($client, $testcase, $question, $currentData) = @_;

	my $listIndex = 0;
	my $currentRating = undef;
	my @listRef = ();

	# Prepare question answers, it should be possible to select a rating number
	foreach my $rating (qw(5 4 3 2 1)) {
		my %ratingItem = (
			'value' => $rating,
			'name' => $rating,
		);
		# Mark the currently selected rating if the user has answered the question already
		if(exists($currentData->{'result'}->{$currentData->{'image'}}->{$question}) && $currentData->{'result'}->{$currentData->{'image'}}->{$question} eq $rating) {
			$ratingItem{'name'} .= ' *';
			$currentRating = $ratingItem{'value'};
			$listIndex = 5-$ratingItem{'value'};
		}
		push @listRef,\%ratingItem;
	}

	# Prepare mode parameters and move player into the new mode
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
		return uc($testcases{$client->id}->{$client->modeParam('testcase')}->{'id'}).' {PLUGIN_ABTESTER_DATA} '.$currentData->{'image'}.' {count}';
	}else {
		return uc($testcases{$client->id}->{$client->modeParam('testcase')}->{'id'}).' {PLUGIN_ABTESTER_NONE} {count}';
	}
}

sub _executeInitCommands {
	my $client = shift;
	my $testcase = shift;

	# Iterate through all specified init element in the test case
	if(exists $testcases{$client->id}->{$testcase}->{'init'}) {
		my $initCommands = $testcases{$client->id}->{$testcase}->{'init'};
		foreach my $key (sort keys %$initCommands) {
			my $cmd = $initCommands->{$key};
			_executeCommand($client,$testcase,$cmd);
		}
	}
}

sub _executeCommand {
	my ($client, $testcase, $cmd) = @_;

	if($cmd->{'type'} eq 'cli') {
		my $execString = $cmd->{'content'};

		# Replace special keywords in the CLI command
		$execString = _replaceKeywords($execString,$client,$testcase);

		# Call the CLI Command
		my @cmdParts = split(/ /,$execString);
		if(scalar(@cmdParts)>0) {
			my @executeCmds = ();
			foreach my $part (@cmdParts) {
				push @executeCmds,URI::Escape::uri_unescape($part);
			}
			$log->debug("Executing CLI: $execString");
			$client->execute(\@executeCmds);
		}else {
			$log->error("Empty CLI command found, not executing");
		}
	}else {
		$log->error("Unknown command type found, not executing");
	}
}

sub _deleteFiles {
	my $client = shift;

	# Remove any test audio files from the SqueezeCenter database
	my $currentTestcases = $testcases{$client->id};
	foreach my $testcase (keys %$currentTestcases) {
		if(exists $testcases{$client->id}->{$testcase}->{'audio'}) {
			my $audioHash = $testcases{$client->id}->{$testcase}->{'audio'};
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

	# Remove any downloaded test cases
	my $downloadDir = $serverPrefs->get('cachedir');
	$downloadDir = catdir($downloadDir,'ABTester','Downloaded');
	if(-d $downloadDir) {
		$log->debug("Deleting directory $downloadDir");
		rmtree($downloadDir) or do {
			$log->error("Unable to delete directory: $downloadDir");
		};
	}

	# Remove any recorded test cases
	my $downloadDir = $serverPrefs->get('cachedir');
	$downloadDir = catdir($downloadDir,'ABTester','Recorded');
	if(-d $downloadDir) {
		$log->debug("Deleting directory $downloadDir");
		rmtree($downloadDir) or do {
			$log->error("Unable to delete directory: $downloadDir");
		};
	}
	refreshTestdata($client);
}
sub _playAudio {
	my $client = shift;
	my $url = shift;
	my $fileId = shift;
	my %attributeHash = %{Slim::Formats->readTags($url)};

	# Remove scanned tags which we don't want to show to the user
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

	# Add the track to the SqueezeCenter database
	my $track = Slim::Schema->updateOrCreate({
		'url' => $url,
		'readTags' => 0,
		'checkMTime' => 0,
		'attributes' => \%attributeHash,
	});

	# Start to play the track
	my @tracks = ();
	push @tracks,$track;
	$client->execute(['playlist','loadtracks','listRef',\@tracks]);
}

sub _getImageDir {
	my $testcase = shift;

	# Return test case from the Images directory under the plugin, if it exist
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		my $dir = catdir($plugindir,"ABTester","Testcases",$testcase);
		return $dir if -d $dir;
		$dir = catdir($plugindir,"ABTester","Images",$testcase);
		return $dir if -d $dir;
	}
	
	# Return test case from the extracted zip files
	my $imageDir = $serverPrefs->get('cachedir');
	$imageDir = catdir($imageDir,'ABTester','Testcases',$testcase);
	return $imageDir;
}

sub loadImage {
	my ($client, $image) = @_;
	
	if($client->model eq 'boom') {
		if($image) {
			$log->info("Loading ".$image);
			return $client->upgradeDAC($image);
		}else {
			$log->info("Loading default image");
			$client->sendBDACFrame("DACDEFAULT");
			return 1;
		}

	# If we aren't using a Boom, we just need to log what a Boom would be doing to simplify testing
	}elsif($image) {
		$log->info("Simulate loading of $image");
	}else {
		$log->info("Simulate loading of default image");
	}
	return 1;
}

sub _replaceKeywords {
	my $script = shift;
	my $client = shift;
	my $testcase = shift;

	my $playername = $client->name;
	$script =~ s/\$PLAYERNAME/$playername/;
	
	my $testdir = _getImageDir($testcase);
	$script =~ s/\$TESTDIR/$testdir/;

	return $script;
}

sub _executeScript {
	my ($client, $testcase, $script) = @_;

	# Replace special keywords in the script script command
	$script = _replaceKeywords($script,$client,$testcase);

	# Execute the script as a system call
	$log->debug("Executing: $script");
	my $result = system($script);
	if($result) {
		$result = $result / 256;
		$log->error("Error ($result) when executing script: $script");
	}
	return $result;
}

sub _executeCommands {
	my ($client, $testcase, $commands) = @_;

	foreach my $key (sort keys %$commands) {
		my $cmd = $commands->{$key};
		_executeCommand($client,$testcase,$cmd);
	}
}

sub _executeFunction {
	my ($client, $testcase, $script) = @_;

	# Replace special keywords in the script function parameters
	$script = _replaceKeywords($script,$client,$testcase);

	my @args = split(/ /,$script);
	
	# Add the test case directory temporarily to @INC so the perl modules can be found
	my $testdir = _getImageDir($testcase);
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

	# Load the module, make the function call and unload the module
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

	# Remove the test case directory from @INC to avoid side effects later on
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

# Disable the screen saver as long as the player is in a ABTester mode
sub disableScreenSaver {
	my $client = shift;

	# Disable screen saver by changing the last IR time every 4'th second to the current time
	Slim::Hardware::IR::setLastIRTime($client, Time::HiRes::time());
	if($client->modeParam('modeName') =~ /ABTester.*/) {
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 4,\&disableScreenSaver);
	}
}

sub publishResult {
	my ($client, $testcase, $result) = @_;

	# TODO: Write publishing code to publish the test result to Logitech provided php scripts when they are available
	$log->warn("Publish result for testcase ".$testcases{$client->id}->{$testcase}->{'id'}.": ".Dumper($result));
}

sub _extractTestcaseAndImageFiles {
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	my $cacheDir = $serverPrefs->get('cachedir');
	$cacheDir = catdir($cacheDir,'ABTester');
	mkdir($cacheDir);

	# Remove previously extracted test cases
	if(-d catdir($cacheDir,'Testcases')) {
		$log->debug("Deleting dir: ".catdir($cacheDir,'Testcases')."\n");
		rmtree(catdir($cacheDir,'Testcases')) or do {
			$log->error("Unable to delete directory: ".catdir($cacheDir,'Testcases'));
		};
	}
	mkdir(catdir($cacheDir,'Testcases'));

	# Remove previously extracted images
	if(-d catdir($cacheDir,'Images')) {
		$log->debug("Deleting dir: ".catdir($cacheDir,'Images')."\n");
		rmtree(catdir($cacheDir,'Images')) or do {
			$log->error("Unable to delete directory: ".catdir($cacheDir,'Images'));
		};
	}
	mkdir(catdir($cacheDir,'Images'));

	# Extract test cases bundled with the plugin
	for my $plugindir (@pluginDirs) {
		my $dir = catdir($plugindir,"ABTester","Testcases");
		$log->debug("Checking for directory: $dir");
		if(! -d $dir) {
			$dir = catdir($plugindir,"ABTester","Images");
			$log->debug("Checking for directory: $dir");
			next unless -d $dir;
		}
		
		_extractZipFiles($dir,catdir($cacheDir,'Testcases'));
	}

	my $downloadDir = catdir($cacheDir,'Downloaded');
	return unless -d $downloadDir;

	# Extract test cases downloaded from internet
	my $dir = catdir($downloadDir,'Testcases');
	if(-d $dir) {
		_extractZipFiles($dir,catdir($cacheDir,'Testcases'));
	}

	# Extract images downloaded from internet
	my $dir = catdir($downloadDir,'Images');
	if(-d $dir) {
		_extractZipFiles($dir,catdir($cacheDir,'Images'));
	}
}

sub _extractZipFiles {
	my $dir = shift;
	my $cacheDir = shift;

	my @dircontents = Slim::Utils::Misc::readDirectory($dir,"zip");

	# Extract all zip files in the specified directory
	for my $item (@dircontents) {
		next unless $item =~ /\.zip$/;
		next if -d catdir($dir, $item);

		extractZipFile($dir,$item,$cacheDir);
	}

}
sub extractZipFile {
	my $dir = shift;
	my $file = shift;
	my $cacheDir = shift;

	my $extensionRegexp = "\\.zip\$";

	my $filepath = catfile($dir,$file);

	my $zip = Archive::Zip->new();
	unless ( $zip->read( $filepath ) == AZ_OK ) {
		$log->error("Unable to read zip file: $filepath");
		return;
	}
	my $itemDir = $file;
	$itemDir =~ s/$extensionRegexp//;
	my $extractDir = catdir($cacheDir,$itemDir);
	if(-d $extractDir) {
		$log->debug("Deleting dir: ".$extractDir."\n");
		rmtree($extractDir) or do {
			$log->error("Unable to delete directory: $extractDir");
		};
	}
	mkdir($extractDir);
	$log->debug("Extracting $file to $extractDir");
	$zip->extractTree(undef,$extractDir."/");
}

sub _readTestcases {
	my $client = shift;
	my %localTestcases = ();

	# Find test cases bundled with plugin
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		my $dir = catdir($plugindir,"ABTester","Testcases");
		if(! -d $dir) {
			$dir = catdir($plugindir,"ABTester","Images");
			next unless -d $dir;
		}

		my @imageDirs = Slim::Utils::Misc::readDirectory($dir);
		for my $imageDir (@imageDirs) {
			next unless -d catdir($dir, $imageDir);

			_readTestcase($client,$dir,$imageDir,\%localTestcases);
		}
	}
	
	# Find test cases extracted from zip files
	my $cacheDir = $serverPrefs->get('cachedir');
	$cacheDir = catdir($cacheDir,'ABTester','Testcases');

	if(-d $cacheDir) {

		my @imageDirs = Slim::Utils::Misc::readDirectory($cacheDir);
		for my $imageDir (@imageDirs) {
			next unless -d catdir($cacheDir, $imageDir);
			next if exists $localTestcases{$imageDir};
			_readTestcase($client,$cacheDir,$imageDir,\%localTestcases);
		}
	}

	# Find recorded test cases
	$cacheDir = $serverPrefs->get('cachedir');
	$cacheDir = catdir($cacheDir,'ABTester','Recorded');

	if(-d $cacheDir) {
		my @imageDirs = Slim::Utils::Misc::readDirectory($cacheDir);
		for my $imageDir (@imageDirs) {
			next unless -d catdir($cacheDir, $imageDir);
			next if exists $localTestcases{$imageDir};
			_readTestcase($client,$cacheDir,$imageDir,\%localTestcases);
		}
	}

	return \%localTestcases;
}

sub _readTestcase {
	my $client = shift;
	my $cacheDir = shift;
	my $imageDir = shift;
	my $localTestcases = shift;

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
		if(!exists($xml->{'image'}) && !exists($xml->{'audio'}) && !exists($xml->{'script'}) && !exists($xml->{'perlfunction'}) && !exists($xml->{'commands'})) {
			$log->error("Failed to parse configuration ($imageDir) because: No 'image' or 'audio' or 'script' or 'perlfunction' or 'commands' elements defined");
			return;
		}
		if(exists($xml->{'image'}))  {
			my $imageElements = $xml->{'image'};
			if(scalar(keys %$imageElements) lt 2) {
				$log->error("Failed to parse configuration ($imageDir) because: At least two 'image' elements is required");
				return;
			}
		}elsif(exists($xml->{'commands'})) {
			my $commandsElements = $xml->{'commands'};
			if(scalar(keys %$commandsElements) lt 2) {
				$log->error("Failed to parse configuration ($imageDir) because: At least two 'commands' elements is required");
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
		$localTestcases->{$imageDir} = $xml;
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

# Implementation of CLI command "abtester images"
sub cliListImages {
	my $request = shift;
	
	my @images = ();

	# Add the "From Firmware" entry
	my %default = (
		'name' => string('PLUGIN_ABTESTER_RESTORE_DEFAULT_IMAGE'),
		'value' => 'fromfirmware',
	);
	push @images, \%default;
	
	my $availableImages = _getAvailableImages();
	if(scalar(@$availableImages)>0) {
		push @images, @$availableImages;
	}

  	$request->addResult('count',scalar(@images));

	my $imageno = 0;
	for my $image (@images) {
	  	$request->addResultLoop('@images',$imageno,'path',$image->{'value'});
	  	$request->addResultLoop('@images',$imageno,'name',$image->{'name'});
		$imageno++;
	}
	
	$request->setStatusDone();
}

# Implementation of CLI command "abtester image _image"
sub cliLoadImage {
	my $request = shift;
	my $client = $request->client();

	if(!defined $client) {
		$log->warn("Client required\n");
		$request->setStatusNeedsClient();
		return;
	}
	
  	my $image = $request->getParam('_image');
	if($client->model ne 'boom' && $prefs->get("restrictedtohardware")) {
		$log->warn("Can't load DSP images on this player type");
		$request->setStatusBadConfig();
		return;
	}

	if($image ne 'fromfirmware' && ! -e $image) {
		# Search for default DSP image bundled with plugin (in case full path hasn't been specified)
		my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
		for my $plugindir (@pluginDirs) {
			my $dir = catdir($plugindir,"ABTester","StandardImages");
			if(-e catfile($dir,$image)) {
				$image = catfile($dir,$image);
				last;
			}
		}

		if(!-e $image) {
			$log->warn("Image files doesn't exist: $image");
			$request->setStatusBadParams();
			return;
		}
	}

	if($image ne 'fromfirmware') {
		loadImage($client,$image);
	}else {
		loadImage($client);
	}
	$request->setStatusDone();
}

1;

__END__
