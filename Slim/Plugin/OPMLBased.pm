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
		*{$class.'::'.'feed'} = sub { $args{feed} } if $args{feed};
		*{$class.'::'.'tag'}  = sub { $args{tag} };
		*{$class.'::'.'menu'} = sub { $args{menu} };
	}

	if (!$class->_pluginDataFor('icon')) {

		Slim::Web::Pages->addPageLinks("icons", { $class->getDisplayName => 'html/images/radio.png' });
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
	
	my $cli_menu = $args{menu} eq 'music_services' ? 'music_services' : 'radios';	
		
	$cli_next{$class} = Slim::Control::Request::addDispatch(
		[ $cli_menu, '_index', '_quantity' ],
		[ 0, 1, 1, $class->cliRadiosQuery( \%args, $cli_menu ) ]
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
		url      => $class->feed( $client ),
		title    => $client->string( $name ),
		timeout  => 35,
	);

	Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );

	# we'll handle the push in a callback
	$client->modeParam( handledTransition => 1 );
}

sub cliRadiosQuery {
	my ( $class, $args, $cli_menu ) = @_;
	my $tag  = $args->{tag};

	my $icon = $class->_pluginDataFor('icon') ? $class->_pluginDataFor('icon') : 'html/images/radio.png';

	return sub {
		my $request = shift;

		my $menu = $request->getParam('menu');

		my $data;
		# what we want the query to report about ourself
		if (defined $menu) {
			$data = {
				text         => Slim::Utils::Strings::string( $class->getDisplayName() ),  # nice name
				'icon-id'    => $icon,
				actions      => {
						go => {
							cmd => [ $tag, 'items' ],
							params => {
								menu => $tag,
							},
						},
				},
				window        => {
							titleStyle => 'album',
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
		Slim::Control::Queries::dynamicAutoQuery( $request, $cli_menu, $cli_next{$class}, $data );
	};
}

sub webPages {
	my $class = shift;

	my $title = $class->getDisplayName();
	my $url   = 'plugins/' . $class->tag() . '/index.html';
	
	Slim::Web::Pages->addPageLinks( $class->menu(), { $title => $url });

	Slim::Web::HTTP::addPageFunction( $url, sub {
		Slim::Web::XMLBrowser->handleWebIndex( {
			feed    => $class->feed(),
			title   => $title,
			timeout => 35,
			args    => \@_
		} );
	} );
}

1;
