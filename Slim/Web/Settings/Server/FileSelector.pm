package Slim::Web::Settings::Server::FileSelector;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Misc qw(readDirectory);
use File::Spec::Functions qw(:ALL);

BEGIN {
        if ($^O =~ /Win32/) {
        		require Slim::Utils::Win32;
        }
}

my $log = logger('os.files');

my $pages = {
	'autocomplete' => 'settings/server/fileselector_autocomplete.html',
};

sub page {
	return $pages->{'autocomplete'};
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	my @subdirs;
	my $currDir = $paramRef->{'currDir'};

	if (Slim::Utils::OSDetect::OS() eq 'win') {
		$currDir = undef if ($currDir =~ /^\\+$/);
	}

	# a correct folder	
	if (-d $currDir) {
		$log->debug('regular folder: ' . $currDir);
		@subdirs = _mapDirectories($currDir);
	}

	# something else...
	elsif ($currDir) {
		$log->debug('unknown folder: ' . $currDir);

		# partial file/foldernames - filter the list of the parent folder
		my ($parent, $file);
		if ($currDir =~ /^(\\\\\w.*)\\.+/ && Slim::Utils::OSDetect::OS() eq 'win') {
			$parent = $1;
		}
		else {
			(my $vol, $parent, $file) = eval { splitpath($currDir) };
			$parent = $vol . $parent;
			$log->debug("path elements: '$vol', '$parent', '$file'");
		}

		if ($parent && $parent ne '.' && -d $parent) {
			$log->debug("getting subfolders for: $parent");
			my $d = $currDir;
			$d =~ s/\\/\\\\/g;
			@subdirs = grep m|^$d|i, _mapDirectories($parent);
			$currDir = $parent;
		}

		# didn't find anything useful - display a list of reasonable choices (root, drive letters)
		if (Slim::Utils::OSDetect::OS() eq 'win' && !@subdirs) {
			$log->debug('getting Windows drive list');
			@subdirs = Slim::Utils::Win32::getDrives();
		}
		elsif (!@subdirs && !$parent) {
			@subdirs = _mapDirectories($currDir);
		}
	}

	@subdirs = grep { -d } @subdirs if ($paramRef->{'foldersonly'});

	$paramRef->{'folders'} = \@subdirs;

	return Slim::Web::HTTP::filltemplatefile($class->page, $paramRef);	
}

sub _mapDirectories {
	my $currDir = shift;
	return map { catdir($currDir, $_) } readDirectory($currDir, qr/./); 
}

1;

__END__
