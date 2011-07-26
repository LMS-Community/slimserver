#!/usr/bin/perl

use strict;
use FindBin qw($Bin);
use lib "$Bin/lib";

use Data::Dump qw(dump);
use JSON::RPC::Client;
use Test::More;
use LWP::Simple ();
use Net::UPnP::ControlPoint;
use Net::UPnP::AV::MediaRenderer;
use Net::UPnP::AV::MediaServer;
use XML::Simple qw(XMLin);
use GENA;
use URI;

plan tests => 138;

my $cp = Net::UPnP::ControlPoint->new;
my $mr;  # MediaRenderer
my $cm;  # ConnectionManager
my $cm_events;
my $rc;  # RenderingControl
my $rc_events;
my $avt; # AVTransport
my $avt_events;
my $player;
my $res;

print "# Searching for MediaRenderer:1...\n";
my @dev_list = $cp->search( st => 'urn:schemas-upnp-org:device:MediaRenderer:1', mx => 1 );
for my $dev ( @dev_list ) {
	if ( $dev->getserialnumber =~ /^00:04:20:26:03:20/ ) { # test against a hardware SB
		$mr = Net::UPnP::AV::MediaRenderer->new();
		$mr->setdevice($dev);
		
		$player = $dev->getserialnumber;
		
		$cm  = $dev->getservicebyname('urn:schemas-upnp-org:service:ConnectionManager:1');
		$rc  = $dev->getservicebyname('urn:schemas-upnp-org:service:RenderingControl:1');
		$avt = $dev->getservicebyname('urn:schemas-upnp-org:service:AVTransport:1');
		
		print "# Using " . $dev->getfriendlyname . " for tests\n";
		last;
	}
}

if ( !$cm || !$rc || !$avt ) {
	warn "# No MediaRenderer:1 devices found\n";
	exit;
}

#goto TEMP;

### Eventing

# Setup 3 subscriptions, with a callback for the initial notify data
my $sub_count = 0;

print "# Subscribing to ConnectionManager...\n";
$cm_events = GENA->new( $cm->geteventsuburl, sub {
	my ( $req, $props ) = @_;
	$sub_count++;
	
	is( $req->method, 'NOTIFY', 'CM notify ok' );
	is( $req->header('Content-Length'), length($req->content), 'CM notify length ok' );
	is( $props->{SourceProtocolInfo}, '', 'CM notify SourceProtocolInfo ok' );
	is( $props->{CurrentConnectionIDs}, 0, 'CM notify CurrentConnectionIDs ok' );
	like( $props->{SinkProtocolInfo}, qr{http-get:\*:audio/mpeg:\*}, 'CM notify SinkProtocolInfo ok' );
	# XXX test DLNA extras
} );
like( $cm_events->{sid}, qr{^uuid:[A-F0-9-]+$}, 'ConnectionManager subscribed ok' );
GENA->wait(1);
ok( $cm_events->unsubscribe, 'ConnectionManager unsubscribed ok' );

print "# Subscribing to RenderingControl...\n";
$rc_events = GENA->new( $rc->geteventsuburl, sub {
	my ( $req, $props ) = @_;
	$sub_count++;
	
	ok( $props->{LastChange}, 'RC notify LastChange ok' );
	
	my $lc = XMLin( $props->{LastChange} );
	my $data = $lc->{InstanceID};
	like( $data->{Brightness}->{val}, qr/^\d+$/, 'RC notify Brightness ok' );
	like( $data->{Mute}->{val}, qr/^\d+$/, 'RC notify Mute ok' );
	is( $data->{PresetNameList}->{val}, 'FactoryDefaults', 'RC notify PresetNameList ok' );
	like( $data->{Volume}->{val}, qr/^-?\d+$/, 'RC notify Volume ok' );
} );
like( $rc_events->{sid}, qr{^uuid:[A-F0-9-]+$}, 'RenderingControl subscribed ok' );
GENA->wait(1);
ok( $rc_events->unsubscribe, 'RenderingControl unsubscribed ok' );

=pod XXX FIXME
# Play a track, so we can properly test URI and Metadata values
my $res = _jsonrpc_get( [ 'titles', 0, 1, 'year:2000', 'tags:ldtagGpPsASeiqtymMkovrfjJnCYXRTIuwc', 'sort:tracknum' ] );
if ( !$res->{count} ) {
	warn "# No tracks found, at least 1 track from year:2000 is required\n";
	exit;
}
my $track = $res->{titles_loop}->[0];

_jsonrpc_get( $player, [ 'playlist', 'clear' ] );

