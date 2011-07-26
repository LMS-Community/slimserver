#!/usr/bin/perl

use strict;
use FindBin qw($Bin);
use lib "$Bin/lib";

use Data::Dump qw(dump);
use GENA;
use Test::More;
use Net::UPnP::ControlPoint;
use Net::UPnP::AV::MediaServer;
use XML::Fast;

plan tests => 262;

# Force a server to use, in case there is more than one on the network
my $force_ip = shift;

my $cp = Net::UPnP::ControlPoint->new;
my $ms; # MediaServer
my $cm; # ConnectionManager
my $cm_events;
my $cd; # ContentDirectory
my $cd_events;

print "# Searching for MediaServer:1...\n";
my @dev_list = $cp->search( st => 'urn:schemas-upnp-org:device:MediaServer:1', mx => 1 );
for my $dev ( @dev_list ) {
	if ( $dev->getmodelname =~ /Logitech Media Server/ ) {
		$ms = Net::UPnP::AV::MediaServer->new();
		$ms->setdevice($dev);
		
		$cm = $dev->getservicebyname('urn:schemas-upnp-org:service:ConnectionManager:1');
		$cd = $dev->getservicebyname('urn:schemas-upnp-org:service:ContentDirectory:1');
		
		next if $force_ip && $cm->geteventsuburl !~ /$force_ip/;
		
		print '# Using MediaServer: ' . $dev->getfriendlyname . "\n";
		last;
	}
}

if ( !$cm || !$cd ) {
	warn "# No MediaServer:1 devices found\n";
	exit;
}

#goto HERE;

### Eventing

# Setup 2 subscriptions, with a callback for the initial notify data
my $sub_count = 0;

print "# Subscribing to ConnectionManager...\n";
$cm_events = GENA->new( $cm->geteventsuburl, sub {
	my ( $req, $props ) = @_;
	$sub_count++;
	
	is( $req->method, 'NOTIFY', 'CM notify ok' );
	is( $req->header('Content-Length'), length($req->content), 'CM notify length ok' );
	like( $props->{SourceProtocolInfo}, qr{http-get:\*:audio/mpeg:\*}, 'CM notify SourceProtocolInfo ok' );
	is( $props->{CurrentConnectionIDs}, 0, 'CM notify CurrentConnectionIDs ok' );
	is( $props->{SinkProtocolInfo}, '', 'CM notify SinkProtocolInfo ok' );
} );
like( $cm_events->{sid}, qr{^uuid:[A-F0-9-]+$}, 'ConnectionManager subscribed ok' );

print "# Subscribing to ContentDirectory...\n";
$cd_events = GENA->new( $cd->geteventsuburl, sub {
	my ( $req, $props ) = @_;
	$sub_count++;
	
	like( $props->{SystemUpdateID}, qr/^\d+$/, 'CD notify SystemUpdateID ok' );
} );
like( $cd_events->{sid}, qr{^uuid:[A-F0-9-]+$}, 'ContentDirectory subscribed ok' );

# Wait for notifications for each service
GENA->wait(2);

is( $sub_count, 2, 'Eventing: 2 notifications received ok' );

ok( $cm_events->renew, 'CM renewed ok' );
ok( $cd_events->renew, 'CD renewed ok' );

ok( $cm_events->unsubscribe, 'CM unsubscribed ok' );
ok( $cd_events->unsubscribe, 'CD unsubscribed ok' );

# Renew after unsubscribe should fail
ok( !$cm_events->renew, 'CM renew after unsubscribe failed ok' );

### ConnectionManager

# Invalid action
{
	my $res = _action( $cm, 'InvalidAction' );
	is( $res->{errorCode}->{t}, 401, 'CM: InvalidAction errorCode ok' );
	is( $res->{errorDescription}->{t}, 'Invalid Action', 'CM: InvalidAction errorDescription ok' );
}

# GetProtocolInfo
{
	my $res = _action( $cm, 'GetProtocolInfo' );
	like( $res->{Source}->{t}, qr{audio/mpeg}, 'CM: GetProtocolInfo Source ok' );
}

# GetCurrentConnectionIDs
{
	my $res = _action( $cm, 'GetCurrentConnectionIDs' );
	is( $res->{ConnectionIDs}->{t}, 0, 'CM: GetCurrentConnectionIDs ConnectionIDs ok' );
}

# GetCurrentConnectionInfo
{
	my $res = _action( $cm, 'GetCurrentConnectionInfo', { ConnectionID => 0 } );
	is( $res->{AVTransportID}->{t}, -1, 'CM: GetCurrentConnectionInfo ok' );
	
	# Test invalid ConnectionID
	$res = _action( $cm, 'GetCurrentConnectionInfo', { ConnectionID => 1 } );
	is( $res->{errorDescription}->{t}, 'Invalid connection reference', 'CM: GetCurrentConnectionInfo invalid ConnectionID ok' );
}

### ContentDirectory

# GetSearchCapabilities
{
	my $res = _action( $cd, 'GetSearchCapabilities' );
	like( $res->{SearchCaps}->{t}, qr/dc:title/, 'CD: GetSearchCapabilities ok' );
}

# GetSortCapabilities
{
	my $res = _action( $cd, 'GetSortCapabilities' );
	like( $res->{SortCaps}->{t}, qr/dc:title/, 'CD: GetSortCapabilities ok' );
}

# GetSystemUpdateID
{
	my $res = _action( $cd, 'GetSystemUpdateID' );
	like( $res->{Id}->{t}, qr/\d+/, 'CD: GetSystemUpdateID ok' );
}

# XXX test triggering a SystemUpdateID change

