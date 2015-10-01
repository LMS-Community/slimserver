package Slim::Plugin::Podcast::Parser;

use Date::Parse qw(strptime str2time);
use URI;

use Slim::Formats::XML;
use Slim::Utils::Cache;
use Slim::Utils::DateTime;
use Slim::Utils::Strings qw(cstring);

sub parse {
	my ($class, $http, $params) = @_;
	
	my $client = $http->params->{params}->{client};
	
	my $cache = Slim::Utils::Cache->new;

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
		my $duration = $item->{duration};
		$duration =~ s/00:(\d\d:\d\d)/$1/;
		
		my ($s, $m, $h) = strptime($item->{duration} || 0);
		
		if ($s || $m || $h) {
			$item->{duration} = $h*3600 + $m*60 + $s;
		}
		
		# track progress of our listening
		my $key = 'podcast-' . $item->{enclosure}->{url};
		my $position = $cache->get($key);
		if ( !defined $position ) {
			$cache->set($key, 0, '30days');
		}
		
		# do we have duration stored from previous playback?
		if ( !$item->{duration} ) {
			my $trackObj = Slim::Schema->objectForUrl( { url => $item->{enclosure}->{url} } );
			$item->{duration} = $trackObj->duration if $trackObj && blessed $trackObj;

			# fall back to cached value - if available
			$item->{duration} ||= $cache->get("$key-duration");
		}
		
		my $progress = $client->symbols($client->progressBar(12, $position ? 1 : 0, 0));
		
		# if we've played this podcast before, add a menu level to ask whether to continue or start from scratch
		if ( $position && $position < $item->{duration} - 15 ) {
			delete $item->{description};     # remove description, or xmlbrowser would consider this to be a RSS feed

			my $enclosure = delete $item->{enclosure};
			my $url       = $enclosure->{url} . '#slimpodcast';
			
			$cache->set('podcast-position-' . $url, $position, '10days');
			
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

			$progress = $client->symbols($client->progressBar(12, 0.5, 0));
		}

		$item->{title} = $progress . '  ' . $item->{title} if $progress;
		
		if ( $item->{duration} && !$duration ) {
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
