package Slim::Web::Settings::Server::FileSelector;

# SlimServer Copyright (c) 2001-2007 Logitech.
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
                require Win32::File;
                require Win32::DriveInfo;
        }
}

my $log = logger('os.files');

my $pages = {
	'autocomplete' => 'settings/server/fileselector_autocomplete.html',
	'fileselector' => 'settings/server/fileselector.html'
};

sub new {
	my $class = shift;

	Slim::Web::HTTP::addPageFunction($pages->{'autocomplete'}, \&autoCompleteHandler);

	$class->SUPER::new($class);
}

sub page {
	return $pages->{'fileselector'};
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	$paramRef->{'audiodir'} = '';

	my $prev = '';
	foreach (split /\//, preferences('server')->get('audiodir')) {
		if ($_) {
			$prev .= "/$_";
			$paramRef->{'audiodir'} .= '|' . $prev;
		}
	}

	return Slim::Web::HTTP::filltemplatefile($class->page, $paramRef);
}

sub autoCompleteHandler {
	my ($client, $paramRef) = @_;

	my @subdirs;
	my $currDir = $paramRef->{'currDir'};

	if (Slim::Utils::OSDetect::OS() eq 'win') {
		$currDir = undef if ($currDir =~ /^\\+$/);
	}

	# a correct folder	
	if (-d $currDir) {
		$log->debug('regular folder: ' . $currDir);
		@subdirs = readDirectory($currDir, qr/./);
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
		}

		if ($parent && $parent ne '.' && -d $parent) {
			@subdirs = grep /^$file/i, readDirectory($parent, qr/./);
			$currDir = $parent;
		}

		# didn't find anything useful - display a list of reasonable choices (root, drive letters)
		if (Slim::Utils::OSDetect::OS() eq 'win' && !@subdirs) {
			@subdirs = map { "$_:" } grep /^[^AB]/i, Win32::DriveInfo::DrivesInUse();
		}
		elsif (!@subdirs && !$parent) {
			@subdirs = readDirectory('/', qr/./);
		}
	}

	@subdirs = map { catdir($currDir, $_) } @subdirs;
	@subdirs = grep { -d } @subdirs if ($paramRef->{'foldersonly'});

	$paramRef->{'folders'} = \@subdirs;

	return Slim::Web::HTTP::filltemplatefile($pages->{'autocomplete'}, $paramRef);	
}

1;

__END__