# Browse top-level menu
{
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => 0,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 1,
		SortCriteria   => '',
	} );
	
	is( $res->{NumberReturned}->{t}, 1, 'CD: Browse ObjectID 0 RequestedCount 1, NumberReturned ok' );
	is( $res->{TotalMatches}->{t}, 2, 'CD: Browse ObjectID 0 RequestedCount 1, TotalMatches ok' );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'container' ] );
	my $container = $menu->{'DIDL-Lite'}->{container};
	is( scalar @{$container}, 1, 'CD: Browse ObjectID 0 RequestedCount 1, container count ok' );
	
	my $item1 = $container->[0];
	is( $item1->{'-id'}, '/music', 'CD: Browse ObjectID 0 RequestedCount 1, container 1 id ok' );
	is( $item1->{'-parentID'}, 0, 'CD: Browse ObjectID 0 RequestedCount 1, container 1 parentID ok' );
	is( $item1->{'-restricted'}, 1, 'CD: Browse ObjectID 0 RequestedCount 1, container 1 restricted ok' );
	is( $item1->{'-searchable'}, 0, 'CD: Browse ObjectID 0 RequestedCount 1, container 1 searchable ok' );
	is( $item1->{'dc:title'}, 'Music', 'CD: Browse ObjectID 0 RequestedCount 1, container 1 dc:title ok' );
	is( $item1->{'upnp:class'}, 'object.container', 'CD: Browse ObjectID 0 RequestedCount 1, container 1 upnp:class ok' );
	
	# Test top-level menu metadata
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => 0,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, 'BrowseMetadata ObjectID 0 TotalMatches is 1' );
	is( $res->{NumberReturned}->{t}, 1, 'BrowseMetadata ObjectID 0 NumberReturned is 1' );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't' );
	$container = $menu->{'DIDL-Lite'}->{container};
	
	is( $container->{'-id'}, 0, 'CD: BrowseMetadata ObjectID 0, id ok' );
	is( $container->{'-parentID'}, -1, 'CD: BrowseMetadata ObjectID 0, parentID ok' );
	is( $container->{'-searchable'}, 1, 'CD: BrowseMetadata ObjectID 0, searchable ok' );
	like( $container->{'dc:title'}, qr/^Logitech Media Server/, 'CD: BrowseMetadata ObjectID 0, dc:title ok' );
}

# Browse music menu
{
	# Fetch first menu item only
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => '/music',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 1,
		SortCriteria   => '',
	} );
	
	is( $res->{NumberReturned}->{t}, 1, 'CD: Browse ObjectID /music RequestedCount 1, NumberReturned ok' );
	is( $res->{TotalMatches}->{t}, 7, 'CD: Browse ObjectID /music RequestedCount 1, TotalMatches ok' );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'container' ] );
	my $container = $menu->{'DIDL-Lite'}->{container};
	is( scalar @{$container}, 1, 'CD: Browse ObjectID /music RequestedCount 1, container count ok' );
	
	my $item1 = $container->[0];
	is( $item1->{'-id'}, '/a', 'CD: Browse ObjectID /music RequestedCount 1, container 1 id ok' );
	is( $item1->{'-parentID'}, '/music', 'CD: Browse ObjectID /music RequestedCount 1, container 1 parentID ok' );
	is( $item1->{'-restricted'}, 1, 'CD: Browse ObjectID /music RequestedCount 1, container 1 restricted ok' );
	is( $item1->{'-searchable'}, 0, 'CD: Browse ObjectID /music RequestedCount 1, container 1 searchable ok' );
	is( $item1->{'dc:title'}, 'Artists', 'CD: Browse ObjectID /music RequestedCount 1, container 1 dc:title ok' );
	is( $item1->{'upnp:class'}, 'object.container', 'CD: Browse ObjectID /music RequestedCount 1, container 1 upnp:class ok' );
	
	# Fetch rest of menu, with sorting
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => '/music',
		Filter         => '*',
		StartingIndex  => 1,
		RequestedCount => 6,
		SortCriteria   => '+dc:title',
	} );
	
	is( $res->{NumberReturned}->{t}, 6, 'CD: Browse ObjectID /music RequestedCount 6, NumberReturned ok' );
	is( $res->{TotalMatches}->{t}, 7, 'CD: Browse ObjectID /music RequestedCount 6, TotalMatches ok' );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'container' ] );
	$container = $menu->{'DIDL-Lite'}->{container};
	is( scalar @{$container}, 6, 'CD: Browse ObjectID /music RequestedCount 6, container count ok' );
	
	# Check sorting is correct
	is( $container->[0]->{'-id'}, '/a', 'CD: Browse ObjectID /music RequestedCount 6, sorted container 1 id ok' );
	is( $container->[-1]->{'-id'}, '/y', 'CD: Browse ObjectID /music RequestedCount 6, sorted container 6 id ok' );
	
	# Test music menu metadata
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => '/music',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, 'BrowseMetadata ObjectID /music TotalMatches is 1' );
	is( $res->{NumberReturned}->{t}, 1, 'BrowseMetadata ObjectID /music NumberReturned is 1' );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't' );
	$container = $menu->{'DIDL-Lite'}->{container};
	
	is( $container->{'-id'}, '/music', 'CD: BrowseMetadata ObjectID /music, id ok' );
	is( $container->{'-parentID'}, 0, 'CD: BrowseMetadata ObjectID /music, parentID ok' );
	is( $container->{'-searchable'}, 0, 'CD: BrowseMetadata ObjectID /music, searchable ok' );
	is( $container->{'dc:title'}, 'Music', 'CD: BrowseMetadata ObjectID /music, dc:title ok' );
}

# Browse video menu
{
	# Fetch first menu item only
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => '/video',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 1,
		SortCriteria   => '',
	} );
	
	is( $res->{NumberReturned}->{t}, 1, 'CD: Browse ObjectID /video RequestedCount 1, NumberReturned ok' );
	is( $res->{TotalMatches}->{t}, 2, 'CD: Browse ObjectID /video RequestedCount 1, TotalMatches ok' );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'container' ] );
	my $container = $menu->{'DIDL-Lite'}->{container};
	is( scalar @{$container}, 1, 'CD: Browse ObjectID /video RequestedCount 1, container count ok' );
	
	my $item1 = $container->[0];
	is( $item1->{'-id'}, '/v', 'CD: Browse ObjectID /video RequestedCount 1, container 1 id ok' );
	is( $item1->{'-parentID'}, '/video', 'CD: Browse ObjectID /video RequestedCount 1, container 1 parentID ok' );
	is( $item1->{'-restricted'}, 1, 'CD: Browse ObjectID /video RequestedCount 1, container 1 restricted ok' );
	is( $item1->{'-searchable'}, 0, 'CD: Browse ObjectID /video RequestedCount 1, container 1 searchable ok' );
	is( $item1->{'dc:title'}, 'Video Folder', 'CD: Browse ObjectID /video RequestedCount 1, container 1 dc:title ok' );
	is( $item1->{'upnp:class'}, 'object.container', 'CD: Browse ObjectID /video RequestedCount 1, container 1 upnp:class ok' );
	
	# Fetch rest of menu, with sorting
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => '/video',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 2,
		SortCriteria   => '+dc:title',
	} );
	
	is( $res->{NumberReturned}->{t}, 2, 'CD: Browse ObjectID /video RequestedCount 2, NumberReturned ok' );
	is( $res->{TotalMatches}->{t}, 2, 'CD: Browse ObjectID /video RequestedCount 2, TotalMatches ok' );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'container' ] );
	$container = $menu->{'DIDL-Lite'}->{container};
	is( scalar @{$container}, 2, 'CD: Browse ObjectID /video RequestedCount 2, container count ok' );
	
	# Check sorting is correct
	is( $container->[0]->{'-id'}, '/va', 'CD: Browse ObjectID /video RequestedCount 2, sorted container 1 id ok' );
	is( $container->[-1]->{'-id'}, '/v', 'CD: Browse ObjectID /video RequestedCount 2, sorted container 2 id ok' );
	
	# Test video menu metadata
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => '/video',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, 'BrowseMetadata ObjectID /video TotalMatches is 1' );
	is( $res->{NumberReturned}->{t}, 1, 'BrowseMetadata ObjectID /video NumberReturned is 1' );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't' );
	$container = $menu->{'DIDL-Lite'}->{container};
	
	is( $container->{'-id'}, '/video', 'CD: BrowseMetadata ObjectID /video, id ok' );
	is( $container->{'-parentID'}, 0, 'CD: BrowseMetadata ObjectID /video, parentID ok' );
	is( $container->{'-searchable'}, 0, 'CD: BrowseMetadata ObjectID /video, searchable ok' );
	is( $container->{'dc:title'}, 'Video', 'CD: BrowseMetadata ObjectID /video, dc:title ok' );
}
exit;

