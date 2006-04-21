# Runtime Cache
# Copyright (c) 2005 Slim Devices, Inc. (www.slimdevices.com)

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# A simple cache for arbitrary data using FileCache.
# TODO: use timers to periodically clean up expired entries. (currently does lazy cleanup)

package Slim::Utils::Cache;

use strict;
use base qw(Class::Singleton);
use Cache::FileCache ();
use Slim::Utils::Prefs;

sub new { shift->instance(@_) }

sub _new_instance {
	my $class = shift;
	
	my $cache = Cache::FileCache->new( {
		namespace          => 'FileCache',
		default_expires_in => $Cache::FileCache::EXPIRES_NEVER,
		cache_root         => Slim::Utils::Prefs::get('cachedir'),
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

1;
