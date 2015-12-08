package Slim::Plugin::RemoteLibrary::Plugin;

use strict;

use Slim::Plugin::RemoteLibrary::ProtocolHandler;

my $log = Slim::Utils::Log->addLogCategory( {
	'category'     => 'plugin.remotelibrary',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_REMOTE_LIBRARY_MODULE_NAME',
} );


sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		lms => 'Slim::Plugin::RemoteLibrary::ProtocolHandler'
	);

	Slim::Web::ImageProxy->registerHandler(
		match => qr/^http:lms/,
		func  => \&_artworkProxy,
	);
}

sub getDisplayName () {
	return 'PLUGIN_REMOTE_LIBRARY_MODULE_NAME';
}

# Custom proxy to let the remote server handle the resizing.
# The remote server very likely already has pre-cached artwork.
sub _artworkProxy {
	my ($url, $spec) = @_;
	
	$url =~ s/http:lms/http/;
	$url .= '_' . $spec if $spec;
	
	return $url;
}

1;
