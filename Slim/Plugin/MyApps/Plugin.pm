package Slim::Plugin::MyApps::Plugin;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased);

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(
		tag    => 'myapps',
		node   => 'home',
		weight => 80,
	);
}

# return SN based feed, or fetch it and add on nonSN apps
sub feed {
	my $client = shift;

	my $feedUrl = Slim::Networking::SqueezeNetwork->url('/api/myapps/v1/opml');

	if (my $nonSNApps = Slim::Plugin::Base->nonSNApps) {

		my @nonSNApps = sort { ($a->can('weight') && $a->weight) <=> ($b->can('weight') && $b->weight) } @$nonSNApps;

		return sub {
			my ($client, $callback, $args) = @_;

			Slim::Formats::XML->getFeedAsync(

				sub {
					my $feed = shift;

					for my $app (@nonSNApps) {

						if ($app->condition($client)) {

							my $name = Slim::Utils::Strings::getString($app->getDisplayName);
							my $tag  = $app->can('tag') && $app->tag;
							my $icon = $app->_pluginDataFor('icon');

							my $item = {
								name   => $name,
								icon   => $icon,
								type   => 'redirect',
								player => {
									mode => $app,
									modeParams => {},
								},
							};

							if ($tag) {
								$item->{jive} = {
									actions => {
										go => {
											cmd => [ $app->tag, 'items' ],
											params => {
												menu => $app->tag,
											},
										},
									},
								};
							}
								
							push @{$feed->{'items'}}, $item;
						}
					}

					$callback->($feed);
				},

				sub { 
					$callback->();
				},

				{ client => $client, url => $feedUrl, timeout => 35 },
			);
		}
			
	} else {

		return $feedUrl;
	}
}

# Don't add this item to any menu
sub playerMenu { }

1;
