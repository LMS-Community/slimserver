# RssNews Ticker v1.0
# $Id: RssNews.pm,v 1.9 2004/11/23 22:26:16 dave Exp $
# Copyright (c) 2004 Slim Devices, Inc. (www.slimdevices.com)

# Based on BBCTicker 1.3 which had this copyright...
# Copyright (c) 2002-2004 Gordon Johnston (gordonj@newswall.org.uk)
# http://newswall.org.uk/~slimp3/news_ticker.html

# Also based on Vidur Apparao's Yahoo News plugin.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

package Plugins::RssNews;
use strict;

# User Agent used to retrieve RSS feeds via HTTP
my $ua;

# plugin state variables.
my %feed_urls;
my %feed_names;
my @feed_order;
my %context;
my $screensaver_mode = 0;

# in screensaver mode, number of items to display per channel before switching
my $screensaver_items_per_feed;

# how long to scroll news before switching channels.
my $screensaver_sec_per_channel = 0; # if 0, we use sec_per_letter instead
my $screensaver_sec_per_letter = (1/6); # about 6 letters per second
my $screensaver_sec_per_letter_double = (1/4); # When extra large fonts shown

# How to display items shown by screen saver.
# %1\$s is item 'number'
# %2\$s is item title
# %3\%s is item description
my $screensaver_item_format = "%2\$s -- %3\$s                         ";

# defaults only if file not found...
use constant FEEDS_VERSION => 1.0;
my %default_feeds = (
					 'BBC News World Edition' => 'http://news.bbc.co.uk/rss/newsonline_world_edition/front_page/rss091.xml',
					 'CNET News.com' => 'http://news.com.com/2547-1_3-0-5.xml',
					 'New York Times Home Page' => 'http://www.nytimes.com/services/xml/rss/nyt/HomePage.xml',
					 'RollingStone.com Music News' => 'http://www.rollingstone.com/rssxml/music_news.xml',
					 'Slashdot' => 'http://slashdot.org/index.rss',
					 'Yahoo! News: Business' => 'http://rss.news.yahoo.com/rss/business',
);

#my @default_names = (
#);



######
# CHANGELOG
######
#
# Initial version based in part on Yahoo News plugin and BbcNews.pm version 1.3
# 

######
# TODO
######
#
#
######

# INTERNAL VARIABLES and STUFF!. Do not edit.
use Slim::Buttons::Common;
use Slim::Web::RemoteStream;
use Slim::Control::Command;
use Slim::Utils::Strings qw (string);
use Slim::Utils::Timers;
use Slim::Utils::Misc;
use Socket;
use vars qw($VERSION);

use LWP::UserAgent;
use XML::Simple;
use File::Spec::Functions qw(:ALL);

use Slim::Utils::Prefs;

$VERSION = substr(q$Revision: 1.9 $,10);
my %thenews = ();
my $state = "wait";
my $refresh_last = 0;
my $screensaver_timeout = 0;
my $screensaver_reset_interval = 0;
my $running_as = 'plugin';
# $refresh_min is the minimum time in seconds between refreshes of the ticker from the RSS.
# Please do not lower this value. It prevents excessive queries to the RSS.
# This value is ignored when a refresh is manually requested via the remote.
my $refresh_sec = 30 * 60; 

