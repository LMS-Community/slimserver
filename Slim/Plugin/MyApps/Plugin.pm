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

	my $feedUrl = main::NOMYSB ? '' : Slim::Networking::SqueezeNetwork->url('/api/myapps/v1/opml');

	if (my $nonSNApps = Slim::Plugin::Base->nonSNApps) {

		return sub {
			my ($client, $callback, $args) = @_;

			my $mergeCB = sub {

				my $feed = shift;
				
				# override the text message saying no apps are installed
				if (scalar @{$feed->{'items'}} == 1 && $feed->{'items'}->[0]->{'type'} eq 'text') {
					$feed->{'items'} = [];
				}
				
				for my $app (@$nonSNApps) {
					
					if ($app->condition($client)) {
						
						my $name = Slim::Utils::Strings::getString($app->getDisplayName);
						my $tag  = $app->can('tag') && $app->tag;
						my $icon = $app->_pluginDataFor('icon');
						
						# Let a local plugin override a mysb.com feed
						# This is an ugly hack, as it's purely name based. But we don't have any ID here.
						$feed->{'items'} = [ grep { $_->{name} ne $name } @{$feed->{'items'}} ];
						
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
				
				$feed->{'items'} = [ sort { $a->{'name'} cmp $b->{'name'} } @{$feed->{'items'}} ];
				
				$callback->($feed);
			};
				
			if (main::NOMYSB) {
				$mergeCB->({ items => [] });
			}
			else {
				Slim::Formats::XML->getFeedAsync(
	
					$mergeCB, 
	
					sub { $mergeCB->({ items => [] }) },	
	
					{ client => $client, url => $feedUrl, timeout => 35 },
				);
			}
		}
			
	} elsif (main::NOMYSB) {
		
		return sub {
			my ($client, $callback, $args) = @_;

			$callback->({ items => [ {
				name => $client->string('PLUGIN_MY_APPS_NO_APPS'),
				type => 'text'
			} ] });
		}
		
	} else {

		return $feedUrl;
	}
}

# Don't add this item to any menu
sub playerMenu { }

1;
