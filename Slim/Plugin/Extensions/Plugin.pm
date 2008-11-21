package Slim::Plugin::Extensions::Plugin;

# Plugin to allow server Plugins and extensions for Jive to be maintained via one or more repository xml files
# which define available plugins/applets/wallpapers/sounds which can then be selected by the user for installation.
#
# This is implemented in a plugin for the moment so it can be verified and to allow it to be disabled.
# Once proven it may move to the core server.
#
# Operation:
# The plugin maintains a list of urls for XML repository files.  This is used by Slim::Contoller::Jive and
# Slim::Plugins::Extensions::Settings to maintain a list of available extensions. When jive or the plugin downloader
# makes a request for available extensions these are fetched and parsed to create the list of available extensions.
# The list is filtered by the criteria passed to it so that only extensions which are relavent to the platform are returned.
# The main repository file will be served by slimdevices.com and will contain details verified 3rd party extensions.
# Most users will only have this defined.  For power users and extension authors, there is also the ability to define
# additional XML repository urls.  These will not be verified so users defining additional repositories must trust them.
#
# Security discussion:
# This plugin provides the ability to link to executable code (perl plugins, lua applets and binaries) which will be
# automatically downloaded and installed on the server or jive controllers/desktop versions of squeezeplay without
# users verifying the source or contents of the code themselves.  The security model is based on trusting
# the integrity of the hosted repository files.  For this reason it is expected that normal users will only use
# the repository file hosted on slimdevices.com which will only contain links to trusted extensions.  Users adding
# additional respository locations should trust the integrity of the respository owner.  For plugins, each downloaded file
# is verified by a sha1 digest which is stored in the repo file to ensure that the downloaded file matches the original
# created by the author and referred to in the repo file.  This enforces the trust model of relying on the repo file.
#
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
# </extensions>
#
# Applet and Plugin entries are of the form:
# 
# <applet name="AppletName" version="1.0" target="jive" minTarget="7.3" maxTarget="7.3">
#   <title lang="EN">English Title</title>
#   <title lang="DE">German Title</title>
#   <desc lang="EN">EN description</desc>
#   <desc lang="DE">DE description</desc>
#   <creator>Name of Author</creator>
#   <email>email of Author</email>
#   <url>url for zip file</url>
# </applet>
#
# <plugin name="PluginName" version="1.0" target="windows" minTarget="7.3" maxTarget="7.3">
#   <title lang="EN">English Title</title>
#   <title lang="DE">German Title</title>
#   <desc lang="EN">EN description</desc>
#   <desc lang="DE">DE description</desc>
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
# TODO:
# an additional element: <action>remove</action> may be included if it is desired to automatically remove an installed
# applet/plugin matching the version defined (to be used if it causes instability or is found to cause undesireable effects...)
#

use strict;

use base qw(Slim::Plugin::Base);

use XML::Simple;

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Networking::SqueezeNetwork;
use Slim::Control::Jive;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use Slim::Plugin::Extensions::PluginDownloader;
if ( !main::SLIM_SERVICE && !$::noweb ) {
	require Slim::Plugin::Extensions::Settings;
}

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.extensions',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_EXTENSIONS',
});

my $prefs = preferences('plugin.extensions');

my $masterRepo = Slim::Networking::SqueezeNetwork->url('/public/plugins/repository.xml');

my %repos = ();

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin;

	for my $repo ( $masterRepo, @{$prefs->get('repos')} ) {
		if ($repo) {
			$repos{$repo} = 1;
			Slim::Control::Jive::registerExtensionProvider($repo, \&getExtensions);
		}
	}

	Slim::Plugin::Extensions::PluginDownloader->init;

	if ( !main::SLIM_SERVICE && !$::noweb ) {
		Slim::Plugin::Extensions::Settings->new;
	}
}

sub addRepo {
	my $class = shift;
	my $repo  = shift;

	$log->info("adding repository $repo");

	$repos{$repo} = 1;
	Slim::Control::Jive::registerExtensionProvider($repo, \&getExtensions);
}

sub removeRepo {
	my $class = shift;
	my $repo  = shift;

	$log->info("removing repository $repo");

	delete $repos{$repo};
	Slim::Control::Jive::removeExtensionProvider($repo, \&getExtensions);
}

