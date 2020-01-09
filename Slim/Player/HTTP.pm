# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
package Slim::Player::HTTP;

use strict;
use vars qw(@ISA);
use Slim::Player::Client;

use Slim::Display::NoDisplay;

@ISA = qw(Slim::Player::Client);

sub new {
	my ($class, $id, $paddr, $tcpsock) = @_;
	
	my $client = $class->SUPER::new($id, $paddr);

	$client->streamingsocket($tcpsock);

	$client->display( Slim::Display::NoDisplay->new($client) );

	return $client;
}

sub init {
	my $client = shift;
	$client->SUPER::init(@_);
	push @{$client->modeParameterStack}, {};
	$client->startup();
}

sub bytesReceived {
	my $client = shift;
	return @_ ? $client->songBytes(shift) : $client->songBytes();
}

sub connected { 
	my $client = shift;

	return ($client->streamingsocket() && $client->streamingsocket->connected()) ? 1 : 0;
}

sub string {
	my $client = shift;
	Slim::Utils::Strings::string(@_)
};

# dummy methods
sub update      { }
sub isPlayer    { 0 }
sub stop        { Slim::Web::HTTP::clearOutputBuffer(shift); 1 }
sub play        { Slim::Web::HTTP::clearOutputBuffer(shift); 1 }
sub pause       { Slim::Web::HTTP::clearOutputBuffer(shift); 1 }
sub rebuffer    { 1 }
sub resume      { 1 }
sub volume      { 1 }
sub fade_volume { 1 }
sub bufferFullness { 0 }
sub formats     { 'mp3' }
sub model       { 'http' }
sub modelName   { 'Web Client' }
sub decoder     { 'http' }
sub vfd         { undef }
sub canPowerOff { 0 }

sub power {
	my $client = shift;
	my $toggle = shift;

	if ($toggle) {
		Slim::Web::HTTP::clearOutputBuffer($client);
	}

	return 1;
}

sub nextChunk {
	my $client = $_[0];
	
	my $chunk = Slim::Player::Source::nextChunk(@_);
	
	if (defined($chunk) && length($$chunk) == 0) {
		# EndOfStream
		$client->controller()->playerEndOfStream($client);
		
		$client->controller()->playerReadyToStream($client);

		$client->controller()->playerStopped($client);

		return undef;	
	}
	
	return $chunk;
}

sub isReadyToStream { 1 }


1;
