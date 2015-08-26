package Slim::Plugin::InternetRadio::Plugin;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Plugin::RadioTime::Plugin;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log   = logger('plugin.radio');
my $prefs = preferences('server');

sub initPlugin {
	my $class = shift;
	
	if ( $class eq __PACKAGE__ ) {
		# When called initially, fetch the list of radio plugins
		Slim::Utils::Timers::setTimer(
			undef,
			time(),
			\&_initRadio,
		);
		
		# Setup cant_open handler for RadioTime reporting
		Slim::Control::Request::subscribe(
			\&cantOpen,
			[['playlist'],['cant_open' ]],
		);
	}

	if ( $class ne __PACKAGE__ ) {
		# Create a real plugin only for our sub-classes
		return $class->SUPER::initPlugin(@_);
	}
	
	return;
}

sub _initRadio {
	if ( main::SLIM_SERVICE ) {
		# On SN, fetch the list of radio menu items directly
		require SDI::Util::RadioMenus;
		
		my $menus = SDI::Util::RadioMenus->menus(
			uri_prefix => 'http://' . Slim::Networking::SqueezeNetwork->get_server('sn'),
		);
		
		__PACKAGE__->buildMenus( $menus );
		
		return;
	}
	
	Slim::Formats::XML->getFeedAsync(
		\&_gotRadio,
		\&_gotRadioError,
		{
			url     => Slim::Plugin::RadioTime::Plugin->mainUrl,
			Timeout => 30,
		},
	);
}

sub _gotRadio {
	my $opml = shift;

	my $menu = Slim::Plugin::RadioTime::Plugin->parseMenu($opml);
	
	__PACKAGE__->buildMenus( $menu );
}

my $retry = 5;
sub _gotRadioError {
	my $error = shift;
	
	$log->error( "Unable to retrieve radio directory from SN: $error" );
	
	# retry in a bit, but don't wait any longer than 5 minutes 
	$retry ||= 5;
	$retry = $retry > 300 ? $retry : ($retry * 2);
	
	Slim::Utils::Timers::setTimer(
		undef,
		time() + $retry,
		\&_initRadio
	);
}

sub buildMenus {
	my ( $class, $items ) = @_;
	
	for my $item ( @{$items} ) {
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
	my $icon    = $item->{icon};
	my $iconRE  = $item->{iconre} || 0;
	
	# SN needs to dynamically filter radio plugins per-user and append values such as RT username
	my $filter;
	my $append;
	if ( main::SLIM_SERVICE ) {
		$filter = $item->{filter}; # XXX needed?
		$append = $item->{append};
	}
	elsif ( $feed =~ /username=([^&]+)/ ) {
		Slim::Plugin::RadioTime::Plugin->setUsername($1);
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

# Some RadioTime-specific code to add formats param if Alien is installed
sub radiotimeFeed {
	my ( $class, $feed, $client ) = @_;

	return Slim::Plugin::RadioTime::Plugin->fixUrl($feed, $client);
}

sub _pluginDataFor {
	my ( $class, $key ) = @_;

	return $class->icon if $key eq 'icon';
	
	return $class->SUPER::_pluginDataFor($key);
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
		Slim::Plugin::RadioTime::Plugin->reportError($url, $error);
	}
}

1;
