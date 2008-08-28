package Slim::Utils::Win32;
use strict;

# SqueezeCenter Copyright 2001-2008 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Utils::Win32

=head1 DESCRIPTION

L<Slim::Utils::Win32> handles Windows specific details.

=cut

use Win32;
use Win32::TieRegistry;
use Win32API::File qw(:Func :DRIVE_);
use File::Path;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);

my $driveList  = {};
my $driveState = {};

=head2 getDrives()

Returns a list of drives available to SqueezeCenter, filtering out floppy drives etc.

=cut

sub getDrives {

	if (!defined $driveList->{ttl} || !$driveList->{drives} || $driveList->{ttl} < time) {
	
		my @drives = grep {
			s/\\//;
	
			my $driveType = GetDriveType($_);
			Slim::Utils::Log::logger('os.paths')->debug("Drive of type '$driveType' found: $_");
	
			# what USB drive is considered REMOVABLE, what's FIXED?
			# have an external HDD -> FIXED, USB stick -> REMOVABLE
			# would love to filter out REMOVABLEs, but I'm not sure it's save
			#($driveType != DRIVE_UNKNOWN && $driveType != DRIVE_REMOVABLE);
			($driveType != DRIVE_UNKNOWN && /[^AB]:/i);
		} getLogicalDrives();
		
		$driveList = {
			ttl    => time() + 60,
			drives => \@drives
		}
	}

	return @{ $driveList->{drives} };
}

=head2 isDriveReady()

Verifies whether a drive can be accessed or not

=cut

sub isDriveReady {
	my $drive = shift;

	# shortcut - we've already tested this drive	
	if (!defined $driveState->{$drive} || $driveState->{$drive}->{ttl} < time) {

		$driveState->{$drive} = {
			state => 0,
			ttl   => time() + 60	# cache state for a minute
		};

		# don't check inexisting drives
		if (scalar(grep /$drive/, getDrives()) && -r $drive) {
			$driveState->{$drive}->{state} = 1;
		}

		Slim::Utils::Log::logger('os.paths')->debug("Checking drive state for $drive");
		Slim::Utils::Log::logger('os.paths')->debug('      --> ' . ($driveState->{$drive}->{state} ? 'ok' : 'nok'));
	}
	
	return $driveState->{$drive}->{state};
}

=head2 writablePath()

Returns a path which is expected to be writable by all users on Windows without virtualisation on Vista.
This should mean that the server always sees consistent versions of files under this path.

TODO: this needs to be rewritten to use the proper API calls instead of poking around the registry and environment!

=cut

sub writablePath {
	my $folder = shift;
	my ($root, $path);

	# use the "Common Application Data" folder to store SqueezeCenter configuration etc.
	# c:\documents and settings\all users\application data - on Windows 2000/XP
	# c:\ProgramData - on Vista
	my $swKey = $Win32::TieRegistry::Registry->Open(
		'LMachine/Software/Microsoft/Windows/CurrentVersion/Explorer/Shell Folders/', 
		{ 
			Access => Win32::TieRegistry::KEY_READ(), 
			Delimiter =>'/' 
		}
	);

	if (defined $swKey && $swKey->{'Common AppData'}) {
		$root = catdir($swKey->{'Common AppData'}, 'SqueezeCenter');
	}
	elsif ($ENV{'ProgramData'}) {
		$root = catdir($ENV{'ProgramData'}, 'SqueezeCenter');
	}
	else {
		$root = $Bin;
	}

	$path = catdir($root, $folder);

	return $path if -d $path;

	if (! -d $root) {
		mkdir $root;
	}

	mkdir $path;

	return $path;
}

1;

__END__
