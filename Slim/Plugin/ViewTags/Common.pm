package Slim::Plugin::ViewTags::Common;

# Logitech Media Server Copyright 2005-2022 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Storable;

use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

my $prefs = preferences('plugin.viewtags');

my %tags = (
	WCOM => {
		name => string('PLUGIN_VIEW_TAGS_WCOM'),
		url => 1,
	},
	WCOP => {
		name => string('PLUGIN_VIEW_TAGS_WCOP'),
		url => 1,
		alt => ['LICENSE'],
	},
	WOAF => {
		name => string('PLUGIN_VIEW_TAGS_WOAF'),
		url => 1,
	},
	WOAR => {
		name => string('PLUGIN_VIEW_TAGS_WOAR'),
		url => 1,
		alt => ['WEBSITE', 'WEBLINK'],
	},
	WOAS => {
		name => string('PLUGIN_VIEW_TAGS_WOAS'),
		url => 1,
	},
	WORS => {
		name => string('PLUGIN_VIEW_TAGS_WORS'),
		url => 1,
	},
	WPUB => {
		name => string('PLUGIN_VIEW_TAGS_WPUB'),
		url => 1,
	},
);

my @defaultTagNames = keys %tags;

# expand list for alternative tags
foreach my $tag (keys %tags) {
	foreach (delete $tags{$tag}->{alt} || []) {
		$tags{$_} = $tags{$tag};
		$tags{$_}->{dupe} = 1;
	}
}

sub getDefaultTags {
	return \%tags;
}

sub getDefaultTagNames {
	return Storable::dclone(\@defaultTagNames);
}

sub getActiveTags {
	my @activeTags = keys %{$prefs->get('customTags') || {}};

	foreach (keys %tags) {
		push @activeTags, $_ if $prefs->get($_);
	}

	return \@activeTags;
}

sub getDetailsForTag {
	my ($tag) = @_;

	my $customTags = $prefs->get('customTags');
	return $customTags->{$tag} || ($prefs->get($tag) && $tags{uc($tag)});
}

1;