package Slim::Plugin::InfoBrowser::Plugin;

# InfoBrowser - an extensible information parser for Logitech Media Server 7.0
#
# $Id$
#
# InfoBrowser provides a framework to use Squeezebox Server's xmlbrowser to fetch remote content and convert it into a format
# which can be displayed via the server web interface, cli for jive or another cli client or via the player display.
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
# The parser may be passed a parameter string by including it after ? in the parser specification.  The parser definition is split
# on either side of the ? to specify the perl module to load and a string to pass as third param to its parse method. 
#
# <outline text="Menu text" URL="url to fetch" parser="Plugins::InfoBrowserAddons::Folder::File?param1=1&param2=2" />
#
# In this case Plugins::InfoBrowserAddons::parse gets called with ( $class, $html, $paramstring ).
#
# Addons are stored in Plugins/InfoBrowserAddons or within a plugin with name InfoBrowser<somename>.  InfoBrowser will search all folder
# within Plugins/InfoBrowserAddons and Plugins/InfoBrowser<somename> for opml files and add them to the main information browser menu.
#
# Users may remove or reorder menu entries in the top level opml menu via settings.  They may also reset the menu which will reimport all
# default and Addon opml files.
# 
# Authors are encouraged to publish their addons on the following wiki page:
#   http://wiki.slimdevices.com/index.php/InformationBrowser
#

use strict;

use base qw(Slim::Plugin::Base);

use File::Spec::Functions qw(catdir);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings;
use Slim::Plugin::Favorites::Opml;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.infobrowser',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

if ( main::WEBUI ) {
 	require Slim::Plugin::InfoBrowser::Settings;
}

my $prefs = preferences('plugin.infobrowser');
my $prefsServer = preferences('server');

my $menuUrl;    # menu fileurl location
my @searchDirs; # search directories for menu opml files

sub initPlugin {
	my $class = shift;

	if ( main::WEBUI ) {
		Slim::Plugin::InfoBrowser::Settings->new($class);
	}

	$menuUrl    = $class->_menuUrl;
	@searchDirs = $class->_searchDirs;
	
	$class->importNewMenuFiles;

	$class->SUPER::initPlugin;

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
		url      => $menuUrl,
		title    => getDisplayName(),
	);

	Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);

	# we'll handle the push in a callback
	$client->modeParam('handledTransition',1)
}

sub webPages {
	my $class = shift;

	my $title = getDisplayName();
	my $url   = 'plugins/Favorites/index.html?new=' . $class->_menuUrl() . '&autosave';

	Slim::Web::Pages->addPageLinks('plugins', { $title => $url });
}

sub cliQuery {
	my $request = shift;

	Slim::Control::XMLBrowser::cliQuery('infobrowser', $menuUrl, $request);
}


sub importNewMenuFiles {
	my $class = shift;
	my $clear = shift;

	my $imported = $prefs->get('imported');

	if (!defined $imported || $clear) {
		$imported = {};
		$clear = 'clear';
	}

	main::INFOLOG && $log->info($clear ? "clearing old menu" : "searching for new menu files to import");

	my @files = ();
	my $iter  = File::Next::files(
		{ 
			'file_filter' => sub { /\.opml$/ }, 
			'descend_filter' => sub { $_ ne 'HTML' } 
		}, 
		$class->searchDirs
	);

	while (my $file = $iter->()) {
		if ( !$imported->{ $file } ) {
			push @files, $file;
			$imported->{ $file } = 1;
		}
	}

	if (@files) {
		$class->_import($clear, \@files);
		$prefs->set('imported', $imported);
	}
}

sub _import {
	my $class = shift;
	my $clear = shift;
	my $files = shift;
	
	my $menuOpml = Slim::Plugin::Favorites::Opml->new({ 'url' => $class->menuUrl });

	if ($clear) {
		splice @{$menuOpml->toplevel}, 0;
	}

	for my $file (sort @$files) {

		main::INFOLOG && $log->info("importing $file");
	
		my $import = Slim::Plugin::Favorites::Opml->new({ 'url' => $file });

		if ($import->title =~ /Default/) {
			# put these at the top of the list
			for my $entry (reverse @{$import->toplevel}) {
				unshift @{ $menuOpml->toplevel }, $entry;
			}
		} else {
			for my $entry (@{$import->toplevel}) {
				push @{ $menuOpml->toplevel }, $entry;
			}
		}
	}

	$menuOpml->save;
}

sub searchDirs {
	return @searchDirs;
}

sub menuUrl {
	return $menuUrl;
}

sub _menuUrl {
	my $class = shift;

	my $dir = Slim::Utils::Misc::getPlaylistDir();

	if (!$dir || !-w $dir) {
		$dir = $prefsServer->get('cachedir');
	}

	my $file = catdir($dir, "infobrowser.opml");

	my $menuUrl = Slim::Utils::Misc::fileURLFromPath($file);

	if (-r $file) {

		if (-w $file) {
			main::INFOLOG && $log->info("infobrowser menu file: $file");

		} else {
			$log->warn("unable to write to infobrowser menu file: $file");
		}

	} else {

		main::INFOLOG && $log->info("creating infobrowser menu file: $file");

		my $newopml = Slim::Plugin::Favorites::Opml->new;
		$newopml->title(Slim::Utils::Strings::string('PLUGIN_INFOBROWSER'));
		$newopml->save($file);

		$class->importNewMenuFiles('clear');
	}

	return $menuUrl;
}

sub _searchDirs {
	my $class = shift;

	my @searchDirs;
	
	# find locations of main Plugin and Addons and add these to the path searched for opml menus
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');

	for my $dir (@pluginDirs) {

		next unless -d $dir;

		opendir(DIR, $dir);

		my @entries = readdir(DIR);

		close(DIR);

		for my $entry (@entries) {

			if ($entry =~ /^InfoBrowser/) {
				push @searchDirs, catdir($dir,$entry);
			}
		}
	}

	return @searchDirs;
}


1;
