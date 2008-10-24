package Slim::Formats::RemoteMetadata::YALP;

# $Id$
#
# WMA metadata parser for YALP radio
# /tilive1.alice.cdn.interbusiness.it/

use strict;

use Slim::Formats::RemoteMetadata;
use Slim::Utils::Log;

my $log = logger('formats.metadata');

use constant IMAGE_PREFIX => 'http://images.rossoalice.alice.it/musicbox/';

sub init {
	Slim::Formats::RemoteMetadata->registerParser(
		match => qr/tilive1.alice.cdn.interbusiness.it/,
		func  => \&parser,
	);
	
	Slim::Formats::RemoteMetadata->registerProvider(
		match => qr/tilive1.alice.cdn.interbusiness.it/,
		func  => \&provider,
	);
}

sub parser {
	my ( $client, $url, $metadata ) = @_;

	# Sequence number|Asset ID|Song Title|Artist Name|Comment|Sellable|Small Image|Large Image
	# XXX: this is really inconsistent, data is often truncated, etc
	
	# Text data is in UTF-16LE, between ;0| .. ; (UTF-16 3B 00 30 00 7C 00)
	my ($inner) = $metadata =~ /\x3B\x00\x30\x00\x7C\x00([^\x3B]+)/;
	
	# But sometimes second semicolon is not there, detect end of text with double-null
	$inner =~ s/\x00\x00.+//g;
	
	$inner = eval { Encode::decode('UTF-16LE', $inner) } || return;
	
	my ($title, $artist, $comment, $simage, $limage) 
		= $inner =~ m{\d+\|([^|]+)?\|([^|]+)?\|([^|]+)?\|\d?\|([^|]+)?\|([^|]+)?};
	
	my $cover
	 	= $limage =~ /\.(?:jpg|png|gif)/i ? IMAGE_PREFIX . $limage
		: $simage =~ /\.(?:jpg|png|gif)/i ? IMAGE_PREFIX . $simage
		: undef;
	
	my $meta = {
		title   => $title,
		artist  => $artist,
		comment => $comment,
		cover   => $cover,
	};
	
	$log->is_debug && $log->debug( "YALP metadata: " . Data::Dump::dump($meta) );
}

sub provider {
	my ( $client, $url ) = @_;
	
	# XXX: todo
	
	return {};
}

1;