package Slim::Plugin::YALP::Plugin;

# WMA metadata parser for YALP radio
# /tilive1.alice.cdn.interbusiness.it/

use strict;

use Slim::Formats::RemoteMetadata;
use Slim::Utils::Log;

my $log = logger('formats.metadata');

use constant IMAGE_PREFIX => 'http://images.rossoalice.alice.it/musicbox/';

sub initPlugin {
	Slim::Formats::RemoteMetadata->registerParser(
		match => qr/tilive1.alice.cdn.interbusiness.it/,
		func  => \&parser,
	);
}

sub parser {
	my ( $client, $url, $metadata ) = @_;

	# Sequence number|Asset ID|Song Title|Artist Name|Comment|Sellable|Small Image|Large Image
	# There are 4 songs in the metadata, separated by semicolons, 
	# the current song has sequence number 0
	
	my ($title, $artist, $comment, $simage, $limage) 
		= $metadata =~ m{;0\|\d+\|([^|]+)?\|([^|]+)?\|([^|]+)?\|\d?\|([^|]+)?\|([^|]+)?;};
	
	my $cover
	 	= $limage =~ /\.(?:jpg|png|gif)/i ? IMAGE_PREFIX . $limage
		: $simage =~ /\.(?:jpg|png|gif)/i ? IMAGE_PREFIX . $simage
		: undef;
	
	my $meta = {
		title   => $title,
		artist  => $artist,
		cover   => $cover,
	};
	
	# This metadata is read by HTTP's getMetadataFor
	$client->playingSong->pluginData( wmaMeta => $meta );
	
	main::DEBUGLOG && $log->is_debug && $log->debug( "YALP metadata: " . Data::Dump::dump($meta) );
	
	return 1;
}

1;