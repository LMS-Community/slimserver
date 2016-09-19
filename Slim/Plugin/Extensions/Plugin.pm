package Slim::Plugin::Extensions::Plugin;

# Repository XML format:
#
# Each repository file may contain entries for applets, wallpapers, sounds (and in future plugins):
#
# The xml structure is of the following format:
#
# <?xml version="1.0"?>
# <extensions>
#   <applets>
# 	  <applet ... />
#     <applet ... />
#   </applets>
#   <wallpapers>
#     <wallpaper ... />
#     <wallpaper ... />
#   </wallpaper>
#   <sounds>
#     <sound ... />
#     <sound ... />
#   </sounds>
#   <plugins>
#     <plugin ... />
#     <plugin ... />
#   </plugins>
#   <details>
#     <title lang="EN">The Repository's Title</title>
#   </details>
# </extensions>
#
# Applet and Plugin entries are of the form:
# 
# <applet name="AppletName" version="1.0" target="jive" minTarget="7.3" maxTarget="7.3">
#   <title lang="EN">English Title</title>
#   <title lang="DE">Deutscher Titel</title>
#   <desc lang="EN">Description</desc>
#   <desc lang="DE">Deutschsprachige Beschreibung</desc>
#   <changes lang="EN">Changelog</changes>
#   <changes lang="DE">Änderungen</changes>
#   <creator>Name of Author</creator>
#   <email>email of Author</email>
#   <url>url for zip file</url>
# </applet>
#
# <plugin name="PluginName" version="1.0" target="windows" minTarget="7.3" maxTarget="7.3">
#   <title lang="EN">English Title</title>
#   <title lang="DE">Deutscher Titel</title>
#   <desc lang="EN">Description</desc>
#   <desc lang="DE">Deutschsprachige Beschreibung</desc>
#   <changes lang="EN">Changelog</changes>
#   <changes lang="DE">Änderungen</changes>
#   <creator>Name of Author</creator>
#   <email>email of Author</email>
#   <url>url for zip file</url>
#   <sha>digest of zip</sha>
# </plugin>
#
# name       - the name of the applet/plugin - must match the file naming of the lua/perl packages
# version    - the version of the applet/plugin (used to decide if a newer version should be installed)
# target     - string defining the target, squeezeplay currently uses 'jive', for plugins if set this specfies the
#              the target archiecture and may include multiple strings separated by '|' from "windows|mac|unix"
# minTarget  - min version of the target software
# maxTarget  - max version of the target software
# title      - contains localisations for the title of the applet (optional - uses name if not defined)
# desc       - localised description of the applet or plugin (optional)
# changes    - localised change log of the applet or plugin (optional)
# link       - (plugin only) url for web page describing the plugin in more detail 
# creator    - identify of author(s)
# email      - email address of authors
# url        - url for the applet/plugin itself, this sould be a zip file
# sha        - (plugin only) sha1 digest of the zip file which is verifed before the zip is extracted
#
# Wallpaper and sound entries can include all of the above elements, but the minimal definition is:
# 
# <wallpaper name="WallpaperName" url="url for wallpaper file" />
#
# <sound     name="SoundName"     url="url for sound file"     />
#

use strict;

use base qw(Slim::Plugin::Base);

use XML::Simple;

use Slim::Networking::Repositories;
use Slim::Control::Jive;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

if ( main::WEBUI ) {
	require Slim::Plugin::Extensions::Settings;
}

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.extensions',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_EXTENSIONS',
});

my $prefs = preferences('plugin.extensions');

$prefs->init({ repos => [], plugin => {}, auto => 0 });

$prefs->migrate(2, 
				sub {
					# find any plugins already installed via previous version of extension downloader and save as selected
					# this should avoid trying to remove existing plugins when this version is first loaded
					for my $plugin (Slim::Utils::PluginManager->installedPlugins) {
						if (Slim::Utils::PluginManager->allPlugins->{$plugin}->{'basedir'} =~ /InstalledPlugins/) {
							$prefs->set($plugin, 1);
						}
					}
					1;
				});

$prefs->migrate(3,
				sub {
					# Bug: 14690 - remove any old format plugin pref (used temporarily during beta)
					if (ref $prefs->get('plugin') ne 'HASH') {
						$prefs->set('plugin', {});
					}
					1;
				});

my %repos = (
	# default repos mapped to weight which defines the order they are sorted in
	'http://repos.squeezecommunity.org/extensions.xml' => 1,
);

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin;

	for my $repo (keys %repos) {
		Slim::Control::Jive::registerExtensionProvider($repo, \&getExtensions);
	}

	if ( main::WEBUI ) {

		for my $repo ( @{$prefs->get('repos')} ) {
			$class->addRepo({ repo => $repo });
		}
		
		Slim::Plugin::Extensions::Settings->new;

		# clean out plugin entries for plugins which are manually installed
		# this can happen if a developer moves an automatically installed plugin to a manually installed location
		my $installPlugins = $prefs->get('plugin');
		my $loadedPlugins = Slim::Utils::PluginManager->allPlugins;
		
		for my $plugin (keys %$installPlugins) {
			
			if ($loadedPlugins->{ $plugin } && $loadedPlugins->{ $plugin }->{'basedir'} !~ /InstalledPlugins/) {
				
				$log->warn("removing $plugin from install list as it is already manually installed");
				
				delete $installPlugins->{ $plugin };
				
				$prefs->set('plugin', $installPlugins);
			}
			
			# a plugin could have failed to download (Thanks Google for taking down googlecode.com!...) - let's not re-try to install it
			elsif ( !$loadedPlugins->{ $plugin } ) {
				$log->warn("$plugin failed to download or install in some other way. Please try again.");
				
				delete $installPlugins->{ $plugin };
				
				$prefs->set('plugin', $installPlugins);
			}
		}
	}

	Slim::Control::Request::addDispatch(['appsquery'], [0, 1, 1, \&appsQuery]);
}

