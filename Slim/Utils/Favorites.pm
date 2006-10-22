package Slim::Utils::Favorites;

# $Id$

# SlimServer Copyright (C) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This class persists a user's choice of favorite tracks.  In this
# implementation, the favorites are stored as server-wide prefs.
# However, its important to abstract the underlying implementation.
# Callers need not know how the favorites are stored.  In the future,
# they could be stored as a playlist file or in a database table.

use strict;

use FindBin qw($Bin);
use Scalar::Util qw(blessed);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

use Slim::Utils::Prefs;

my $log = logger('favorites');

# Class-only method, not an instance method
# Adds a favorite for the given client to the database.  
# Should station titles be localized??  Should they be pulled from tags in the stream?
sub clientAdd {
	my ($class, $client, $url, $title) = @_;

	# this is a class only method.
	assert(!ref($class), "call clientAdd as a class method, not an instance\n");

	# don't crash if no url
	if (!$url) {

		logWarning("No url passed! Skipping.");
		return undef;
	}

	if (blessed($url) && $url->can('url')) {

		$url = $url->url;
	} 

	# Bug 3362, ignore sessionID's within URLs (Live365)
	$url =~ s/\?sessionid.+//i;

	$log->info(sprintf("%s, %s, %s)", $client->id, $url, $title));

	# if its already a favorite, don't add it again
	my $fav = $class->findByClientAndURL($client, $url);

	if (defined($fav)) {
		return $fav->{'num'};
	}

	# find any vacated spots
	$fav = $class->findByClientAndURL($client, '');

	if (defined($fav)) {

		Slim::Utils::Prefs::set('favorite_urls', $url, $fav->{'num'}-1);
		Slim::Utils::Prefs::set('favorite_titles', $title, $fav->{'num'}-1);

		return $fav->{'num'};
	}

	# append to list
	Slim::Utils::Prefs::push('favorite_urls', $url);
	Slim::Utils::Prefs::push('favorite_titles', $title);

	# return the favorite number
	return Slim::Utils::Prefs::getArrayMax('favorite_urls') + 1;
}

# for internal use only.  Get pref index for given url
sub _indexByUrl {
	my $url = shift || return undef;

	# Bug 3362, ignore sessionID's within URLs (Live365)
	# This allows either a URL with session or without to be found properly
	my $strippedURL = $url;
	$strippedURL    =~ s/\?sessionid.+//i;

	my @urls = Slim::Utils::Prefs::getArray('favorite_urls');

	my $i     = 0;
	my $found = 0;

	while (!$found && $i < scalar(@urls)) {

		if ( $urls[$i] eq $url || $urls[$i] eq $strippedURL ) {
			$found = 1;
		} else {
			$i++;
		}
	}

	if ($found) {
		return $i;
	} else {
		return undef;
	}
}

sub findByClientAndURL {
	my $class  = shift;
	my $client = shift;
	my $url    = shift;

	my $i = _indexByUrl($url);

	if (defined($i)) {

		$log->info("Found favorite number " . ($i+1) . ": $url");

		my $title = Slim::Utils::Prefs::getInd('favorite_titles', $i);

		return {
			'url'   => $url,
			'title' => $title,
			'num'   => $i+1
		};

	} else {

		$log->debug("Not found: $url");

		return undef;
	}
}

