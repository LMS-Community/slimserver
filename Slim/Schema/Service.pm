package Slim::Schema::Service;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2025 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use warnings;

use Slim::Music::Info;
use Slim::Utils::Log;

my $log = logger('database.info');
my %contentTypeCache;

sub searchTypes {
	return qw(contributor album genre track);
}

sub contentType {
	my ($class, $urlOrObj) = @_;

	# Bug 15779 - if we have it in the cache then just use it
	if (defined $contentTypeCache{$urlOrObj}) {
		return $contentTypeCache{$urlOrObj};
	}

	my $defaultType = 'unk';
	my $contentType = $defaultType;

	# See if we were handed a track object already, or just a plain url.
	my ($track, $url, $blessed) = _validTrackOrURL($urlOrObj);

	if (!defined $url) {
		return $defaultType;
	}

	if (defined $contentTypeCache{$url}) {
		return $contentTypeCache{$url};
	}

	if ($track) {
		$contentType = $track->content_type;
	} else {
		$contentType = Slim::Music::Info::typeFromPath($url);
	}

	if ((!defined $contentType || $contentType eq $defaultType) && !$track) {
		# Calling back to Schema to get object if needed
		# This dependency loop is improved by the Schema delegating to us, 
		# but if we need to fetch an object we must call Schema.
		# For now, we assume if we don't have the object, we try to use the schema class passed in
		# if it provides an accessor, otherwise we might need to require Slim::Schema.
		
		# In the original code, $self->objectForUrl($url) was called.
		# Ideally the service shouldn't know about Schema, but for this refactor we might need to.
		$track = Slim::Schema->objectForUrl($url);

		if (defined $track && $track->can('content_type')) {
			$contentType = $track->content_type;
		}
	}

	if ((!defined $contentType || $contentType eq $defaultType) && $blessed) {
		$contentType = Slim::Music::Info::typeFromPath($url);
	}

	if (defined $contentType && $contentType ne $defaultType) {
		$contentTypeCache{$url} = $contentType;
	}

	return $contentType;
}

sub clearContentTypeCache {
	my ($class, $urlOrObj) = @_;
	delete $contentTypeCache{$urlOrObj};
}

sub _validTrackOrURL {
	my $urlOrObj = shift;

	my $track;
	my $url;
	my $blessed;

	if ( Scalar::Util::blessed($urlOrObj) ) {

		$blessed = 1;

		if ( $urlOrObj->isa('Slim::Schema::Track') ) {
			$track = $urlOrObj;
			$url   = $track->url;
		} elsif ( $urlOrObj->can('url') ) {
			$url = $urlOrObj->url;
		}

	} else {
		$url = $urlOrObj;
	}

	return ($track, $url, $blessed);
}

1;
