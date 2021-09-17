package Slim::Plugin::Podcast::Parser;

use strict;

use Date::Parse qw(strptime str2time);
use Scalar::Util qw(blessed);
use URI;

use Slim::Formats::XML;
use Slim::Utils::Cache;
use Slim::Utils::DateTime;
use Slim::Utils::Strings qw(cstring);

use Slim::Plugin::Podcast::Plugin;

my $cache = Slim::Utils::Cache->new;

my $fetching;
my @scanQueue;

sub parse {
	my ($class, $http, $params) = @_;

	my $client = $http->params->{params}->{client};

	# don't use eval() - caller is Slim::Formats::XML is doing so already
	my $feed = Slim::Formats::XML::parseXMLIntoFeed( $http->contentRef, $http->headers()->content_type );

	# refresh precached image & more info data - keeps them up to date
	my $feedUrl = $http->params->{params}->{url};
	Slim::Plugin::Podcast::Plugin::precacheFeedData($feedUrl, $feed);

	foreach my $item ( @{$feed->{items}} ) {
		if ($item->{type} && $item->{type} eq 'link') {
			$item->{parser} = $class;
		}

		next unless $item->{enclosure} && keys %{$item->{enclosure}};

		# remove "link" item, as it confuses XMLBrowser
		# see http://forums.slimdevices.com/showthread.php?t=100446
		$item->{link} = '';

		$item->{line1} = $item->{title} || $item->{name};
		$item->{line2} = Slim::Utils::DateTime::longDateF(str2time($item->{pubdate})) if $item->{pubdate};
		$item->{'xmlns:slim'} = 1;

		# some podcasts come with formatted duration ("00:54:23") - convert into seconds
		my $duration = $item->{duration} || '';
		$duration =~ s/00:(\d\d:\d\d)/$1/;

		my ($s, $m, $h) = strptime($item->{duration} || 0);

		if ($s || $m || $h) {
			$item->{duration} = $h*3600 + $m*60 + $s;
		}
		
		my $url = $item->{enclosure}->{url};
		$item->{enclosure}->{url} = Slim::Plugin::Podcast::Plugin::wrapUrl($url);

		# track progress of our listening
		my $key = 'podcast-' . $url;
		my $from = $cache->get($key);
		my $position;

		# do we have duration stored from previous playback?
		if ( !$item->{duration} ) {
			my $trackObj = Slim::Schema->objectForUrl( { url => $item->{enclosure}->{url} } );
			$item->{duration} = $trackObj->duration if $trackObj && blessed $trackObj;

			# fall back to cached value - if available
			$item->{duration} ||= $cache->get("$key-duration");

			if ( $item->{duration} && $item->{duration} =~ /(\d+):(\d)/ ) {
				$item->{duration} = $1*60 + $2;
			}
		}

		# cache what we have anyway
		$cache->set("$key-duration", $item->{duration}, '30days');
		
		# if we've played this podcast before, add a menu level to ask whether to continue or start from scratch
		if ( $from && $from < $item->{duration} - 15 ) {
			$position = Slim::Utils::DateTime::timeFormat($from);
			$position =~ s/^0+[:\.]//;
			
			# remote_image is now cached, so replace enclosure with a play attribute 
			# so that XMLBrowser shows a sub-menu *and* we can play from top
			my $enclosure = delete $item->{enclosure};
			$item->{on_select} = 'play';
			$item->{play} = Slim::Plugin::Podcast::Plugin::wrapUrl($url);
			$item->{type}  = 'link';
			
			$item->{items} = [{
				title => cstring($client, 'PLUGIN_PODCAST_PLAY_FROM_POSITION_X', $position),
				name  => cstring($client, 'PLUGIN_PODCAST_PLAY_FROM_POSITION_X', $position),
				description => $item->{description},
				cover => $item->{image},
				enclosure => {
					type   => $enclosure->{type},
					length => $enclosure->{length},
					url    => Slim::Plugin::Podcast::Plugin::wrapUrl($url, $from),
				},
			},{
				title => cstring($client, 'PLUGIN_PODCAST_PLAY_FROM_BEGINNING'),
				name  => cstring($client, 'PLUGIN_PODCAST_PLAY_FROM_BEGINNING'),
				description => $item->{description},
				cover => $item->{image},
				enclosure => {
					type   => $enclosure->{type},
					length => $enclosure->{length},
					# little trick to make sure "play from" url is not the main url
					url    => Slim::Plugin::Podcast::Plugin::wrapUrl($url, 0),
				},
			}];

			# delete description or XML browser treats is as RSS
			delete $item->{description};
		}

		if ( $item->{duration} && (!$duration || $duration !~ /:/) ) {
			my $s = $item->{duration};
			my $h = int($s / (60*60));
			my $m = int(($s - $h * 60 * 60) / 60);
			$s = int($s - $h * 60 * 60 - $m * 60);
			$s = "0$s" if length($s) < 2;
			$m = "0$m" if length($m) < 2 && $h;

			$duration = join(':', $m, $s);
			$duration = join(':', $h, $duration) if $h;
		}

		if ($position && $duration) {
			$position = "$position / $duration";
			$item->{line2} = $item->{line2} ? $item->{line2} . ' (' . $position . ')' : $position;
		}
		elsif ($duration) {
			$item->{line2} = $item->{line2} ? $item->{line2} . ' (' . $duration . ')' : $duration;
		}
	}

	$feed->{nocache} = 1;
	$feed->{cachetime} = 0;

	return $feed;
}

1;