sub strings() { return q!
PLUGIN_RSSNEWS
	EN	RSS News Ticker
	
PLUGIN_RSSNEWS_ADD_NEW
	EN	Add new feed -->
	
PLUGIN_RSSNEWS_WAIT
	EN	Please wait requesting...

PLUGIN_RSSNEWS_ERROR
	EN	Failed to retrieve RSS feed

PLUGIN_RSSNEWS_NO_DESCRIPTION
	EN	Description not available

PLUGIN_RSSNEWS_SCREENSAVER
	EN	RSS News Ticker

PLUGIN_RSSNEWS_NAME
	EN	RSS News Ticker

PLUGIN_RSSNEWS_SCREENSAVER_SETTINGS
	EN	RSS News Screensaver Settings

PLUGIN_RSSNEWS_SCREENSAVER_ACTIVATE
	EN	Select Current Screensaver

PLUGIN_RSSNEWS_SCREENSAVER_ACTIVATE_TITLE
	EN	Current Screensaver

PLUGIN_RSSNEWS_SCREENSAVER_ACTIVATED
	EN	Use RSS News as current screensaver

PLUGIN_RSSNEWS_SCREENSAVER_DEFAULT
	EN	Use default screensaver (not RSS News)

PLUGIN_RSSNEWS_SCREENSAVER_ENABLE
	EN	Activating ticker as current screensaver

PLUGIN_RSSNEWS_SCREENSAVER_DISABLE
	EN	Returning to default screensaver

PLUGIN_RSSNEWS_ERROR_IN_FEED
	EN	Error parsing RSS feed

PLUGIN_RSSNEWS_LOADING_FEED
	EN	Loading RSS feed...

SETUP_GROUP_PLUGIN_RSSNEWS
	EN	RSS News Ticker

SETUP_GROUP_PLUGIN_RSSNEWS_DESC
	EN	The RSS News Ticker plugin can be used to browse and display items from RSS Feeds. The preferences below can be used to determine which RSS Feeds to use and control how they are displayed. Click on the Change button when you are done.

SETUP_PLUGIN_RSSNEWS_FEEDS
	EN	Modify RSS feeds

SETUP_PLUGIN_RSSNEWS_FEEDS_DESC
	EN	This is the list of RSS Feeds to display. To add a new one, just type its URL into the empty line. To remove one, simply delete the URL from the corresponding line. To change the URL of an existing feed, edit its text value. Click on the Change button when you are done.

SETUP_PLUGIN_RSSNEWS_RESET
	EN	Reset default RSS feeds

SETUP_PLUGIN_RSSNEWS_RESET_DESC
	EN	Click the Reset button to revert to the default set of RSS Feeds.

PLUGIN_RSSNEWS_RESETTING
	EN	Resetting to default RSS Feeds.

SETUP_PLUGIN_RSSNEWS_RESET_BUTTON
	EN	Reset

SETUP_PLUGIN_RSSNEWS_ITEMS_PER_FEED
	EN	Items displayed per channel

SETUP_PLUGIN_RSSNEWS_ITEMS_PER_FEED_DESC
	EN	The maximum number of items displayed for each feed while the screensaver is active. A larger value implies that the screensaver will display more items before switching to the next feed.

SETUP_PLUGIN_RSSNEWS_ITEMS_PER_FEED_CHOOSE
	EN	Items per channel

SETUP_PLUGIN_RSSNEWS_FEEDS_CHANGE
	EN	RSS Feeds list changed.
!};

sub param {
	my $client = shift;
	my $paramname = shift;
	my $paramvalue = shift;
	# why isn't this a method on Client?????
	return Slim::Buttons::Common::param($client, $paramname, $paramvalue);
}

# Plugin descriptions

sub getDisplayName() {return string('PLUGIN_RSSNEWS')}

# advance to next RSS feed
sub nextTopic {
    my $client = shift;
	my $display_current;
	
	my $display_stack = param($client, 'PLUGIN.RssNews.display_stack');
    #if there are no topics left then wrap around if selected (always wrap when running as screensaver)
    if((!$display_stack) ||
	   (scalar(@$display_stack) == 0)) {
        my @display_stack_copy = @feed_order;
		$display_stack = \@display_stack_copy;
		param($client, 'PLUGIN.RssNews.display_stack', $display_stack);
    }
	
    #Move up the list of topics
    if($display_stack) {
        $display_current=shift @{$display_stack};
		param($client, 'PLUGIN.RssNews.display_current', $display_current);
    } else {
		assert(0, 'display stack empty');
	}
	# returns a feed name (not the URL)
	return $display_current;
}

