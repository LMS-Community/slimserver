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
}

sub getDisplayName () {
	return 'PLUGIN_REMOTE_LIBRARY_MODULE_NAME';
}

sub handleError {
	my ( $error, $client ) = @_;
	
	main::DEBUGLOG && $log->debug("Error during request: $error");
}

1;
