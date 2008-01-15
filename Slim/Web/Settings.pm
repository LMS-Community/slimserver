package Slim::Web::Settings;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# This is a base class for all the server settings pages.
=head1 NAME

Slim::Web::Settings

=head1 SYNOPSIS

	use base qw(Slim::Web::Settings);

=head1 DESCRIPTION

L<Slim::Web::Settings> is a base class for all the server/player settings pages.

=cut


use strict;

use Slim::Utils::Log;
use Slim::Web::HTTP;
use Slim::Web::Pages;

use Scalar::Util qw(blessed);

my @playerSettingsClasses;

# the items we want to have in the top level of
# new skin's settings window
my @topLevelItems = (
		'BASIC_SERVER_SETTINGS',
		'ITUNES',
		'PLUGIN_PODCAST',
		'SQUEEZENETWORK_SETTINGS',
		'INTERFACE_SETTINGS',
		'SETUP_PLUGINS',
		'SERVER_STATUS',
		'BEHAVIOR_SETTINGS'
	);


=head1 METHODS

=head2 new( )

Register a new settings subclass.  Add the new page handler references to the server settings, and creates a list of registered
player setting pages for player settings.

=cut

sub new {
	my $class = shift;

	if ($class->can('page') && $class->can('handler') && $class->page) {

		Slim::Web::HTTP::addPageFunction($class->page, $class);
	}

	if ($class->can('page') && $class->can('name') && $class->page && $class->name) {

		if ($class->needsClient) {

			push @playerSettingsClasses, $class;

		} else {

			Slim::Web::Pages->addPageLinks('setup', { $class->name => $class->page });
		}
	}
}

=head2 name( )

String Token for producing the setting page name.

=cut
sub name {
	my $class = shift;

	return '';
}

=head2 page( )

url for the setting page template.

=cut
sub page {
	my $class = shift;

	return '';
}

=head2 validFor( )

Used for player settings to validate against the current client

=cut
sub validFor {
	my $class = shift;
	
	return 1;
}

=head2 needsClient( )

Setting page requies a client. Used for player settings.

=cut
sub needsClient {
	my $class = shift;

	return 0;
}

=head2 prefs( )

array of prefs to be used on the template page.

=cut
sub prefs {
	return ();
}

=head2 handler( )

Basic handler for setting page template, records changed prefs and presents current prefs to the user.
Complex handling and processing of specialised prefs should be done in the subclass handler.

=cut
sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	# Handle the simple case where validation is done by prefs obj.
	my ($prefsClass, @prefs) = $class->prefs($client);

	my (@valid);

	for my $pref (@prefs) {

		if ($paramRef->{'saveSettings'}) {

			my (undef, $ok) = $prefsClass->set($pref, $paramRef->{$pref});

			if ($ok) {
				$paramRef->{'validated'}->{$pref} = 1; 
			}
			else { 
				$paramRef->{'warning'} .= sprintf(Slim::Utils::Strings::string('SETTINGS_INVALIDVALUE'), $paramRef->{$pref}, $pref) . '<br/>';
				$paramRef->{'validated'}->{$pref} = 0;
			}
		}

		$paramRef->{'validate'}->{$pref} = $prefsClass->hasValidator($pref);
		$paramRef->{'prefs'}->{$pref} = $prefsClass->get($pref);
		if (defined $client && $pref eq 'playername') {
			$client->execute(['name', $paramRef->{'prefs'}->{$pref}]);
		}
	}

	if ($prefsClass) {
		$paramRef->{'namespace'} = $prefsClass->namespace;
	}

	if ($paramRef->{'saveSettings'} && !$paramRef->{'warning'}) {
		$paramRef->{'warning'} = Slim::Utils::Strings::string('SETUP_CHANGES_SAVED');
	}	

	# Common values
	$paramRef->{'page'} = $class->name;
	
	# Needed to generate the drop down settings chooser list.
	$paramRef->{'additionalLinks'} = \%Slim::Web::Pages::additionalLinks;

	map { $paramRef->{'topLevelItems'}->{$_} = $paramRef->{'additionalLinks'}->{'setup'}->{$_} } @topLevelItems; 
	
	# builds playersetup hash
	if (defined $client) {

		my %playerSetupLinks;
		
		for my $settingclass (@playerSettingsClasses) {

			if ($settingclass->validFor($client)) {

				$playerSetupLinks{$settingclass->name} = $settingclass->page . '?';
			}
		}

		$paramRef->{'playersetup'} = \%playerSetupLinks;
		$paramRef->{'playername'}  = $client->name();
		$paramRef->{'needsClient'} = $class->needsClient();
		$paramRef->{'hasdisplay'}  = !$client->display->isa('Slim::Display::NoDisplay');
	}

	if ($class->needsClient()) {

		my @orderedLinks = 
			map { $_->[1] }
			sort { $a->[0] cmp $b->[0] }
			map { [ uc( Slim::Utils::Strings::string($_) ), $_ ] } 
			keys %{$paramRef->{'playersetup'}};
	
		$paramRef->{'orderedLinks'} = \@orderedLinks;
	}

	else {

		# the new skins want to have a list of advanced settings
		# which does not include the top-level items
		my @orderedLinks = map { $_->[1] }
			sort { $a->[0] cmp $b->[0] }
			map { [ uc( Slim::Utils::Strings::string($_) ), $_ ] }
			grep { !$paramRef->{'topLevelItems'}->{$_} }
			keys %{$paramRef->{'additionalLinks'}->{'setup'}};

		$paramRef->{'orderedLinks'} = \@orderedLinks;
	}

	return Slim::Web::HTTP::filltemplatefile($paramRef->{'useAJAX'} ? 'settings/ajaxSettings.txt' : $class->page, $paramRef);
}

1;

__END__