# Test localized dc:title values
{
	local $ENV{ACCEPT_LANGUAGE} = 'de,en-us;q=0.7,en;q=0.3';
	
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => '/music',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '-dc:title',
	} );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'container' ] );
	my $container = $menu->{'DIDL-Lite'}->{container};
	
	is( $container->[0]->{'dc:title'}, 'Wiedergabelisten', 'CD: Browse ObjectID /music Accept-Language: de, sorted container 1 ok' );
	is( $container->[-1]->{'dc:title'}, 'Alben', 'CD: Browse ObjectID /music Accept-Language: de, sorted container 7 ok' );
}

### /a artists menu

# Test browsing artists menu
my $artist;
{
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => '/a',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 100,
		SortCriteria   => '',
	} );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'container' ] );
	my $container = $menu->{'DIDL-Lite'}->{container};
	
	# Skip Various Artists artist if it's there
	$artist = $container->[0]->{'dc:title'} eq 'Various Artists' ? $container->[1] : $container->[0];
	
	like( $artist->{'-id'}, qr{^/a/\d+/l$}, 'Artist container id ok' );
	is( $artist->{'-parentID'}, '/a', 'Artist container parentID ok' );
	ok( $artist->{'dc:title'}, 'Artist container dc:title ok' );
	is( $artist->{'upnp:class'}, 'object.container.person.musicArtist', 'Artist container upnp:class ok' );
	
	# Test BrowseMetadata on artist item
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => '/a',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, '/a BrowseMetadata TotalMatches is 1' );
	is( $res->{NumberReturned}->{t}, 1, '/a BrowseMetadata NumberReturned is 1' );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't' );
	$container = $menu->{'DIDL-Lite'}->{container};
	
	is( $container->{'-id'}, '/a', '/a BrowseMetadata id ok' );
	is( $container->{'-parentID'}, '/music', '/a BrowseMetadata parentID ok' );
	is( $container->{'dc:title'}, 'Artists', '/a BrowseMetadata dc:title ok' );
	is( $container->{'upnp:class'}, 'object.container', '/a BrowseMetadata upnp:class ok' );
	
	# Test BrowseMetadata on an artist
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => $artist->{'-id'},
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, 'Artist BrowseMetadata TotalMatches is 1' );
	is( $res->{NumberReturned}->{t}, 1, 'Artist BrowseMetadata NumberReturned is 1' );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't' );
	$container = $menu->{'DIDL-Lite'}->{container};
	
	is( $container->{'-id'}, $artist->{'-id'}, 'Artist BrowseMetadata id ok' );
	is( $container->{'-parentID'}, $artist->{'-parentID'}, 'Artist BrowseMetadata parentID ok' );
	is( $container->{'dc:title'}, $artist->{'dc:title'}, 'Artist BrowseMetadata dc:title ok' );
	is( $container->{'upnp:class'}, $artist->{'upnp:class'}, 'Artist BrowseMetadata upnp:class ok' );
	
	# Test requesting only 1 artist (used by iOS app 'Dixim DMC')
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => '/a',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 1,
		SortCriteria   => '',
	} );
	
	is( $res->{NumberReturned}->{t}, 1, 'Artist BrowseDirectChildren 0 1 ok' );
}

# Test browsing an artist's menu (albums)
my $album;
{
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => $artist->{'-id'},
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 100,
		SortCriteria   => '', # XXX test sort
	} );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'container' ] );
	my $container = $menu->{'DIDL-Lite'}->{container};
	
	$album = $container->[0];
	like( $album->{'-id'}, qr{^/a/\d+/l/\d+/t$}, 'Album container id ok' );
	is( $album->{'-parentID'}, $artist->{'-id'}, 'Album container parentID ok' );
	ok( $album->{'dc:title'}, 'Album container dc:title ok' );
	like( $album->{'dc:date'}, qr/^\d{4}-\d{2}-\d{2}$/, 'Album container dc:date ok' );
	ok( $album->{'dc:creator'}, 'Album container dc:creator ok' );
	ok( $album->{'upnp:artist'}, 'Album container upnp:artist ok' );
	ok( $album->{'upnp:albumArtURI'}, 'Album container upnp:albumArtURI ok' );
	#cmp_ok( $album->{'-childCount'}, '>', 0, 'Album container childCount ok' );
	is( $album->{'upnp:class'}, 'object.container.album.musicAlbum', 'Album container upnp:class ok' );
	
	# Test BrowseMetadata + filtering to avoid getting some of the album's items
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => $album->{'-id'},
		Filter         => 'upnp:artist',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, 'Album BrowseMetadata TotalMatches is 1' );
	is( $res->{NumberReturned}->{t}, 1, 'Album BrowseMetadata NumberReturned is 1' );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't' );
	$container = $menu->{'DIDL-Lite'}->{container};
	
	is( $container->{'-id'}, $album->{'-id'}, 'Album BrowseMetadata id ok' );
	is( $container->{'-parentID'}, $album->{'-parentID'}, 'Album BrowseMetadata parentID ok' );
	is( $container->{'dc:title'}, $album->{'dc:title'}, 'Album BrowseMetadata dc:title ok' ); # required
	is( $container->{'upnp:class'}, $album->{'upnp:class'}, 'Album BrowseMetadata upnp:class ok' ); # required
	is( $container->{'upnp:artist'}, $album->{'upnp:artist'}, 'Album BrowseMetadata upnp:artist ok' ); # in filter
	ok( !exists $container->{'dc:creator'}, 'Album BrowseMetadata dc:creator filtered out' ); # optional
	ok( !exists $container->{'upnp:albumArtURI'}, 'Album BrowseMetadata upnp:albumArtURI filtered out' ); # optional
	ok( !exists $container->{'dc:date'}, 'Album BrowseMetadata dc:date filtered out' ); # optional
}

