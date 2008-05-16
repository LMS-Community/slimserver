#    Copyright (C) 2008 Erland Isaksson (erland_i@hotmail.com)
#    
#    This library is free software; you can redistribute it and/or
#    modify it under the terms of the GNU Lesser General Public
#    License as published by the Free Software Foundation; either
#    version 2.1 of the License, or (at your option) any later version.
#    
#    This library is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#    Lesser General Public License for more details.
#    
#    You should have received a copy of the GNU Lesser General Public
#    License along with this library; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA


package Slim::Plugin::ABTester::ImageZipParser;

use strict;

use base qw(Slim::Plugin::ABTester::ZipParser);

use File::Spec::Functions qw(:ALL);
use File::Path;

sub execute {
	my $class = shift;
	my $client = shift;
	my $cacheDir = shift;
	my $filename = shift;

	my $testcase = $filename;
	my $extensionRegexp = "\\.zip\$";
	$testcase =~ s/$extensionRegexp//;

	my $dir = catdir($cacheDir,$testcase);
	my @dircontents = Slim::Utils::Misc::readDirectory($dir,"i2c");

	# Iterate through all files in the specified directory
	for my $item (@dircontents) {
		next if -d catdir($dir, $item);

		Slim::Utils::Timers::setTimer($client, Time::HiRes::time(),\&loadImage,catdir($dir, $item));
		return;
	}
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time(),\&Slim::Buttons::Common::popMode);
}

sub loadImage {
	my $client = shift;
	my $file = shift;

	Slim::Plugin::ABTester::Plugin::loadImage($client,$file);
	Slim::Buttons::Common::popMode($client);
}

sub getExtractDir() {
	return "Images";
}

1;

__END__

