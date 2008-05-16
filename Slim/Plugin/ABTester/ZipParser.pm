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


package Slim::Plugin::ABTester::ZipParser;

use strict;

use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use Slim::Utils::Log;
use Data::Dumper;
use File::Spec::Functions qw(:ALL);

my $prefs = preferences('plugin.abtester');
my $serverPrefs = preferences('server');

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.abtester',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_ABTESTER',
});

sub parse {
	my $class        = shift;
	my $http         = shift;
	my $url   = shift;

	my $params = $http->params('params');
	my $url    = $params->{'url'};
	my $filename = $url;

	if(defined($filename) && $filename =~ /^.*\/([^\/]+\.zip)$/) {
		$filename = $1;
	}else {
		$filename = undef;
	}
	if(exists $params->{'item'}->{'filename'}) {
		$filename = $params->{'item'}->{'filename'};
	}

	if(defined($filename)) {
		my $cacheDir = $serverPrefs->get('cachedir');
		my $downloadDir = catdir($cacheDir,'ABTester','Downloaded');
		$cacheDir = catdir($cacheDir,'ABTester');
		mkdir($downloadDir) unless -d $downloadDir;
		$downloadDir = catdir($downloadDir,$class->getExtractDir());
		mkdir($downloadDir) unless -d $downloadDir;
		$cacheDir = catdir($cacheDir,$class->getExtractDir());
		my $file = catfile($downloadDir,$filename);
		my $fh;
                open($fh,"> $file") or do {
                    $log->error("Failed to write downloaded file");
                };
                print $fh $http->content;
                close $fh;
		Slim::Plugin::ABTester::Plugin::extractZipFile($downloadDir,$filename,$cacheDir);
		$class->execute($params->{'client'},$cacheDir,$filename);

		return {
			nocache => 1,
			title => "Downloaded $filename",
		};
	}else {
		my $feed = Slim::Formats::XML::parseXMLIntoFeed($http->contentRef);
		$feed->{'nocache'} = 1;
		$class->addParser($feed);
		return $feed;
	}
}

sub addParser {
	my $class = shift;
	my $feed = shift;

	if(exists $feed->{'items'}) {
		foreach my $item (@{$feed->{'items'}}) {
			$item->{'parser'} = $class;
			$class->addParser($item);
		}
	}
}

1;

__END__

