package Slim::Plugin::InternetRadio::Plugin;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Digest::MD5 ();
use File::Basename qw(basename);
use File::Path qw(mkpath);
use File::Spec::Functions qw(catdir catfile);
use HTTP::Date;
use JSON::XS::VersionOneAndTwo;
use Tie::IxHash;
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
	
	if ( $class eq __PACKAGE__ ) {
		# When called initially, fetch the list of radio plugins
		Slim::Utils::Timers::setTimer(
			undef,
			time(),
			sub {
				if ( main::SLIM_SERVICE ) {
					# On SN, fetch the list of radio menu items directly
					require SDI::Util::RadioMenus;
					
					my $menus = SDI::Util::RadioMenus->menus(
						uri_prefix => 'http://' . Slim::Networking::SqueezeNetwork->get_server('sn'),
					);
					
					$class->buildMenus( $menus );
					
					return;
				}
				
				if ( $prefs->get('sn_email') && $prefs->get('sn_password_sha') ) {
					# Do nothing, menu is returned via SN login
				}
				else {
					# Initialize radio menu for non-SN user
					my $http = Slim::Networking::SqueezeNetwork->new(
						\&_gotRadio,
						\&_gotRadioError,
						{
							Timeout => 30,
						},
					);
					
					my $url = Slim::Networking::SqueezeNetwork->url('/api/v1/radio');
					
					$http->get($url);
				}
			},
		);
		
		# Setup cant_open handler for RadioTime reporting
		Slim::Control::Request::subscribe(
			\&cantOpen,
			[[ 'playlist','cant_open' ]],
		);
	}

	if ( $class ne __PACKAGE__ ) {
		# Create a real plugin only for our sub-classes
		return $class->SUPER::initPlugin(@_);
	}
	
	return;
}

sub _gotRadio {
	my $http = shift;
	
	my $json = eval { from_json( $http->content ) };
	
	if ( $log->is_debug ) {
		$log->debug( 'Got radio menu from SN: ' . Data::Dump::dump($json) );
	}
	
	if ( $@ ) {
		$http->error( $@ );
		return _gotRadioError($http);
	}
	
	__PACKAGE__->buildMenus( $json->{radio_menu} );
}