sub getPlugins {
	my $class = shift;
	my $cb    = shift;
	my $pt    = shift || [];

	my $data = { remaining => scalar keys %repos, results => [], errors => {} };

	for my $repo (keys %repos) {
		getExtensions({
			'name'   => $repo, 
			'type'   => 'plugin', 
			'target' => Slim::Utils::OSDetect::OS(),
			'version'=> $::VERSION, 
			'lang'   => $Slim::Utils::Strings::currentLang,
			'cb'     => \&_getPluginsCB,
			'pt'     => [ $data, $cb, $pt ],
			'onError'=> sub { $data->{'errors'}->{ $_[0] } = $_[1] },
		});
	}

	if (!keys %repos) {
		$cb->( @$pt, [], {} );
	}
}

sub _getPluginsCB {
	my $data  = shift;
	my $cb    = shift;
	my $pt    = shift;
	my $res   = shift;

	splice @{$data->{'results'}}, 0, 0, @$res;

	if ( ! --$data->{'remaining'} ) {

		$cb->( @$pt, $data->{'results'}, $data->{'errors'} );
	}
}

sub getExtensions {
	my $args = shift;

	my $cache = Slim::Utils::Cache->new;

	if ( my $cached = $cache->get( $args->{'name'} . '_XML' ) ) {

		$log->debug("using cached extensions xml $args->{name}");
	
		_parseXML($args, $cached);

	} else {
	
		$log->debug("fetching extensions xml $args->{name}");

		Slim::Networking::SimpleAsyncHTTP->new(
			\&_parseResponse, \&_noResponse, { 'args' => $args, 'cache' => 1 }
		   )->get( $args->{'name'} );
	}
}

sub _parseResponse {
	my $http = shift;
	my $args = $http->params('args');

	my $xml  = {};

	eval { $xml = XMLin($http->content,
						SuppressEmpty => 1,
						KeyAttr    => { title => 'lang', desc => 'lang' },
						ContentKey => '-content',
						GroupTags  => { applets => 'applet', sounds => 'sound', wallpapers => 'wallpaper', plugins => 'plugin' },
						ForceArray => [ 'applet', 'wallpaper', 'sound', 'plugin', 'title', 'desc' ],
					   ) };

	if ($@) {

		$log->warn("Error parsing $args->{name}: $@");

	} else {

		my $cache = Slim::Utils::Cache->new;
		
		$cache->set( $args->{'name'} . '_XML', $xml, '5m' );
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

	my $targetRE = $target ? qr/$target/ : undef;

	my $debug = $log->is_debug;

	$debug && $log->debug("searching $args->{name} for type: $type target: $target version: $version");

	my @res = ();

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
				'name' => $entry->{'name'},
				'url'  => $entry->{'url'},
			};

			if ($entry->{'title'} && ref $entry->{'title'} eq 'HASH') {
				$new->{'title'} = $entry->{'title'}->{ $lang } || $entry->{'title'}->{ 'EN' };
			} else {
				$new->{'title'} = $entry->{'name'};
			}

			if ($entry->{'desc'} && ref $entry->{'desc'} eq 'HASH') {
				$new->{'desc'} = $entry->{'desc'}->{ $lang } || $entry->{'desc'}->{ 'EN' };
			}

			$new->{'version'} = $entry->{'version'} if $entry->{'version'};
			$new->{'link'}    = $entry->{'link'}    if $entry->{'link'};
			$new->{'sha'}     = $entry->{'sha'}     if $entry->{'sha'};
			$new->{'creator'} = $entry->{'creator'} if $entry->{'creator'};
			$new->{'email'}   = $entry->{'email'}   if $entry->{'email'};
			$new->{'action'}  = $entry->{'action'}  if $entry->{'action'};

			push @res, $new;

			$debug && $log->debug("entry $entry->{name} title: $new->{title} vers: $new->{version} url: $new->{url}");
		}

	} else {

		$debug && $log->debug("no $type entry in $args->{name}");
	}

	$debug && $log->debug("found " . scalar(@res) . " extensions");

	$args->{'cb'}->( @{$args->{'pt'}}, \@res );
}


1;
