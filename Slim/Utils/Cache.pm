# Copyright (c) 2005 Slim Devices, Inc. (www.slimdevices.com)

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Slim::Utils::Cache;

=head1 NAME

Slim::Utils::Cache

=head1 SYNOPSIS

my $cache = Slim::Utils::Cache->new($namespace, $version, $noPeriodicPurge)

$cache->set($file, $data);

my $data = $cache->get($file);

$cache->remove($file);

$cache->cleanup;

=head1 DESCRIPTION

A simple cache for arbitrary data using L<Cache::FileCache>.

=head1 METHODS

=head2 new( [ $namespace ], [ $version ], [ $noPeriodicPurge ] )

$namespace allows unique namespace for cache to give control of purging on per namespace basis

$version - version number of cache content, first new call with different version number empties existing cache

$noPeriodicPurge - set for namespaces expecting large caches so purging only happens at startup

Creates a new Slim::Utils::Cache instance.

=head1 SEE ALSO

L<Cache::Cache> and L<Cache::FileCache>.

=cut

use strict;

use Cache::FileCache ();

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

my $DEFAULT_EXPIRES_TIME = '1 hour';

my $PURGE_INTERVAL = 60 * 60 * 24; # interval between purge cycles
my $PURGE_RETRY    = 60 * 60;      # retry time if players are on
my $PURGE_NEXT     = 30;           # purge next namespace

my $defaultNameSpace = 'FileCache';
my $defaultVersion = 1;

# hash of caches which we have created by namespace
my %caches = ();

my @thisCycle = (); # namespaces to be purged this purge cycle
my @eachCycle = (); # namespaces to be purged every PURGE_INTERVAL

my $startUpPurge = 1; # Flag for purging at startup

my $log = logger('server');

# create proxy methods
{
	my @methods = qw(
		get set get_object set_object
		clear purge remove size
	);
		
	no strict 'refs';
	for my $method (@methods) {
		*{ __PACKAGE__ . "::$method" } = sub {
			return shift->{_cache}->$method(@_);
		};
	}
}

sub init {
	my $class = shift;

	# cause the default cache to be created if it is not already
	__PACKAGE__->new();

	# start purge routine in 10 seconds to purge all caches created during server and plugin startup
	Slim::Utils::Timers::setTimer( undef, time() + 10, \&cleanup );
}

# Backwards-compat
*instance = \&new;

sub new {
	my $class = shift;
	my $namespace = shift || $defaultNameSpace;

	# return existing instance if exists for this namespace
	return $caches{$namespace} if $caches{$namespace};

	# otherwise create new cache object taking acount of additional params
	my ($version, $noPeriodicPurge);

	if ($namespace eq $defaultNameSpace) {
		$version = $defaultVersion;
	} else {
		$version = shift || 0;
		$noPeriodicPurge = shift;
	}

	my $cache = Cache::FileCache->new( {
		namespace          => $namespace,
		default_expires_in => $DEFAULT_EXPIRES_TIME,
		cache_root         => Slim::Utils::Prefs::get('cachedir'),
		directory_umask    => umask(),
	} );
	
	my $self = bless {
		_cache => $cache,
	}, $class;
	
	# empty existing cache if version number is different
	my $cacheVersion = $self->get('Slim::Utils::Cache-version');

	unless (defined $cacheVersion && $cacheVersion eq $version) {

		$log->info("Version changed for cache: $namespace - clearing out old entries");
		$self->clear();
		$self->set('Slim::Utils::Cache-version', $version, 'never');

	}

	# store cache object and add namespace to purge lists
	$caches{$namespace} = $self;
	push @thisCycle, $namespace;
	push @eachCycle, $namespace unless $noPeriodicPurge;

	return $self;
}

sub cleanup {
	# This routine purges the complete list of namespaces, one per timer call
	# NB Purging is expensive and blocks the server
	#
	# namespaces with $noPeriodicPurge set are only purged at server startup
	# others are purged at max once per $PURGE_INTERVAL.
	#
	# To allow disks to spin down, each namespace is purged within a short period 
	# and then no purging is done for $PURGE_INTERVAL
	#
	# After the startup purge, if any players are on it reschedules in $PURGE_RETRY

	my $namespace; # namespace to purge this call
	my $interval;  # interval to next call

	# take one namespace from list to purge this cycle
	$namespace = shift @thisCycle;

	# after startup don't purge if a player is on - retry later
	unless ($startUpPurge) {
		for my $client ( Slim::Player::Client::clients() ) {
			if ($client->power()) {
				unshift @thisCycle, $namespace;
				$namespace = undef;
				$interval = $PURGE_RETRY;
				last;
			}
		}
	}

	unless ($interval) {
		if (@thisCycle) {
			$interval = $startUpPurge ? 0.1 : $PURGE_NEXT;
		} else {
			$interval = $PURGE_INTERVAL;
			$startUpPurge = 0;
			push @thisCycle, @eachCycle;
		}
	}
	
	my $now = Time::HiRes::time();
	
	if ($namespace && $caches{$namespace}) {

		my $cache = $caches{$namespace};
		my $lastpurge = $cache->get('Slim::Utils::Cache-purgetime'); 

		unless ($lastpurge && ($now - $lastpurge) < $PURGE_INTERVAL) {
			my $start = $now;
			$cache->purge;
			$cache->set('Slim::Utils::Cache-purgetime', $start, 'never');
			$now = Time::HiRes::time();
			$log->info(sprintf("Cache purge: $namespace - %f sec", $now - $start));
		} else {
			$log->info("Cache purge: $namespace - skipping, purged recently");
		}
	}

	Slim::Utils::Timers::setTimer( undef, $now + $interval, \&cleanup );
}


1;
