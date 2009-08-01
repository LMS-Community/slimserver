package Slim::Plugin::InfoBrowser::Settings;

use strict;
use base qw(Slim::Web::Settings);

use File::Basename;
use File::Next;

use Slim::Utils::Prefs;

use Slim::Plugin::Favorites::Opml;

my $prefs = preferences('plugin.infobrowser');

my $plugin; # reference to main plugin

sub new {
	my $class = shift;
	$plugin   = shift;

	$class->SUPER::new;
}

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_INFOBROWSER');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/InfoBrowser/settings/basic.html');
}

sub handler {
	my ($class, $client, $params) = @_;

	if ($params->{'reset'}) {
		$prefs->set('imported', {});
		Slim::Plugin::InfoBrowser::Plugin->importNewMenuFiles('clear');
	}

	$params->{'opmlfile'} = $plugin->menuUrl;

	return $class->SUPER::handler($client, $params);
}

		
1;
