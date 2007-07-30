package Slim::Utils::Filesystem;

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Utils::Log;
use File::Basename qw(dirname);

my $log = logger('filesystem');

BEGIN {
        if ($^O =~ /Win32/) {
                require Win32::File;
                require Win32::DriveInfo;
        }
}


sub getChildren {
	my $currDir = shift;
	my $filter = shift;

	my @subdirs;

	if (Slim::Utils::OSDetect::OS() eq 'win') {
		$currDir = undef if ($currDir =~ /^\\+$/);
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

	if (ref $filter eq 'CODE') {
		@subdirs = grep { &$filter } @subdirs;
	}
	elsif ($filter) {
		@subdirs = grep /$filter/i, @subdirs;
	}
	
	return \@subdirs;
}
