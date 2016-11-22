package Slim::Web::Settings::Server::FileTypes;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
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
	return Slim::Web::HTTP::CSRF->protectName('FORMATS_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/server/filetypes.html');
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	# If this is a settings update
	if ($paramRef->{'saveSettings'}) {

		$prefs->set('disabledextensionsaudio',    $paramRef->{'disabledextensionsaudio'});
		$prefs->set('disabledextensionsvideo',    $paramRef->{'disabledextensionsvideo'});
		$prefs->set('disabledextensionsimages',   $paramRef->{'disabledextensionsimages'});
		$prefs->set('disabledextensionsplaylist', $paramRef->{'disabledextensionsplaylist'});
		
		my %disabledformats = map { $_ => 1 } @{ $prefs->get('disabledformats') };

		my @disabled = ();

		my $formatslistref = Slim::Player::TranscodingHelper::Conversions();

		foreach my $profile (sort {$a cmp $b} (grep {$_ !~ /transcode/} (keys %{$formatslistref}))) {

			# If the conversion pref is enabled confirm that 
			# it's allowed to be checked.
			$paramRef->{$profile} ||= '';
			if ($paramRef->{$profile} ne 'DISABLED' && $disabledformats{$profile}) {

				if (!Slim::Player::TranscodingHelper::checkBin($profile,'IgnorePrefs')) {

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

		# skip internal formats which should not be shown or disabled 
		next if $profile =~ /^spdr|^test/;

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
				$binstring = $1 if $1 eq '-' || Slim::Utils::Misc::findbin($1);

				if ($binstring && defined $3) {
					if ($3 eq '-' || Slim::Utils::Misc::findbin($3)) {
						$binstring .= "/" . $3;
					}
					else {
						$binstring = undef;
					}
				}
				
				$binstring ||= '';
			}iegsx;

		if ($binstring && $binstring ne '-') {
			push @binaries, $binstring;

		} elsif ($cmdline eq '-' || $binstring eq '-') {

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
	$paramRef->{'disabledextensionsvideo'}  = $prefs->get('disabledextensionsvideo');
	$paramRef->{'disabledextensionsimages'} = $prefs->get('disabledextensionsimages');
	$paramRef->{'disabledextensionsplaylist'} = $prefs->get('disabledextensionsplaylist');

	$paramRef->{'noimage'} = 1 if !(main::IMAGE && main::MEDIASUPPORT);
	$paramRef->{'novideo'} = 1 if !(main::VIDEO && main::MEDIASUPPORT);

	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}

1;

__END__
