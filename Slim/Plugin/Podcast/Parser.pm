package Slim::Plugin::Podcast::Parser;

use Date::Parse qw(strptime str2time);
use URI;

use Slim::Formats::XML;
use Slim::Utils::Cache;
use Slim::Utils::DateTime;
use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

my $log = logger('plugin.podcast');

sub parse {
	my ($class, $http, $params) = @_;
	
	my $client = $http->params->{params}->{client};
	
	my $cache = Slim::Utils::Cache->new;

	# don't use eval() - caller is Slim::Formats::XML is doing so already
	my $feed = Slim::Formats::XML::parseXMLIntoFeed( $http->contentRef, $http->headers()->content_type );

	foreach my $item ( @{$feed->{items}} ) {
		# some podcasts come with formatted duration ("00:54:23") - convert into seconds
		my ($s, $m, $h) = strptime($item->{duration});
		
		if ($s || $m || $h) {
			$item->{duration} = $h*3600 + $m*60 + $s;
		}
		
		# track progress of our listening
		my $key = 'podcast-' . $item->{enclosure}->{url};
		my $position = $cache->get($key);
		if ( !defined $position ) {
			$cache->set($key, 0, '30days');
		}
		
		# if we've played this podcast before, add a menu level to ask whether to continue or start from scratch
		if ( $item->{enclosure} && $position && $position < $item->{duration} - 15 ) {
			delete $item->{description};     # remove description, or xmlbrowser would consider this to be a RSS feed

			my $enclosure = delete $item->{enclosure};
			my $url       = $enclosure->{url} . '#slimpodcast';
			
			$cache->set('podcast-position-' . $url, $position, '10days');
			
			$position = Slim::Utils::DateTime::timeFormat($position);
			$position =~ s/^0+[:\.]//;

			$item->{items} = [{
				title => cstring($client, 'PLUGIN_PODCAST_PLAY_FROM_POSITION_X', $position),
				enclosure => {
					type   => $enclosure->{type},
					length => $enclosure->{length},
					url    => $url,
				},
				duration => $item->{duration},
			},{
				title => cstring($client, 'PLUGIN_PODCAST_PLAY_FROM_BEGINNING'),
				enclosure => {
					type   => $enclosure->{type},
					length => $enclosure->{length},
					url    => $enclosure->{url},
				},
				duration => $item->{duration},
			}];
		}

		$item->{line2} = Slim::Utils::DateTime::longDateF(str2time($item->{pubdate})) if $item->{pubdate};
		$item->{'xmlns:slim'} = 1;
	}
	
	$feed->{nocache} = 1;
	$feed->{cachetime} = 0;
	
	return $feed;
}

1;