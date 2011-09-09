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

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.imagebrowser',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_IMAGEBROWSER_MODULE_NAME',
} );

use constant PLUGIN_TAG => 'imagebrowser';

sub initPlugin {
	my $class = shift;

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
	
	eval {
		require Slim::Plugin::UPnP::Plugin;
		require Slim::Plugin::UPnP::MediaServer::ContentDirectory;
		$enabled = 1;
	};

	if ($@) {
		$enabled = 0;
		main::DEBUGLOG && $log->is_debug && $log->debug($@);
		$log->warn("The ImageBrowser plugin requires the UPnP plugin to be enabled");
		return 0;
	}	

	return 1;
}

# Don't add this item to any menu
sub playerMenu { }


# Extend initJive to setup albums screensavers
sub initJive {
	my ( $class, %args ) = @_;
	
	my $menu = $class->SUPER::initJive( %args );
	
	return if !$menu;
	
	my $data = _parseOPML('/il');
	my $screensavers = [];
	
	my $albums = $data->{container};
	
	foreach my $item ( @$albums ) {
		if ( $item->{'upnp:class'} =~ /^object.container/ ) {
			push @$screensavers, {
				cmd    => [ $args{tag}, 'items', 'id:' . $item->{id}, 'slideshow:1' ],
				text => $item->{'dc:title'},
			}
		}
	}
	
	$menu->[0]->{screensavers} = $screensavers;
	
	return $menu;
}			


# fetch content from UPnP handler, and convert into OPML as understood by XMLBrowser
sub handleFeed {
	my ($client, $cb, $params, $args) = @_;
	
	my $qid = $args->{id} || '';
	
	my $wantSlideshow;
	if ( $params && $params->{params} && ($wantSlideshow = $params->{params}->{slideshow}) ) {
		$qid = $params->{params}->{id};
	}

	my $data = _parseOPML($qid, $params->{start}, $params->{sort});
	
	my $items = [];
	my $dateFormat = preferences('server')->get('shortdateFormat');
	
	foreach my $itemLoop ($data->{container}, $data->{item}) {
		foreach my $item ( @$itemLoop ) {
			if ( $item->{'upnp:class'} =~ /^object.container/ ) {
				push @$items, {
					type => 'link',
					name => $item->{'dc:title'},
					url  => \&handleFeed,
					# show folder icon if we have images and folders in the same view only
					icon => $data->{item} ? 'html/images/icon_folder.png' : undef,
					passthrough => [ {
						id => $item->{id}
					} ],
				} if !$wantSlideshow;
			}

			elsif ( $item->{'upnp:class'} eq 'object.item.imageItem.photo' ) {
				my ($id) = $item->{'upnp:icon'} =~ m{(?:music|image)/([0-9a-f]{8})/};
				my $date = $item->{'dc:date'} ? strftime($dateFormat, strptime($item->{'dc:date'})) : '';
				
				push @$items, $wantSlideshow 
				? {
					image => "image/$id/cover{resizeParams}",
					name  => $item->{'dc:title'},
					owner => $item->{'upnp:album'},
					date  => $date,
				}
				: {
					type => 'link',
					name => $item->{'dc:title'} . ($date ? ' - ' . $date : ''),
					weblink => $item->{res}->{content},
					image => $item->{'upnp:icon'},
					jive => $id ? {
						actions => {
							go => {
								player => 0,
								cmd => [ PLUGIN_TAG, 'items' ],
								params => {
									id => "/ia/$id",
									slideshow => 1,
								}
							},
						}
					} : undef
				};
			}
			
			else {
				# what here?
				$log->error('unhandled upnp:class? ' . Data::Dump::dump($item));
			}
		}
		
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
		XMLin($data, KeyAttr => ['container', 'item'], ForceArray => ['container', 'item']) 
	} : {};

	if ( $@ ) {
		$log->error( "Unable to parse: " . $@ );
		$parsed = {};
	}
	
	return $parsed;
}

1;