print "# Subscribing to AVTransport...\n";
$avt_events = GENA->new( $avt->geteventsuburl, sub {
	my ( $req, $props ) = @_;
	$sub_count++;
	
	ok( $props->{LastChange}, 'AVT notify LastChange ok' );
	
	my $lc = XMLin( $props->{LastChange} );
	my $e = $lc->{InstanceID};	
	is( $e->{AVTransportURI}->{val}, '', 'AVT AVTransportURI ok' );
	is( $e->{AVTransportURIMetaData}->{val}, '', 'AVT AVTransportURIMetaData ok' );
	is( $e->{AbsoluteCounterPosition}->{val}, 0, 'AVT AbsoluteCounterPosition ok' );
	is( $e->{AbsoluteTimePosition}->{val}, '00:00:00', 'AVT AbsoluteTimePosition ok' );
	is( $e->{CurrentMediaDuration}->{val}, '00:00:00', 'AVT CurrentMediaDuration ok' );
	is( $e->{CurrentPlayMode}->{val}, 'NORMAL', 'AVT CurrentPlayMode ok' );
	is( $e->{CurrentRecordQualityMode}->{val}, 'NOT_IMPLEMENTED', 'AVT CurrentRecordQualityMode ok' );
	is( $e->{CurrentTrack}->{val}, 0, 'AVT CurrentTrack ok' );
	is( $e->{CurrentTrackDuration}->{val}, '00:00:00', 'AVT CurrentTrackDuration ok' );
	is( $e->{CurrentTrackMetaData}->{val}, '', 'AVT CurrentTrackMetaData ok' );
	is( $e->{CurrentTrackURI}->{val}, '', 'AVT CurrentTrackURI ok' );
	is( $e->{CurrentTransportActions}->{val}, 'PLAY,STOP', 'AVT CurrentTransportActions ok' );
	is( $e->{NextAVTransportURI}->{val}, '', 'AVT NextAVTransportURI ok' );
	is( $e->{NextAVTransportURIMetaData}->{val}, '', 'AVT NextAVTransportURIMetaData ok' );
	is( $e->{NumberOfTracks}->{val}, 0, 'AVT NumberOfTracks ok' );
	is( $e->{PlaybackStorageMedium}->{val}, 'NONE', 'AVT PlaybackStorageMedium ok' );
	is( $e->{PossiblePlaybackStorageMedia}->{val}, 'NONE,HDD,NETWORK,UNKNOWN', 'AVT PossiblePlaybackStorageMedia ok' );
	is( $e->{PossibleRecordQualityModes}->{val}, 'NOT_IMPLEMENTED', 'AVT PossibleRecordQualityModes ok' );
	is( $e->{PossibleRecordStorageMedia}->{val}, 'NOT_IMPLEMENTED', 'AVT PossibleRecordStorageMedia ok' );
	is( $e->{RecordMediumWriteStatus}->{val}, 'NOT_IMPLEMENTED', 'AVT RecordMediumWriteStatus ok' );
	is( $e->{RecordStorageMedium}->{val}, 'NOT_IMPLEMENTED', 'AVT RecordStorageMedium ok' );
	is( $e->{RelativeCounterPosition}->{val}, 0, 'AVT RelativeCounterPosition ok' );
	is( $e->{RelativeTimePosition}->{val}, '00:00:00', 'AVT RelativeTimePosition ok' );
	is( $e->{TransportPlaySpeed}->{val}, 1, 'AVT TransportPlaySpeed ok' );
	is( $e->{TransportState}->{val}, 'STOPPED', 'AVT TransportState ok' );
	is( $e->{TransportStatus}->{val}, 'OK', 'AVT TransportStatus ok' );
} );
like( $avt_events->{sid}, qr{^uuid:[A-F0-9-]+$}, 'AVTransport subscribed ok' );

GENA->wait(1);
$avt_events->clear_callback;

is( $sub_count, 3, 'Eventing: 3 notifications received ok' );

# Get the first 2 tracks from the album that will be played
$res = _jsonrpc_get( [ 'titles', 0, 100, 'album_id:' . $track->{album_id}, 'tags:ldtagGpPsASeiqtymMkovrfjJnCYXRTIuwc', 'sort:tracknum' ] );
my $track1 = $res->{titles_loop}->[0];
my $track2 = $res->{titles_loop}->[1];