# initialize the list of channels (feeds) to display
sub initPlugin {
	my @feedURLPrefs = Slim::Utils::Prefs::getArray("plugin_RssNews_feeds");
	my @feedNamePrefs = Slim::Utils::Prefs::getArray("plugin_RssNews_names");
	my $feedsModified = Slim::Utils::Prefs::get("plugin_RssNews_feeds_modified");
	my $version = Slim::Utils::Prefs::get("plugin_RssNews_feeds_version");

	# No prefs set or we've had a version change and they weren't modified, 
	# so we'll use the defaults
	if (scalar(@feedURLPrefs) == 0 || 
		(!$feedsModified && (!$version  || $version != FEEDS_VERSION))) {
		my @default_names = sort(keys (%default_feeds));
		@feedURLPrefs = map $default_feeds{$_}, @default_names;
	    Slim::Utils::Prefs::set("plugin_RssNews_feeds", \@feedURLPrefs);
		@feedNamePrefs = @default_names;
	    Slim::Utils::Prefs::set("plugin_RssNews_names", \@feedNamePrefs);
	    Slim::Utils::Prefs::set("plugin_RssNews_feeds_version", FEEDS_VERSION);
	}

	@feed_urls{@feedNamePrefs} = @feedURLPrefs;
	%feed_names = reverse %feed_urls;
    @feed_order = @feedNamePrefs;

    if ($::d_plugins) {
        msg("RSS Feed Info:\n");
        foreach (@feed_order) {
            msg("$_, $feed_urls{$_} \n");
        }
        msg("\n");
    }

	$screensaver_items_per_feed = Slim::Utils::Prefs::get('plugin_RssNews_items_per_feed');
	unless (defined $screensaver_items_per_feed) {
		$screensaver_items_per_feed = 3;
		Slim::Utils::Prefs::set('plugin_RssNews_items_per_feed', 
								$screensaver_items_per_feed);
	}
}

sub updateFeedNames {
	my @feedURLPrefs = Slim::Utils::Prefs::getArray("plugin_RssNews_feeds");
	my @names = ();

	for my $feed (@feedURLPrefs) {
		if ($feed) {
			my $name = $feed_names{$feed};
			if ($name && $name !~ /^http\:/) {
				push @names, $name;
			}
			elsif ($feed =~ /^http\:/) {
				my $xml = getFeedXml($feed);
				if ($xml && exists $xml->{channel}->{title}) {
					push @names, $xml->{channel}->{title};
				}
				else {
					push @names, $feed;
				}
			}
		}
	}

	# No prefs set, so we'll use the defaults
	if (scalar(@names) == 0) {
		my @default_names = sort(keys (%default_feeds));
		@feedURLPrefs = map {$default_feeds{$_}} @default_names;
	    Slim::Utils::Prefs::set("plugin_RssNews_feeds", \@feedURLPrefs);
	    Slim::Utils::Prefs::set("plugin_RssNews_names", \@default_names);
		@names = @default_names;
	}
	elsif (join('', sort @feedURLPrefs) ne join('', sort values %default_feeds)) {
		Slim::Utils::Prefs::set("plugin_RssNews_feeds_modified", 1);
	}

	Slim::Utils::Prefs::set("plugin_RssNews_names", \@names);
	@feed_urls{@names} = @feedURLPrefs;
	%feed_names = reverse %feed_urls;
    @feed_order = @names;	
}

sub initUserAgent {
    my $proxy = Slim::Utils::Prefs::get('webproxy');
    # set parse_head to 0 so news feeds which claim to be HTML do not cause HeadParser.pm not to be found. (i.e. Rolling Stones Music News)
    $ua = LWP::UserAgent->new('parse_head' => 0);
    $ua->timeout(5);
    if ($proxy) {
        $ua->proxy('http', "http://$proxy");
    }
}

sub unescape {
	my $data = shift;

	return '' unless(defined($data));

	use utf8; # required for 5.6
	
	$data =~ s/&amp;/&/sg;
	$data =~ s/&lt;/</sg;
	$data =~ s/&gt;/>/sg;
	$data =~ s/&quot;/\"/sg;
	$data =~ s/&bull;/\*/sg;
	$data =~ s/&mdash;/-/sg;
	$data =~ s/&\#(\d+);/chr($1)/gse;

	return $data;
}

sub trim {
	my $data = shift;
	return '' unless(defined($data));
	use utf8; # important for regexps that follow

	$data =~ s/\s+/ /g; # condense multiple spaces
	$data =~ s/^\s//g; # remove leading space
	$data =~ s/\s$//g; # remove trailing spaces

	return $data;
}

# unescape and also remove unnecesary spaces
# also get rid of markup tags
sub unescapeAndTrim {
	my $data = shift;
	return '' unless(defined($data));
	use utf8; # important for regexps that follow
	my $olddata = $data;
	
	$data = unescape($data);

	$data = trim($data);
	
	# strip all markup tags
	$data =~ s/<[a-zA-Z\/][^>]*>//gi;

	# apparently utf8::decode is not available in perl 5.6.
	# (Some characters may not appear correctly in perl < 5.8 !)
	if ($] >= 5.008) {
		utf8::decode($data);
	  }

	return $data;
}

