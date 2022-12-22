package Slim::Plugin::ViewTags::Settings;

# Logitech Media Server Copyright 2001-2022 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Plugin::ViewTags::Common;
use Slim::Utils::Prefs;

my $prefs = preferences('plugin.viewtags');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_VIEW_TAGS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/ViewTags/settings.html');
}

sub prefs {
	return ($prefs, , 'toplevel', @{Slim::Plugin::ViewTags::Common::getDefaultTagNames()});
}

sub handler {
	my $class = shift;
	my ($client, $params) = @_;

	if ($params->{'saveSettings'}) {
		my $customTags = {};
		foreach my $pref (keys %{$params}) {
			if ($pref =~ /(.*)_tag$/) {
				my $key = $1;
				my $tag = $params->{$pref};

				if ($tag) {
					$customTags->{$tag} = {
						name => $params->{$key . '_name'} || $tag,
						url => $params->{$key . '_url'} ? 1 : 0,
					};
				}
			}
		}

		$prefs->set('customTags', $customTags);
	}

	return $class->SUPER::handler(@_);
}

sub beforeRender {
	my ($class, $params) = @_;

	$params->{defaultTagOrder} = [ sort @{Slim::Plugin::ViewTags::Common::getDefaultTagNames()} ];
	$params->{customTags} = $prefs->get('customTags');
}

1;
