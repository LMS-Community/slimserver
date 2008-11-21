package Slim::Plugin::InternetRadio::Plugin;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased);

use File::Basename qw(basename);
use File::Path qw(mkpath);
use File::Spec::Functions qw(:ALL);
use HTTP::Date;
use URI::Escape qw(uri_escape_utf8);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log   = logger('server.plugins');
my $prefs = preferences('server');

my $MENU  = [];
my $ICONS = {};

sub initPlugin {
	my $class = shift;
	
	# Do nothing on init for this plugin
	if ( $class eq __PACKAGE__ ) {
		
		if ( main::SLIM_SERVICE ) {
			# On SN, create the Internet Radio menu as an OPML link
			Slim::Buttons::Home::addMenuOption(
				RADIO => {
					useMode => sub {
						my $client = shift;
						
						my $name = $client->string('RADIO');
						
						my %params = (
							header   => $name,
							modeName => $name,
							url      => Slim::Networking::SqueezeNetwork->url('/api/v1/radio/opml'),
							title    => $name,
							timeout  => 35,
						);

						Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );

						# we'll handle the push in a callback
						$client->modeParam( handledTransition => 1 );
					},
				},
			);
			
			# Add a CLI command for this for Jive on SN
			my $cliQuery = sub {
			 	my $request = shift;
				Slim::Control::XMLBrowser::cliQuery(
					'internetradio',
					Slim::Networking::SqueezeNetwork->url('/api/v1/radio/opml'),
					$request,
				);
			};
			
			Slim::Control::Request::addDispatch(
				[ 'internetradio', 'items', '_index', '_quantity' ],
			    [ 1, 1, 1, $cliQuery ]
			);
		}
		
		return;
	}
	
	return $class->SUPER::initPlugin(@_);
}

sub buildMenus {
	my ( $class, $items ) = @_;
	
	$MENU = $items;
	
	# Initialize icon directory
	my $cachedir = $prefs->get('cachedir');
	my $icondir  = catdir( $cachedir, 'icons' );
	
	if ( !-d $icondir ) {
		mkpath($icondir) or do {
			logError("Unable to create plugin icon cache dir $icondir");
			$icondir = undef;
		};
	}
	
	for my $item ( @{$items} ) {
		if ( $item->{icon} && $icondir ) {
			# Download and cache icons so we can support resizing on them
			$class->cacheIcon( $icondir, $item->{icon} );
		}
		
		$class->generate( $item );
	}
	
	# Update main menu in case players were connected before the menus were created
	for my $client ( Slim::Player::Client::clients() ) {
		Slim::Buttons::Home::updateMenu($client);
		$client->update;
	}
}

sub generate {
	my ( $class, $item ) = @_;
	
	my $package  = __PACKAGE__;
	my $subclass = $item->{class} || return;
	
	my $tag    = lc $subclass;
	my $name   = $item->{name};
	my $feed   = $item->{URL};
	my $weight = $item->{weight};
	my $type   = $item->{type};
	my $icon   = $ICONS->{ $item->{icon} }; # local path to cached icon
	my $iconRE = $item->{iconre} || 0;
	
	my $code = qq{
package ${package}::${subclass};

use strict;
use base qw($package);

sub initPlugin {
	my \$class = shift;
	
	my \$iconre = '$iconRE';
	
	if ( \$iconre ) {
		Slim::Player::ProtocolHandlers->registerIconHandler(
	        qr/\$iconre/,
	        sub { return \$class->_pluginDataFor('icon'); }
	    );
	}

	\$class->SUPER::initPlugin(
		tag    => '$tag',
		menu   => 'radios',
		weight => $weight,
		type   => '$type',
	);
}

sub getDisplayName { '$name' }

sub playerMenu { 'RADIO' }

};

	# RadioTime URLs require special handling
	if ( $feed =~ /radiotime\.com/ ) {
		$code .= qq{
sub feed {
	my \$class = shift;
	
	return \$class->radiotimeFeed( '$feed', \@_ );
}
};
	}
	else {
		$code .= qq{
sub feed { '$feed' }
};
	}

	$code .= qq{

sub icon { '$icon' }

1;
};

	eval $code;
	if ( $@ ) {
		$log->error( "Unable to dynamically create radio class $subclass: $@" );
		return;
	}
	
	$subclass = "${package}::${subclass}";
	
	$subclass->initPlugin();
}

sub cacheIcon {
	my ( $class, $icondir, $icon ) = @_;
	
	if ( $ICONS->{$icon} ) {
		# already cached
		return;
	}
	
	my $iconpath = catfile( $icondir, basename($icon) );
	
	if ( $log->is_debug ) {
		$log->debug( "Caching remote icon $icon as $iconpath" );
	}
	
	$ICONS->{$icon} = $iconpath;
	
	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		sub {},
		\&cacheIconError,
		{
			saveAs => $iconpath,
			icon   => $icon,
		},
	);
	
	my %headers;
	
	if ( -e $iconpath ) {
		$headers{'If-Modified-Since'} = time2str( (stat $iconpath)[9] );
	}
	
	$http->get( $icon, %headers );
}

sub cacheIconError {
	my $http  = shift;
	my $error = $http->error;
	my $icon  = $http->params('icon');
	
	$log->error( "Error caching remote icon $icon: $error" );
	
	delete $ICONS->{$icon};
}

# Some RadioTime-specific code to add formats param if Alien is installed
sub radiotimeFeed {
	my ( $class, $feed, $client ) = @_;
	
	# RadioTime's listing defaults to giving us mp3 and wma streams.
	# If AlienBBC is installed we can ask for Real streams too.
	if ( exists $INC{'Plugins/Alien/Plugin.pm'} ) {
		$feed .= ( $feed =~ /\?/ ) ? '&' : '?';
		$feed .= 'formats=mp3,wma,real';
	}
	
	return $feed;
}

sub _pluginDataFor {
	my ( $class, $key ) = @_;
	
	if ( $key ne 'icon' ) {
		return $class->SUPER::_pluginDataFor($key);
	}
	
	# Special handling for cached remote icons from SN
	# The Web::Graphics code will use this special URL to find the
	# cached icon path.
	return 'plugins/cache/icons/' . basename( $class->icon );
}

1;