sub getFeedXml {
    my $feed_url = shift;
    
    if (!$ua) {
        initUserAgent();
    }

    my $response = $ua->get($feed_url);
    
    if ($response->is_success && $response->content) {
        my $xml;
		# forcearray to treat items as array,
		# keyattr => [] prevents id attrs from overriding
        eval {$xml = XMLin($response->content,
						   forcearray => ["item"],
						   keyattr => [])};
        if ($@) {
            return 0;  
        }
        return $xml;
    }
    return 0;
}

sub retrieveNews {
    my $client = shift;
    my $feedname = shift;

    my $now = time();
    
    my $must_get_news = 0;
	my $display_current = param($client, 'PLUGIN.RssNews.display_current');

    if (!$display_current) {
		# should never be here, but just in case...
		$display_current = nextTopic($client);
    }
	
    if (!$feedname) {
        $feedname = $display_current;
    } else {
    }
    
    if (!$thenews{$feedname}) {
        $must_get_news = 1;
    } elsif ($now - $thenews{$feedname}{"refresh_last"} > $refresh_sec) {
        $must_get_news = 1;
    }
    
    if ($must_get_news) {
        $thenews{$feedname} = ();
		if (!Slim::Buttons::Common::param($client, 'PLUGIN.RssNews.screensaver_mode')){
			Slim::Buttons::Block::block($client, 
										string('PLUGIN_RSSNEWS_LOADING_FEED'));
		}

        my $xml = getFeedXml($feed_urls{$feedname});

		if (!Slim::Buttons::Common::param($client, 'PLUGIN.RssNews.screensaver_mode')) {
			Slim::Buttons::Block::unblock($client);
		}

		my $show_error = 0;
        if ($xml) {
            if ($xml->{channel}) {
                $thenews{$feedname} = $xml->{channel};
                # slashdot needs this, yahoo doesn't
                if ($xml->{item}) {
                    $thenews{$feedname}->{item} = $xml->{item};
                }
            } else {
                # TODO: better error handling
                $::d_plugins && msg("RssNews.pm failed to parse from $feed_urls{$feedname}. \n");
				$show_error = 1;
            }
        } else {
            # TODO: better error handling
            $::d_plugins && msg("RssNews.pm failed to retrieve news from $feed_urls{$feedname}.\n");
			$show_error = 1;
        }
		if ($show_error) {
			# we did not get the news
			Slim::Display::Animation::showBriefly($client, 
												  string('PLUGIN_RSSNEWS_ERROR_IN_FEED'));
		  } else {
			  # record the time we last got the news
			  $thenews{$feedname}{"refresh_last"} = $now;
		  }
    }
	
    return $thenews{$feedname};
}

sub setupGroup {
	my %Group = (
		PrefOrder => [
			'plugin_RssNews_items_per_feed', 'plugin_RssNews_reset', 'plugin_RssNews_feeds', 
		],
		GroupHead => string( 'SETUP_GROUP_PLUGIN_RSSNEWS' ),
		GroupDesc => string( 'SETUP_GROUP_PLUGIN_RSSNEWS_DESC' ),
		GroupLine => 1,
		GroupSub => 1,
		Suppress_PrefSub  => 1,
		Suppress_PrefLine => 1,
	);

	my %Prefs = (
		plugin_RssNews_items_per_feed => {
			'validate' => \&Slim::Web::Setup::validateInt
			,'validateArgs' => [1,undef,1]
			,'onChange' => sub {
				$screensaver_items_per_feed = $_[1]->{plugin_RssNews_items_per_feed}->{new};
				Slim::Utils::Prefs::set('plugin_RssNews_items_per_feed', 
										$screensaver_items_per_feed);
			}
		},
		plugin_RssNews_reset => {
			'validate' => \&Slim::Web::Setup::validateAcceptAll
			,'onChange' => sub {
				Slim::Utils::Prefs::set("plugin_RssNews_feeds_modified", undef);
				Slim::Utils::Prefs::set("plugin_RssNews_feeds_version", undef);
				initPlugin();
			}
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => string('PLUGIN_RSSNEWS_RESETTING')
			,'ChangeButton' => string('SETUP_PLUGIN_RSSNEWS_RESET_BUTTON')
			,'dontSet' => 1
			,'changeMsg' => ''
		},
		plugin_RssNews_feeds => { 
			'isArray' => 1
			,'arrayAddExtra' => 1
			,'arrayDeleteNull' => 1
			,'arrayDeleteValue' => ''
			,'arrayBasicValue' => 0
			,'PrefSize' => 'large'
			,'inputTemplate' => 'setup_input_array_txt.html'
			,'PrefInTable' => 1
			,'showTextExtValue' => 1
			,'externalValue' => sub {
				my ($client, $value, $key) = @_;
				
				if ($key =~ /^(\D*)(\d+)$/ && ($2 < scalar(@feed_order))) {
					return $feed_order[$2];
				}

				return '';
			}
			,'onChange' => sub {
				my ($client,$changeref,$paramref,$pageref) = @_;
				if (exists($changeref->{'plugin_RssNews_feeds'}{'Processed'})) {
					return;
				}
				Slim::Web::Setup::processArrayChange($client,
													 'plugin_RssNews_feeds',
													 $paramref, $pageref);
				updateFeedNames();

				$changeref->{'plugin_RssNews_feeds'}{'Processed'} = 1;
			}
			,'changeMsg' => string('SETUP_PLUGIN_RSSNEWS_FEEDS_CHANGE')
		},
	);

	return( \%Group, \%Prefs );
}