# Test browsing an album's menu (tracks)
my $track;
{
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => $album->{'-id'},
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 100,
		SortCriteria   => '', # XXX test sort
	} );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'item' ] );
	my $item = $menu->{'DIDL-Lite'}->{item};
	
	$track = $item->[0];
	like( $track->{'-id'}, qr{^/a/\d+/l/\d+/t/\d+$}, 'Track item id ok' );
	is( $track->{'-parentID'}, $album->{'-id'}, 'Track item parentID ok' );
	ok( $track->{'dc:contributor'}, 'Track item dc:contributor ok' );
	ok( $track->{'dc:creator'}, 'Track item dc:creator ok' );
	like( $track->{'dc:date'}, qr/^\d{4}-\d{2}-\d{2}$/, 'Track item dc:date ok' );
	ok( $track->{'dc:title'}, 'Track item dc:title ok' );
	ok( $track->{'upnp:album'}, 'Track item upnp:album ok' );
	ok( $track->{'upnp:albumArtURI'}, 'Track item upnp:albumArtURI ok' );
	ok( $track->{'upnp:artist'}, 'Track item upnp:artist ok' );
	is( $track->{'upnp:class'}, 'object.item.audioItem.musicTrack', 'Track item upnp:class ok' );
	ok( $track->{'upnp:genre'}, 'Track item upnp:genre ok' );
	like( $track->{'upnp:originalTrackNumber'}, qr/^\d+$/, 'Track item upnp:originalTrackNumber ok' );
	
	$track->{res} = $track->{res}->[0] if ref $track->{res} eq 'ARRAY';
	my $res = $track->{res};
	like( $res->{'-bitrate'}, qr/^\d+$/, 'Track item res@bitrate ok' );
	like( $res->{'-duration'}, qr/^\d+:\d{2}:\d{2}(\.\d+)?$/, 'Track item res@duraton ok' );
	like( $res->{'-protocolInfo'}, qr{^http-get:\*:audio/[^:]+:\*$}, 'Track item res@protocolInfo ok' );
	like( $res->{'-sampleFrequency'}, qr/^\d+$/, 'Track item res@sampleFrequency ok' );
	like( $res->{'-size'}, qr/^\d+$/, 'Track item res@size ok' );
	like( $res->{t}, qr{^http://[^/]+/music/\d+/download}, 'Track item res URL ok' );
}

# Test BrowseMetadata on track + filter
{
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => $track->{'-id'},
		Filter         => 'upnp:album,upnp:albumArtURI,res,res@bitrate',
		StartingIndex  => 0,
		RequestedCount => 100,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, 'Track BrowseMetadata TotalMatches is 1' );
	is( $res->{NumberReturned}->{t}, 1, 'Track BrowseMetadata NumberReturned is 1' );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $item = $menu->{'DIDL-Lite'}->{item};
	
	is( $item->{'-id'}, $track->{'-id'}, 'Track BrowseMetadata id ok' );
	is( $item->{'-parentID'}, $track->{'-parentID'}, 'Track BrowseMetadata parentID ok' );
	is( $item->{'dc:title'}, $track->{'dc:title'}, 'Track BrowseMetadata dc:title ok' ); # required
	is( $item->{'upnp:class'}, $track->{'upnp:class'}, 'Track BrowseMetadata upnp:class ok' ); # required
	is( $item->{'upnp:album'}, $track->{'upnp:album'}, 'Track BrowseMetadata upnp:album ok' ); # in filter
	is( $item->{'upnp:albumArtURI'}, $track->{'upnp:albumArtURI'}, 'Track BrowseMetadata upnp:albumArtURI ok' ); # in filter
	ok( !exists $item->{'dc:contributor'}, 'Track BrowseMetadata dc:contributor filtered out' ); # optional
	ok( !exists $item->{'dc:creator'}, 'Track BrowseMetadata dc:creator filtered out' ); # optional
	ok( !exists $item->{'dc:date'}, 'Track BrowseMetadata dc:date filtered out' ); # optional
	ok( !exists $item->{'upnp:artist'}, 'Track BrowseMetadata upnp:artist filtered out' ); # optional
	ok( !exists $item->{'upnp:genre'}, 'Track BrowseMetadata upnp:genre filtered out' ); # optional
	ok( !exists $item->{'upnp:originalTrackNumber'}, 'Track BrowseMetadata upnp:originalTrackNumber filtered out' ); # optional
	
	my $res = $item->{res};
	$res = $res->[0] if ref $res eq 'ARRAY';
	is( $res->{'-bitrate'}, $track->{res}->{'-bitrate'}, 'Track BrowseMetadata item res@bitrate ok' ); # in filter
	ok( !exists $res->{'-duration'}, 'Track BrowseMetadata item res@duraton filtered out' ); # optional
	is( $res->{'-protocolInfo'}, $track->{res}->{'-protocolInfo'}, 'Track BrowseMetadata item res@protocolInfo ok' ); # required
	ok( !exists $res->{'-sampleFrequency'}, 'Track BrowseMetadata item res@sampleFrequency filtered out' ); # optional
	ok( !exists $res->{'-size'}, 'Track BrowseMetadata item res@size filtered out' ); # optional
	is( $res->{t}, $track->{res}->{t}, 'Track BrowseMetadata item res URL ok' ); # in filter
}

### /l albums tree