sub addCurrentItem {
	my $class  = shift;
	my $client = shift;
	
	# First lets try for a listRef from INPUT.*
	my $list = $client->modeParam('listRef');
	my $obj;
	my $title;
	my $url;
	
	# If there is a list, try grabbing the current index.
	if ($list) {
	
		$obj = $list->[$client->modeParam('listIndex')];
	
	# hack to grab currently browsed item from current playlist (needs to use INPUT.List at some point)
	} elsif (Slim::Buttons::Common::mode($client) eq 'playlist') {
	
		$obj = Slim::Player::Playlist::song($client, Slim::Buttons::Playlist::browseplaylistindex($client));
	}
	
	# if that doesn't work, perhaps we have a track param from something like trackinfo
	if (!blessed($obj)) {
		
		if ($client->modeParam('track')) {
	
			$obj = $client->modeParam('track');
	
		# specific HACK for Live365
		} elsif(Slim::Player::ProtocolHandlers->handlerForURL('live365://') && (Plugins::Live365::Plugin::getLive365($client))) {

			my $live365 = Plugins::Live365::Plugin::getLive365($client);
			my $station = $live365->getCurrentStation();
			
			$title = $station->{STATION_TITLE};
			$url   = $station->{STATION_ADDRESS};
			
			# fix url to activate protocol handler
			$url =~ s/http\:/live365\:/;
		}
	}
	
	# start with the object if we have one
	if ($obj && !$url) {
		
		if (blessed($obj) && $obj->can('url')) {
			$url = $obj->url;
		
		# xml browser uses hash lists with url and name values.
		} elsif (ref($obj) eq 'HASH') {
			
			$url = $obj->{'url'};
		}
		
		if (blessed($obj) && $obj->can('name')) {

			$title = $obj->name;
		} elsif (ref($obj) eq 'HASH') {

			$title = $obj->{'name'} || $obj->{'title'};
		}
		
		if (!$title) {
			
			# failing specified name values, try the db title
			$title = Slim::Music::Info::standardTitle($client, $obj) || $url;
		}
	} 
	
	# remoteTrackInfo uses url and title params for lists.
	if ($client->modeParam('url') && !$url) {
		
		$url   = $client->modeParam('url');
		$title = $client->modeParam('title');
	}

	if ($url && $title) {
		$class->clientAdd($client, $url, $title);
		$client->showBriefly($client->string('FAVORITES_ADDING'), $title);
	
	# if all of that fails, send the debug with a best guess helper for tracing back
	} else {

		if ($log->is_error) { 

			$log->error("Error: No valid url found, not adding favorite!");
			
			if ($obj) {
				$log->error(Data::Dump::dump($obj));
			} else {
				$log->logBacktrace;
			}
		}
	}
}

sub moveItem {
	my $class  = shift;
	my $client = shift;
	my $from   = shift;
	my $to     = shift;

	if (defined $to && $to =~ /^[\+-]/) {
		$to = $from + $to;
	}

	my @titles = titles();
	my @urls   = urls();

	if (defined $from && defined $to && 
		$from < scalar @titles && 
		$to < scalar @titles && $from >= 0 && $to >= 0) {

		Slim::Utils::Prefs::set('favorite_titles',$titles[$from],$to);
		Slim::Utils::Prefs::set('favorite_urls',$urls[$from],$to);
		Slim::Utils::Prefs::set('favorite_titles',$titles[$to],$from);
		Slim::Utils::Prefs::set('favorite_urls',$urls[$to],$from);
	}
}

sub deleteByClientAndURL {
	my $class  = shift;
	my $client = shift;
	my $url    = shift;

	$class->deleteByClientAndId($client, _indexByUrl($url));
}

sub deleteByClientAndId {
	my $class  = shift;
	my $client = shift;
	my $i      = shift;

	if (defined($i)) {
		
		my @titles = titles();
		my @urls   = urls();
		
		splice @titles, $i, 1;
		splice @urls,   $i, 1;
		
		Slim::Utils::Prefs::setArray( 'favorite_titles', \@titles );
		Slim::Utils::Prefs::setArray( 'favorite_urls', \@urls );
		
		$log->info("Deleting favorite number " . ($i+1));
	}
}

# creates a read-only list of favorites.
# if you need to modify the list, use add then call new again.
sub new {
	my $class = shift;

	# this is a class only method.
	assert (!ref($class), "new is a class method, not an instance\n");

	# nothing really to do for this implementation
	return bless({}, $class);
}

# returns an array of titles
sub titles {
	return Slim::Utils::Prefs::getArray('favorite_titles');
}

# returns an array of urls
sub urls {
	return Slim::Utils::Prefs::getArray('favorite_urls');
}

1;

__END__