################################
# ScreenSaver Mode
#

sub autoScrollTimer {
    my $client = shift;
    
    my $display_current = &nextTopic($client);
    # retrieveNews will only really get new news after refresh_sec time
    &retrieveNews($client, $display_current);
	
	# forget any lines we've cached...
	Slim::Buttons::Common::param($client, 'PLUGIN.RssNews.lines',
								 0);
	# ensure the display is refreshed
    $client->update();
	
    my $wait_time;
    if ($screensaver_sec_per_channel > 0) {
        $wait_time = $screensaver_sec_per_channel;
    } else {
        my ($line1, $line2) = lines($client);
		$::d_plugins && assert($line2, 'Line2 not defined.\n');
		# when is line2 not defined?  Occasionally, but I'm not sure why.
		# its not really a problem because the screensaver will simply go the next topic, but this code prevents any message from appearing.
		if (!$line2) {
			$line2 = '';
		}
		if ($client->linesPerScreen() != 1) {
			$wait_time = length($line2) * $screensaver_sec_per_letter;
		} else {
			$wait_time = length($line2) * $screensaver_sec_per_letter_double;
		}
    }
    
    Slim::Utils::Timers::setTimer($client, time() + $wait_time,
                                  \&autoScrollTimer);
}

sub lines {
    #This returns the 2 lines to display on the unit 
    my $client = shift;
    my $lineref;
    my $now = time();

	# the current RSS feed
	my $display_current = param($client, 'PLUGIN.RssNews.display_current');
	assert($display_current, 'current rss feed not set\n');

	# the current item within each feed.
	my $display_current_items = param($client, 'PLUGIN.RssNews.display_current_items');

	#remember which item in feed we are currently showing
	# this will be stored on a per-client basis
	if (!defined ($display_current_items)) {
		$display_current_items = {$display_current => {'next_item' => 0}};
	} elsif (!defined($display_current_items->{$display_current})) {
		$display_current_items->{$display_current} = {'next_item' => 0};
	}
    if (!scalar(%thenews) ||
		!($thenews{$display_current})) {
        &retrieveNews($client, $display_current);
        # use this to display new news each time through the screensaver
        $display_current_items->{$display_current}->{'next_item'} = 0;
		Slim::Buttons::Common::param($client, 'PLUGIN.RssNews.lines',
									 undef);
    }
	
    if (exists($thenews{$display_current}) &&
		Slim::Buttons::Common::param($client, 'PLUGIN.RssNews.lines')) {
		$lineref = Slim::Buttons::Common::param($client, 'PLUGIN.RssNews.lines');
	}

	# if we don't have lines cached, get them from cached news...
	if (!($lineref) || ($lineref->[1] eq "")) {
		# if no cached news theres a problem.
		if (defined($thenews{$display_current})) {
			#if (!exists($display_current_items->{$display_current}->{'next_item'})) {
				#$display_current_items->{$display_current}->{'next_item'} = 0;
			#}
			# if we've already seen all items in this channel, loop back to first item
			if (!exists($thenews{$display_current}->{item}[$display_current_items->{$display_current}->{'next_item'}])) {
				$display_current_items->{$display_current}->{'next_item'} = 0;
			}
			my $line1 = unescapeAndTrim($thenews{$display_current}->{title});
			my $line2 = "";
			my $i = $display_current_items->{$display_current}->{'next_item'};
			my $max = $i + $screensaver_items_per_feed;
			while (($i < $max) &&
				   ($thenews{$display_current}->{item}[$i])) {
				my $description;
				if ((!($thenews{$display_current}->{item}[$i]->{description})) ||
					ref ($thenews{$display_current}->{item}[$i]->{description})) {
					# description not available, just show title
					$description = "";
				} else {
					$description = $thenews{$display_current}->{item}[$i]->{description};
				}
				$line2 .= sprintf($screensaver_item_format,
								  $i + 1,
								  unescapeAndTrim($thenews{$display_current}->{item}[$i]->{title}),
								  unescapeAndTrim($description));
				$i++;
			}
			# remove tags
			# this is now done in unescape and trim
			#$line2 =~ s/<\/?[A-Za-z]+ ?\/?>/ /g; # matches, for example, "<b>" and "<br />"
			# convert newlines in line2 to spaces
			#$line2 =~ s/\n/ /g; # no longer needed (unescape and trim)
			$display_current_items->{$display_current}->{'next_item'} = $i;
			$lineref->[0] = $line1;
			$lineref->[1] = $line2;
			param($client, 'PLUGIN.RssNews.lines', $lineref);
			param($client, 'PLUGIN.RssNews.display_current_items', $display_current_items);
		} else {
			my $line1 = "RSS News - ".$display_current;
			my $line2;
			if ($state eq 'wait') {
				$line2 = string('PLUGIN_RSSNEWS_WAIT');
			} else {
				$line2 = string('PLUGIN_RSSNEWS_ERROR');
			}
			$lineref->[0] = $line1;
			$lineref->[1] = $line2;
		}
	}
	
	return @$lineref;
}