# /l
{
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => '/l',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, '/l BrowseMetadata TotalMatches is 1' );
	is( $res->{NumberReturned}->{t}, 1, '/l BrowseMetadata NumberReturned is 1' );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $c = $menu->{'DIDL-Lite'}->{container};
	
	is( $c->{'-id'}, '/l', '/l BrowseMetadata id ok' );
	is( $c->{'-parentID'}, '/music', '/l BrowseMetadata parentID ok' );
	is( $c->{'dc:title'}, 'Albums', '/l BrowseMetadata dc:title ok' );
	is( $c->{'upnp:class'}, 'object.container', '/l BrowseMetadata upnp:class ok' );
	
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => '/l',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 10,
		SortCriteria   => '',
	} );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'container' ] );
	$c = $menu->{'DIDL-Lite'}->{container};
	
	is( scalar @{$c}, 10, '/l child count ok' );
	
	$album = $c->[0];
	like( $album->{'-id'}, qr{^/l/\d+/t$}, '/l album id ok' );
	is( $album->{'-parentID'}, '/l', '/l album parentID ok' );
	#cmp_ok( $album->{'-childCount'}, '>', 0, '/l album childCount ok' );
	is( $album->{'upnp:class'}, 'object.container.album.musicAlbum', '/l album upnp:class ok' );	
}

# /l/<id>/t
{
	my $aid = $album->{'-id'};
	
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => $aid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, "$aid BrowseMetadata TotalMatches is 1" );
	is( $res->{NumberReturned}->{t}, 1, "$aid BrowseMetadata NumberReturned is 1" );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $c = $menu->{'DIDL-Lite'}->{container};
	
	is_deeply( $c, $album, "$aid BrowseMetadata ok" );
	
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => $aid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 100,
		SortCriteria   => '',
	} );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'item' ] );
	my $items = $menu->{'DIDL-Lite'}->{item};
	
	$track = $items->[0];
	
	like( $track->{'-id'}, qr{^$aid/\d+$}, "$aid BrowseDirectChildren id ok" );
	is( $track->{'-parentID'}, $aid, "$aid BrowseDirectChildren parentID ok" );
}

# /l/<id>/t/<id>
{
	my $tid = $track->{'-id'};
	
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => $tid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, "$tid BrowseMetadata TotalMatches is 1" );
	is( $res->{NumberReturned}->{t}, 1, "$tid BrowseMetadata NumberReturned is 1" );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $item = $menu->{'DIDL-Lite'}->{item};
	
	is_deeply( $item, $track, "$tid BrowseMetadata ok" );
}

### /g genres tree

# /g
my $genre;
{
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => '/g',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, '/g BrowseMetadata TotalMatches is 1' );
	is( $res->{NumberReturned}->{t}, 1, '/g BrowseMetadata NumberReturned is 1' );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $c = $menu->{'DIDL-Lite'}->{container};
	
	is( $c->{'-id'}, '/g', '/g BrowseMetadata id ok' );
	is( $c->{'-parentID'}, '/music', '/g BrowseMetadata parentID ok' );
	is( $c->{'dc:title'}, 'Genres', '/g BrowseMetadata dc:title ok' );
	is( $c->{'upnp:class'}, 'object.container', '/g BrowseMetadata upnp:class ok' );
	
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => '/g',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 10,
		SortCriteria   => '',
	} );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'container' ] );
	$c = $menu->{'DIDL-Lite'}->{container};
	
	is( scalar @{$c}, 10, '/g child count ok' );
	
	$genre = $c->[0];
	like( $genre->{'-id'}, qr{^/g/\d+/a$}, '/g genre id ok' );
	is( $genre->{'-parentID'}, '/g', '/g genre parentID ok' );
	is( $genre->{'upnp:class'}, 'object.container.genre.musicGenre', '/g genre upnp:class ok' );
}

# /g/<id>/a
{
	my $gid = $genre->{'-id'};
	
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => $gid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, "$gid BrowseMetadata TotalMatches is 1" );
	is( $res->{NumberReturned}->{t}, 1, "$gid BrowseMetadata NumberReturned is 1" );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $c = $menu->{'DIDL-Lite'}->{container};
	
	is_deeply( $c, $genre, "$gid BrowseMetadata ok" );
	
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => $gid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 100,
		SortCriteria   => '',
	} );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'container' ] );
	$c = $menu->{'DIDL-Lite'}->{container};
	
	$artist = $c->[0];
	
	like( $artist->{'-id'}, qr{^$gid/\d+/l$}, "$gid BrowseDirectChildren id ok" );
	is( $artist->{'-parentID'}, $gid, "$gid BrowseDirectChildren parentID ok" );
}

# /g/<id>/a/<id>/l
{
	my $aid = $artist->{'-id'};
	
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => $aid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, "$aid BrowseMetadata TotalMatches is 1" );
	is( $res->{NumberReturned}->{t}, 1, "$aid BrowseMetadata NumberReturned is 1" );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $c = $menu->{'DIDL-Lite'}->{container};
	
	is_deeply( $c, $artist, "$aid BrowseMetadata ok" );
	
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => $aid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 100,
		SortCriteria   => '',
	} );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't' );
	$c = $menu->{'DIDL-Lite'}->{container};
	
	$album = $c;
	
	like( $album->{'-id'}, qr{^$aid/\d+/t$}, "$aid BrowseDirectChildren id ok" );
	is( $album->{'-parentID'}, $aid, "$aid BrowseDirectChildren parentID ok" );
}

# /g/<id>/a/<id>/l/<id>/t
{
	my $aid = $album->{'-id'};
	
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => $aid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, "$aid BrowseMetadata TotalMatches is 1" );
	is( $res->{NumberReturned}->{t}, 1, "$aid BrowseMetadata NumberReturned is 1" );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $c = $menu->{'DIDL-Lite'}->{container};
	
	is_deeply( $c, $album, "$aid BrowseMetadata ok" );
	
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => $aid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 100,
		SortCriteria   => '',
	} );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'item' ] );
	my $items = $menu->{'DIDL-Lite'}->{item};
	
	$track = $items->[0];
	
	like( $track->{'-id'}, qr{^$aid/\d+$}, "$aid BrowseDirectChildren id ok" );
	is( $track->{'-parentID'}, $aid, "$aid BrowseDirectChildren parentID ok" );
}

