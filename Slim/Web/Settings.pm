package Slim::Web::Settings;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
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

my $log = logger('prefs');

my (@playerSettingsClasses, @topLevelItems, %topLevelItems);

=head1 METHODS

=head2 new( )

Register a new settings subclass.  Add the new page handler references to the server settings, and creates a list of registered
player setting pages for player settings.

=cut

sub new {
	my $class = shift;

	if ($class->can('page') && $class->can('handler') && $class->page) {

		Slim::Web::Pages->addPageFunction($class->page, $class);
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

=head2 beforeRender( )

A sub called before the page is rendered, but after the prefs have been processed/saved

=cut
sub beforeRender {}


=head2 handler( )

Basic handler for setting page template, records changed prefs and presents current prefs to the user.
Complex handling and processing of specialised prefs should be done in the subclass handler.

=cut
sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	# some settings change required a rescan, and user did confirm it
	if (Slim::Utils::Prefs::preferences('server')->get('dontTriggerScanOnPrefChange') && Slim::Music::Import->hasScanTask && $paramRef->{'doRescanNow'}) {
		Slim::Music::Import->nextScanTask();
	}

	# don't display player preference pane if it doesn't exist for the player (eg. Display for an SBR)
	# redirect to basic settings instead
	if (defined $client && !$class->validFor($client)) {
		return Slim::Web::Settings::Player::Basic->handler($client, $paramRef, $pageSetup);
	}

	# Handle the simple case where validation is done by prefs obj.
	my ($prefsClass, @prefs) = $class->prefs($client);

	my (@valid);

	for my $pref (@prefs) {

		if ($paramRef->{'saveSettings'}) {
			if (!defined $paramRef->{'pref_' . $pref} && defined $paramRef->{$pref}) {
				$log->error('Preference names must be prefixed by "pref_" in the page template: ' . $pref . ' (' . $class->name . ')');
				$paramRef->{'pref_' . $pref} = $paramRef->{$pref};
			}

			my (undef, $ok) = $prefsClass->set($pref, $paramRef->{'pref_' . $pref});

			if ($ok) {
				$paramRef->{'validated'}->{$pref} = 1; 
			}
			else {
				$paramRef->{'warning'} .= sprintf(Slim::Utils::Strings::string('SETTINGS_INVALIDVALUE'), $paramRef->{'pref_' . $pref}, $pref) . '<br/>';
				$paramRef->{'validated'}->{$pref} = 0;
			}
		}

		$paramRef->{'validate'}->{$pref} = $prefsClass->hasValidator($pref);
		$paramRef->{'prefs'}->{'pref_' . $pref} = $prefsClass->get($pref);
	
		# XXX store prefs in legacy style, too - to be removed once we can give up on 7.0 backwards compatibility for plugins
		$paramRef->{'prefs'}->{$pref} = $prefsClass->get($pref);

		if (defined $client && $pref eq 'playername') {
			$client->execute(['name', $paramRef->{'prefs'}->{'pref_' . $pref}]);
		}
	}

	if ($prefsClass) {
		$paramRef->{'namespace'} = $prefsClass->namespace;
	}
	
	# ask the user to run a scan
	if (Slim::Utils::Prefs::preferences('server')->get('dontTriggerScanOnPrefChange') && Slim::Music::Import->hasScanTask && !$paramRef->{'warning'} && !Slim::Music::Import->stillScanning()) {
		$paramRef->{'rescanUrl'} = $paramRef->{webroot} . $paramRef->{path} . '?doRescanNow=1';
		$paramRef->{'rescanUrl'} .= '&rand=' . $paramRef->{'rand'} if $paramRef->{'rand'};

		$paramRef->{'warning'} = '<span id="rescanWarning">'
			. Slim::Utils::Strings::string('SETUP_SCAN_ON_PREF_CHANGE_PROMPT', $paramRef->{'rescanUrl'})
			. '</span>';
	}

	if ($paramRef->{'saveSettings'} && !$paramRef->{'warning'}) {
		$paramRef->{'warning'} = Slim::Utils::Strings::string('SETUP_CHANGES_SAVED');
	}	

	# Common values
	$paramRef->{'page'} = $class->name;
	
	# Needed to generate the drop down settings chooser list.
	$paramRef->{'additionalLinks'} = \%Slim::Web::Pages::additionalLinks;

	# the items we want to have in the top level of
	# new skin's settings window
	if (! scalar(@topLevelItems)) {
		@topLevelItems = map {
			$topLevelItems{$_} = 1;
			[ $_, $paramRef->{'additionalLinks'}->{'setup'}->{$_} ];
		}
		grep { 
			if (/ITUNES/) { Slim::Utils::PluginManager->isEnabled('Slim::Plugin::iTunes::Plugin') }
			elsif (/PLUGIN_PODCAST/) { Slim::Utils::PluginManager->isEnabled('Slim::Plugin::Podcast::Plugin') }
			elsif (/SQUEEZENETWORK_SETTINGS/) { !main::NOMYSB }
			else { 1 }
		}
		(
			'BASIC_SERVER_SETTINGS',
			'BASIC_PLAYER_SETTINGS',
			'BEHAVIOR_SETTINGS',
			'SQUEEZENETWORK_SETTINGS',
			'ITUNES',
			'INTERFACE_SETTINGS',
			'SETUP_PLUGINS',
			'PLUGIN_PODCAST',
			'ADVANCED_SETTINGS',
			'SERVER_STATUS'
		);
	}

	$paramRef->{'topLevelItems'} = \@topLevelItems;

	# builds playersetup hash
	if (defined $client) {

		my %playerSetupLinks;
		
		for my $settingclass (@playerSettingsClasses) {

			if ($settingclass->validFor($client)) {

				$playerSetupLinks{$settingclass->name} = $settingclass->page . '?';
			}
		}

		$paramRef->{'playerid'}    = $client->id;
		$paramRef->{'playersetup'} = \%playerSetupLinks;
		$paramRef->{'playername'}  = $client->name();
		$paramRef->{'needsClient'} = $class->needsClient();
		$paramRef->{'hasdisplay'}  = !$client->display->isa('Slim::Display::NoDisplay');
	}

	if ($class->needsClient()) {

		my $basic = 'BASIC_PLAYER_SETTINGS';

		my @orderedLinks = 
			map { $_->[1] }
			sort { $a->[0] cmp $b->[0] }
			map { [ uc( Slim::Utils::Strings::string($_) ), $_ ] }
			grep { $_ !~ /$basic/ } 
			keys %{$paramRef->{'playersetup'}};
	
		unshift @orderedLinks, $basic if $paramRef->{'playersetup'}->{$basic};
	
		$paramRef->{'orderedLinks'} = \@orderedLinks;
	}

	else {

		# the new skins want to have a list of advanced settings
		# which does not include the top-level items
		my @orderedLinks = map { $_->[1] }
			sort { $a->[0] cmp $b->[0] }
			map { [ uc( Slim::Utils::Strings::string($_) ), $_ ] }
			grep { !$topLevelItems{$_} }
			keys %{$paramRef->{'additionalLinks'}->{'setup'}};

		$paramRef->{'orderedLinks'} = \@orderedLinks;
	}
	
	$class->beforeRender($paramRef, $client);

	return Slim::Web::HTTP::filltemplatefile($paramRef->{'useAJAX'} ? 'settings/ajaxSettings.txt' : $class->page, $paramRef);
}

1;

__END__
