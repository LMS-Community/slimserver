package Slim::Web::Settings::Server::Index;

# $Id: UserInterface.pm 13299 2007-09-27 08:59:36Z mherger $

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

sub page {
	return Slim::Web::HTTP::protectURI('settings/index.html');
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	$paramRef->{additionalLinks} = \%Slim::Web::Pages::additionalLinks;

	my @sortedLinks = 
		map { $_->[1] }
		sort { $a->[0] cmp $b->[0] }
		map { [ uc( Slim::Utils::Strings::string($_) ), $_ ] } 
		keys %{$paramRef->{additionalLinks}->{setup}};

	$paramRef->{sortedLinks} = \@sortedLinks;

	$paramRef->{iTunesEnabled}  = Slim::Utils::PluginManager->isEnabled('Slim::Plugin::iTunes::Plugin');
	$paramRef->{podcastEnabled} = Slim::Utils::PluginManager->isEnabled('Slim::Plugin::Podcast::Plugin');

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
