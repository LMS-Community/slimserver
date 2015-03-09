package Slim::Networking::Repositories;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Music::Repositories

=head1 DESCRIPTION

Slim::Networking::Repositories provides some mechanisms to allow for a simple 
load balancing and failover etc. Callers can register multiple repositories,
from which the fastest would be chosen automaically.

This module is doing a HEAD request on the URLs to measure latency. When a 
URL for a repository is requested, the fastest will be returned. URLs with a
latency within a certain threshold are considered on par with each other, and
a random URL will be chosen.

This module will not validate the URLs any further than trying to do a HEAD
request. Whether it's pointing to a file or a folder is up to the caller. 
URLs which fail the latency check are filtered out. No check will be run if 
there is only one URL for a repository.

PLEASE NOTE that the URLs need to be available for a HEAD request! If the URL
is pointing to a folder which has no default document and where the directory
index is disabled will fail the latency check! In such a case please put a 
minimalistic index.html in the folder.

Optionally there can be a repositories.conf with a list of repositories in 
the same folder as strings.txt. This must not be writable by the server, as 
otherwise a malicious plugin could redirect update checks etc.!

repositories.conf:

# sample content of a repositories file
servers http://downloads.myserver.com/respository.xml
firmware http://downloads.myserver.com/firmware.xml

=head1 METHODS
	
	# get the repository file from the "best" mirror:
	Slim::Networking::Repositories->get(
		'servers',
		\&_handleDownloads,
		\&_handleError,
		{ ... },		# params passed through to the callbacks
	);
	
	# ... or get the best URL to further deal with:
	Slim::Networking::Repositories->getUrlForRepository('servers');
	
	# ... or get a mirror (or self) for a given URL:
	Slim::Networking::Repositories->getMirrorForUrl('http://downloads.myserver.com/repository.xml');
	
=cut

use strict;
use File::Spec::Functions qw(catfile);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

use constant POLL_INTERVAL => 3600 * 6;

# mirrors whose latency is within this range (in seconds) will be picked randomly
use constant OK_THRESHOLD => 0.5;	

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'network.repositories',
	defaultLevel => 'ERROR',
} );

my $prefs = preferences('server');

# These lists are hashes instead of simple lists to facilitate
# weighting. The default of 1 would be replaced with the latency in order to
# allow latency based load balancing.
my %repositories = (
	servers    => { 'http://repos.squeezecommunity.org/' => 1 },
	firmware   => { 'http://update.slimdevices.com/update/firmware/' => 1 },
	extensions => { 'http://repos.squeezecommunity.org/extensions.xml' => 1 }, 
);

sub init {
	# read optional file with additinal repositories
	my $reposfile = catfile(Slim::Utils::OSDetect::dirsFor('repositories'), 'repositories.conf');
	
	if ( -f $reposfile && open(CONVERT, $reposfile) ) {
		while (my $line = <CONVERT>) {

			# skip comments and whitespace
			next if $line =~ /^\s*#/;
			next if $line =~ /^\s*$/;

			# get rid of comments and leading and trailing white space
			$line =~ s/#.*$//o;
			$line =~ s/^\s*//o;
			$line =~ s/\s*$//o;
	
			if ( $line =~ m|^([a-z_]+)\s+(https?://\S+)\s*$|i ) {
				$repositories{$1}->{$2} = 1;
			}
		}
	}
	
	foreach (keys %repositories) {
		Slim::Utils::Timers::setTimer($_, time() + rand(5), \&measureLatency);
	}
}

# get a repository file for a repository
sub get {
	my $class = shift;
	my $item  = shift;
	
	my $url = $item =~ /^https?:/ ? $class->getMirrorForUrl($item) : $class->getUrlForRepository($item);
	
	Slim::Networking::SimpleAsyncHTTP->new( @_ )->get( $url );
}

sub getUrlForRepository {
	my ($class, $repository) = @_;
	
	return '' unless $repository;
	
	my @urls = keys %{ $repositories{$repository} || {} };
	
	return '' unless scalar @urls;
	
	return $urls[0] if scalar @urls == 1;
	
	my $repositories = $repositories{$repository};

	# filter out slow mirrors (difference to fastest larger than OK_THRESHOLD)
	my $latency = 0;
	@urls = grep {
		$latency ||= $repositories->{$_};
		$repositories->{$_} - $latency < OK_THRESHOLD ? 1 : 0;
	} sort { 
		$repositories->{$a} <=> $repositories->{$b}
	} @urls;
	
	# pick random URL from remaining list
	my $url = $urls[ rand @urls ];
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Picked URL for repository '$repository': " . $url);
	
	return $url;
}

sub getMirrorForUrl {
	my ($class, $url) = @_;
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Trying to find a mirror for URL: " . $url);
	
	my ($repository) = grep { 
		$repositories{$_}->{$url} ? $_ : undef 
	} keys %repositories;
	
	if ($repository) {
		return $class->getUrlForRepository($repository);
	}
	
	return $url;
}

sub measureLatency {
	my $repository = shift;

	Slim::Utils::Timers::killTimers($repository, \&measureLatency);

	return unless keys %{$repositories{$repository}} > 1;
	
	for my $repo ( keys %{$repositories{$repository}} ) {
		Slim::Networking::SimpleAsyncHTTP->new(
			\&_measureLatencyDone, 
			\&_measureLatencyDone, 
			{ 
				repository => $repository, 
				sent       => Time::HiRes::time(), 
				cache      => 0,
				timeout    => 5,
			}
		)->head( $repo );
	}

	Slim::Utils::Timers::setTimer($repository, time() + POLL_INTERVAL + rand(5), \&measureLatency);
}

sub _measureLatencyDone {
	my $http = shift;
	
	my $code = $http->code || 0;
	my $url  = $http->url;

	my $latency = Time::HiRes::time() - $http->params('sent');
	
	if ( $code == 200 ) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Got latency for $url: $latency");
	}
	else {
		$latency = 999_999;
		$log->warn("Failed to measure latency for $url: " . ($http->error || Data::Dump::dump($http)));
	}

	my $repository = $http->params('repository');

	if ( $repository && (my $repositories = $repositories{$repository}) ) {
		if ( $repositories->{$url} ) {
			$repositories->{$url} = $latency;
		}
	}
}

1;