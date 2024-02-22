package Slim::Plugin::Podcast::Settings;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Favorites;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

my $log   = logger('plugin.podcast');
my $prefs = preferences('plugin.podcast');
my @hidden = qw(maxNew newSince country);

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_PODCAST');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/Podcast/settings/basic.html');
}

sub prefs {
	return ($prefs, qw(skipSecs provider), @hidden);
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	if ( $params->{saveSettings} && $params->{newfeed} && !grep { $_->{value} eq $params->{newfeed} } @{ $prefs->get('feeds') } ) {
		$class->validateFeed($client, $params, $callback, \@args);
		return;
	}

	return $class->saveSettings( $client, $params, $callback, \@args );
}

sub beforeRender {
	my ($class, $params, $client) = @_;
	my $provider = Slim::Plugin::Podcast::Plugin::getProviderByName;
	$params->{newsHandler} = defined $provider->can('newsHandler');
	$params->{hasCountry} = $provider->hasCountry;
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

		# don't erase hidden parameters if they are not set
		foreach (@hidden) {
			$params->{"pref_$_"} //= $prefs->get($_);
		}

		$prefs->set( feeds => $feeds );
	}

	# set the list of providers
	$params->{providers} = Slim::Plugin::Podcast::Plugin::getProviders;

	for my $feed ( @{$feeds} ) {
		push @{ $params->{prefs}->{feeds} }, [ $feed->{value}, $feed->{name} ];
	}

	my $body = $class->SUPER::handler($client, $params);

	return $callback->( $client, $params, $body, @$args );
}

sub validateFeed {
	my ( $class, $client, $params, $callback, $args ) = @_;

	my $newFeedUrl = $params->{newfeed};

	main::INFOLOG && $log->is_info && $log->info("validating $newFeedUrl...");

	Slim::Formats::XML->getFeedAsync(
		sub {
			my ( $feed ) = @_;

			my $title = $feed->{title} || $newFeedUrl;

			main::INFOLOG && $log->is_info && $log->info( "Verified feed $newFeedUrl, title: $title" );

			Slim::Control::Request::executeRequest(undef, ["podcasts", "addshow", $newFeedUrl, $title]);

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

1;

__END__
