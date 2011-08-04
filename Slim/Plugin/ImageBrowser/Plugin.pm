package Slim::Plugin::ImageBrowser::Plugin;

# $Id:  $

use strict;
use base qw(Slim::Plugin::OPMLBased);
use XML::Simple;
use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(string);
use Slim::Plugin::UPnP::Common::Utils qw(absURL);

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.imagebrowser',
	defaultLevel => 'WARN',
	description  => 'PLUGIN_IMAGEBROWSER_MODULE_NAME',
} );

use constant CONTENTURL => 'plugins/imagegallery/content.json';
use constant PLUGIN_TAG => 'imagebrowser';

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(
		feed   => absURL( '/' . CONTENTURL ),
		tag    => PLUGIN_TAG,
		node   => 'extras',		# used for SP
		menu   => 'plugins',	# used in web UI
	);
	
	Slim::Control::Request::addDispatch(
		[ PLUGIN_TAG, 'slideshow' ],
		[ 0, 1, 1, \&cliSlideshowQuery ]
	);
	
	
	Slim::Web::Pages->addPageFunction( CONTENTURL, \&renderOPML );
}

# we depend on Slim::Plugin::UPnP::Plugin
# can probably be removed if we move SOAP::Lite to the main CPAN folder 
my $enabled;
sub condition {
	
	return $enabled if defined $enabled;
	
	eval {
		require Slim::Plugin::UPnP::Plugin;
		require Slim::Plugin::UPnP::MediaServer::ContentDirectory;
		$enabled = 1;
	};

	if ($@) {
		$enabled = 0;
		main::DEBUGLOG && $log->is_debug && $log->debug($@);
		$log->warn("The ImageBrowser plugin requires the UPnP plugin to be enabled");
		return 0;
	}	

	return 1;
}

# Don't add this item to any menu
sub playerMenu { }


# fetch content from UPnP handler, and convert into OPML as understood by XMLBrowser
sub renderOPML {
	my ($client, $params) = @_;
	
	my ($data, $count, $total) = Slim::Plugin::UPnP::MediaServer::ContentDirectory->Browse(undef, {
		BrowseFlag     => 'BrowseDirectChildren',
		Filter         => '*',
		ObjectID       => $params->{id} || '/images',
		RequestedCount => 999999,		# get them all, XMLBrowser does the paging... a good idea?
		SortCriteria   => $params->{sort} || '+dc:title',
		StartingIndex  => $params->{start} || 0,
	});	
	
	$data = $data->name('Result')->value();
	
	my $xml = eval { XMLin($data) };

	if ( $@ ) {
		$log->error( "Unable to parse: " . $@ );
		$xml = {};
	}
	
	my $items = [];

	foreach my $itemLoop ($xml->{container}, $xml->{item}) {
	
		# normalize hash?!?
		if ($itemLoop->{id} && $itemLoop->{'upnp:class'}) {
			$itemLoop = {
				$itemLoop->{id} => $itemLoop,
			};
		}
	
		while ( my ($id, $item) = each( %$itemLoop ) ) {
			if ( $item->{'upnp:class'} =~ /^object.container/ ) {
				push @$items, {
					type => 'link',
					text => $item->{'dc:title'},
					url  => absURL( '/' . CONTENTURL ) . "?id=$id",
				}
			}
			
			elsif ( $item->{'upnp:class'} eq 'object.item.imageItem.photo' ) {
				my ($id) = $item->{'upnp:icon'} =~ m{(?:music|image)/([0-9a-f]{8})/};
				
				push @$items, {
					type => 'link',
					text => $item->{'dc:title'},
					owner => $item->{'upnp:album'},
					date => $item->{'dc:date'},
					weblink => $item->{res}->{content},
					image => $item->{'upnp:icon'},
					jive => $id ? {
						actions => {
							go => {
								player => 0,
								cmd => [ PLUGIN_TAG, 'slideshow' ],
								params => {
									id => $id,
									slideshow => 1,
								}
							},
						}
					} : undef
				};
			}
			
			else {
				# what here?
				$log->error('unhandled upnp:class? ' . Data::Dump::dump($item));
			}
		}
		
	}
	
	push @$items, {
		type => 'text',
		text => Slim::Utils::Strings::clientString($client, 'EMPTY'),
	} if not scalar @$items;
	
	main::DEBUGLOG && $log->is_debug && $log->debug( Data::Dump::dump($items) );
	
	# create OPML
	$data = eval { to_json({
		body => {
			outline => $items,
		},
		head => {
			title => Slim::Utils::Strings::clientString($client, 'PLUGIN_IMAGEBROWSER_MODULE_NAME'),
			cachetime => 0,		# don't cache result
		},
	}) };

	return \$data;
}


# return a slideshow type json structure
# XXX - currently only for single images, might be extended to show real slideshows
sub cliSlideshowQuery {
	my $request = shift;

	if ($request->isNotQuery([[PLUGIN_TAG]])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	$request->setStatusProcessing();
	
	my $id = $request->getParam('id');
	
	my $sub = Slim::Control::Request->new( undef, [ 'image_titles', 0, 1, 'image_id:' . $id, 'tags:tnl' ] );
	$sub->execute();
	
	my $results = $sub->getResults;
	my $imageInfo = $results->{images_loop}->[0];
	
	$request->addResult( data => [{
		image => "image/$id/cover{resizeParams}",
		name  => $imageInfo->{title},
		date  => $imageInfo->{date} || '',
		owner => $imageInfo->{album} || '',
	}] );
	$request->addResult( offset => 0 );
	$request->setStatusDone();
}

1;