sub screenSaver() {
    Slim::Utils::Strings::addStrings(&strings());
      Slim::Buttons::Common::addSaver('SCREENSAVER.rssnews', getScreensaverRssNews(), \&setScreensaverRssNewsMode,\&leaveScreenSaverRssNews,string('PLUGIN_RSSNEWS_SCREENSAVER'));
  }

my %screensaverRssNewsFunctions = (
        'done' => sub  {
		my ($client, $funct, $functarg) = @_;
       		Slim::Buttons::Common::popMode($client);
		$client->update();
		#pass along ir code to new mode if requested
		if (defined $functarg && $functarg eq 'passback') {
			Slim::Hardware::IR::resendButton($client);
		}
	}
);

sub getScreensaverRssNews {
        return \%screensaverRssNewsFunctions;
}


sub setScreensaverRssNewsMode() {
    my $client = shift;

    Slim::Buttons::Common::param($client, 'PLUGIN.RssNews.screensaver_mode', 1);

    # call the method that updates the display...
    autoScrollTimer($client);

    $client->lines(\&lines);

}

sub leaveScreenSaverRssNews {
    #kill timers
    my $client = shift;
    Slim::Utils::Timers::killTimers($client, \&autoScrollTimer);
    Slim::Buttons::Common::param($client, 'PLUGIN.RssNews.screensaver_mode', 0);
}


#############################
# Screensaver Settings Mode
#

my @screensaverSettingsMenu = ('PLUGIN_RSSNEWS_SCREENSAVER_ACTIVATE');
my %current;
my %menuParams = (
				  'rssnews' => {
					  'listRef' => \@screensaverSettingsMenu
						  ,'stringExternRef' => 1
						  ,'header' => 'PLUGIN_RSSNEWS_SCREENSAVER_SETTINGS'
						  ,'stringHeader' => 1
						  ,'headerAddCount' => 1
						  ,'callback' => \&screensaverSettingsCallback
						  ,'overlayRef' => sub {return (undef,Slim::Display::Display::symbol('rightarrow'));}
					  ,'overlayRefArgs' => ''
					  }
				  ,catdir('rssnews','PLUGIN_RSSNEWS_SCREENSAVER_ACTIVATE') => {
					  'useMode' => 'INPUT.List'
						  ,'listRef' => [0,1]
						  ,'externRef' => ['PLUGIN_RSSNEWS_SCREENSAVER_DEFAULT', 'PLUGIN_RSSNEWS_SCREENSAVER_ACTIVATED']
						  ,'stringExternRef' => 1
						  ,'header' => 'PLUGIN_RSSNEWS_SCREENSAVER_ACTIVATE_TITLE'
						  ,'stringHeader' => 1
						  ,'onChange' => sub { Slim::Utils::Prefs::clientSet($_[0],'screensaver',$_[1]?'SCREENSAVER.rssnews':'screensaver'); }
					  ,'onChangeArgs' => 'CV'
						  ,'initialValue' => sub { (Slim::Utils::Prefs::clientGet($_[0],'screensaver') eq 'SCREENSAVER.rssnews' ? 1 : 0); }
				  }
				  );