# /g/<id>/a/<id>/l/<id>/t/<id>
{
	my $tid = $track->{'-id'};
	
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => $tid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, "$tid BrowseMetadata TotalMatches is 1" );
	is( $res->{NumberReturned}->{t}, 1, "$tid BrowseMetadata NumberReturned is 1" );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $item = $menu->{'DIDL-Lite'}->{item};
	
	is_deeply( $item, $track, "$tid BrowseMetadata ok" );
}

### /y years tree

# /y
my $year;
{
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => '/y',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, '/y BrowseMetadata TotalMatches is 1' );
	is( $res->{NumberReturned}->{t}, 1, '/y BrowseMetadata NumberReturned is 1' );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $c = $menu->{'DIDL-Lite'}->{container};
	
	is( $c->{'-id'}, '/y', '/y BrowseMetadata id ok' );
	is( $c->{'-parentID'}, '/music', '/y BrowseMetadata parentID ok' );
	is( $c->{'dc:title'}, 'Years', '/y BrowseMetadata dc:title ok' );
	is( $c->{'upnp:class'}, 'object.container', '/y BrowseMetadata upnp:class ok' );
	
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => '/y',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 10,
		SortCriteria   => '',
	} );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'container' ] );
	$c = $menu->{'DIDL-Lite'}->{container};
	
	is( scalar @{$c}, 10, '/y child count ok' );
	
	# Make sure to get a proper year
	($year) = grep { $_->{'dc:title'} =~ /^(19|20)/ } reverse @{$c};
	
	like( $year->{'-id'}, qr{^/y/\d+/l$}, '/y year id ok' );
	is( $year->{'-parentID'}, '/y', '/y year parentID ok' );
	is( $year->{'upnp:class'}, 'object.container', '/y year upnp:class ok' );
}

# /y/<id>/l
{
	my $yid = $year->{'-id'};
	
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => $yid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, "$yid BrowseMetadata TotalMatches is 1" );
	is( $res->{NumberReturned}->{t}, 1, "$yid BrowseMetadata NumberReturned is 1" );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $c = $menu->{'DIDL-Lite'}->{container};
	
	is_deeply( $c, $year, "$yid BrowseMetadata ok" );
	
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => $yid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 100,
		SortCriteria   => '',
	} );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'container' ] );
	$c = $menu->{'DIDL-Lite'}->{container};
	
	$album = $c->[0];
	
	like( $album->{'-id'}, qr{^$yid/\d+/t$}, "$yid BrowseDirectChildren id ok" );
	is( $album->{'-parentID'}, $yid, "$yid BrowseDirectChildren parentID ok" );
}

# /y/<id>/l/<id>/t
{
	my $aid = $album->{'-id'};
	
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => $aid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, "$aid BrowseMetadata TotalMatches is 1" );
	is( $res->{NumberReturned}->{t}, 1, "$aid BrowseMetadata NumberReturned is 1" );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $c = $menu->{'DIDL-Lite'}->{container};
	
	is_deeply( $c, $album, "$aid BrowseMetadata ok" );
}

### /n new music tree

# /n
{
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => '/n',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, '/n BrowseMetadata TotalMatches is 1' );
	is( $res->{NumberReturned}->{t}, 1, '/n BrowseMetadata NumberReturned is 1' );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $c = $menu->{'DIDL-Lite'}->{container};
	
	is( $c->{'-id'}, '/n', '/n BrowseMetadata id ok' );
	is( $c->{'-parentID'}, '/music', '/n BrowseMetadata parentID ok' );
	is( $c->{'dc:title'}, 'New Music', '/n BrowseMetadata dc:title ok' );
	is( $c->{'upnp:class'}, 'object.container', '/n BrowseMetadata upnp:class ok' );
	
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => '/n',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 200, # to check that we only get 100 (default age limit pref)
		SortCriteria   => '',
	} );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'container' ] );
	$c = $menu->{'DIDL-Lite'}->{container};
	
	is( scalar @{$c}, 100, '/n child count ok (limited to 100)' );
	
	$album = $c->[0];
	like( $album->{'-id'}, qr{^/n/\d+/t$}, '/n album id ok' );
	is( $album->{'-parentID'}, '/n', '/n album parentID ok' );
	#cmp_ok( $album->{'-childCount'}, '>', 0, '/n album childCount ok' );
	is( $album->{'upnp:class'}, 'object.container.album.musicAlbum', '/n album upnp:class ok' );	
}

# /n/<id>/t
{
	my $aid = $album->{'-id'};
	
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => $aid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, "$aid BrowseMetadata TotalMatches is 1" );
	is( $res->{NumberReturned}->{t}, 1, "$aid BrowseMetadata NumberReturned is 1" );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $c = $menu->{'DIDL-Lite'}->{container};
	
	is_deeply( $c, $album, "$aid BrowseMetadata ok" );
	
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => $aid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 100,
		SortCriteria   => '',
	} );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'item' ] );
	my $items = $menu->{'DIDL-Lite'}->{item};
	
	$track = $items->[0];
	
	like( $track->{'-id'}, qr{^$aid/\d+$}, "$aid BrowseDirectChildren id ok" );
	is( $track->{'-parentID'}, $aid, "$aid BrowseDirectChildren parentID ok" );
}

# /n/<id>/t/<id>
{
	my $tid = $track->{'-id'};
	
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => $tid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, "$tid BrowseMetadata TotalMatches is 1" );
	is( $res->{NumberReturned}->{t}, 1, "$tid BrowseMetadata NumberReturned is 1" );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $item = $menu->{'DIDL-Lite'}->{item};
	
	is_deeply( $item, $track, "$tid BrowseMetadata ok" );
}

### /m music folder tree

print "# Note: /m musicfolder tests require an artist/album/track folder structure\n";

# /m
my $folder;
{
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => '/m',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, '/m BrowseMetadata TotalMatches is 1' );
	is( $res->{NumberReturned}->{t}, 1, '/m BrowseMetadata NumberReturned is 1' );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $c = $menu->{'DIDL-Lite'}->{container};
	
	is( $c->{'-id'}, '/m', '/m BrowseMetadata id ok' );
	is( $c->{'-parentID'}, '/music', '/m BrowseMetadata parentID ok' );
	is( $c->{'dc:title'}, 'Music Folder', '/m BrowseMetadata dc:title ok' );
	is( $c->{'upnp:class'}, 'object.container', '/m BrowseMetadata upnp:class ok' );
	
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => '/m',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 10,
		SortCriteria   => '',
	} );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'container' ] );
	$c = $menu->{'DIDL-Lite'}->{container};
	
	is( scalar @{$c}, 10, '/m child count ok' );
	
	$folder = $c->[0];
	like( $folder->{'-id'}, qr{^/m/\d+/m$}, '/m folder id ok' );
	is( $folder->{'-parentID'}, '/m', '/m folder parentID ok' );
	is( $folder->{'upnp:class'}, 'object.container.storageFolder', '/m folder upnp:class ok' );	
}

