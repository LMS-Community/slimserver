package Slim::Plugin::OPMLGeneric::Plugin;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased);

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(
		feed => Slim::Networking::SqueezeNetwork->url( '/api/myapps/v1/opml' ),
		tag  => 'opml_generic',
		node => '',
	);
}

# No ip3k menu for this plugin
sub modeName { }

# No SP menus are created by this plugin
sub initJive { }

# CLI is handled a bit differently, using the opml_url param
sub initCLI {
	my ( $class, %args ) = @_;
	
	my $cliQuery = sub {
		my $request = shift;
		my $url = $request->getParam('opml_url');
		
		Slim::Control::XMLBrowser::cliQuery( $args{tag}, $url, $request );
	};
	
	# CLI support
	Slim::Control::Request::addDispatch(
		[ $args{tag}, 'items', '_index', '_quantity' ],
	    [ 1, 1, 1, $cliQuery ]
	);
	
	# XXX: This works (due to XMLBrowser caching)
	# but isn't really right, as opml_url is not passed through properly
	Slim::Control::Request::addDispatch(
		[ $args{tag}, 'playlist', '_method' ],
		[ 1, 1, 1, $cliQuery ]
	);
}

sub webPages { }

1;
