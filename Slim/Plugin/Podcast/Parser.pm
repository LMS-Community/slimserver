package Slim::Plugin::Podcast::Parser;

use Date::Parse qw(strptime str2time);
use Scalar::Util qw(blessed);
use URI;

use Slim::Formats::XML;
use Slim::Utils::Cache;
use Slim::Utils::DateTime;
use Slim::Utils::Strings qw(cstring);

my $cache = Slim::Utils::Cache->new;

my $fetching;
my @scanQueue;

sub parse {
	my ($class, $http, $params) = @_;
	
	my $client = $http->params->{params}->{client};
	
	# don't use eval() - caller is Slim::Formats::XML is doing so already
	my $feed = Slim::Formats::XML::parseXMLIntoFeed( $http->contentRef, $http->headers()->content_type );

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
		
		# track progress of our listening
		my $key = 'podcast-' . $item->{enclosure}->{url};
		my $position = $cache->get($key);
		if ( !$position ) {
			if ( my $redirect = $cache->get("$key-redirect") ) {
				$position = $cache->get("podcast-$redirect");
			}
			
			$cache->set($key, $position || 0, '30days');
		}
		
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

		$cache->set("$key-duration", $item->{duration}, '30days');

		# sometimes the URL would redirect - store data for the real URL, too
		# only check when we're seeing this URL for the first time!
		if ( !(scalar grep { $_->{key} eq $key } @scanQueue) && !defined $cache->get("$key-redirect") ) {
			push @scanQueue, { 
				url      => $item->{enclosure}->{url}, 
				duration => $item->{duration}, 
				position => $position,
				key      => $key,
			};
			
			_scanItem();
		}
		
		my $progress = $client->symbols($client->progressBar(12, $position ? 1 : 0, 0)) if $client && !$client->display->isa('Slim::Display::NoDisplay');
		
		# if we've played this podcast before, add a menu level to ask whether to continue or start from scratch
		if ( $position && $position < $item->{duration} - 15 ) {
			delete $item->{description};     # remove description, or xmlbrowser would consider this to be a RSS feed

			my $enclosure = delete $item->{enclosure};
			my $url       = $cache->get("$key-redirect") || $enclosure->{url};
			$position     = $cache->get("podcast-$url");
			
			$position = Slim::Utils::DateTime::timeFormat($position);
			$position =~ s/^0+[:\.]//;

			$item->{items} = [{
				title => cstring($client, 'PLUGIN_PODCAST_PLAY_FROM_POSITION_X', $position),
				name  => cstring($client, 'PLUGIN_PODCAST_PLAY_FROM_POSITION_X', $position),
				enclosure => {
					type   => $enclosure->{type},
					length => $enclosure->{length},
					url    => $url,
				},
				duration => $item->{duration},
			},{
				title => cstring($client, 'PLUGIN_PODCAST_PLAY_FROM_BEGINNING'),
				name  => cstring($client, 'PLUGIN_PODCAST_PLAY_FROM_BEGINNING'),
				enclosure => {
					type   => $enclosure->{type},
					length => $enclosure->{length},
					url    => $enclosure->{url},
				},
				duration => $item->{duration},
			}];
			
			$item->{type} = 'link';

			$progress = $client->symbols($client->progressBar(12, 0.5, 0)) if $client && !$client->display->isa('Slim::Display::NoDisplay');
		}

		$item->{title} = $progress . '  ' . $item->{title} if $progress;
		
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

sub _scanItem {
	return if $fetching;

	if ( my $item = shift @scanQueue ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL($item->{url});
	
		if ($handler && $handler->can('scanUrl')) {
			$fetching = 1;
			
			$handler->scanUrl($item->{url}, {
				client => $client,
				cb     => \&_gotUrl,
				pt => [$item]
			} );
		}
	}
	else {
		$fetching = 0;
	}
}

sub _gotUrl {
	my ( $newTrack, $error, $pt ) = @_;
	
	if ( $pt && $pt->{url} && $newTrack && blessed($newTrack) && (my $url = $newTrack->url) ) {
		my $key = $pt->{key} || '';
		
		if ($pt->{url} ne $url) {
			my $key = 'podcast-' . $url;
			my $position = $cache->get($key);
			if ( !defined $position ) {
				$cache->set($key, $pt->{position} || 0, '30days');
			}
			
			$cache->set("$key-duration", $pt->{duration}, '30days') if $pt->{duration};
		}

		$cache->set("$key-redirect", $url || '', '30days');
	}
	
	# check next item
	$fetching = 0;
	_scanItem();
}
1;