# /m/<id>/m
{
	my $fid = $folder->{'-id'};
	
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => $fid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, "$fid BrowseMetadata TotalMatches is 1" );
	is( $res->{NumberReturned}->{t}, 1, "$fid BrowseMetadata NumberReturned is 1" );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $c = $menu->{'DIDL-Lite'}->{container};
	
	is_deeply( $c, $folder, "$fid BrowseMetadata ok" );
	
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => $fid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 100,
		SortCriteria   => '',
	} );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'container' ] );
	$c = $menu->{'DIDL-Lite'}->{container};
	
	$folder = $c->[0];
	
	like( $folder->{'-id'}, qr{^$fid/\d+/m$}, "$fid BrowseDirectChildren id ok" );
	is( $folder->{'-parentID'}, $fid, "$fid BrowseDirectChildren parentID ok" );
}

# /m/<id>/m/<id>/m (an album's menu, at least in my dir structure)
{
	my $fid = $folder->{'-id'};
	
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => $fid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, "$fid BrowseMetadata TotalMatches is 1" );
	is( $res->{NumberReturned}->{t}, 1, "$fid BrowseMetadata NumberReturned is 1" );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $c = $menu->{'DIDL-Lite'}->{container};
	
	is_deeply( $c, $folder, "$fid BrowseMetadata ok" );
	
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => $fid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 100,
		SortCriteria   => '',
	} );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'item' ] );
	my $items = $menu->{'DIDL-Lite'}->{item};
	
	$track = $items->[0];
	
	# Handle changed track ID
	my $fidtrack = $fid;
	$fidtrack =~ s/m$/t/;
	
	like( $track->{'-id'}, qr{^$fidtrack/\d+$}, "$fid BrowseDirectChildren id ok" );
	is( $track->{'-parentID'}, $fid, "$fid BrowseDirectChildren parentID ok" );
}

# /m/<id>/m/<id>/t/<id>
{
	my $tid = $track->{'-id'};
	
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => $tid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, "$tid BrowseMetadata TotalMatches is 1" );
	is( $res->{NumberReturned}->{t}, 1, "$tid BrowseMetadata NumberReturned is 1" );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $item = $menu->{'DIDL-Lite'}->{item};
	
	is_deeply( $item, $track, "$tid BrowseMetadata ok" );
}

### /p playlists tree

print "# These tests require at least 1 playlist\n";

# /p
my $playlist;
{
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => '/p',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, '/p BrowseMetadata TotalMatches is 1' );
	is( $res->{NumberReturned}->{t}, 1, '/p BrowseMetadata NumberReturned is 1' );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $c = $menu->{'DIDL-Lite'}->{container};
	
	is( $c->{'-id'}, '/p', '/p BrowseMetadata id ok' );
	is( $c->{'-parentID'}, '/music', '/p BrowseMetadata parentID ok' );
	is( $c->{'dc:title'}, 'Playlists', '/p BrowseMetadata dc:title ok' );
	is( $c->{'upnp:class'}, 'object.container', '/p BrowseMetadata upnp:class ok' );
	
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => '/p',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 100,
		SortCriteria   => '',
	} );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'container' ] );
	$c = $menu->{'DIDL-Lite'}->{container};
	
	cmp_ok( scalar @{$c}, '>=', 1, '/p child count ok' );
	
	$playlist = $c->[0];
	like( $playlist->{'-id'}, qr{^/p/\d+/t$}, '/p playlist id ok' );
	is( $playlist->{'-parentID'}, '/p', '/p playlist parentID ok' );
	is( $playlist->{'upnp:class'}, 'object.container.playlistContainer', '/p playlist upnp:class ok' );	
}

# /p/<id>/t
{
	my $pid = $playlist->{'-id'};
	
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => $pid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, "$pid BrowseMetadata TotalMatches is 1" );
	is( $res->{NumberReturned}->{t}, 1, "$pid BrowseMetadata NumberReturned is 1" );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $c = $menu->{'DIDL-Lite'}->{container};
	
	is_deeply( $c, $playlist, "$pid BrowseMetadata ok" );
	
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => $pid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 10,
		SortCriteria   => '',
	} );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $items = $menu->{'DIDL-Lite'}->{item};
	
	$track = $items->[0];
	
	like( $track->{'-id'}, qr{^$pid/\d+$}, "$pid BrowseDirectChildren id ok" );
	is( $track->{'-parentID'}, $pid, "$pid BrowseDirectChildren parentID ok" );
}

# /p/<id>/t/<id>
{
	my $tid = $track->{'-id'};
	
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => $tid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, "$tid BrowseMetadata TotalMatches is 1" );
	is( $res->{NumberReturned}->{t}, 1, "$tid BrowseMetadata NumberReturned is 1" );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $item = $menu->{'DIDL-Lite'}->{item};
	
	is_deeply( $item, $track, "$tid BrowseMetadata ok" );
}

### Special /t/<id> track ID
{
	my ($id) = $track->{'-id'} =~ m{t/(\d+)};
	my $tid = "/t/${id}";
	
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => $tid,
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, "$tid BrowseMetadata TotalMatches is 1" );
	is( $res->{NumberReturned}->{t}, 1, "$tid BrowseMetadata NumberReturned is 1" );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $item = $menu->{'DIDL-Lite'}->{item};
	
	# Fix IDs
	$track->{'-id'} = $tid;
	$track->{'-parentID'} = '/t';
	
	is_deeply( $item, $track, "$tid BrowseMetadata ok" );
}

### All Videos (/va)

