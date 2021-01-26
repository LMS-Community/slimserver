package Slim::Networking::SqueezeNetwork::Base;

# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Utils::Accessor);

use URI::Escape qw(uri_escape);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

if ( main::NOMYSB ) {
	logBacktrace("Support for mysqueezebox.com has been disabled. Please update your code: don't call me if main::NOMYSB.");
}

# This is a hashref of mysqueezebox.com server types
#   and names.

my $_Servers = {
	sn      => 'www.mysqueezebox.com',
	update  => 'update.mysqueezebox.com',
};

sub get_server {
	my ($class, $stype) = @_;

	if ( $stype eq 'sn' && $ENV{MYSB_TEST} ) {
		return $ENV{MYSB_TEST};
	}

	return $_Servers->{$stype}
		|| die "No hostname known for server type '$stype'";
}

# Return a correct URL for mysqueezebox.com
sub _url {
	my ( $class, $path, $external ) = @_;

	if (main::NOMYSB) {
		logBacktrace("Support for mysqueezebox.com has been disabled. Please update your code: don't call me if main::NOMYSB.");
	}

	my $base = ($class->hasSSL() && !$ENV{MYSB_TEST} ? 'https://' : 'http://') . $class->get_server('sn');

	$path ||= '';

	$base = '' if $path =~ /^http/;

	return $base . $path;
}

sub getCookie {
	my ( $self, $client ) = @_;

	# Add session cookie if we have it
	if ( my $sid = $prefs->get('sn_session') ) {
		return 'sdi_squeezenetwork_session=' . uri_escape($sid);
	}

	return;
}

1;