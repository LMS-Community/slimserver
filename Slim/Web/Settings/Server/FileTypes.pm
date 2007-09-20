package Slim::Web::Settings::Server::FileTypes;

# $Id$

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Player::TranscodingHelper;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

my $prefs = preferences('server');

sub name {
	return Slim::Web::HTTP::protectName('FORMATS_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::protectURI('settings/server/filetypes.html');
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	# If this is a settings update
	if ($paramRef->{'saveSettings'}) {

		$prefs->set('disabledextensionsaudio',    $paramRef->{'disabledextensionsaudio'});
		$prefs->set('disabledextensionsplaylist', $paramRef->{'disabledextensionsplaylist'});

		my %disabledformats = map { $_ => 1 } @{ $prefs->get('disabledformats') };

		my @disabled = ();

		my $formatslistref = Slim::Player::TranscodingHelper::Conversions();

		foreach my $profile (sort {$a cmp $b} (grep {$_ !~ /transcode/} (keys %{$formatslistref}))) {

			# If the conversion pref is enabled confirm that 
			# it's allowed to be checked.
			if ($paramRef->{$profile} ne 'DISABLED' && $disabledformats{$profile}) {

				if (!Slim::Player::TranscodingHelper::checkBin($profile)) {

					$paramRef->{'warning'} .= 
						string('SETUP_FORMATSLIST_MISSING_BINARY') . " $@ " . string('FOR') ." $profile<br>";

					push @disabled, $profile;
				}

			} elsif ($paramRef->{$profile} eq 'DISABLED') {

				push @disabled, $profile;
			}
		}

		$prefs->set('disabledformats', \@disabled);
	}

	my %disabledformats = map { $_ => 1 } @{ $prefs->get('disabledformats') };
	my $formatslistref  = Slim::Player::TranscodingHelper::Conversions();
	my @formats         = (); 

	for my $profile (sort { $a cmp $b } (grep { $_ !~ /transcode/ } (keys %{$formatslistref}))) {

		my @profileitems = split('-', $profile);
		my @binaries     = ('DISABLED');
		
		# TODO: expand this to handle multiple command lines, but use binary case for now
		my $enabled = Slim::Player::TranscodingHelper::checkBin($profile) ? 1 : 0;
		
		# build setup string from commandTable
		my $cmdline = $formatslistref->{$profile};
		my $binstring;

		$cmdline =~ 
			s{^\[(.*?)\](.*?\|?\[(.*?)\].*?)?}
			{
				$binstring = $1;
				$binstring .= "/".$3 if defined $3;
			}iegsx;

		if (defined $binstring && $binstring ne '-') {

			push @binaries, $binstring;

		} else {

			push @binaries, 'NATIVE';
		}

		push @formats, {
			'profile'  => $profile,
			'input'    => $profileitems[0],
			'output'   => $profileitems[1],
			'binaries' => \@binaries,
			'enabled'  => $enabled,
		};
	}
	
	$paramRef->{'formats'} = \@formats;

	$paramRef->{'disabledextensionsaudio'}  = $prefs->get('disabledextensionsaudio');
	$paramRef->{'disabledextensionsplaylist'} = $prefs->get('disabledextensionsplaylist');

	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}

1;

__END__
