package Slim::Plugin::OPMLBased;

# $Id$

# Base class for all plugins that use OPML feeds

use strict;
use base 'Slim::Plugin::Base';

my %cli_next = ();

sub initPlugin {
	my ( $class, %args ) = @_;
	
	{
		no strict 'refs';
		*{$class.'::'.'feed'} = sub { $args{feed} };
		*{$class.'::'.'tag'}  = sub { $args{tag} };
		*{$class.'::'.'menu'} = sub { $args{menu} };
	}
	
	my $cliQuery = sub {
	 	my $request = shift;
		Slim::Buttons::XMLBrowser::cliQuery( $args{tag}, $args{feed}, $request );
	};
	
	# CLI support
	Slim::Control::Request::addDispatch(
		[ $args{tag}, 'items', '_index', '_quantity' ],
	    [ 0, 1, 1, $cliQuery ]
	);
	
	Slim::Control::Request::addDispatch(
		[ $args{tag}, 'playlist', '_method' ],
		[ 1, 1, 1, $cliQuery ]
	);
		
	$cli_next{$class} = Slim::Control::Request::addDispatch(
		[ 'radios', '_index', '_quantity' ],
		[ 0, 1, 1, $class->cliRadiosQuery( $args{tag} ) ]
	);
	
	$class->SUPER::initPlugin();
}

sub setMode {
	my ( $class, $client, $method ) = @_;

	if ($method eq 'pop') {

		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.Choice to display the list of feeds
	my $name = $class->getDisplayName();
	
	my %params = (
		header   => $name,
		modeName => $name,
		url      => $class->feed(),
		title    => $client->string( $name ),
		timeout  => 35,
	);

	Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );

	# we'll handle the push in a callback
	$client->modeParam( handledTransition => 1 );
}

sub cliRadiosQuery {
	my ( $class, $tag ) = @_;
	
	return sub {
		my $request = shift;

		my $menu = $request->getParam('menu');

		my $data;
		# what we want the query to report about ourself
		if (defined $menu) {
			$data = {
				text => Slim::Utils::Strings::string(getDisplayName()),  # nice name
				actions => {
					go => {
						cmd => [ $tag, 'items' ],
						params => {
							menu => $tag,
						},
					},
				},
			};
		}
		else {
			$data = {
				cmd  => $tag,
				name => Slim::Utils::Strings::string( $class->getDisplayName() ),
				type => 'xmlbrowser',
			};
		}
	
		# let our super duper function do all the hard work
		Slim::Control::Queries::dynamicAutoQuery( $request, 'radios', $cli_next{$class}, $data );
	};
}

sub webPages {
	my $class = shift;

	my $title = $class->getDisplayName();
	my $url   = 'plugins/' . $class->tag() . '/index.html';
	
	Slim::Web::Pages->addPageLinks( $class->menu(), { $title => $url });

	Slim::Web::HTTP::addPageFunction( $url, sub {
		Slim::Web::XMLBrowser->handleWebIndex( {
			feed   => $class->feed(),
			title  => $title,
			args   => \@_
		} );
	} );
}

1;