package Slim::Utils::ExtensionsManager;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# The Extensions Manager deals with Extensions Repositories. These can be plugins, applets,
# wallpapers, or sounds. In the case of plugins it's tightly integrated with the Plugins
# Manager and the Plugins Downloader.

# The Extensions Manager keeps track of the list of extensions it has enabled. In the case
# of plugins this can be confusing, as the Plugin Manager keeps its own state. But that
# latter does so for all plugins, installed using the Extensions Manager or not. Therefore
# we unfortunately have to deal with these two states.

# Repository XML format:
#
# Each repository file may contain entries for applets, wallpapers, sounds, plugins:
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
#   <category>musicservices|radio|hardware|skin|information|playlists|scanning|tools|misc</category>
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
# category   - a category under which to group the plugin
# icon       - a public URL to the plugin icon, to be shown in the plugin manager
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

use Async::Util;
use XML::Simple;

use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log = logger('server.plugins');
my $prefs = preferences('plugin.extensions');

$prefs->init({ repos => [], plugin => {}, auto => 0, useUnsupported => 0 });

my %repos = (
	# default repos mapped to weight which defines the order they are sorted in
	'https://lyrion.org/lms-plugin-repository/extensions.xml' => 1,
);

my $UNSUPPORTED_REPO = 'https://lms-community.github.io/lms-plugin-repository/unsupported.xml';

$prefs->setChange(\&initUnsupportedRepo, 'useUnsupported');

$prefs->migrate(4, sub {
	# remove invalid characters from the end of the URL. These seem to sometimes be added by the forum software
	my %seen;
	$prefs->set('repos', [ grep {
		!$seen{$_}++
	} map {
		s/\W*$//r;
	} @{$prefs->get('repos')} ]);
	1;
});

sub init {
	my $class = shift;

	initUnsupportedRepo();

	for my $repo (keys %repos) {
		Slim::Control::Jive::registerExtensionProvider($repo, \&getExtensions);
	}

	for my $repo ( @{$prefs->get('repos')} ) {
		$class->addRepo({ repo => $repo });
	}

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

	Slim::Control::Request::addDispatch(['appsquery'], [0, 1, 1, \&appsQuery]);
}

sub addRepo {
	my $class = shift;
	my $args = shift;

	my $repo   = $args->{'repo'} =~ s/\W*$//r;
	my $weight = 10;

	main::INFOLOG && $log->info("adding repository $repo weight $weight");

	$repos{$repo} = $weight;

	if (!grep { $_ eq $repo } @{$class->repos}) {
		$prefs->set('repos', [ @{$class->repos}, $repo ]);
	}

	Slim::Control::Jive::registerExtensionProvider($repo, \&getExtensions, 'user');
}

sub removeRepo {
	my $class = shift;
	my $args = shift;

	my $repo = $args->{'repo'};

	main::INFOLOG && $log->info("removing repository $repo");

	delete $repos{$repo};

	$prefs->set('repos', [
		grep {
			$_ ne $repo
		} @{$class->repos()}
	]);

	Slim::Control::Jive::removeExtensionProvider($repo, \&getExtensions);
}

sub repos {
	return $prefs->get('repos') || [];
}

sub initUnsupportedRepo {
	if ($prefs->get('useUnsupported')) {
		$repos{$UNSUPPORTED_REPO} = 2;
	}
	else {
		delete $repos{$UNSUPPORTED_REPO};
	}
}

sub useUnsupported {
	my ($class, $newValue) = @_;

	if (defined $newValue) {
		$prefs->set('useUnsupported', $newValue || 0);
	}

	$prefs->get('useUnsupported') ;
}

sub autoUpdate {
	my ($class, $newValue) = @_;

	if (defined $newValue) {
		$prefs->set('auto', $newValue ? 1 : 0);
	}

	$prefs->get('auto') ;
}

sub enablePlugin {
	my ($class, $plugin) = @_;

	my $plugins = $prefs->get('plugin');
	$plugins->{$plugin} = 1;
	$prefs->set('plugin', $plugins);
}

sub disablePlugin {
	my ($class, $plugin) = @_;

	my $plugins = $prefs->get('plugin');
	delete $plugins->{$plugin};
	$prefs->set('plugin', $plugins);
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

	$request->setStatusProcessing();

	my $data = { results => [] };

	getAllPluginRepos({
		type    => $args->{type},
		target  => $args->{targetPlat} || Slim::Utils::OSDetect::OS(),
		version => $args->{tarcgetVers} || $::VERSION,
		lang    => $args->{lang} || $Slim::Utils::Strings::currentLang,
		details => $args->{details},
		stepCb  => sub {
			my ($res, $info, $weight) = @_;
			push @{$data->{results}}, @{$res || []};
		},
		cb => sub {
			my $actions = findUpdates($data->{results}, $args->{current}, $args->{type}, $args->{details});

			if ($prefs->get('auto')) {

				$request->addResult('actions', $actions);

			} elsif ($args->{details}) {

				$request->addResult('updates', $actions);

			} else {

				$request->addResult('updates', join(',', keys %$actions));
			}

			$request->setStatusDone();
		},
	});
}

