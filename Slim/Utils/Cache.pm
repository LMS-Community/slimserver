# Copyright (c) 2005 Slim Devices, Inc. (www.slimdevices.com)

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Slim::Utils::Cache;

=head1 NAME

Slim::Utils::Cache

=head1 SYNOPSIS

my $cache = Slim::Utils::Cache->new

$cache->set($file, $data);

my $data = $cache->get($file);

$cache->remove($file);

$cache->cleanup;

=head1 DESCRIPTION

A simple cache for arbitrary data using L<Cache::FileCache>.

=head1 METHODS

=head2 new()

Creates a new Slim::Utils::Cache instance.

=head1 SEE ALSO

L<Cache::Cache> and L<Cache::FileCache>.

=cut

use strict;
use base qw(Class::Singleton);
use Cache::FileCache ();
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

my $PURGE_INTERVAL = 3600;

sub init {
	my $class = shift;
	
	# Clean up the cache at startup
	__PACKAGE__->new->purge();
	
	# And continue to clean it up regularly
	Slim::Utils::Timers::setTimer( undef, time() + $PURGE_INTERVAL, \&cleanup );
}

sub new { shift->instance(@_) }

sub _new_instance {
	my $class = shift;
	
	my $cache = Cache::FileCache->new( {
		namespace          => 'FileCache',
		default_expires_in => $Cache::FileCache::EXPIRES_NEVER,
		cache_root         => Slim::Utils::Prefs::get('cachedir'),
		directory_umask    => umask(),
	} );
	
	my $self = bless {
		_cache => $cache,
	}, $class;
	
	# create proxy methods
	{
		my @methods = qw(
			get set get_object set_object
			clear purge remove size
		);
		
		no strict 'refs';
		for my $method (@methods) {
			*{"$class\::$method"} = sub {
				return shift->{_cache}->$method(@_);
			};
		}
	}
	
	return $self;
}

sub cleanup {
	
	# Use the same method the Scheduler uses to run only when idle
	my $busy;
	
	for my $client ( Slim::Player::Client::clients() ) {

		if (Slim::Player::Source::playmode($client) eq 'play' && 
		    $client->isPlayer() && 
		    $client->usage() < 0.5) {

			$busy = 1;
			last;
		}
	}
	
	if ( !$busy ) {
		$::d_server && msg("Cache: Cleaning up expired items...\n");
	
		__PACKAGE__->new->purge();
	
		$::d_server && msg("Cache: Done\n");
		
		Slim::Utils::Timers::setTimer( undef, time() + $PURGE_INTERVAL, \&cleanup );
	}
	else {
		# try again soon
		$::d_server && msg("Cache: Skipping cleanup, server is busy\n");
		Slim::Utils::Timers::setTimer( undef, time() + ($PURGE_INTERVAL / 6), \&cleanup );
	}	
}

1;
