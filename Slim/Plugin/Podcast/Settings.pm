package Slim::Plugin::Podcast::Settings;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Favorites;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings;
use Slim::Networking::SqueezeNetwork;

my $log   = logger('plugin.podcast');
my $prefs = preferences('plugin.podcast');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_PODCAST');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/Podcast/settings/basic.html');
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	if ( $params->{saveSettings} && $params->{newfeed} && !grep { $_->{value} eq $params->{newfeed} } @{ $prefs->get('feeds') } ) {
		$class->validateFeed($client, $params, $callback, \@args);
		return;
	}
	
	elsif ( $params->{importFromMySB} ) {
		$class->importFromMySB($client, $params, $callback, \@args);
		return;
	}

	return $class->saveSettings( $client, $params, $callback, \@args );
}

sub saveSettings {
	my ( $class, $client, $params, $callback, $args ) = @_;
	
	my $feeds = $prefs->get('feeds');

	if ( $params->{saveSettings} ) {
		
		# save re-ordered stream list
		my $ordered = $params->{feedorder};
		$ordered = [ $ordered ] unless ref $ordered eq 'ARRAY';
	
		my @new = map { $feeds->[$_] } @$ordered;
		
		# push newly added stream (if any) on new feeds list
		push @new, $feeds->[-1] if scalar @$feeds > scalar @new;
		$feeds = \@new;
		
		my @delete = @{ ref $params->{delete} eq 'ARRAY' ? $params->{delete} : [ $params->{delete} ] };
	
		for my $deleteItem (@delete) {
			
			next unless defined $deleteItem;
			
			my $i = 0;
			while ( $i < scalar @{$feeds} ) {
				if ( $deleteItem eq $feeds->[$i]->{value} ) {
					splice @{$feeds}, $i, 1;
					next;
				}
				$i++;
			}
		}
	
		$prefs->set( feeds => $feeds );
	}

	for my $feed ( @{$feeds} ) {
		push @{ $params->{prefs} }, [ $feed->{value}, $feed->{name} ];
	}
	
	my $body = $class->SUPER::handler($client, $params);
	return $callback->( $client, $params, $body, @$args );
}

sub validateFeed {
	my ( $class, $client, $params, $callback, $args ) = @_;
	
	my $newFeedUrl = $params->{newfeed};
	
	$log->info("validating $newFeedUrl...");

	Slim::Formats::XML->getFeedAsync(
		sub {
			my ( $feed ) = @_;
			
			my $title = $feed->{title} || $newFeedUrl;
			
			$log->info( "Verified feed $newFeedUrl, title: $title" );
				
			my $feeds = $prefs->get('feeds');
			push @$feeds, {
				name  => $title,
				value => $newFeedUrl,
			};
			
			$prefs->set( feeds => $feeds );
		
			$class->saveSettings( $client, $params, $callback, $args );
		},
		sub {
			my ( $error ) = @_;
			
			$log->error( "Error validating feed $newFeedUrl: $error" );
		
			$params->{warning}   .= string( 'SETUP_PLUGIN_PODCAST_INVALID_FEED', $error );
			$params->{newfeedval} = $newFeedUrl;
		
			$class->saveSettings( $client, $params, $callback, $args );
		},
		{
			url     => $newFeedUrl,
			timeout => 10,
		}
	);
}

sub importFromMySB {
	my ( $class, $client, $params, $callback, $args ) = @_;

	my $url = $class->getMySBPodcastsUrl();

	my $ecb = sub {
		my ( $error ) = @_;
		
		$log->error( "Error importing feeds from mysqueezebox.com: $error" );
		$params->{warning} .= string( 'SETUP_PLUGIN_PODCAST_INVALID_FEED', $error );
	
		$class->saveSettings( $client, $params, $callback, $args );
	};


	if ( $url ) {
		$log->info( "Trying to get podcast list from mysqueezebox.com: $url" );
		
		Slim::Formats::XML->getFeedAsync(
			sub {
				my ( $feed ) = @_;
				
				my $feeds = $prefs->get('feeds');
				my %urls  = map { $_->{value} => 1 } @$feeds;
				
				if ( $feed->{items} && ref $feed->{items} eq 'ARRAY' ) {
					foreach ( @{ $feed->{items} }) {
						my $url = $_->{url} || $_->{value};
						
						if ( !$urls{$url} ) {
							push @$feeds, {
								name  => $_->{name} || $url,
								value => $url
							};
							
							$urls{$url}++;
						}
					}
				}

				$prefs->set( feeds => $feeds );
			
				delete $params->{saveSettings};
				
				$class->saveSettings( $client, $params, $callback, $args );
			},
			$ecb,
			{
				url     => $url,
				timeout => 15,
			}
		);
	}
	else {
		$ecb->(string('PLUGIN_PODCAST_IMPORT_FROM_MYSB_FAILED'))
	}
}

sub getMySBPodcastsUrl {
	my $url;
	
	foreach ( @{ Slim::Utils::Favorites->new->toplevel } ) {
		if ( $_->{URL} =~ m|^http://.*mysqueezebox\.com/public/opml/.*/favorites\.opml| ) {
			
			$url = $_->{URL};
			$url =~ s/favorites/podcasts/;
			
			last;
		}
	}
	
	return $url;
}

1;

__END__
