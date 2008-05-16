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


package Slim::Plugin::ABTester::TestcaseZipParser;

use strict;

use base qw(Slim::Plugin::ABTester::ZipParser);

sub execute {
	my $class = shift;
	my $client = shift;
	my $cacheDir = shift;
	my $filename = shift;

	Slim::Plugin::ABTester::Plugin::refreshTestdata($client);
	my $testcase = $filename;
	my $extensionRegexp = "\\.zip\$";
	$testcase =~ s/$extensionRegexp//;
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time(),\&Slim::Plugin::ABTester::Plugin::runTestcase,$testcase);
}

sub getExtractDir() {
	return "Testcases";
}
1;

__END__

