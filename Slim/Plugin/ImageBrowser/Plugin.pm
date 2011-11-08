package Slim::Plugin::ImageBrowser::Plugin;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::OPMLBased);
use POSIX qw(strftime);
use Date::Parse qw(strptime);
use XML::Simple;
use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;
use Slim::Plugin::UPnP::Common::Utils qw(absURL);
use Slim::Plugin::UPnP::MediaServer::ContentDirectory;

my $prefs = preferences('server');

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.imagebrowser',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_IMAGEBROWSER_MODULE_NAME',
} );

use constant PLUGIN_TAG => 'imagebrowser';

sub initPlugin {
	my $class = shift;
	
	return unless $class->condition;

	$class->SUPER::initPlugin(
		feed   => \&handleFeed,
		tag    => PLUGIN_TAG,
		node   => 'extras',		# used for SP
		menu   => 'plugins',	# used in web UI
	);
}


# we depend on Slim::Plugin::UPnP::Plugin
# can probably be removed if we move SOAP::Lite to the main CPAN folder 
my $enabled;
sub condition {
	
	return $enabled if defined $enabled;
	
	# not checking the noupnp pref here, it's a web UI setting for the old client only
 	if ( !main::IMAGE ) {
		$enabled = 0;
		return 0;
	}	

	return 1;
}

# Don't add this item to any menu
sub playerMenu { }


# Extend initJive to setup albums screensavers
sub initJive {
	my ( $class, %args ) = @_;
	
	return if !$class->condition;
	
	my $menu = $class->SUPER::initJive( %args );
	
	return if !$menu;
	
	# bug 17737 - we need a better design, make screensavers optional, selectable etc.
#	my $data = _parseOPML('/il');
#	my $screensavers = [];
#	
#	my $albums = $data->{container};
#	
#	foreach my $item ( @$albums ) {
#		if ( $item->{'upnp:class'} =~ /^object.container/ ) {
#			push @$screensavers, {
#				cmd    => [ $args{tag}, 'items', 'id:' . $item->{id}, 'type:slideshow', 'slideshowId:' . $item->{id} ],
#				text => $item->{'dc:title'},
#			}
#		}
#	}
#	
#	$menu->[0]->{screensavers} = $screensavers;
	
	return $menu;
}			


# fetch content from UPnP handler, and convert into OPML as understood by XMLBrowser
sub handleFeed {
	my ($client, $cb, $params, $args) = @_;
	
	my $qid = $args->{id} || '';
	
	my ($wantSlideshow, $firstSlide);
	if ( $params && $params->{params} && ($params->{params}->{type} eq 'slideshow' || $params->{params}->{slideshow}) ) {
		$wantSlideshow = $params->{params}->{id};
		$qid = $params->{params}->{slideshowId};
		main::DEBUGLOG && $log->debug("Start slideshow at item ID $wantSlideshow");
	}

	my $data = _parseOPML($qid, $params->{start}, $params->{sort});
	
	my $items = [];
	my $dateFormat   = $prefs->get('shortdateFormat');
	my $thumbSize    = $prefs->get('thumbSize') || 100;
	my $resizeParams = $params->{isWeb} ? "_${thumbSize}x${thumbSize}_m.png" : '.png';
	my $maxSize      = $prefs->get('maxUPnPImageSize');
	
	my $x = 0;
	foreach my $itemLoop ($data->{container}, $data->{item}) {
		foreach my $item ( @$itemLoop ) {

			if ( $item->{'upnp:class'} =~ /^object.container/ ) {
				
				# don't show "All images" item: listing tens of thousands of images can kill some clients
				next if $item->{id} eq '/ia';
				next if $wantSlideshow;
 
				push @$items, {
					type => $params->{isWeb} ? 'slideshow' : 'link',
					name => $item->{'dc:title'},
					url  => \&handleFeed,
					# show folder icon if we have images and folders in the same view only
					icon => $data->{item} ? 'html/images/icon_folder.png' : undef,
					passthrough => [ {
						id => $item->{id}
					} ],
				};
			}

			elsif ( $item->{'upnp:class'} eq 'object.item.imageItem.photo' ) {
				my $id   = _getId($item);
				my $date = $item->{'dc:date'} ? strftime($dateFormat, strptime($item->{'dc:date'})) : '';
				
				if ( $wantSlideshow && !$firstSlide && $id eq $wantSlideshow ) {
					$firstSlide = $x;
				}
				
				push @$items, $wantSlideshow 
				? {
					image => "image/$id/cover{resizeParams}",
					name  => $item->{'dc:title'},
					owner => $item->{'upnp:album'},
					date  => $date,
				}
				: {
					name => $item->{'dc:title'} . ($date ? ' - ' . $date : ''),
					weblink => $id ? "/image/$id/cover_${maxSize}x${maxSize}_o" : undef,
					image => $id ? "/image/$id/cover$resizeParams" : undef,
					jive => $id ? {
						actions => {
							go => {
								player => 0,
								cmd => [ PLUGIN_TAG, 'items' ],
								params => {
									id => $id,
									type => 'slideshow',
									slideshowId => $qid,
								}
							},
						}
					} : undef
				};
			
				$x++;
			}
			
			else {
				# what here?
				require Data::Dump;
				$log->error('unhandled upnp:class? ' . Data::Dump::dump($item));
			}
		}
		
	}
	
	# if we want a slide show, make sure we start at the selected image
	if ( $wantSlideshow && $firstSlide && $firstSlide < @$items ) {
		my @tail = splice(@$items, $firstSlide);
		unshift(@$items, @tail);
	}
	
	push @$items, {
		type => 'text',
		name => Slim::Utils::Strings::clientString($client, 'EMPTY'),
	} if not scalar @$items;
	
	main::DEBUGLOG && $log->is_debug && $log->debug( Data::Dump::dump($items) );

	$cb->({
		items => $items,
	});
}

sub _parseOPML {
	my ($id, $start, $sort) = @_;
	
	my ($data, $count, $total) = Slim::Plugin::UPnP::MediaServer::ContentDirectory->Browse(undef, {
		BrowseFlag     => 'BrowseDirectChildren',
		Filter         => '*',
		ObjectID       => $id || '/images',
		RequestedCount => 999999,		# get them all, XMLBrowser does the paging... a good idea?
		SortCriteria   => $sort || '+dc:title',
		StartingIndex  => $start || 0,
	});	
	
	$data = $data->name('Result')->value();
	
	my $parsed = $data ? eval { 
		XMLin($data, KeyAttr => ['container', 'item'], ForceArray => ['container', 'item', 'res']) 
	} : {};

	if ( $@ ) {
		$log->error( "Unable to parse: " . $@ );
		$parsed = {};
	}
	
	return $parsed;
}

sub _getId {
	my $item = shift;
	
	return unless $item && $item->{res} && ref $item->{res} eq 'ARRAY';

	my $id;
	foreach ( @{$item->{res}} ) {
		if ( ($id) = $_->{content} =~ m{image/([0-9a-f]{8})/} ) {
			last;
		}
	}
	
	if (!$id) {
		($id) = $item->{'upnp:icon'} =~ m{image/([0-9a-f]{8})/};
	}
	
	return $id;
}

1;