sub screensaverSettingsCallback {
    my ($client,$exittype) = @_;
    $exittype = uc($exittype);
    if ($exittype eq 'LEFT') {
        Slim::Buttons::Common::popModeRight($client);
      } elsif ($exittype eq 'RIGHT') {
		  my $nextmenu = catdir('rssnews',$current{$client});
		  if (exists($menuParams{$nextmenu})) {
			  my %nextParams = %{$menuParams{$nextmenu}};
			  if ($nextParams{'useMode'} eq 'INPUT.List' && exists($nextParams{'initialValue'})) {
				#set up valueRef for current pref
				my $value;
				if (ref($nextParams{'initialValue'}) eq 'CODE') {
					$value = $nextParams{'initialValue'}->($client);
				} else {
					$value = Slim::Utils::Prefs::clientGet($client,$nextParams{'initialValue'});
				}
				$nextParams{'valueRef'} = \$value;
			}
			  Slim::Buttons::Common::pushModeLeft(
												  $client
												  ,$nextParams{'useMode'}
												  ,\%nextParams
												  );
		  } else {
			  $client->bumpRight();
		  }
	  } else {
		  return;
	  }
	
	
}

sub screensaverSettingsSetMode {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		  return;
	  }
	my %params = %{$menuParams{'rssnews'}};
	$params{'valueRef'} = \$current{$client};
	
	Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
	$client->update();
}
my %noModeFunctions = (
                              );

Slim::Buttons::Common::addMode('PLUGIN.RssNews.screensaversettings', 
                               \%noModeFunctions, 
                               \&screensaverSettingsSetMode);






#############################
# Main mode
# 

sub mainModeCallback {
    my ($client,$exittype) = @_;
    
    $exittype = uc($exittype);
    if ($exittype eq 'LEFT') {
        Slim::Buttons::Common::popModeRight($client);
      } 
    elsif ($exittype eq 'RIGHT') {
        my $listIndex = Slim::Buttons::Common::param($client, 'listIndex');
        my $feedname = $feed_order[$listIndex];
        
        retrieveNews($client, $feedname);
		
		if ($thenews{$feedname} &&
			$thenews{$feedname}->{title} &&
			$thenews{$feedname}->{item}) {
            Slim::Buttons::Common::pushModeLeft($client, 
                                                'PLUGIN.RssNews.headlines',
                                                { feed => unescapeAndTrim($thenews{$feedname}->{title}),
                                                  feedItems => $thenews{$feedname}->{item} });
          } else {
              Slim::Display::Animation::showBriefly($client, 
                                                    string('PLUGIN_RSSNEWS_ERROR'));
                return;  
            }
    }
}

sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
            Slim::Buttons::Common::popMode($client);
              return;
          }
        
	my %params = (
                      stringHeader => 1,
                      header => 'PLUGIN_RSSNEWS_NAME',
                      listRef => \@feed_order,
                      callback => \&mainModeCallback,
                      valueRef => \$context{$client}->{mainModeIndex},
                      headerAddCount => 1,
                      overlayRef => sub {return (undef,Slim::Display::Display::symbol('rightarrow'));},
                      parentMode => Slim::Buttons::Common::mode($client),		  
                      );
        
	Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
	$client->update();
}

# needed in getFunctions
my %mainModeFunctions = (
);

# The server will call this subroutine
sub getFunctions() {
	return \%mainModeFunctions;
}


#############################
# Headlines mode
# 