# Test browsing All Videos menu
my $video;
{
	my $res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseDirectChildren',
		ObjectID       => '/va',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 100,
		SortCriteria   => '',
	} );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't', array => [ 'container' ] );
	my $container = $menu->{'DIDL-Lite'}->{container};
	
	# Skip Various Artists artist if it's there
	$video = $container->[0];
	
	like( $video->{'-id'}, qr{^/va/\d+/v$}, 'Video container id ok' );
	is( $video->{'-parentID'}, '/a', 'Video container parentID ok' );
	ok( $video->{'dc:title'}, 'Video container dc:title ok' );
	ok( $video->{'upnp:album'}, 'Video container upnp:album ok' );
	is( $video->{'upnp:class'}, 'object.container.person.musicArtist', 'Video container upnp:class ok' );
	
	# Test BrowseMetadata on videos item
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => '/va',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, '/va BrowseMetadata TotalMatches is 1' );
	is( $res->{NumberReturned}->{t}, 1, '/va BrowseMetadata NumberReturned is 1' );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't' );
	$container = $menu->{'DIDL-Lite'}->{container};
	
	is( $container->{'-id'}, '/va', '/va BrowseMetadata id ok' );
	is( $container->{'-parentID'}, '/video', '/va BrowseMetadata parentID ok' );
	is( $container->{'dc:title'}, 'All Videos', '/va BrowseMetadata dc:title ok' );
	is( $container->{'upnp:class'}, 'object.container', '/va BrowseMetadata upnp:class ok' );
	
	# Test BrowseMetadata on a video
	$res = _action( $cd, 'Browse', {
		BrowseFlag     => 'BrowseMetadata',
		ObjectID       => $video->{'-id'},
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 0,
		SortCriteria   => '',
	} );
	
	is( $res->{TotalMatches}->{t}, 1, 'Video BrowseMetadata TotalMatches is 1' );
	is( $res->{NumberReturned}->{t}, 1, 'Video BrowseMetadata NumberReturned is 1' );
	
	$menu = xml2hash( $res->{Result}->{t}, text => 't' );
	$container = $menu->{'DIDL-Lite'}->{container};
	
	is( $container->{'-id'}, $video->{'-id'}, 'Video BrowseMetadata id ok' );
	is( $container->{'-parentID'}, $video->{'-parentID'}, 'Video BrowseMetadata parentID ok' );
	is( $container->{'dc:title'}, $video->{'dc:title'}, 'Video BrowseMetadata dc:title ok' );
	is( $container->{'upnp:album'}, $video->{'upnp:album'}, 'Video BrowseMetadata upnp:album ok' );
	is( $container->{'upnp:class'}, $video->{'upnp:class'}, 'Video BrowseMetadata upnp:class ok' );
}

### Search

# Windows 7 WMP uses this query to build a complete index of all audio tracks on the server
{	
	my $res = _action( $cd, 'Search', {
		ContainerID    => 0,
		SearchCriteria => 'upnp:class derivedfrom "object.item.audioItem" and @refID exists false',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 200,
		SortCriteria   => '+upnp:artist,+upnp:album,+upnp:originalTrackNumber,+dc:title',
	} );
	
	cmp_ok( $res->{TotalMatches}->{t}, '>', 0, "Win7 Search TotalMatches is >0" );
	cmp_ok( $res->{NumberReturned}->{t}, '>', 0, "Win7 Search NumberReturned is >0" );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $items = $menu->{'DIDL-Lite'}->{item};
	
	$track = $items->[0];
	
	like( $track->{'-id'}, qr{^/t/\d+$}, 'Win7 Search result id ok' );
	is( $track->{'-parentID'}, '/t', 'Win7 Search result parentID ok' );
}

# Revue Media Player 1.0 uses this query
{
	my $res = _action( $cd, 'Search', {
		ContainerID    => 0,
		SearchCriteria => '(dc:title contains "david") or (dc:creator contains "david") or (upnp:artist contains "david") or (upnp:genre contains "david") or (upnp:album contains "david")',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 10,
		SortCriteria   => '+dc:title',
	} );
	
	cmp_ok( $res->{TotalMatches}->{t}, '>', 0, "Revue Search TotalMatches is >0" );
	cmp_ok( $res->{NumberReturned}->{t}, '>', 0, "Revue Search NumberReturned is >0" );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $items = $menu->{'DIDL-Lite'}->{item};
	
	$track = $items->[0];
	
	like( $track->{'-id'}, qr{^/t/\d+$}, 'Revue Search result id ok' );
	is( $track->{'-parentID'}, '/t', 'Revue Search result parentID ok' );
}

# Test searching for new videos only
{	
	my $res = _action( $cd, 'Search', {
		ContainerID    => 0,
		SearchCriteria => 'pv:lastUpdated > 0 and upnp:class derivedfrom "object.item.videoItem"',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 10,
		SortCriteria   => '-pv:lastUpdated',
	} );
	
	cmp_ok( $res->{TotalMatches}->{t}, '>', 0, "Video Search TotalMatches is >0" );
	cmp_ok( $res->{NumberReturned}->{t}, '>', 0, "Video Search NumberReturned is >0" );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $items = $menu->{'DIDL-Lite'}->{item};
	
	my $video = $items->[0];
	
	like( $video->{'-id'}, qr{^/v/[0-9a-f]{8}$}, 'Video Search result id ok' );
	is( $video->{'-parentID'}, '/v', 'Video Search result parentID ok' );
}

# Test searching for images
{	
	my $res = _action( $cd, 'Search', {
		ContainerID    => 0,
		SearchCriteria => 'pv:lastUpdated > 0 and upnp:class derivedfrom "object.item.imageItem"',
		Filter         => '*',
		StartingIndex  => 0,
		RequestedCount => 10,
		SortCriteria   => '-pv:lastUpdated',
	} );
	
	cmp_ok( $res->{TotalMatches}->{t}, '>', 0, "Image Search TotalMatches is >0" );
	cmp_ok( $res->{NumberReturned}->{t}, '>', 0, "Image Search NumberReturned is >0" );
	
	my $menu = xml2hash( $res->{Result}->{t}, text => 't' );
	my $items = $menu->{'DIDL-Lite'}->{item};
	
	my $image = $items->[0];
	
	like( $image->{'-id'}, qr{^/i/[0-9a-f]{8}$}, 'Image Search result id ok' );
	is( $image->{'-parentID'}, '/i', 'Image Search result parentID ok' );
}
exit;

sub _action {
	my ( $service, $action, $args ) = @_;
	
	$args ||= {};
	
	my $res = $service->postaction($action, $args);
	my $hash = xml2hash( $res->gethttpresponse->getcontent, text => 't' );
	
	if ( $res->getstatuscode == 200 ) {	
		return $hash->{'s:Envelope'}->{'s:Body'}->{"u:${action}Response"};
	}
	else {
		return $hash->{'s:Envelope'}->{'s:Body'}->{'s:Fault'}->{detail};
	}
}
