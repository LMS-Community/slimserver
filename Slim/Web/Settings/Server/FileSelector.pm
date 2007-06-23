package Slim::Web::Settings::Server::FileSelector;

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use File::Basename qw(dirname);

BEGIN {
        if ($^O =~ /Win32/) {
                require Win32::File;
                require Win32::DriveInfo;
        }
}

my $log = logger('fileselector');

sub page {
	return 'settings/server/fileselector.html';
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	my @subdirs;
	
	my $currDir = $paramRef->{'currDir'};
	
	if (Slim::Utils::OSDetect::OS() eq 'win') {
		$currDir = undef if ($currDir =~ /^\\+$/);
		#$currDir =~ s/\\/\//g;
	}

	# a correct folder	
	if (-d $currDir) {
		$log->debug('regular folder: ' . $currDir);
		my $dir = Path::Class::Dir->new($currDir);
		@subdirs = map { $_->stringify() } $dir->children();
	}

	# something else...
	elsif ($currDir) {
		$log->debug('unknown: ' . $currDir);

		# partial file/foldernames - filter the list of the parent folder
		my $parent;
		if ($currDir =~ /^(\\\\\w.*)\\.+/ && Slim::Utils::OSDetect::OS() eq 'win') {
			$parent = $1;
		}
		else {
			$parent = eval { dirname($currDir) };
		}

		if ($parent && $parent ne '.' && -d $parent) {
			$currDir =~ s/\\/\\\\/g;
			my $dir  = Path::Class::Dir->new($parent);
			@subdirs = grep { /$currDir/i } $dir->children();
		}
	}

	# didn't find anything useful - display a list of reasonable choices (root, drive letters)
	if (Slim::Utils::OSDetect::OS() eq 'win' && !@subdirs) {
		@subdirs = map { "$_:" } Win32::DriveInfo::DrivesInUse();
	}
	elsif (!@subdirs) {
		my $dir  = Path::Class::Dir->new('/');
		@subdirs = map { $_->stringify() } $dir->children();
	}

	if ($paramRef->{'foldersonly'}) {
		@subdirs = grep { -d } @subdirs;
	}
	
	$paramRef->{'folders'} = \@subdirs;

	return Slim::Web::HTTP::filltemplatefile($class->page, $paramRef);
}

1;

__END__
