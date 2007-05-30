package Slim::Utils::Alarms;

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# This class implements SlimServer alarms.

use strict;

use Scalar::Util qw(blessed);

use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

my %possibleSpecialPlaylistsIDs = (
	'CURRENT_PLAYLIST'          => -1,
	'PLUGIN_RANDOM_TRACK'	    => -2,
	'PLUGIN_RANDOM_ALBUM'	    => -3,
	'PLUGIN_RANDOM_CONTRIBUTOR' => -4,
);

################################################################################
# Package methods
################################################################################

sub init { }

################################################################################
# Constructors
################################################################################

sub new {
	my $class  = shift;            # class to construct
	my $client = shift;            # client to which the alarm applies
	my $dow    = shift;            # dow
	
	return unless defined $client;
	return unless (defined $dow && (0 <= $dow) && ($dow <= 7));
	
	my $self = {
		'_client'   => $client,
		'_dow'      => $dow,
		'_enabled'  => 0,
		'_time'     => 0,
		'_playlist' => '',
		'_volume'   => 50,
	};

	bless $self, $class;
	
	return $self;
}

sub newLoaded {
	my $class  = shift;            # class to construct
	my $client = shift;            # client to which the alarm applies
	my $dow    = shift;            # dow
	
	return unless defined $client;
	return unless (defined $dow && (0 <= $dow) && ($dow <= 7));

	my $self = new($class, $client, $dow);
	
	$self->load();
	
	return $self;
}

################################################################################
# Read/Write basic query attributes
################################################################################

# sets/returns the client
sub client {
	my $self = shift;
	my $newvalue = shift;
	
	$self->{'_client'} = $newvalue if defined $newvalue;
	
	return $self->{'_client'};
}

# sets/returns the dow
sub dow {
	my $self = shift;
	my $newvalue = shift;
	
	$self->{'_dow'} = $newvalue if defined $newvalue;
	
	return $self->{'_dow'};
}

# sets/returns the enabled state
sub enabled {
	my $self = shift;
	my $newvalue = shift;
	
	$self->{'_enabled'} = $newvalue if defined $newvalue;
	
	return $self->{'_enabled'};
}

# sets/returns the alarmtime
sub time {
	my $self = shift;
	my $newvalue = shift;
	
	$self->{'_time'} = $newvalue if defined $newvalue;
	
	return $self->{'_time'};
}

# sets/returns the alarmvolume
sub volume {
	my $self = shift;
	my $newvalue = shift;
	
	$self->{'_volume'} = $newvalue if defined $newvalue;
	
	return $self->{'_volume'};
}

# sets/returns the alarmplaylist
sub playlist {
	my $self = shift;
	my $newvalue = shift;
	
	$self->{'_playlist'} = $newvalue if defined $newvalue;
	
	return $self->{'_playlist'};
}

################################################################################
# Compound methods
################################################################################
sub undefined {
	my $self = shift;
	
	return (
		$self->{'_enabled'} == 0 &&
		$self->{'_time'} == 0 &&
		$self->{'_volume'} == 50 &&
		$self->{'_playlist'} eq ''
	);
}

sub playlistid {
	my $self = shift;
	my $newvalue = shift;

	if (defined $newvalue) {

		my $playlistObj = Slim::Schema->find('Playlist', $newvalue);

		if (blessed($playlistObj) && $playlistObj->can('url')) {

			$self->playlist($playlistObj->url);

			return $newvalue;
		}

	} else {

		my $playlist  = $self->playlist();
		my $specialID = $possibleSpecialPlaylistsIDs{$playlist};
		
		return $specialID if defined $specialID;

		my $playlistObj = Slim::Schema->single('Playlist', { 'url' => $playlist });

		if (blessed($playlistObj) && $playlistObj->can('id')) {
			return $playlistObj->id;
		}
	}

	return undef;
}

################################################################################
# Persistence management
################################################################################

sub save {
	my $self = shift;
	my $client = $self->{'_client'};
	my $dow    = $self->{'_dow'};

	my $clientprefs = $prefs->client($client);

	my $alarm    = $clientprefs->get('alarm');
	my $time     = $clientprefs->get('alarmtime');
	my $playlist = $clientprefs->get('alarmplaylist');
	my $volume   = $clientprefs->get('alarmvolume');

	$alarm->[ $dow ]    = $self->{'_enabled'};
	$time->[ $dow ]     = $self->{'_time'};
	$playlist->[ $dow ] = $self->{'_playlist'};
	$volume->[ $dow ]   = $self->{'_volume'};

	$clientprefs->set('alarm',        $alarm   );
	$clientprefs->set('alarmtime',    $time    );
	$clientprefs->set('alarmplaylist',$playlist);
	$clientprefs->set('alarmvolume',  $volume  );
}

sub load {
	my $self = shift;
	my $client = $self->{'_client'};
	my $dow    = $self->{'_dow'};

	my $clientprefs = $prefs->client($client);

	$self->{'_enabled'}  = $clientprefs->get('alarm')->[ $dow ];
	$self->{'_time'}     = $clientprefs->get('alarmtime')->[ $dow ];
	$self->{'_playlist'} = $clientprefs->get('alarmplaylist')->[ $dow ];
	$self->{'_volume'}   = $clientprefs->get('alarmvolume')->[ $dow ];
}

1;

__END__