sub _gotRadioError {
	my $http  = shift;
	my $error = $http->error;
	
	$log->error( "Unable to retrieve radio directory from SN: $error" );
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
		if ( !main::SLIM_SERVICE && !Slim::Utils::OSDetect::isSqueezeOS() ) {
			if ( $item->{icon} && $icondir ) {
				# Download and cache icons so we can support resizing on them
				$class->cacheIcon( $icondir, $item->{icon} );
			}
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
	
	my $tag     = lc $subclass;
	my $name    = $item->{name};    # a string token
	my $strings = $item->{strings}; # all strings for this item
	my $feed    = $item->{URL};
	my $weight  = $item->{weight};
	my $type    = $item->{type};
	my $icon    = $ICONS->{ $item->{icon} } || $item->{icon};
	my $iconRE  = $item->{iconre} || 0;
	
	# SN needs to dynamically filter radio plugins per-user and append values such as RT username
	my $filter;
	my $append;
	if ( main::SLIM_SERVICE ) {
		$filter = $item->{filter}; # XXX needed?
		$append = $item->{append};
	}
	
	# Bug 14245, this class may already exist if it was created on startup with no SN account,
	# and then we tried to re-create it after an SN account has been entered
	my $pclass = "${package}::${subclass}";
	if ( $pclass->can('initPlugin') ) {
		# The plugin may have a new URL, we can change the URL in the existing plugin
		$pclass->setFeed($feed);
		
		main::DEBUGLOG && $log->is_debug && $log->debug("$pclass already exists, changing URL to $feed");
		
		return;
	}
	
	if ( $strings && uc($name) eq $name ) {
		# Use SN-supplied translations
		Slim::Utils::Strings::storeExtraStrings([{
			strings => $strings,
			token   => $name,
		}]);
	}
	
	my $code = qq{
package ${package}::${subclass};

use strict;
use base qw($package);

};

	if ( main::SLIM_SERVICE ) {
		$code .= qq{
use Slim::Utils::Prefs;

my \$prefs = preferences('server');
};
	}
	
	$code .= qq{
sub initPlugin {
	my \$class = shift;
	
	my \$iconre = '$iconRE';
	
	if ( \$iconre ) {
		Slim::Player::ProtocolHandlers->registerIconHandler(
	        qr/\$iconre/,
	        sub { return \$class->_pluginDataFor('icon'); }
	    );
	}
	
	\$class->setFeed('$feed');

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

	if ( main::SLIM_SERVICE && $append ) {
		# Feed method must append a pref to the URL
		$code .= qq{
sub feed {
	my ( \$class, \$client ) = \@_;
	
	my \$val = \$prefs->client(\$client)->get('$append');
	
	my \$feed = '$feed';
	
	\$feed .= ( \$feed =~ /\\\?/ ) ? '&' : '?';
	\$feed .= \$val;
	
	return \$class->radiotimeFeed( \$feed, \$client );
}
};
	}
	else {
		# RadioTime URLs require special handling
		if ( $feed =~ /(?:radiotime|tunein)\.com/ ) {
			$code .= qq{
sub feed {
	my \$class = shift;
	
	my \$feed = getFeed();
	
	return \$class->radiotimeFeed( \$feed, \@_ );
}
};
		}
		else {
			$code .= qq{
sub feed { getFeed() }
};
		}
	}

	$code .= qq{

sub icon { '$icon' }

# Provide a way to change the feed later
my \$localFeed;

sub getFeed { \$localFeed }

sub setFeed { \$localFeed = \$_[1] }

1;
};

	eval $code;
	if ( $@ ) {
		$log->error( "Unable to dynamically create radio class $subclass: $@" );
		return;
	}
	
	$subclass = "${package}::${subclass}";
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Creating radio plugin: $subclass");
	
	$subclass->initPlugin();
}

sub cacheIcon {
	my ( $class, $icondir, $icon ) = @_;
	
	if ( $ICONS->{$icon} ) {
		# already cached
		return;
	}
	
	my $iconpath = catfile( $icondir, basename($icon) );
	
	if ( main::DEBUGLOG && $log->is_debug ) {
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

	# In order of preference
	tie my %rtFormats, 'Tie::IxHash', (
		aac     => 'aac',
		ogg     => 'ogg',
		mp3     => 'mp3',
		wmpro   => 'wmap',
		wma     => 'wma',
		wmvoice => 'wma',
		# Real Player is supported through the AlienBBC plugin
		real    => 'rtsp',
	);

	my @formats = keys %rtFormats;
	my $id = '';
	
	if ($client) {
		my %playerFormats = map { $_ => 1 } $client->formats;
	
		# RadioTime's listing defaults to giving us mp3 and wma streams only,
		# but we support a few more
		@formats = grep {
		
			# format played natively on player?
			my $canPlay = $playerFormats{$rtFormats{$_}};
				
			if ( !$canPlay && main::TRANSCODING ) {
	
				foreach my $supported (keys %playerFormats) {
					
					if ( Slim::Player::TranscodingHelper::checkBin(sprintf('%s-%s-*-*', $rtFormats{$_}, $supported)) ) {
						$canPlay = 1;
						last;
					}
	
				}
			}
	
			$canPlay;
	
		} keys %rtFormats;
		
		$id = $client->uuid || $client->id;
	}

	$feed .= ( $feed =~ /\?/ ) ? '&' : '?';
	$feed .= 'formats=' . join(',', @formats);
	
	# Bug 15568, pass obfuscated serial to RadioTime
	$feed .= '&serial=' . Digest::MD5::md5_hex($id);
	
	return $feed;
}

sub _pluginDataFor {
	my ( $class, $key ) = @_;
	
	if ( $key ne 'icon' ) {
		return $class->SUPER::_pluginDataFor($key);
	}
	
	if ( main::SLIM_SERVICE || Slim::Utils::OSDetect::isSqueezeOS() ) {
		return $class->icon;
	}
	
	# Special handling for cached remote icons from SN
	# The Web::Graphics code will use this special URL to find the
	# cached icon path.
	return 'plugins/cache/icons/' . basename( $class->icon );
}

sub cantOpen {
	my $request = shift;
	
	my $url   = $request->getParam('_url');
	my $error = $request->getParam('_error');
	
	if ( !main::SLIM_SERVICE ) {
		# Do not report if the user has turned off stats reporting
		# Reporting is always enabled on SN
		return if $prefs->get('sn_disable_stats');
	}
	
	if ( $error && $url =~ /(?:radiotime|tunein)\.com/ ) {
		my ($id) = $url =~ /id=([^&]+)/;
		if ( $id ) {
			my $reportUrl = 'http://opml.radiotime.com/Report.ashx?c=stream&partnerId=16'
				. '&id=' . uri_escape_utf8($id)
				. '&message=' . uri_escape_utf8($error);
		
			main::INFOLOG && $log->is_info && $log->info("Reporting stream failure to RadioTime: $reportUrl");
		
			my $http = Slim::Networking::SimpleAsyncHTTP->new(
				sub {
					main::INFOLOG && $log->is_info && $log->info("RadioTime failure report OK");
				},
				sub {
					my $http = shift;
					main::INFOLOG && $log->is_info && $log->info( "RadioTime failure report failed: " . $http->error );
				},
				{
					timeout => 30,
				},
			);
		
			$http->get($reportUrl);
			
			if ( main::SLIM_SERVICE ) {
				# Let's log these on SN too
				$error =~ s/"/'/g;
				SDI::Util::Syslog::error("service=RadioTime-Error rtid=${id} error=\"${error}\"");
			}
		}
	}
}

1;
