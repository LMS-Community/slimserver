package Slim::Player::Protocols::MMS;
		  
# $Id: MMS.pm,v 1.1 2004/10/11 19:17:18 vidur Exp $

# SlimServer Copyright (c) 2001-2004 Vidur Apparao, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.  

use strict;

use File::Spec::Functions qw(:ALL);
use FileHandle;
use IO::Socket qw(:DEFAULT :crlf);

use vars qw(@ISA);

@ISA = qw(FileHandle);

use Slim::Display::Display;
use Slim::Utils::Misc;

sub new {
	my $class = shift;
	my $url = shift;
	my $client = shift;

	my $self = $class->SUPER::new();
	
	# Set the content type to 'wma' to get the convert command
	Slim::Music::Info::setContentType($url, 'wma');
	my ($command, $type, $format) = Slim::Player::Source::getConvertCommand($client, $url);
	unless (defined($command) && $command ne '-') {
		$::d_remotestream && msg "Couldn't find conversion command for wma\n";
		return undef;
	}
	Slim::Music::Info::setContentType($url, 'wav');

	my $maxRate = Slim::Utils::Prefs::maxRate($client);
	$command = Slim::Player::Source::tokenizeConvertCommand($command,
															$type, 
															$url, $url,
															0 , $maxRate);

	unless ($self->open($command)) {
		$::d_remotestream && msg "Error launching conversion helper: $!\n";
		return undef;
	}

	return $self;
}


1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