sub headlinesModeCallback {
    my ($client,$exittype) = @_;
    
    $exittype = uc($exittype);
    if ($exittype eq 'LEFT') {
        Slim::Buttons::Common::popModeRight($client);
      } 
    elsif ($exittype eq 'RIGHT') {
        my $listIndex = Slim::Buttons::Common::param($client, 'listIndex');
        my $items = Slim::Buttons::Common::param($client, 'feedItems');

        my $item = $items->[$listIndex];
        my $description;
		if (!$item->{description} ||
			ref($item->{description})) {
			$description = string('PLUGIN_RSSNEWS_NO_DESCRIPTION');
		} else {
			$description = $item->{description};
		}
        my $title = $item->{title};
        my $feed = Slim::Buttons::Common::param($client, 'feed');
        
        Slim::Buttons::Common::pushModeLeft($client, 
                                            'PLUGIN.RssNews.description',
                                            { feed => $feed,
                                              title => "$title",
                                              description => "$description" });
    }
}

my %headlinesModeFunctions = (
                              );

sub headlinesSetMode {
    my $client = shift;
    my $method = shift;
    
	if ($method eq 'pop') {
            Slim::Buttons::Common::popMode($client);
              return;
          }
    
    my $feed = Slim::Buttons::Common::param($client, 'feed');
    my $items = Slim::Buttons::Common::param($client, 'feedItems');
    
    my @lines = map unescapeAndTrim($_->{title}), @$items;
    
    my %params = (
                  header => $feed,
                  listRef => \@lines,
                  callback => \&headlinesModeCallback,
                  valueRef => \$context{$client}->{headlinesModeIndex},
                  headerAddCount => 1,
                  overlayRef => sub {return (undef,Slim::Display::Display::symbol('rightarrow'));},
                  parentMode => Slim::Buttons::Common::mode($client),		  
                  feed => $feed,		  
                  feedItems => $items,
                  );
    
    Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
    $client->update();
}

Slim::Buttons::Common::addMode('PLUGIN.RssNews.headlines', 
                               \%headlinesModeFunctions, 
                               \&headlinesSetMode);


#############################
# Descriptions mode
# 

sub descriptionModeCallback {
    my ($client,$exittype) = @_;
    
    $exittype = uc($exittype);
    if ($exittype eq 'LEFT') {
        Slim::Buttons::Common::popModeRight($client);
      } 
    elsif ($exittype eq 'RIGHT') {
        $client->bumpRight();
    }
}

my %descriptionModeFunctions = (						  
                                                                                  );

sub descriptionSetMode {
    my $client = shift;
    my $method = shift;
    
    if ($method eq 'pop') {
        Slim::Buttons::Common::popMode($client);
          return;
      }
    
    my $feed = Slim::Buttons::Common::param($client, 'feed');
    my $title = unescapeAndTrim(Slim::Buttons::Common::param($client, 'title'));
    my $description = unescapeAndTrim(Slim::Buttons::Common::param($client, 'description'));
    
    my @lines;
    my $curline = '';
    # break story up into lines.
    while ($description =~ /(\S+)/g) {
        my $newline = $curline . ' ' . $1;
        if ($client->measureText($newline, 2) > $client->displayWidth) {
            push @lines, trim($curline);
            $curline = $1;
        }
        else {
            $curline = $newline;
        }
    }
    if ($curline) {
        push @lines, trim($curline);
    }
    
    # also shorten title to fit
    # leave a bunch of extra pixels to display the (n out of M) text
    my $titleline = '';
    while ($title =~ /(\S+)/g) {
        my $newline = $titleline . ' ' . $1;
        if ($client->measureText($newline . "... (?? of ??)", 1) > ($client->displayWidth)) {
            $titleline .= '...';
            last;
        } else {
            $titleline = $newline;
        }
    }
    
    my %params = (
                  header => trim($titleline),
                  listRef => \@lines,
                  callback => \&descriptionModeCallback,
                  valueRef => \$context{$client}->{descriptionModeIndex},
                  headerAddCount => 1,
                  parentMode => Slim::Buttons::Common::mode($client),		  
                  );
    
    Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
    $client->update();
    
}

Slim::Buttons::Common::addMode('PLUGIN.RssNews.description', 
                               \%descriptionModeFunctions, 
                               \&descriptionSetMode);

sub addMenu {
	# add a mode to the screensaver submenu...
	my %params = ('useMode' => "PLUGIN.RssNews.screensaversettings",
				  'header' => "PLUGIN_RSSNEWS_SCREENSAVER");
	Slim::Buttons::Home::addSubMenu("SCREENSAVERS",'RssNews', \%params);	  

	# also add ourselves to the plugins menu
	return "PLUGINS";
}


1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
