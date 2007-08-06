package Slim::Web::Settings::Server::Wizard;

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Filesystem;

my $showProxy = 1;
my $prefs = preferences('server');

my %prefs = (
	'server' => ['language', 'weproxy', 'sn_email', 'sn_password', 'audiodir', 'playlistdir'],
	'plugin.itunes' => ['itunes', 'xml_path'],
	'plugin.musicmagic' => ['musicmagic', 'port']
);

sub new {
	my $class = shift;

	# try to connect to squeezenetwork.com to test for the need of proxy settings
	# just don't start the wizard before the request has been answered/failed
	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&checkSqnCB, \&checkSqnError);
	$http->get('http://www.squeezenetwork.com/');

	$class->SUPER::new($class);
}

sub page {
	return 'settings/server/wizard.html';
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	# don't display the language selection when run for the first time on Windows,
	# as this should have been set by the Windows installer
	if (Slim::Utils::OSDetect::OS() eq 'win' && not $prefs->get('wizarddone')) {
		$paramRef->{'showLanguage'} = 1;	
	}

	foreach my $namespace (keys %prefs) {
		foreach my $pref (@{$prefs{$namespace}}) {
			if ($paramRef->{'saveSettings'}) {	
				my (undef, $ok) = preferences($namespace)->set($pref, $paramRef->{$pref});
			}

			$paramRef->{'prefs'}->{$pref} = preferences($namespace)->get($pref);

			# Cleanup the checkbox
			if ($pref =~ /itunes|musicmagic/) {
				$paramRef->{'prefs'}->{$pref} = defined $paramRef->{'prefs'}->{$pref} ? 1 : 0;
			}
		}
	}

	# build the tree for the currently set music path
	# The tree control is expecting something like 
	# |/|/home|/home/myself|/home/myself/music
	my $prev = '';
	foreach (split /\//, $prefs->get('audiodir')) {
		if ($_) {
			$prev .= "/$_";
			$paramRef->{'audiodir_tree'} .= '|' . $prev;
		}
	}

	$paramRef->{'showiTunes'} = (preferences('plugin.itunes')->get('xml_file') || Slim::Plugin::iTunes::Common->canUseiTunesLibrary() == undef);
	$paramRef->{'showProxy'} = $showProxy;
	$paramRef->{'languageoptions'} = Slim::Utils::Strings::languageOptions();

	return Slim::Web::HTTP::filltemplatefile($class->page, $paramRef);
}

sub checkSqnCB {
	my $http = shift;

	# TODO: check for a proxy server's answer
#	if ($http->{code} =~ /^[24]\d\d/) {
		$showProxy = 0;
#	}
}

sub checkSqnError {
	my $http = shift;

	logger('wizard')->error("Couldn't connect to squeezenetwork.com - do we need a proxy?\n" . $http->error);
}

1;

__END__
