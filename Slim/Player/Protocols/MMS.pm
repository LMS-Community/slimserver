package Slim::Player::Protocols::MMS;
		  
# $Id$

# SlimServer Copyright (c) 2001-2004 Vidur Apparao, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.  

use strict;

use File::Spec::Functions qw(:ALL);
use IO::Socket qw(:DEFAULT :crlf);

use Slim::Player::Pipeline;

use base qw(Slim::Player::Pipeline);

use Slim::Display::Display;
use Slim::Utils::Misc;

sub new {
	my $class = shift;
	my $args  = shift;

	my $url    = $args->{'url'};
	my $client = $args->{'client'};

	# Set the content type to 'wma' to get the convert command
	Slim::Music::Info::setContentType($url, 'wma');

	my ($command, $type, $format) = Slim::Player::Source::getConvertCommand($client, $url);

	unless (defined($command) && $command ne '-') {
		$::d_remotestream && msg "Couldn't find conversion command for wma\n";
		Slim::Player::Source::errorOpening($client,Slim::Utils::Strings::string('WMA_NO_CONVERT_CMD'));
		return undef;
	}

	Slim::Music::Info::setContentType($url, $format);

	my $maxRate = defined($client) ? Slim::Utils::Prefs::maxRate($client) : 0;
	my $quality = Slim::Utils::Prefs::clientGet($client,'lameQuality');

	$command = Slim::Player::Source::tokenizeConvertCommand($command, $type, $url, $url, 0, $maxRate, 1, $quality);

	return $class->SUPER::new(undef, $command);
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
