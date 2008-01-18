package Slim::Plugin::RSSNews::Settings;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log   = logger('plugin.rssnews');
my $prefs = preferences('plugin.rssnews');

use constant FEED_VERSION => 2; # bump this number when changing the defaults below

# Default feed list
my @default_feeds = (
	{
		name  => 'BBC News World Edition',
		value => 'http://news.bbc.co.uk/rss/newsonline_world_edition/front_page/rss.xml',
	},
	{
		name  => 'CNET News.com',
		value => 'http://news.com.com/2547-1_3-0-5.xml',
	},
	{
		name  => 'New York Times Home Page',
		value => 'http://www.nytimes.com/services/xml/rss/nyt/HomePage.xml',
	},
	{
		name  => 'RollingStone.com Music News',
		value => 'http://www.rollingstone.com/rssxml/music_news.xml',
	},
	{
		name  => 'Slashdot',
		value => 'http://rss.slashdot.org/Slashdot/slashdot',
	},
	{
		name  => 'Yahoo! News: Business',
		value => 'http://rss.news.yahoo.com/rss/business',
	},
);

# migrate old prefs across
$prefs->migrate(1, sub {
	my @names  = @{Slim::Utils::Prefs::OldPrefs->get('plugin_RssNews_names') || [] };
	my @values = @{Slim::Utils::Prefs::OldPrefs->get('plugin_RssNews_feeds') || [] };
	my @feeds;

	for my $name (@names) {
		push @feeds, { 'name' => $name, 'value' => shift @values };
	}

	if (@feeds) {
		$prefs->set('feeds', \@feeds);
		$prefs->set('modified', 1);
	}

	$prefs->set('items_per_feed', Slim::Utils::Prefs::OldPrefs->get('plugin_RssNews_items_per_feed') || 3);

	1;
});

# migrate to latest version of default feeds if they have not been modified
$prefs->migrate(FEED_VERSION, sub {
	$prefs->set('feeds', \@default_feeds) unless $prefs->get('modified');
	1;
});

sub name {
	return Slim::Web::HTTP::protectName('PLUGIN_RSSNEWS');
}

sub page {
	return Slim::Web::HTTP::protectURI('plugins/RSSNews/settings/basic.html');
}

sub prefs {
	return ($prefs, 'items_per_feed');
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	if ( $params->{reset} ) {

		$prefs->set( feeds => \@default_feeds );
		$prefs->set( modified => 0 );

		Slim::Plugin::RSSNews::Plugin::updateOPMLCache(\@default_feeds);
	}
	
	my @feeds = @{ $prefs->get('feeds') };

	if ( $params->{saveSettings} ) {

		if ( my $newFeedUrl  = $params->{newfeed} ) {
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
					$params->{newfeedval} = $params->{newfeed};
				
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

	$log->info("validating $url...");

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
	
	$log->info( "Verified feed $params->{url}, title: $title" );
		
	$params->{cb}->( $title );
}

sub _validateError {
	my ( $error, $params ) = @_;
	
	$log->error( "Error validating feed $params->{url}: $error" );
	
	$params->{ecb}->( $error );
}

1;

__END__
