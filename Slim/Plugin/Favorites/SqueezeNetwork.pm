package Slim::Plugin::Favorites::SqueezeNetwork;

# Pull favorites from the SN database

# $Id$

use strict;

use Scalar::Util qw(blessed);

use Slim::Utils::Log;

my $log = logger('favorites');

sub new {
	my ( $class, $client ) = @_;
	
	my $self = bless {
		userid => $client->playerData->userid->id,
	}, $class;
	
	return $self;
}

# Not part of the Favorites API, but needed by the Alarm Clock
sub all {
	my $self = shift;
	
	my @favs = SDI::Service::Model::Favorite->search(
		userid => $self->{userid},
		{
			order_by => 'num'
		}
	);
	
	my $all = [];
	
	for my $fav ( @favs ) {
		push @{$all}, {
			title => $fav->title,
			url   => $fav->url,
		};
	}
	
	return $all;
}

sub add {
	my ( $self, $url, $title ) = @_;
	
	if ( blessed($url) && $url->can('url') ) {
		$url = $url->url;
	}
	
	# See if this favorite already exists
	my ($fav) = SDI::Service::Model::Favorite->search(
		userid => $self->{userid},
		url    => $url,
	);
	
	if ( !$fav ) {	
		my $max = SDI::Service::Model::Favorite->max( $self->{userid} );
	
		$fav = SDI::Service::Model::Favorite->find_or_create( {
			userid => $self->{userid},
			url    => $url,
			title  => $title,
			num    => $max + 1,
		} );
		
		main::DEBUGLOG && $log->debug( "Added favorite $title ($url) at index " . ( $max + 1 ) );
	}
	else {
		$fav->title( $title );
		$fav->update;
		
		main::DEBUGLOG && $log->debug("Favorite $url already exists");
	}
	
	# NOMEMCACHE
	# Slim::Utils::Cache->new->set( 'favorites_last_mod_' . $self->{userid}, time(), 86400 * 30 );
	
	return $fav->num - 1;
}

sub hasUrl {
	my ( $self, $url ) = @_;
	
	my $fav = SDI::Service::Model::Favorite->findByUserAndURL( $self->{userid}, $url );
	
	if ( $fav ) {
		main::DEBUGLOG && $log->debug( "User has favorite $url" );
		return 1;
	}
	
	return;
}

sub findUrl {
	my ( $self, $url ) = @_;
	
	my $fav = SDI::Service::Model::Favorite->findByUserAndURL( $self->{userid}, $url );

	if ( $fav ) {
		main::DEBUGLOG && $log->is_debug && $log->debug( "User has favorite $url at index " . $fav->num );
		return $fav->num - 1;
	}

	return;
}

sub deleteUrl {
	my ( $self, $url ) = @_;
	
	my $fav = SDI::Service::Model::Favorite->findByUserAndURL( $self->{userid}, $url );
	
	if ( $fav ) {
		SDI::Service::Model::Favorite->deleteAndRenumber( $self->{userid}, $fav->id );
		
		main::DEBUGLOG && $log->debug( "Deleted favorite for $url" );
		
		# NOMEMCACHE
		# Slim::Utils::Cache->new->set( 'favorites_last_mod_' . $self->{userid}, time(), 86400 * 30 );
		
		return 1;
	}
	
	return;
}

sub deleteIndex {
	my ( $self, $index ) = @_;
	
	my ($fav) = SDI::Service::Model::Favorite->search(
		userid => $self->{userid},
		num    => $index + 1,
	);
	
	if ( $fav ) {
		main::DEBUGLOG && $log->is_debug && $log->debug( "Deleted favorite index $index (" . $fav->url . ")" );
		
		SDI::Service::Model::Favorite->deleteAndRenumber( $self->{userid}, $fav->id );
		
		Slim::Utils::Cache->new->set( 'favorites_last_mod_' . $self->{userid}, time(), 86400 * 30 );
		
		return 1;
	}
	
	return;
}

sub entry {
	my ( $self, $index ) = @_;
	
	my ($fav) = SDI::Service::Model::Favorite->search(
		userid => $self->{userid},
		num    => $index + 1,
	);
	
	if ( $fav ) {
		return {
			title => $fav->title,
			text  => $fav->title,
			URL   => $fav->url,
			type  => 'audio',
		};
	}
	
	return;
}

# legacy method to support migration to presets
sub hotkeys {
	my $self = shift;

	my @keys;

	for my $key (1..9,0) {
		my ($item) = SDI::Service::Model::Favorite->search(
			userid => $self->{userid},
			hotkey => $key,
		);
		push @keys, {
			key   => $key,
			used  => $item ? 1 : 0,
			title => $item ? $item->title : undef,
			index => $item ? $item->num - 1 : undef,
		};
	}

	return \@keys;
}

1;