# This will trigger an AVT event
$sub_count = 0;
$avt_events->set_callback( sub {
	my ( $req, $props ) = @_;
	$sub_count++;
	
	my $lc = XMLin( $props->{LastChange} );
	my $e = $lc->{InstanceID};	
	$e->{AVTransportURIMetaData}     = XMLin( $e->{AVTransportURIMetaData}->{val} );
	$e->{CurrentTrackMetaData}       = XMLin( $e->{CurrentTrackMetaData}->{val} );
	$e->{NextAVTransportURIMetaData} = XMLin( $e->{NextAVTransportURIMetaData}->{val} );
	
	my $t1id = $track1->{id};
	my $t2id = $track2->{id};
	my $t1cid = $track1->{coverid};
	my $t2cid = $track2->{coverid};
	
	like( $e->{AVTransportURI}->{val}, qr{^http://.+/music/${t1id}/download$}, 'AVT AVTransportURI change ok' );
	is( $e->{CurrentMediaDuration}->{val}, _secsToHMS($track1->{duration}), 'AVT CurrentMediaDuration change ok' );
	is( $e->{CurrentPlayMode}->{val}, 'NORMAL', 'AVT CurrentPlayMode change ok' );
	is( $e->{CurrentTrack}->{val}, 1, 'AVT CurrentTrack change ok' );
	is( $e->{CurrentTrackDuration}->{val}, _secsToHMS($track1->{duration}), 'AVT CurrentTrackDuration change ok' );
	like( $e->{CurrentTrackURI}->{val}, qr{^http://.+/music/${t1id}/download$}, 'AVT CurrentTrackURI change ok' );
	is( $e->{CurrentTransportActions}->{val}, 'PLAY,STOP,SEEK,PAUSE,NEXT,PREVIOUS', 'AVT CurrentTransportActions change ok' );
	like( $e->{NextAVTransportURI}->{val}, qr{^http://.+/music/${t2id}/download$}, 'AVT NextAVTransportURI change ok' );
	cmp_ok( $e->{NumberOfTracks}->{val}, '>=', 2, 'AVT NumberOfTracks change ok' );	
	is( $e->{TransportState}->{val}, 'PLAYING', 'AVT TransportState -> PLAYING ok' );
	
	### Verify metadata values
	
	# AVTransportURIMetaData
	my $cur = $e->{AVTransportURIMetaData}->{item};
	
	# Handle possible array values
	if ( ref $cur->{'dc:contributor'} eq 'ARRAY' ) {
		$cur->{'dc:contributor'} = $cur->{'dc:contributor'}->[0];
	}
	if ( ref $cur->{'upnp:artist'} eq 'ARRAY' ) {
		$cur->{'upnp:artist'} = $cur->{'upnp:artist'}->[0];
	}
	
	is( $cur->{'dc:contributor'}, $track1->{artist}, 'AVT cur dc:contributor ok' );
	is( $cur->{'dc:creator'}, $track1->{artist}, 'AVT cur dc:creator ok' );
	is( $cur->{'dc:date'}, $track1->{year}, 'AVT cur dc:date ok' );
	is( $cur->{'dc:title'}, $track1->{title}, 'AVT cur dc:title ok' );
	is( $cur->{id}, "/t/${t1id}", 'AVT cur id ok' );
	is( $cur->{parentID}, '/t', 'AVT cur parentID ok' );
	my ($bitrate) = $track1->{bitrate} =~ /^(\d+)/;
	is( $cur->{res}->{bitrate}, (($bitrate * 1000) / 8), 'AVT cur res@bitrate ok' );
	is( $cur->{res}->{content}, $e->{AVTransportURI}->{val}, 'AVT cur res content ok' );
	is( $cur->{res}->{duration}, _secsToHMS($track1->{duration}), 'AVT cur res@duration ok' );
	like( $cur->{res}->{protocolInfo}, qr{^http-get:\*:audio/[^:]+:\*$}, 'AVT cur res@protocolInfo ok' );
	is( $cur->{res}->{sampleFrequency}, $track1->{samplerate}, 'AVT cur res@sampleFrequency ok' );
	is( $cur->{res}->{size}, $track1->{filesize}, 'AVT cur res@size ok' );
	is( $cur->{restricted}, 1, 'AVT cur restricted ok' );
	is( $cur->{'upnp:album'}, $track1->{album}, 'AVT cur upnp:album ok' );
	like( $cur->{'upnp:albumArtURI'}, qr{^http://.+/music/${t1cid}/cover$}, 'AVT cur upnp:albumArtURI ok' );
	is( $cur->{'upnp:artist'}->{content}, $track1->{artist}, 'AVT cur upnp:artist ok' );
	like( $cur->{'upnp:artist'}->{role}, qr{^(track|album)artist$}, 'AVT cur upnp:artist@role ok' );
	is( $cur->{'upnp:class'}, 'object.item.audioItem.musicTrack', 'AVT cur upnp:class ok' );
	is( $cur->{'upnp:genre'}, $track1->{genre}, 'AVT cur upnp:genre ok' );
	is( $cur->{'upnp:originalTrackNumber'}, $track1->{tracknum}, 'AVT cur upnp:originalTrackNumber ok' );
	
	# NextAVTransportURIMetaData
	my $next = $e->{NextAVTransportURIMetaData}->{item};
	
	# Handle possible array values
	if ( ref $next->{'dc:contributor'} eq 'ARRAY' ) {
		$next->{'dc:contributor'} = $next->{'dc:contributor'}->[0];
	}
	if ( ref $next->{'upnp:artist'} eq 'ARRAY' ) {
		$next->{'upnp:artist'} = $next->{'upnp:artist'}->[0];
	}
	
	is( $next->{'dc:contributor'}, $track2->{artist}, 'AVT next dc:contributor ok' );
	is( $next->{'dc:creator'}, $track2->{artist}, 'AVT next dc:creator ok' );
	is( $next->{'dc:date'}, $track2->{year}, 'AVT next dc:date ok' );
	is( $next->{'dc:title'}, $track2->{title}, 'AVT next dc:title ok' );
	is( $next->{id}, "/t/${t2id}", 'AVT next id ok' );
	is( $next->{parentID}, '/t', 'AVT next parentID ok' );
	my ($bitrate) = $track2->{bitrate} =~ /^(\d+)/;
	is( $next->{res}->{bitrate}, (($bitrate * 1000) / 8), 'AVT next res@bitrate ok' );
	is( $next->{res}->{content}, $e->{NextAVTransportURI}->{val}, 'AVT next res content ok' );
	is( $next->{res}->{duration}, _secsToHMS($track2->{duration}), 'AVT next res@duration ok' );
	like( $next->{res}->{protocolInfo}, qr{^http-get:\*:audio/[^:]+:\*$}, 'AVT next res@protocolInfo ok' );
	is( $next->{res}->{sampleFrequency}, $track2->{samplerate}, 'AVT next res@sampleFrequency ok' );
	is( $next->{res}->{size}, $track2->{filesize}, 'AVT next res@size ok' );
	is( $next->{restricted}, 1, 'AVT next restricted ok' );
	is( $next->{'upnp:album'}, $track2->{album}, 'AVT next upnp:album ok' );
	like( $next->{'upnp:albumArtURI'}, qr{^http://.+/music/${t2cid}/cover$}, 'AVT next upnp:albumArtURI ok' );
	is( $next->{'upnp:artist'}->{content}, $track2->{artist}, 'AVT next upnp:artist ok' );
	like( $next->{'upnp:artist'}->{role}, qr{^(track|album)artist$}, 'AVT next upnp:artist@role ok' );
	is( $next->{'upnp:class'}, 'object.item.audioItem.musicTrack', 'AVT next upnp:class ok' );
	is( $next->{'upnp:genre'}, $track2->{genre}, 'AVT next upnp:genre ok' );
	is( $next->{'upnp:originalTrackNumber'}, $track2->{tracknum}, 'AVT next upnp:originalTrackNumber ok' );
} );

# Play an album
$res = _jsonrpc_get( $player, [ 'playlistcontrol', 'cmd:load', 'album_id:' . $track->{album_id} ] );
ok( $res->{count}, 'Played album ok' );

print "# Waiting for AVTransport notification...\n";
GENA->wait(1);
ok( $avt_events->unsubscribe, 'AVT unsubscribed ok' );

is( $sub_count, 1, 'AVT notify count ok' );
=cut

### RenderingControl
print "# RenderingControl\n";

$rc_events = GENA->new( $rc->geteventsuburl, sub {} );
GENA->wait(1);

# Volume pref change eventing
{
	my $ec = 0;
	my $newval;
	
	$rc_events->set_callback( sub {
		my ( $req, $props ) = @_;
		$ec++;
		my $lc = XMLin( $props->{LastChange} );
		my $e = $lc->{InstanceID};
		
		is( $e->{Volume}->{channel}, 'Master', 'RC volume change event channel ok' );
		is( $e->{Volume}->{val}, $newval, 'RC volume change event value ok' );
	} );
	
	# Set volume to +1 or 25, to avoid setting it to the same value and getting no event
	my $res = _jsonrpc_get( $player, [ 'mixer', 'volume', '?' ] );
	$newval = $res->{_volume} == 100 ? 25 : ++$res->{_volume};
	_jsonrpc_get( $player, [ 'mixer', 'volume', $newval ] );
	
	GENA->wait(1);
	$rc_events->clear_callback;

	is( $ec, 1, 'RC volume change notify count ok' );
}

# Mute pref change eventing
{
	my $ec = 0;
	my $newval;
	
	$rc_events->set_callback( sub {
		my ( $req, $props ) = @_;
		$ec++;
		my $lc = XMLin( $props->{LastChange} );
		my $e = $lc->{InstanceID};
		
		is( $e->{Mute}->{channel}, 'Master', 'RC mute change event channel ok' );
		is( $e->{Mute}->{val}, $newval, 'RC mute change event value ok' );
	} );
	
	my $res = _jsonrpc_get( $player, [ 'mixer', 'muting', '?' ] );
	$newval = $res->{_muting} == 1 ? 0 : 1;
	_jsonrpc_get( $player, [ 'mixer', 'muting', $newval ] );
	
	GENA->wait(1);
	$rc_events->clear_callback;

	is( $ec, 1, 'RC mute change notify count ok' );
}

# Brightness pref change eventing
{
	my $ec = 0;
	my $onval;
	my $offval;
	
	$rc_events->set_callback( sub {
		my ( $req, $props ) = @_;
		$ec++;
		my $lc = XMLin( $props->{LastChange} );
		my $e = $lc->{InstanceID};
		
		if ($ec == 1) { # powerOnBrightness
			is( $e->{Brightness}->{val}, $onval, 'RC powerOnBrightness change event ok' );
		}
		elsif ($ec == 2) { # powerOffBrightness
			is( $e->{Brightness}->{val}, $offval, 'RC powerOffBrightness change event ok' );
		}
	} );
	
	my $res = _jsonrpc_get( $player, [ 'playerpref', 'powerOnBrightness', '?' ] );
	$onval = $res->{_p2};
	
	$res = _jsonrpc_get( $player, [ 'playerpref', 'powerOffBrightness', '?' ] );
	$offval = $res->{_p2};
	
	# Turn player on and change the on brightness, will event
	_jsonrpc_get( $player, [ 'power', 1 ] );
	$onval = $onval == 4 ? 1 : ++$onval;
	_jsonrpc_get( $player, [ 'playerpref', 'powerOnBrightness', $onval ] );
	
	# Change off brightness while player is on, will not event
	$offval = $offval == 4 ? 1 : ++$offval;
	_jsonrpc_get( $player, [ 'playerpref', 'powerOffBrightness', $offval ] );
	
	GENA->wait(1);
	
	# Turn player off and change the off brightness, will event
	_jsonrpc_get( $player, [ 'power', 0 ] );
	$offval = $offval == 4 ? 1 : ++$offval;
	_jsonrpc_get( $player, [ 'playerpref', 'powerOffBrightness', $offval ] );
	
	# Change on brightness while player is off, will not event
	$onval = $onval == 4 ? 1 : ++$onval;
	_jsonrpc_get( $player, [ 'playerpref', 'powerOnBrightness', $onval ] );
	
	GENA->wait(1);
	$rc_events->clear_callback;

	is( $ec, 2, 'RC brightness change notify count ok' );
}

# ListPresets
{
	my $res = _action( $rc, 'ListPresets' );
	is( $res->{CurrentPresetNameList}->{content}, 'FactoryDefaults', 'RC ListPresets ok' );
}

# SelectPreset
{
	my $ec = 0;
	
	# This changes 2 prefs but they are batched together into 1 event
	$rc_events->set_callback( sub {
		my ( $req, $props ) = @_;
		$ec++;
		my $lc = XMLin( $props->{LastChange} );
		my $e = $lc->{InstanceID};
		
		is( $e->{Mute}->{val}, 0, 'RC SelectPreset mute change event ok' );
		is( $e->{Volume}->{val}, 50, 'RC SelectPreset volume change event ok' );
	} );
	
	my $res = _action( $rc, 'SelectPreset', { PresetName => 'FactoryDefaults' } );
	ok( !$res->{errorCode}, 'RC SelectPreset ok' );
	
	GENA->wait(1);
	$rc_events->clear_callback;

	is( $ec, 1, 'RC SelectPreset change notify count ok' );
}

# GetBrightness
{
	my $res = _action( $rc, 'GetBrightness' );
	like( $res->{CurrentBrightness}->{content}, qr/^\d+$/, 'RC GetBrightness ok' );
}

# SetBrightness
{
	my $ec = 0;
	my $power;
	my $newval;
	
	my $res = _jsonrpc_get( $player, [ 'power', '?' ] );
	if ( $res->{_power} ) {
		$res = _jsonrpc_get( $player, [ 'playerpref', 'powerOnBrightness', '?' ] );
		$newval = $res->{_p2} == 4 ? 1 : ++$res->{_p2};
	}
	else {
		$res = _jsonrpc_get( $player, [ 'playerpref', 'powerOffBrightness', '?' ] );
		$newval = $res->{_p2} == 4 ? 1 : ++$res->{_p2};
	}
	
	$rc_events->set_callback( sub {
		my ( $req, $props ) = @_;
		$ec++;
		my $lc = XMLin( $props->{LastChange} );
		my $e = $lc->{InstanceID};
		
		is( $e->{Brightness}->{val}, $newval, 'RC SetBrightness change event ok' );
	} );
	
	$res = _action( $rc, 'SetBrightness', { DesiredBrightness => $newval } );
	ok( !$res->{errorCode}, 'RC SetBrightness ok' );
	
	GENA->wait(1);
	$rc_events->clear_callback;

	is( $ec, 1, 'RC SetBrightness change notify count ok' );
}

# GetMute
{
	my $res = _action( $rc, 'GetMute', { Channel => 'Master' } );
	like( $res->{CurrentMute}->{content}, qr/^\d+$/, 'RC GetMute ok' );
}

# SetMute
{
	my $ec = 0;
	my $newval;
	
	$rc_events->set_callback( sub {
		my ( $req, $props ) = @_;
		$ec++;
		my $lc = XMLin( $props->{LastChange} );
		my $e = $lc->{InstanceID};
		
		is( $e->{Mute}->{channel}, 'Master', 'RC SetMute change event channel ok' );
		is( $e->{Mute}->{val}, $newval, 'RC SetMute change event value ok' );
	} );
	
	my $res = _jsonrpc_get( $player, [ 'mixer', 'muting', '?' ] );
	$newval = $res->{_muting} == 1 ? 0 : 1;
	
	$res = _action( $rc, 'SetMute', {
		Channel     => 'Master',
		DesiredMute => $newval,
	} );
	ok( !$res->{errorCode}, 'RC SetMute ok' );
	
	GENA->wait(1);
	$rc_events->clear_callback;

	is( $ec, 1, 'RC SetMute change notify count ok' );
}

# GetVolume
{
	my $res = _action( $rc, 'GetVolume', { Channel => 'Master' } );
	like( $res->{CurrentVolume}->{content}, qr/^\d+$/, 'RC GetVolume ok' );
}

# SetVolume
{
	my $ec = 0;
	my $newval;
	
	$rc_events->set_callback( sub {
		my ( $req, $props ) = @_;
		$ec++;
		my $lc = XMLin( $props->{LastChange} );
		my $e = $lc->{InstanceID};
		
		is( $e->{Volume}->{channel}, 'Master', 'RC SetVolume change event channel ok' );
		is( $e->{Volume}->{val}, $newval, 'RC SetVolume change event value ok' );
	} );
	
	# Set volume to +1 or 25, to avoid setting it to the same value and getting no event
	my $res = _jsonrpc_get( $player, [ 'mixer', 'volume', '?' ] );
	$newval = $res->{_volume} == 100 ? 25 : ++$res->{_volume};
	
	$res = _action( $rc, 'SetVolume', {
		Channel       => 'Master',
		DesiredVolume => $newval,
	} );
	ok( !$res->{errorCode}, 'RC SetVolume ok' );
	
	GENA->wait(1);
	$rc_events->clear_callback;

	is( $ec, 1, 'RC SetVolume change notify count ok' );
}

$rc_events->unsubscribe;
	
### AVTransport
#TEMP:
print "# AVTransport\n";

# Find a non-SBS MediaServer we will stream from
my $cd;

print "# Searching for MediaServer:1...\n";
my @dev_list = $cp->search( st => 'urn:schemas-upnp-org:device:MediaServer:1', mx => 1 );
for my $dev ( @dev_list ) {
	if ( $dev->getmodelname !~ /^Logitech Media Server/ ) {
		my $ms = Net::UPnP::AV::MediaServer->new();
		$ms->setdevice($dev);
		
		$cd = $dev->getservicebyname('urn:schemas-upnp-org:service:ContentDirectory:1');
		
		# Require the Search method on this server
		my $ctluri  = URI->new($cd->getposturl);
		my $scpduri = $cd->getscpdurl;
		if ( $scpduri !~ /^http/ ) {
			if ( $scpduri !~ m{^/} ) {
				$scpduri = '/' . $scpduri;
			}
			$scpduri = 'http://' . $ctluri->host_port . $scpduri;
		}
		my $scpd = LWP::Simple::get($scpduri);
		next unless $scpd =~ /SearchCriteria/;
		
		print "# Using " . $dev->getfriendlyname . " for AVTransport tests\n";
		last;
	}
}
if ( !$cd ) {
	warn "# No MediaServer:1 devices that support Search found, cannot continue\n";
	exit;
}

# Find 2 audioItem items on this server
$res = _action( $cd, 'Search', {
	ContainerID    => 0,
	SearchCriteria => 'upnp:class derivedfrom "object.item.audioItem" and @refID exists false',
	Filter         => '*',
	StartingIndex  => 0,
	RequestedCount => 2,
	SortCriteria   => '',
} );
if ( $res->{NumberReturned} != 2 ) {
	warn "# MediaServer did not return 2 audioItem items, cannot continue\n";
	exit;
}

my ($xml1, $xml2) = $res->{Result} =~ m{(<item.+</item>)(<item.+</item>)};

my $item1 = XMLin($xml1);
my $item2 = XMLin($xml2);

print "# Test track 1: " . $item1->{'dc:title'} . ' (' . $item1->{res}->{duration} . ', ' . $item1->{res}->{bitrate} . " bytes/sec)\n";
print "# Test track 2: " . $item2->{'dc:title'} . ' (' . $item2->{res}->{duration} . ', ' . $item2->{res}->{bitrate} . " bytes/sec)\n";

$xml1 =~ s/\r?\n//g; # newlines break the raw data comparison
$xml2 =~ s/\r?\n//g;

# Add DIDL-Lite wrapper
my $didl = qq{<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/">};
$xml1 = $didl . $xml1 . '</DIDL-Lite>';
$xml2 = $didl . $xml2 . '</DIDL-Lite>';

# Reset player to an empty state
_jsonrpc_get( $player, [ 'playlist', 'clear' ] );
sleep 1;

my $ctluri  = URI->new($avt->getposturl);
my $eventuri = $avt->geteventsuburl;
if ( $eventuri !~ /^http/ ) {
	if ( $eventuri !~ m{^/} ) {
		$eventuri = '/' . $eventuri;
	}
	$eventuri = 'http://' . $ctluri->host_port . $eventuri;
}
$avt_events = GENA->new( $eventuri, sub {
	my ( $req, $props ) = @_;
	my $lc = XMLin( $props->{LastChange} );
	my $e = $lc->{InstanceID};
	
	# Check initial state variables
	is( $e->{TransportState}->{val}, 'NO_MEDIA_PRESENT', 'AVT initial TransportState ok' );
	is( $e->{TransportStatus}->{val}, 'OK', 'AVT initial TransportStatus ok' );
	is( $e->{PlaybackStorageMedium}->{val}, 'NONE', 'AVT initial PlaybackStorageMedium ok' );
	is( $e->{RecordStorageMedium}->{val}, 'NOT_IMPLEMENTED', 'AVT initial RecordStorageMedium ok' );
	is( $e->{PossiblePlaybackStorageMedia}->{val}, 'NONE,NETWORK', 'AVT initial PossiblePlaybackStorageMedia ok' );
	is( $e->{PossibleRecordStorageMedia}->{val}, 'NOT_IMPLEMENTED', 'AVT initial PossibleRecordStorageMedia ok' );
	is( $e->{CurrentPlayMode}->{val}, 'NORMAL', 'AVT initial CurrentPlayMode ok' );
	is( $e->{TransportPlaySpeed}->{val}, 1, 'AVT initial TransportPlaySpeed ok' );
	is( $e->{RecordMediumWriteStatus}->{val}, 'NOT_IMPLEMENTED', 'AVT initial RecordMediumWriteStatus ok' );
	is( $e->{CurrentRecordQualityMode}->{val}, 'NOT_IMPLEMENTED', 'AVT initial CurrentRecordQualityMode ok' );
	is( $e->{PossibleRecordQualityModes}->{val}, 'NOT_IMPLEMENTED', 'AVT initial PossibleRecordQualityModes ok' );
	is( $e->{NumberOfTracks}->{val}, 0, 'AVT initial NumberOfTracks ok' );
	is( $e->{CurrentTrack}->{val}, 0, 'AVT initial CurrentTrack ok' );
	is( $e->{CurrentTrackDuration}->{val}, '00:00:00', 'AVT initial CurrentTrackDuration ok' );
	is( $e->{CurrentMediaDuration}->{val}, '00:00:00', 'AVT initial CurrentMediaDuration ok' );
	is( $e->{CurrentTrackMetaData}->{val}, '', 'AVT initial CurrentTrackMetaData ok' );
	is( $e->{CurrentTrackURI}->{val}, '', 'AVT initial CurrentTrackURI ok' );
	is( $e->{AVTransportURI}->{val}, '', 'AVT initial AVTransportURI ok' );
	is( $e->{AVTransportURIMetaData}->{val}, '', 'AVT initial AVTransportURIMetaData ok' );
	is( $e->{NextAVTransportURI}->{val}, '', 'AVT initial NextAVTransportURI ok' );
	is( $e->{NextAVTransportURIMetaData}->{val}, '', 'AVT initial NextAVTransportURIMetaData ok' );
	is( $e->{CurrentTransportActions}->{val}, 'Play,Stop,Pause,Seek,Next,Previous', 'AVT initial CurrentTransportActions ok' );
} );
GENA->wait(1);

# SetAVTransportURI
{
	my $ec = 0;
	
	# The code will change the first variables, followed by TransportState,
	# so this is also a test of the event batching code
	$avt_events->set_callback( sub {
		my ( $req, $props ) = @_;
		$ec++;
		my $lc = XMLin( $props->{LastChange} );
		my $e = $lc->{InstanceID};
		
		is( $e->{AVTransportURI}->{val}, $item1->{res}->{content}, 'AVT SetAVTransportURI change for AVTransportURI ok' );
		is( $e->{CurrentTrackURI}->{val}, $item1->{res}->{content}, 'AVT SetAVTransportURI change for CurrentTrackURI ok' );
		is( $e->{AVTransportURIMetaData}->{val}, $xml1, 'AVT SetAVTransportURI change for AVTransportURIMetaData ok' );
		is( $e->{CurrentTrackMetaData}->{val}, $xml1, 'AVT SetAVTransportURI change for CurrentTrackMetaData ok' );
		is( $e->{NumberOfTracks}->{val}, 1, 'AVT SetAVTransportURI change for NumberOfTracks ok' );
		is( $e->{CurrentTrack}->{val}, 1, 'AVT SetAVTransportURI change for CurrentTrack ok' );
		is( $e->{CurrentMediaDuration}->{val}, $item1->{res}->{duration}, 'AVT SetAVTransportURI change for CurrentMediaDuration ok' );
		is( $e->{CurrentTrackDuration}->{val}, $item1->{res}->{duration}, 'AVT SetAVTransportURI change for CurrentTrackDuration ok' );
		is( $e->{PlaybackStorageMedium}->{val}, 'NETWORK', 'AVT SetAVTransportURI change for PlaybackStorageMedium ok' );
		is( $e->{TransportState}->{val}, 'STOPPED', 'AVT SetAVTransportURI change for TransportState ok' );
	} );
		
	my $res = _action( $avt, 'SetAVTransportURI', {
		InstanceID         => 0,
		CurrentURI         => $item1->{res}->{content},
		CurrentURIMetaData => xmlEscape($xml1),
	} );
	ok( !$res->{errorCode}, 'AVT SetAVTransportURI ok' );
	
	GENA->wait(1);
	$avt_events->clear_callback;
	
	is( $ec, 1, 'AVT SetAVTransportURI change notify count ok' );
	
	# XXX more tests from different states:
	# STOPPED -> STOPPED
	# PLAYING -> PLAYING
	# PAUSED -> STOPPED
}

# SetNextAVTransportURI
{
	my $ec = 0;
	
	# This changes 2 values but they are batched together into 1 event
	$avt_events->set_callback( sub {
		my ( $req, $props ) = @_;
		$ec++;
		my $lc = XMLin( $props->{LastChange} );
		my $e = $lc->{InstanceID};
		
		is( $e->{NextAVTransportURI}->{val}, $item2->{res}->{content}, 'AVT SetNextAVTransportURI change for NextAVTransportURI ok' );
		is( $e->{NextAVTransportURIMetaData}->{val}, $xml2, 'AVT SetNextAVTransportURI change for NextAVTransportURIMetaData ok' );
	} );
		
	my $res = _action( $avt, 'SetNextAVTransportURI', {
		InstanceID      => 0,
		NextURI         => $item2->{res}->{content},
		NextURIMetaData => xmlEscape($xml2),
	} );
	ok( !$res->{errorCode}, 'AVT SetNextAVTransportURI ok' );
	
	GENA->wait(1);
	$avt_events->clear_callback;
	
	is( $ec, 1, 'AVT SetNextAVTransportURI change notify count ok' );
	
	# XXX test automatic transition from current -> next
}

# GetMediaInfo
{
	my $res = _action( $avt, 'GetMediaInfo', { InstanceID => 0 } );
	
	is( $res->{CurrentURI}->{content}, $item1->{res}->{content}, 'AVT GetMediaInfo CurrentURI ok' );
	is( $res->{CurrentURIMetaData}->{content}, $xml1, 'AVT GetMediaInfo CurrentURIMetaData ok' );
	is( $res->{MediaDuration}->{content}, $item1->{res}->{duration}, 'AVT GetMediaInfo MediaDuration ok' );
	is( $res->{NextURI}->{content}, $item2->{res}->{content}, 'AVT GetMediaInfo NextURI ok' );
	is( $res->{NextURIMetaData}->{content}, $xml2, 'AVT GetMediaInfo NextURIMetaData ok' );
	is( $res->{NrTracks}->{content}, 1, 'AVT GetMediaInfo NrTracks ok' );
	is( $res->{PlayMedium}->{content}, 'NETWORK', 'AVT GetMediaInfo PlayMedium ok' );
	is( $res->{RecordMedium}->{content}, 'NOT_IMPLEMENTED', 'AVT GetMediaInfo RecordMedium ok' );
	is( $res->{WriteStatus}->{content}, 'NOT_IMPLEMENTED', 'AVT GetMediaInfo WriteStatus ok' );	
}

# GetTransportInfo
{
	my $res = _action( $avt, 'GetTransportInfo', { InstanceID => 0 } );
	
	is( $res->{CurrentTransportState}->{content}, 'STOPPED', 'AVT CurrentTransportState CurrentTransportState ok' );
	is( $res->{CurrentTransportStatus}->{content}, 'OK', 'AVT GetTransportInfo CurrentTransportStatus ok' );
	is( $res->{CurrentSpeed}->{content}, 1, 'AVT GetTransportInfo CurrentSpeed ok' );
}

# GetPositionInfo
{
	my $res = _action( $avt, 'GetPositionInfo', { InstanceID => 0 } );
	
	is( $res->{Track}->{content}, 1, 'AVT GetPositionInfo Track ok' );
	is( $res->{TrackDuration}->{content}, $item1->{res}->{duration}, 'AVT GetPositionInfo TrackDuration ok' );
	is( $res->{TrackMetaData}->{content}, $xml1, 'AVT GetPositionInfo TrackMetaData ok' );
	is( $res->{TrackURI}->{content}, $item1->{res}->{content}, 'AVT GetPositionInfo TrackURI ok' );
	is( $res->{RelTime}->{content}, '00:00:00', 'AVT GetPositionInfo RelTime ok' );
	is( $res->{AbsTime}->{content}, '00:00:00', 'AVT GetPositionInfo AbsTime ok' );
	is( $res->{RelCount}->{content}, 0, 'AVT GetPositionInfo RelCount ok' );
	is( $res->{AbsCount}->{content}, 0, 'AVT GetPositionInfo AbsCount ok' );
}

# GetDeviceCapabilities
{
	my $res = _action( $avt, 'GetDeviceCapabilities', { InstanceID => 0 } );
	
	is( $res->{PlayMedia}->{content}, 'NONE,HDD,NETWORK,UNKNOWN', 'AVT GetDeviceCapabilities PlayMedia ok' );
	is( $res->{RecMedia}->{content}, 'NOT_IMPLEMENTED', 'AVT GetDeviceCapabilities RecMedia ok' );
	is( $res->{RecQualityModes}->{content}, 'NOT_IMPLEMENTED', 'AVT GetDeviceCapabilities RecQualityModes ok' );
}

# GetTransportSettings
{
	my $res = _action( $avt, 'GetTransportSettings', { InstanceID => 0 } );
	
	is( $res->{PlayMode}->{content}, 'NORMAL', 'AVT GetTransportSettings PlayMode ok' );
	is( $res->{RecQualityMode}->{content}, 'NOT_IMPLEMENTED', 'AVT GetTransportSettings RecQualityMode ok' );
}

# Play
{
	my $ec = 0;
	
	$avt_events->set_callback( sub {
		my ( $req, $props ) = @_;
		$ec++;
		my $lc = XMLin( $props->{LastChange} );
		my $e = $lc->{InstanceID};
		
		# State goes through TRANSITIONING but it will be too fast to get evented
		is( $e->{TransportState}->{val}, 'PLAYING', 'AVT Play TransportState change to PLAYING ok' );
	} );
	
	my $res = _action( $avt, 'Play', {
		InstanceID => 0,
		Speed      => 1,
	} );
	ok( !$res->{errorCode}, 'AVT Play ok' );
	
	# Play a second time will be ignored, with no event sent
	_action( $avt, 'Play', {
		InstanceID => 0,
		Speed      => 1,
	} );
	
	GENA->wait(1);
	$avt_events->clear_callback;
	
	is( $ec, 1, 'AVT Play notify count ok' );
	
	# Verify it's now playing
	$res = _action( $avt, 'GetTransportInfo', { InstanceID => 0 } );
	is( $res->{CurrentTransportState}->{content}, 'PLAYING', 'AVT Play CurrentTransportState is PLAYING ok' );
	
	sleep 4;
	$res = _action( $avt, 'GetPositionInfo', { InstanceID => 0 } );
	cmp_ok( $res->{AbsCount}->{content}, '>=', 1, 'AVT Play AbsCount ' . $res->{AbsCount}->{content} . ' ok' );
	cmp_ok( $res->{RelCount}->{content}, '>=', 1, 'AVT Play RelCount ' . $res->{RelCount}->{content} . ' ok' );
	like( $res->{AbsTime}->{content}, qr/^0:00:0[1234]\.\d+$/, 'AVT Play AbsTime ' . $res->{AbsTime}->{content} . ' ok' );
	like( $res->{RelTime}->{content}, qr/^0:00:0[1234]\.\d+$/, 'AVT Play RelTime ' . $res->{RelTime}->{content} . ' ok' );
}

# Seek
{
	print "# Note: Seek tests require accurate bitrate/duration, try using CBR MP3 files if this fails\n";
	my $ec = 0;
	
	$avt_events->set_callback( sub {
		my ( $req, $props ) = @_;
		$ec++;
		my $lc = XMLin( $props->{LastChange} );
		my $e = $lc->{InstanceID};
		
		if ($ec == 1) {
			is( $e->{TransportState}->{val}, 'TRANSITIONING', 'AVT Seek TransportState change to TRANSITIONING ok' );
		}
		elsif ($ec == 2) {
			is( $e->{TransportState}->{val}, 'PLAYING', 'AVT Seek TransportState change to PLAYING ok' );
		}
	} );
	
	my $res = _action( $avt, 'Seek', {
		InstanceID => 0,
		Unit       => 'ABS_TIME',
		Target     => '0:01:00.123',
	} );
	ok( !$res->{errorCode}, 'AVT Seek ok' );
	
	GENA->wait(2);
	$avt_events->clear_callback;
	
	is( $ec, 2, 'AVT Seek notify count ok' );
	
	# Check that the playback position changed correctly
	sleep 2;
	$res = _action( $avt, 'GetPositionInfo', { InstanceID => 0 } );
	cmp_ok( $res->{AbsCount}->{content}, '>=', 60, 'AVT Seek AbsCount ' . $res->{AbsCount}->{content} . ' ok' );
	cmp_ok( $res->{RelCount}->{content}, '>=', 60, 'AVT Seek RelCount ' . $res->{RelCount}->{content} . ' ok' );
	like( $res->{AbsTime}->{content}, qr/^0:01:/, 'AVT Seek AbsTime ' . $res->{AbsTime}->{content} . ' ok' );
	like( $res->{RelTime}->{content}, qr/^0:01:/, 'AVT Seek RelTime ' . $res->{RelTime}->{content} . ' ok' );
}

# Pause
{
	my $ec = 0;
	
	$avt_events->set_callback( sub {
		my ( $req, $props ) = @_;
		$ec++;
		my $lc = XMLin( $props->{LastChange} );
		my $e = $lc->{InstanceID};
		
		if ($ec == 1) { # pause event
			is( $e->{TransportState}->{val}, 'PAUSED_PLAYBACK', 'AVT Pause TransportState change to PAUSED_PLAYBACK ok' );
		}
		elsif ($ec == 2) { # play event
			is( $e->{TransportState}->{val}, 'PLAYING', 'AVT Play while paused TransportState change to PLAYING ok' );
		}
	} );
	
	my $res = _action( $avt, 'Pause', { InstanceID => 0 } );
	ok( !$res->{errorCode}, 'AVT Pause ok' );
	
	GENA->wait(1);
	is( $ec, 1, 'AVT Pause notify count ok' );
	
	$res = _action( $avt, 'GetTransportInfo', { InstanceID => 0 } );
	is( $res->{CurrentTransportState}->{content}, 'PAUSED_PLAYBACK', 'AVT Pause CurrentTransportState is PAUSED_PLAYBACK ok' );
	
	# Play while paused
	$res = _action( $avt, 'Play', {
		InstanceID => 0,
		Speed      => 1,
	} );
	ok( !$res->{errorCode}, 'AVT Play while paused ok' );
	
	GENA->wait(1);
	$avt_events->clear_callback;
	
	is( $ec, 2, 'AVT Play while paused notify count ok' );
}

# Stop
{
	my $ec = 0;
	
	$avt_events->set_callback( sub {
		my ( $req, $props ) = @_;
		$ec++;
		my $lc = XMLin( $props->{LastChange} );
		my $e = $lc->{InstanceID};
		
		is( $e->{TransportState}->{val}, 'STOPPED', 'AVT Stop TransportState change to STOPPED ok' );		
	} );
	
	my $res = _action( $avt, 'Stop', { InstanceID => 0 } );
	ok( !$res->{errorCode}, 'AVT Stop ok' );
	
	GENA->wait(1);
	$avt_events->clear_callback;
	
	is( $ec, 1, 'AVT Stop notify count ok' );
	
	$res = _action( $avt, 'GetTransportInfo', { InstanceID => 0 } );
	is( $res->{CurrentTransportState}->{content}, 'STOPPED', 'AVT Stop CurrentTransportState is STOPPED ok' );
}

# Next
{
	# Next is an error with a single track
	my $res = _action( $avt, 'Next', { InstanceID => 0 } );
	is( $res->{errorCode}->{content}, 711, 'AVT Next failed ok' );
}

# Previous
{
	# Previous is an error with a single track
	my $res = _action( $avt, 'Previous', { InstanceID => 0 } );
	is( $res->{errorCode}->{content}, 711, 'AVT Previous failed ok' );
}

# SetPlayMode
{
	my $ec = 0;
	
	$avt_events->set_callback( sub {
		my ( $req, $props ) = @_;
		$ec++;
		my $lc = XMLin( $props->{LastChange} );
		my $e = $lc->{InstanceID};
		
		is( $e->{CurrentPlayMode}->{val}, 'REPEAT_ONE', 'AVT SetPlayMode CurrentPlayMode change to REPEAT_ONE ok' );		
	} );
	
	my $res = _action( $avt, 'SetPlayMode', {
		InstanceID => 0,
		NewPlayMode => 'REPEAT_ONE',
	} );
	ok( !$res->{errorCode}, 'AVT SetPlayMode ok' );
	
	GENA->wait(1);
	$avt_events->clear_callback;
	
	is( $ec, 1, 'AVT SetPlayMode notify count ok' );
}

# XXX test SetPlayMode with playlists

# GetCurrentTransportActions
# XXX when stopped, this should be different...
{
	my $res = _action( $avt, 'GetCurrentTransportActions', { InstanceID => 0 } );
	is( $res->{Actions}->{content}, 'Play,Stop,Pause,Seek,Next,Previous', 'AVT GetCurrentTransportActions ok' );
}

### XXX metadata during internal SBS file playback

### XXX Internet Radio

### XXX File from our own MediaServer

### XXX playlist files

# Reset player
#_jsonrpc_get( $player, [ 'playlist', 'clear' ] );

END {
	$cm_events && $cm_events->unsubscribe;
	$rc_events && $rc_events->unsubscribe;
	$avt_events && $avt_events->unsubscribe;
}

sub _action {
	my ( $service, $action, $args ) = @_;
	
	$args ||= {};
	
	my $res = $service->postaction($action, $args);
	my $hash = XMLin( $res->gethttpresponse->getcontent );
	
	if ( $res->getstatuscode == 200 ) {	
		return $hash->{'s:Body'}->{"u:${action}Response"};
	}
	else {
		return $hash->{'s:Body'}->{'s:Fault'}->{detail};
	}
}

sub _jsonrpc_get {
	my $cmd = shift;
	
	my $client = JSON::RPC::Client->new;
	my $uri    = 'http://localhost:9000/jsonrpc.js';
	
	# Support optional initial player param
	my $player = '';
	if ( !ref $cmd ) {
		$player = $cmd;
		$cmd = shift;
	}
	
	my $res = $client->call( $uri, { method => 'slim.request', params => [ $player, $cmd ] } );
	
	if ( $res && $res->is_success ) {
		return $res->content->{result};
	}
	
	return;
}

# seconds to H:MM:SS[.F+]
sub _secsToHMS {
	my $secs = shift;
	
	my $elapsed = sprintf '%d:%02d:%02d', int($secs / 3600), int($secs / 60), $secs % 60;
	
	if ( $secs =~ /\.(\d+)$/ ) {
		$elapsed .= '.' . $1;
	}
	
	return $elapsed;
}

sub xmlEscape {
	my $text = shift;
	
	if ( $text =~ /[\&\<\>'"]/) {
		$text =~ s/&/&amp;/go;
		$text =~ s/</&lt;/go;
		$text =~ s/>/&gt;/go;
		$text =~ s/'/&apos;/go;
		$text =~ s/"/&quot;/go;
	}
	
	return $text;
}
