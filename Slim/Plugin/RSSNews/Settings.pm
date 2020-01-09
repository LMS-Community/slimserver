package Slim::Plugin::RSSNews::Settings;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log   = logger('plugin.rssnews');
my $prefs = preferences('plugin.rssnews');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_RSSNEWS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/RSSNews/settings/basic.html');
}

sub prefs {
	return ($prefs, 'items_per_feed');
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	if ( $params->{reset} ) {

		$prefs->set( feeds => Slim::Plugin::RSSNews::Plugin::DEFAULT_FEEDS() );
		$prefs->set( modified => 0 );

		Slim::Plugin::RSSNews::Plugin::updateOPMLCache(Slim::Plugin::RSSNews::Plugin::DEFAULT_FEEDS());
	}
	
	my @feeds = @{ $prefs->get('feeds') };

	if ( $params->{saveSettings} ) {

		if ( my $newFeedUrl  = $params->{pref_newfeed} ) {
			validateFeed( $newFeedUrl, {
				cb  => sub {
					my $newFeedName = shift;
				
					push @feeds, {
						name  => $newFeedName,
						value => $newFeedUrl,
					};
				
					my $body = $class->saveSettings( $client, \@feeds, $params );
					$callback->( $client, $params, $body, @args );
				},
				ecb => sub {
					my $error = shift;
				
					$params->{warning}   .= Slim::Utils::Strings::string( 'SETUP_PLUGIN_RSSNEWS_INVALID_FEED', $error );
					$params->{newfeedval} = $params->{pref_newfeed};
				
					my $body = $class->saveSettings( $client, \@feeds, $params );
					$callback->( $client, $params, $body, @args );
				},
			} );
		
			return;
		}
	}

	return $class->saveSettings( $client, \@feeds, $params );
}

sub saveSettings {
	my ( $class, $client, $feeds, $params ) = @_;
	
	my @delete = @{ ref $params->{delete} eq 'ARRAY' ? $params->{delete} : [ $params->{delete} ] };

	for my $deleteItem  (@delete ) {
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
	$prefs->set( modified => 1 );

	Slim::Plugin::RSSNews::Plugin::updateOPMLCache($feeds);
	
	for my $feed ( @{$feeds} ) {
		push @{ $params->{prefs}->{feeds} }, [ $feed->{value}, $feed->{name} ];
	}
	
	return $class->SUPER::handler($client, $params);
}

sub validateFeed {
	my ( $url, $args ) = @_;

	main::INFOLOG && $log->info("validating $url...");

	Slim::Formats::XML->getFeedAsync(
		\&_validateDone,
		\&_validateError,
		{
			url     => $url,
			timeout => 10,
			cb      => $args->{cb},
			ecb     => $args->{ecb},
		}
	);
}

sub _validateDone {
	my ( $feed, $params ) = @_;
	
	my $title = $feed->{title} || $params->{url};
	
	main::INFOLOG && $log->info( "Verified feed $params->{url}, title: $title" );
		
	$params->{cb}->( $title );
}

sub _validateError {
	my ( $error, $params ) = @_;
	
	$log->error( "Error validating feed $params->{url}: $error" );
	
	$params->{ecb}->( $error );
}

1;

__END__
