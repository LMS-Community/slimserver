package Slim::Web::Pages;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use Tie::RegexpHash;

use Slim::Utils::Log;

my $log = logger('network.http');

# this holds pointers to functions handling a given path
our %pageFunctions = ();
tie %pageFunctions, 'Tie::RegexpHash';

# we bypass most of the template stuff to execute those
our %rawFunctions = ();
tie %rawFunctions, 'Tie::RegexpHash';

# raw files we serve directly outside the html directory
our %rawFiles = ();
my $rawFilesRegexp;

our %additionalLinks = ();
our %pageConditions = ();

sub init {
	# Note: init() is not run with --noweb param
		
	require Slim::Web::Pages::Common;
	require Slim::Web::Pages::Home;
	require Slim::Web::Pages::Status;
	require Slim::Web::Pages::EditPlaylist;
	require Slim::Web::Pages::Playlist;
	require Slim::Web::Pages::Progress;
	require Slim::Web::Pages::Trackinfo;
	require Slim::Web::Pages::Search;

	Slim::Web::Pages::Common->init();
	Slim::Web::Pages::Home->init();
	Slim::Web::Pages::Status->init();
	Slim::Web::Pages::EditPlaylist->init();
	Slim::Web::Pages::Playlist->init();
	Slim::Web::Pages::Progress->init();
	Slim::Web::Pages::Trackinfo->init();
	Slim::Web::Pages::Search->init();
}

sub addPageLinks {
	my ($class, $category, $links, $noquery) = @_;

	if (ref($links) ne 'HASH') {
		return;
	}

	while (my ($title, $path) = each %$links) {

		if (defined($path)) {

			my $separator = '';

			if (!$noquery && $category ne 'icons') {

				if ($path =~ /\?/) {
					$separator = '&';
				} else {
					$separator = '?';
				}
			}

			$additionalLinks{$category}->{$title} = $path . $separator;

		} else {

			delete($additionalLinks{$category}->{$title});
		}
	}

	if (not keys %{$additionalLinks{$category}}) {

		delete($additionalLinks{$category});
	}
}

sub getPageLink {
	my ( $class, $category, $title ) = @_;
	
	if ( exists $additionalLinks{$category} ) {
		return $additionalLinks{$category}->{$title};
	}
	
	return;
}

sub delPageLinks {
	my ( $class, $category, $title ) = @_;
	
	delete $additionalLinks{$category}->{$title};
}

sub delPageCategory {
	my ( $class, $category ) = @_;
	
	delete $additionalLinks{$category};
}

sub addPageCondition {
	my ( $class, $title, $condition ) = @_;
	
	$pageConditions{$title} = $condition;
}


sub addPageFunction {
	my ( $class, $regexp, $func ) = @_;
	
	if ( !ref $regexp ) {
		$regexp = qr/$regexp/;
	}

	main::INFOLOG && $log->is_info && $log->info("Adding handler for regular expression /$regexp/");

	$pageFunctions{$regexp} = $func;
}

sub getPageFunction {
	my ( $class, $path ) = @_;
	return $pageFunctions{$path};
}


# addRawFunction
# adds a function to be called when the raw URI matches $regexp
# prototype: function($httpClient, $response), no return value
#            $response is a HTTP::Response object.
sub addRawFunction {
	my ( $class, $regexp, $funcPtr ) = @_;

	if ( main::DEBUGLOG && $log->is_debug ) {
		my $funcName = Slim::Utils::PerlRunTime::realNameForCodeRef($funcPtr);
		$log->debug("Adding RAW handler: /$regexp/ -> $funcName");
	}

	$rawFunctions{$regexp} = $funcPtr;
}

sub getRawFunction {
	my ( $class, $path ) = @_;
	return $rawFunctions{$path};
}


# adds files for downloading via http
# defines a regexp to match the path for downloading a static file outside the http directory
#  $regexp is a regexp to match the request path
#  $file is the file location or a coderef to a function to return it (will be passed the path)
#  $ct is the mime content type, 'text' or 'binary', or a coderef to a function to return it
sub addRawDownload {
	my $class  = shift;
	my $regexp = shift || return;
	my $file   = shift || return;
	my $ct     = shift;

	if ($ct eq 'text') {
		$ct = 'text/plain';
	} elsif ($ct eq 'binary' || !$ct) {
		$ct = 'application/octet-stream';
	}

	$rawFiles{$regexp} = {
		'file' => $file,
		'ct'   => $ct,
	};

	my $str = join('|', keys %rawFiles);
	$rawFilesRegexp = $str ? qr/$str/ : undef;
}

sub getRawFiles {
	return \%rawFiles;
}

# remove files for downloading via http
sub removeRawDownload {
	my ( $class, $regexp ) = @_;
   
	delete $rawFiles{$regexp};
	my $str = join('|', keys %rawFiles);
	$rawFilesRegexp = $str ? qr/$str/ : undef;
}

sub isRawDownload {
	my ( $class, $path ) = @_;
	
	return $path && $rawFilesRegexp && $path =~ $rawFilesRegexp
}


1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
