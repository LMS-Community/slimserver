package Slim::Plugin::Extensions::Plugin;

# Plugin to allow extensions for Jive (and in future server Plugins) to be maintained via one or more
# repository xml files which define available applets/wallpapers/sounds/(plugins) which can then be
# selected by the user for installation.
#
# This is implemented in a plugin for the moment so it can be verified and to allow it to be disabled.
# Once proven it may move to the core server.
#
# Operation:
# The plugin maintains a list of urls for XML repository files.  When jive makes a request for available
# extensions these are fetched and parsed to add to create the list of available extensions (in additon to any
# created by other plugins.  The main repository file will be served by slimdevices.com and will contain
# details verified 3rd party extensions.  Most users will only have this defined.  For power users and extension
# authors, there is also the ability to define additional XML repository urls.  These will not be verified
# so users defining additional repositories must trust them.
#
# Security discussion:
# This plugin provides the ability to link to executable code (Lua and binaries) which will be automatically
# downloaded and installed on jive controllers/desktop versions of squeezeplay via the applet installer without
# users verifying the source or contents of the code themselves.  The security model is based on trusting
# the integrity of the hosted repository files.  For this reason it is expected that normal users will only use
# the repository file hosted on slimdevices.com which will only contain links to trusted extensions.  Users adding
# additional respository locations should trust the integrity of the respository owner.
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
# Applet entries are of the form:
# 
# <applet name="AppletName" version="1.0" target="jive" minTarget="7.3" maxTarget="7.3">
#   <title>
#     <EN>Apples English Title</EN>
#     <DE>Applets German Title</DE>
#   </title>
#   <desc>url for description file</desc>
#   <url>url for zip file</url>
#   <md5>digest of zip</md5>
# </applet>
#
# AppletName - the name of the applet on jive and must match the file naming structure of the applet.
# version    - the version of the applet (used to decide if a newer version should be installed)
# target     - string defining the target, squeezeplay currently uses 'jive'
# minTarget  - min version of the target software
# maxTarget  - max version of the target software
# title      - contains localisations for the title of the applet (optional - uses name if not defined)
# desc       - url for a text file which contains a description of the applet (see below) (optional)
# url        - url for the applet itself, this sould be a zipfile of name AppletName.zip
# md5        - (unimplemented on jive) digest of the zip file which is verifed before the zip is extracted (optional)
#
# an additional element: <action>remove</action> may be included if it is desired to automatically remove an installed
# applet matching the version defined (to be used if it causes instability or is found to cause undesireable effects...)
#
# Wallpaper and sound entries can include all of the above elements, but the minimal definition is:
# 
# <wallpaper name="WallpaperName" url="url for wallpaper file" />
#
# <sound     name="SoundName"     url="url for sound file"     />
#
# Plugin entries - Todo (expected to be based on applet entries)

use strict;

use base qw(Slim::Plugin::Base);

use XML::Simple;

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Control::Jive;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use Slim::Plugin::Extensions::Settings;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.extensions',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_EXTENSIONS',
});

my $prefs = preferences('plugin.extensions');

my $masterRepo = undef; # Repo hosted at slimdevices.com

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin;

	Slim::Plugin::Extensions::Settings->new;

	# register ourselves as an extension provider for each defined repo
	for my $repo ( $masterRepo, @{$prefs->get('repos')} ) {
		Slim::Control::Jive::registerExtensionProvider($repo, \&getExtensions) if $repo;
	}
}

sub addRepo {
	my $repo = shift;
	$log->info("adding repository $repo");
	Slim::Control::Jive::registerExtensionProvider($repo, \&getExtensions);
}

sub removeRepo {
	my $repo = shift;
	$log->info("removing repository $repo");
	Slim::Control::Jive::removeExtensionProvider($repo, \&getExtensions);
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
			\&_parseResponse, \&_parseResponse, { 'args' => $args, 'cache' => 1 }
		   )->get( $args->{'name'} );
	}
}

sub _parseResponse {
	my $http = shift;
	my $args = $http->params('args');

	my $xml  = {};

	eval { $xml = XMLin($http->content, KeyAttr    => [], SuppressEmpty => 1,
						GroupTags  => { applets => 'applet', sounds => 'sound', wallpapers => 'wallpaper', plugins => 'plugin' },
						ForceArray => [ 'applet', 'wallpaper', 'sound' ],
					   ) };

	if ($@) {

		$log->warn("Error parsing $args->{name}: $@");

	} else {

		my $cache = Slim::Utils::Cache->new;
		
		$cache->set( $args->{'name'} . '_XML', $xml, '5m' );
	}

	_parseXML($args, $xml);
}

sub _parseXML {
	my $args = shift;
	my $xml  = shift;

	my $type    = $args->{'type'};
	my $target  = $args->{'target'};
	my $version = $args->{'version'};
	my $lang    = $args->{'lang'};

	my $debug = $log->is_debug;

	$debug && $log->debug("searching $args->{name} for type: $type target: $target version: $version");

	my @res = ();

	if ($xml->{ $type . 's' }) {

		for my $entry (@{ $xml->{ $type . 's' } }) {

			if ($target && $entry->{'target'} && $target ne $entry->{'target'}) {
				$debug && $log->debug("entry $entry->{name} does not match, wrong target [$target != $entry->{'target'}]");
				next;
			}

			if ($version && $entry->{'minTarget'} && $entry->{'maxTarget'}) {
				if (!Slim::Utils::Versions->checkVersion($version, $entry->{'minTarget'}, $entry->{'maxTarget'})) {
					$debug && $log->debug("entry $entry->{name} does not match, bad target version [$version outside $entry->{minTarget}, $entry->{maxTarget}]");
					next;
				}
			}

			my $title;

			if ($entry->{'title'}) {
				$title = $entry->{'title'}->{ $lang } || $entry->{'title'}->{ 'EN' } || $entry->{'title'};
			} else {
				$title = $entry->{'name'};
			}

			my $new = {
				'name'  => $entry->{'name'},
				'title' => $title,
				'url'   => $entry->{'url'},
			};

			$new->{'version'} = $entry->{'version'} if $entry->{'version'};
			$new->{'desc'}    = $entry->{'desc'}    if $entry->{'desc'};
			$new->{'md5'}     = $entry->{'md5'}     if $entry->{'md5'};
			$new->{'action'}  = $entry->{'action'}  if $entry->{'action'};

			push @res, $new;

			$debug && $log->debug("entry $entry->{name} title: $new->{title} vers: $new->{vers} desc: $new->{desc} url: $new->{url}");
		}
	}

	$debug && $log->debug("found " . scalar(@res) . " extensions");

	$args->{'cb'}->( @{$args->{'pt'}}, \@res );
}

1;
