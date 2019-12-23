package Slim::Menu::OnlineLibraries;

use strict;

my %libraryHandlers;

sub registerHandler {
	my ($class, $regex, $handlerToRegister) = @_;

	$libraryHandlers{$regex} = $handlerToRegister;
}

sub itemHandlerForId {
	my ($class, $id) = @_;

	return undef unless $id;
	
	my $handler;
	foreach (keys %libraryHandlers) {
		if ($id =~ $_) {
			$handler = $libraryHandlers{$_};
			last;
		}
	}

	return $handler;
}


1;