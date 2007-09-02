package Slim::Plugin::InfoBrowser::Plugin;

# InfoBrowser - an extensible information parser for slimserver 7.0
#
# $Id$
#
# InfoBrowser provides a framework to use Slimserver's xmlbrowser to fetch remote content and convert it into a format
# which can be displayed via the slimserver web interface, cli for jive or another cli client or via the player display.
#
# The top level menu is defined by an opml file stored in playlistdir or cachedir.  It is created dynamically from any opml
# files found in the plugin dir (Slim/Plugin/InfoBrowser) and the Addon dir (Plugins/InfoBrowserAddons) and any of their subdirs.
# This allows addition of third party addons defining new information sources.
#
# Simple menu entries for feeds which are parsed natively by Slim::Formats::XML are of the form:
#
# <outline text="BBC News World" URL="http://news.bbc.co.uk/rss/newsonline_world_edition/front_page/rss.xml" />
#
# Menu entries which use additional perl scripts to parse the response into a format understood by xmlbrowser are of the form:
#
# <outline text="Menu text" URL="url to fetch" parser="Plugins::InfoBrowserAddons::Folder::File" />
#
# In this case when the content of the remote url has been fetched it is passed to the perl function
# Plugins::InfoBrowserAddons::Folder::File::parser to parse the content into a hash which xmlbrowser will understand.
# This allows arbitary web pages to be parsed by adding the appropriate perl parser files.  The perl module will be dynamically loaded. 
#
# Addons are stored in Plugins/InfoBrowserAddons.  It is suggested that each addon is a separate directory within this top level
# directory containing the opml menu and any associated parser files.  InfoBrowser will search this entire directory tree for
# opml files and add them to the main information browser menu.
#
# Users may remove or reorder menu entries in the top level opml menu via settings.  They may also reset the menu which will reimport all
# default and Addon opml files.
# 
# Authors are encouraged to publish their addons on the following wiki page:
#   http://wiki.slimdevices.com/index.cgi?InformationBrowser
#

use strict;

use base qw(Slim::Plugin::Base);

use File::Spec::Functions qw(:ALL);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings;
use Slim::Plugin::Favorites::Opml;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.infobrowser',
	'defaultLevel' => 'WARN',
	'description'  => getDisplayName(),
});

use Slim::Plugin::InfoBrowser::Settings;

my $prefsServer = preferences('server');

my $menuUrl;    # menu fileurl location
my @searchDirs; # search directories for menu opml files

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin;

	Slim::Plugin::InfoBrowser::Settings->new($class);
	Slim::Plugin::InfoBrowser::Settings->importNewMenuFiles;

    Slim::Control::Request::addDispatch(['infobrowser', 'items', '_index', '_quantity'],
        [0, 1, 1, \&cliQuery]);
}

sub getDisplayName { 'PLUGIN_INFOBROWSER' };

sub setMode {
	my $class  = shift;
    my $client = shift;
    my $method = shift;

    if ( $method eq 'pop' ) {
        Slim::Buttons::Common::popMode($client);
        return;
    }

	my %params = (
		modeName => 'InfoBrowser',
		url      => $class->menuUrl,
		title    => getDisplayName(),
	);

	Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);

	# we'll handle the push in a callback
	$client->modeParam('handledTransition',1)
}

sub webPages {
	my $class = shift;

	my $title = getDisplayName();
	my $url   = 'plugins/InfoBrowser/index.html';

	Slim::Web::Pages->addPageLinks('plugins', { $title => $url });

	Slim::Web::HTTP::addPageFunction($url, sub {

		Slim::Web::XMLBrowser->handleWebIndex( {
			feed   => $class->menuUrl,
			title  => $title,
			args   => \@_
		} );
	});
}

sub cliQuery {
	my $request = shift;

	Slim::Buttons::XMLBrowser::cliQuery('infobrowser', $menuUrl, $request);
}

sub menuUrl {
	my $class = shift;

	return $menuUrl if $menuUrl;

	my $dir = $prefsServer->get('playlistdir');

	if (!$dir || !-w $dir) {
		$dir = $prefsServer->get('cachedir');
	}

	my $file = catdir($dir, "infobrowser.opml");

	$menuUrl = Slim::Utils::Misc::fileURLFromPath($file);

	if (-r $file) {

		if (-w $file) {
			$log->info("infobrowser menu file: $file");

		} else {
			$log->warn("unable to write to infobrowser menu file: $file");
		}

	} else {

		$log->info("creating infobrowser menu file: $file");

		my $newopml = Slim::Plugin::Favorites::Opml->new;
		$newopml->title(Slim::Utils::Strings::string('PLUGIN_INFOBROWSER'));
		$newopml->save($file);

		Slim::Plugin::InfoBrowser::Settings->importNewMenuFiles('clear');
	}

	return $menuUrl;
}

sub searchDirs {
	my $class = shift;

	return @searchDirs if @searchDirs;
	
	push @searchDirs, $class->_pluginDataFor('basedir');

	# find location of Addons dir and add this to the path searched for opml menus and @INC
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $dir (@pluginDirs) {
		my $addonDir = catdir($dir, 'InfoBrowserAddons');
		if (-r $addonDir) {
			push @searchDirs, $addonDir;
			unshift @INC, $addonDir;
		}
	}

	return @searchDirs;
}


1;