sub getCurrentPlugins {
	my $plugins = Slim::Utils::PluginManager->allPlugins;
	my $states  = preferences('plugin.state');

	my $hide = {};
	my $current = {};

	# create entries for built in plugins and those already installed
	my @active;
	my @inactive;

	for my $plugin (keys %$plugins) {

		if ( $plugins->{$plugin}->{needsMySB} && $plugins->{$plugin}->{needsMySB} !~ /false|no/i ) {
			$log->error("Skipping plugin: $plugin - requires mysqueezebox.com, but mysqueezebox.com is no longer available.");
			next;
		}

		my $entry = $plugins->{$plugin};

		# don't show enforced plugins
		next if $entry->{'enforce'};

		my $state = $states->get($plugin);

		my $entry = {
			name    => $plugin,
			title   => Slim::Utils::Strings::getString($entry->{'name'}),
			desc    => Slim::Utils::Strings::getString($entry->{'description'}),
			error   => Slim::Utils::PluginManager->getErrorString($plugin),
			creator => $entry->{'creator'},
			category=> $entry->{'category'},
			icon    => $entry->{'icon'},
			email   => $entry->{'email'},
			homepage=> $entry->{'homepageURL'},
			version => $entry->{'version'},
			settings=> Slim::Utils::PluginManager->isEnabled($entry->{'module'}) ? $entry->{'optionsURL'} : undef,
			installType => $entry->{'basedir'} !~ /InstalledPlugins/ ? 'manual' : 'install',
			enforce => $entry->{'enforce'},
		};

		if ($state =~ /enabled/) {

			push @active, $entry;

			if ($entry->{ installType } ne 'manual') {
				$current->{ $plugin } = $entry->{'version'};
			}

		} elsif ($state =~ /disabled/) {

			push @inactive, $entry;
		}

		$hide->{$plugin} = 1;
	}

	return ($current, \@active, \@inactive, $hide);
}

sub findUpdates {
	my $results = shift;
	my $current = shift;
	my $type    = shift;
	my $info    = shift;
	my $apps    = {};
	my $actions = {};

	my $install = $prefs->get($type) || {};

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

			$actions->{ $app } = { action => 'install', url => $apps->{ $app }->{'url'}, sha => lc($apps->{ $app }->{'sha'}) };

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

sub getAllPluginRepos {
	my $args = shift;

	Async::Util::amap(
		inputs => [ keys %repos ],
		action => sub {
			my ($repo, $cb) = @_;

			getExtensions({
				name    => $repo,
				type    => $args->{type},
				target  => $args->{target} || Slim::Utils::OSDetect::OS(),
				version => $args->{version} || $::VERSION,
				lang    => $args->{lang} || $Slim::Utils::Strings::currentLang,
				details => $args->{details},
				cb      => sub {
					my ($res, $info) = @_;
					$args->{stepCb}->($res, $info, $repos{$repo}) if $args->{stepCb};
					$cb->($res);
				},
				onError => $args->{onError},
			});
		},
		cb => sub {
			my ($repoData, $err) = @_;
			$log->error($err) if $err;

			if ($args->{cb}) {
				my $max = {};

				my @repoData = grep {
					# prune out duplicate entries, favour higher version numbers
					$_->{version} eq $max->{$_->{name}};
				} map {
					# find the higher version numbers
					my $n = $_->{name};
					my $v = $_->{version};

					$max->{$n} = $v if !$max->{$n} || Slim::Utils::Versions->compareVersions($v, $max->{$n}) > 0;

					$_;
				} map { @$_ } @$repoData;

				$args->{cb}->(\@repoData, $err);
			}
		}
	);
}

sub getExtensions {
	my $args = shift;

	my $cache = Slim::Utils::Cache->new;

	if ( my $cached = $cache->get( $args->{'name'} . '_XML' ) ) {

		main::INFOLOG && $log->is_info && $log->info("using cached extensions xml $args->{name}");

		_parseXML($args, $cached);

	} else {

		main::INFOLOG && $log->is_info && $log->info("fetching extensions xml $args->{name}");

		Slim::Networking::SimpleAsyncHTTP->new(
			\&_parseResponse,
			\&_noResponse,
			{ args => $args, cache => 1 }
		)->get( $args->{'name'} );
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
	my $version = $args->{'version'} || $::VERSION;
	my $lang    = $args->{'lang'} || $Slim::Utils::Strings::currentLang;
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

			$new->{'sha'} = lc($entry->{'sha'}) if $entry->{'sha'};

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
				elsif (!ref $entry->{changes}) {
					$new->{changes} = $entry->{changes};
				}
				$new->{changes} = '' if ref $new->{changes};

				$new->{'link'}    = $entry->{'link'}    if $entry->{'link'};
				$new->{'creator'} = $entry->{'creator'} if $entry->{'creator'};
				$new->{'category'}= $entry->{'category'} if $entry->{'category'};
				$new->{'icon'}    = $entry->{'icon'}    if $entry->{'icon'};
				$new->{'email'}   = $entry->{'email'}   if $entry->{'email'};
				$new->{'path'}    = $entry->{'path'}    if $entry->{'path'};
				$new->{'installations'} = $entry->{'installations'} if $entry->{'installations'};

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


package Slim::Utils::PluginRepoManager;

my $warned;

sub getCurrentPlugins {
	Slim::Utils::Log::logBacktrace("Slim::Utils::PluginRepoManager doesn't exist any more. Please use Slim::Utils::ExtensionsManager instead.") if !$warned++;
	return Slim::Utils::ExtensionsManager::getCurrentPlugins(@_);
}

1;


package Slim::Plugin::Extensions::Plugin;

my $warned;

sub getCurrentPlugins {
	Slim::Utils::Log::logBacktrace("Slim::Plugin::Extensions doesn't exist any more. Please use Slim::Utils::ExtensionsManager instead.") if !$warned++;
	return Slim::Utils::ExtensionsManager::getCurrentPlugins(@_);
}

1;
