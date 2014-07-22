# Copyright 2005-2009 Logitech

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

A simple cache for arbitrary data using SQLite, providing an interface similar to Cache::Cache

=head1 METHODS

=head2 new( [ $namespace ], [ $version ], [ $noPeriodicPurge ] )

$namespace allows unique namespace for cache to give control of purging on per namespace basis

$version - version number of cache content, first new call with different version number empties existing cache

$noPeriodicPurge - set for namespaces expecting large caches so purging only happens at startup

Creates a new Slim::Utils::Cache instance.

=head1 SEE ALSO

L<Cache::Cache>.

=cut

use strict;

use Slim::Utils::DbCache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use constant PURGE_INTERVAL    => 3600 * 8;  # interval between purge cycles
use constant PURGE_RETRY       => 3600;      # retry time if players are on
use constant PURGE_NEXT        => 30;        # purge next namespace

use constant DEFAULT_NAMESPACE => 'cache';
use constant DEFAULT_VERSION   => 1;

# hash of caches which we have created by namespace
my %caches = ();

my @thisCycle = (); # namespaces to be purged this purge cycle
my @eachCycle = (); # namespaces to be purged every PURGE_INTERVAL

my $startUpPurge = 1; # Flag for purging at startup

my $log = logger('server');

# create proxy methods
{
	my @methods = qw(
		get set
		clear purge remove 
	);
	#	get_object set_object size
		
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

	if ( !main::SCANNER ) {
		# start purge routine in 10 seconds to purge all caches created during server and plugin startup
		require Slim::Utils::Timers;
		Slim::Utils::Timers::setTimer( undef, time() + 10, \&cleanup );
	}
}

# Backwards-compat
*instance = \&new;

sub new {
	my $class = shift;
	my $namespace = shift || DEFAULT_NAMESPACE;

	# return existing instance if exists for this namespace
	return $caches{$namespace} if $caches{$namespace};

	# otherwise create new cache object taking acount of additional params
	my ($version, $noPeriodicPurge);

	if ($namespace eq DEFAULT_NAMESPACE) {
		$version = DEFAULT_VERSION;
	} else {
		$version = shift || 0;
		$noPeriodicPurge = shift;
	}

	my $cache = Slim::Utils::DbCache->new( {
		namespace => $namespace,
	} );
	
	my $self = bless {
		_cache => $cache,
	}, $class;
	
	# empty existing cache if version number is different
	my $cacheVersion = $self->get('Slim::Utils::Cache-version');

	unless (defined $cacheVersion && $cacheVersion eq $version) {

		main::INFOLOG && $log->info("Version changed for cache: $namespace - clearing out old entries");
		$self->clear();
		$self->set('Slim::Utils::Cache-version', $version, -1);

	}

	# store cache object and add namespace to purge lists
	$caches{$namespace} = $self;
	
	push @eachCycle, $namespace unless $noPeriodicPurge;

	return $self;
}

sub cleanup {
	# This routine purges the complete list of namespaces, one per timer call
	# NB Purging is expensive and blocks the server
	#
	# namespaces with $noPeriodicPurge set are only purged at server startup
	# others are purged at max once per PURGE_INTERVAL.
	#
	# To allow disks to spin down, each namespace is purged within a short period 
	# and then no purging is done for PURGE_INTERVAL
	#
	# After the startup purge, if any players are on it reschedules in PURGE_RETRY

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
				$interval = PURGE_RETRY;
				last;
			}
		}
	}

	unless ($interval) {
		if (@thisCycle) {
			$interval = $startUpPurge ? 0.1 : PURGE_NEXT;
		} else {
			$interval = PURGE_INTERVAL;
			push @thisCycle, @eachCycle;
			
			# always run one purging task at startup
			$namespace ||= shift @thisCycle if $startUpPurge;
			$startUpPurge = 0;
		}
	}
	
	my $now = time();
	
	if ($namespace && $caches{$namespace}) {

		my $cache = $caches{$namespace};
		my $lastpurge = $cache->get('Slim::Utils::Cache-purgetime');

		unless ($lastpurge && ($now - $lastpurge) < PURGE_INTERVAL) {
			my $start = $now;
			
			$cache->purge;
			
			$cache->set('Slim::Utils::Cache-purgetime', $start, '-1');
			$now = time();
			if ( main::INFOLOG && $log->is_info ) {
				$log->info(sprintf("Cache purge: $namespace - %f sec", $now - $start));
			}
		} else {
			main::INFOLOG && $log->info("Cache purge: $namespace - skipping, purged recently");
		}
	}

	Slim::Utils::Timers::setTimer( undef, $now + $interval, \&cleanup );
}


1;
