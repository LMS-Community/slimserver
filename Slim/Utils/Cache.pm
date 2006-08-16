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
use Slim::Utils::Prefs;

sub new { shift->instance(@_) }

sub _new_instance {
	my $class = shift;
	
	my $cache = Cache::FileCache->new( {
		namespace           => 'FileCache',
		default_expires_in  => $Cache::FileCache::EXPIRES_NEVER,
		cache_root          => Slim::Utils::Prefs::get('cachedir'),
		auto_purge_interval => '1 hour',
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