sub addRepo {
	my $class = shift;
	my $args = shift;

	my $repo   = $args->{'repo'};
	my $weight = 10;

	main::INFOLOG && $log->info("adding repository $repo weight $weight");

	$repos{$repo} = $weight;

	Slim::Control::Jive::registerExtensionProvider($repo, \&getExtensions, 'user');
}

sub removeRepo {
	my $class = shift;
	my $args = shift;

	my $repo = $args->{'repo'};

	main::INFOLOG && $log->info("removing repository $repo");

	delete $repos{$repo};

	Slim::Control::Jive::removeExtensionProvider($repo, \&getExtensions);
}

sub repos {
	return \%repos;
}


# This query compares the list of provided apps to the policy setting for apps which should be installed
# If an app is in the wrong state it sends back an action with details of what to change

sub appsQuery {
	my $request = shift;

	if ($request->isNotQuery([['appsquery']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $args = $request->getParam('args');

	my $data = { remaining => scalar keys %repos, results => [] };

	for my $repo (keys %repos) {

		getExtensions({
			'name'   => $repo, 
			'type'   => $args->{'type'}, 
			'target' => $args->{'targetPlat'} || Slim::Utils::OSDetect::OS(),
			'version'=> $args->{'targetVers'} || $::VERSION,
			'lang'   => $args->{'lang'} || $Slim::Utils::Strings::currentLang,
			'details'=> $args->{'details'},
			'cb'     => \&_appsQueryCB,
			'pt'     => [ $request, $data ],
		});
	}

	if (!scalar keys %repos) {

		_appsQueryCB($request, $data, []);
	}

	if (!$request->isStatusDone()) {

		$request->setStatusProcessing();
	}
}

sub _appsQueryCB {
	my $request = shift;
	my $data    = shift;
	my $res     = shift;

	push @{$data->{'results'}}, @$res;

	return if (--$data->{'remaining'} > 0);

	my $args = $request->getParam('args');

	my $actions = findUpdates($data->{'results'}, $args->{'current'}, $prefs->get($args->{'type'}) || {}, $args->{'details'});

	if ($prefs->get('auto')) {

		$request->addResult('actions', $actions);

	} elsif ($args->{'details'}) {

		$request->addResult('updates', $actions);

	} else {

		$request->addResult('updates', join(',', keys %$actions));
	}

	$request->setStatusDone();
}

sub findUpdates {
	my $results = shift;
	my $current = shift;
	my $install = shift || {};
	my $info    = shift;
	my $apps    = {};
	my $actions = {};

	# find the latest version of each app we are interested in installing
	for my $res (@$results) {
		my $app = $res->{'name'};

		if ($install->{ $app }) {

			if (!$apps->{ $app } || Slim::Utils::Versions->compareVersions($res->{'version'}, $apps->{ $app }->{'version'}) > 0) {

				$apps->{ $app } = $res;
			}
		}
	}

	# find any apps which need install/upgrade
	for my $app (keys %$apps) {

		if (!defined $current->{ $app } || Slim::Utils::Versions->compareVersions($apps->{ $app }->{'version'}, $current->{ $app }) > 0){

			main::INFOLOG && $log->info("$app action install version " . $apps->{ $app }->{'version'} . 
										($current->{ $app } ? (" from " . $current->{ $app }) : ''));

			$actions->{ $app } = { action => 'install', url => $apps->{ $app }->{'url'}, sha => $apps->{ $app }->{'sha'} };

			$actions->{ $app }->{'info'} = $apps->{ $app } if $info;
		}
	}

	# find any apps which need uninstall
	for my $app (keys %$current) {

		if (!$install->{ $app }) {

			main::INFOLOG && $log->info("$app action uninstall");

			$actions->{ $app } = { action => 'uninstall' };
		}
	}

	if (scalar keys %$actions == 0) {

		main::INFOLOG && $log->info("no action required");
	}

	return $actions;
}

sub getExtensions {
	my $args = shift;

	my $cache = Slim::Utils::Cache->new;

	if ( my $cached = $cache->get( $args->{'name'} . '_XML' ) ) {

		main::DEBUGLOG && $log->debug("using cached extensions xml $args->{name}");
	
		_parseXML($args, $cached);

	} else {
	
		main::DEBUGLOG && $log->debug("fetching extensions xml $args->{name}");

		Slim::Networking::Repositories->get(
			$args->{'name'},
			\&_parseResponse,
			\&_noResponse,
			{ args => $args, cache => 1 }
		);
	}
}

sub _parseResponse {
	my $http = shift;
	my $args = $http->params('args');

	my $xml  = {};

	eval { 
		$xml = XMLin($http->content,
			SuppressEmpty => undef,
			KeyAttr     => { 
				title   => 'lang', 
				desc    => 'lang', 
				changes => 'lang'
			},
			ContentKey  => '-content',
			GroupTags   => {
				applets => 'applet', 
				sounds  => 'sound', 
				wallpapers => 'wallpaper', 
				plugins => 'plugin',
				patches => 'patch',
			},
			ForceArray => [ 'applet', 'wallpaper', 'sound', 'plugin', 'patch', 'title', 'desc', 'changes' ],
		 )
	};

	if ($@) {

		$log->warn("Error parsing $args->{name}: $@");

	} else {

		my $cache = Slim::Utils::Cache->new;
		
		$cache->set( $args->{'name'} . '_XML', $xml, 300 );
	}

	_parseXML($args, $xml);
}

sub _noResponse {
	my $http = shift;
	my $error= shift;
	my $args = $http->params('args');

	$log->warn("error fetching $args->{name} - $error");

	if ($args->{'onError'}) {
		$args->{'onError'}->( $args->{'name'}, $error );
	}

	$args->{'cb'}->( @{$args->{'pt'}}, [] );
}

sub _parseXML {
	my $args = shift;
	my $xml  = shift;

	my $type    = $args->{'type'};
	my $target  = $args->{'target'};
	my $version = $args->{'version'};
	my $lang    = $args->{'lang'};
	my $details = $args->{'details'};

	my $targetRE = $target ? qr/$target/ : undef;

	my $debug = main::DEBUGLOG && $log->is_debug;

	my $repoTitle;
	
	$debug && $log->debug("searching $args->{name} for type: $type target: $target version: $version");

	my @res = ();
	my $info;

	if ($xml->{ $type . 's' } && ref $xml->{ $type . 's' } eq 'ARRAY') {

		for my $entry (@{ $xml->{ $type . 's' } }) {

			if ($target && $entry->{'target'} && $entry->{'target'} !~ $targetRE) {
				$debug && $log->debug("entry $entry->{name} does not match, wrong target [$target != $entry->{'target'}]");
				next;
			}

			if ($version && $entry->{'minTarget'} && $entry->{'maxTarget'}) {
				if (!Slim::Utils::Versions->checkVersion($version, $entry->{'minTarget'}, $entry->{'maxTarget'})) {
					$debug && $log->debug("entry $entry->{name} does not match, bad target version [$version outside $entry->{minTarget}, $entry->{maxTarget}]");
					next;
				}
			}

			my $new = {
				'name'    => $entry->{'name'},
				'url'     => $entry->{'url'},
				'version' => $entry->{'version'},
			};

			$new->{'sha'} = $entry->{'sha'} if $entry->{'sha'};
			
			$debug && $log->debug("entry $new->{name} vers: $new->{version} url: $new->{url}");

			if ($details) {

				if ($entry->{'title'} && ref $entry->{'title'} eq 'HASH') {
					$new->{'title'} = $entry->{'title'}->{ $lang } || $entry->{'title'}->{ 'EN' };
				} else {
					$new->{'title'} = $entry->{'name'};
				}
				$new->{title} = '' if ref $new->{title};

				if ($entry->{'desc'} && ref $entry->{'desc'} eq 'HASH') {
					$new->{'desc'} = $entry->{'desc'}->{ $lang } || $entry->{'desc'}->{ 'EN' };
				}
				$new->{desc} = '' if ref $new->{desc};
				
				if ($entry->{'changes'} && ref $entry->{'changes'} eq 'HASH') {
					$new->{'changes'} = $entry->{'changes'}->{ $lang } || $entry->{'changes'}->{ 'EN' };
				}
				$new->{changes} = '' if ref $new->{changes};

				$new->{'link'}    = $entry->{'link'}    if $entry->{'link'};
				$new->{'creator'} = $entry->{'creator'} if $entry->{'creator'};
				$new->{'email'}   = $entry->{'email'}   if $entry->{'email'};
				$new->{'path'}    = $entry->{'path'}    if $entry->{'path'};

			}

			push @res, $new;
		}

	} else {

		$debug && $log->debug("no $type entry in $args->{name}");
	}

	if ($details) {

		if ( $xml->{details} && $xml->{details}->{title} 
				 && ($xml->{details}->{title}->{$lang} || $xml->{details}->{title}->{EN}) ) {
			
			$repoTitle = $xml->{details}->{title}->{$lang} || $xml->{details}->{title}->{EN};
			
		} else {
			
			# fall back to repo's URL if no title is provided
			$repoTitle = $args->{name};
		}
		
		$info = {
			'name'   => $args->{'name'},
			'title'  => $repoTitle,
		};
		
	}

	$debug && $log->debug("found " . scalar(@res) . " extensions");

	$args->{'cb'}->( @{$args->{'pt'}}, \@res, $info );
}


1;
