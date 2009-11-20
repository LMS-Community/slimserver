#!/usr/bin/perl

# Watch for mount/unmount of media devices and trigger rescans.
# This is a temporary measure until in-process rescanning is in place.

BEGIN {
	unshift @INC, qw(
		/usr/squeezecenter/lib
		/usr/squeezecenter/CPAN
	);
}

use common::sense;
use Linux::Inotify2;

sub DEBUG () { 0 }

my $running = sbsRunning();
my $active_dir;

DEBUG && warn "inotify: watching /media (running=$running)\n";

my $i = Linux::Inotify2->new or die "$!";

$i->watch( '/media', IN_CREATE | IN_DELETE, sub {
	my $e = shift;
	
	my $dir = $e->fullname;
	
	DEBUG && warn "event: $dir, running=$running, active_dir=$active_dir\n";
	
	if ( $e->IN_CREATE && !$running ) {
		# media was mounted and server is not running
		while (1) {
			sleep 2;
			my $mounts = `/bin/mount | grep /media/`;
			chomp $mounts;
		
			DEBUG && warn "mounts: $mounts\n";
			
			# try again if filesystem isn't mounted yet
			next unless $mounts;
					
			for my $line ( split /\n/, $mounts ) {
				my ($path, $rw) = $line =~ /on ([^ ]+) type [^ ]+ \((\w{2})/;
				next if $rw ne 'rw';
				
				DEBUG && warn "New mount: $path, triggering rescan\n";
				$active_dir = $path;
				
				system("/etc/init.d/squeezecenter rescan");
				
				$running = 1;
				
				last;	
			}
			
			return;
		}
	}
	elsif ( $e->IN_DELETE && $running && $active_dir eq $dir ) {
		# media was unmounted and server is running
		DEBUG && warn "Unmount: $dir, stopping server\n";
		system("/etc/init.d/squeezecenter stop");
		
		$running = 0;
	}
} );

1 while $i->poll;

sub sbsRunning {
	if ( -e '/var/run/squeezecenter.pid' ) {
		open my $fh, '<', '/var/run/squeezecenter.pid' or die $!;
		my $pid = do { local $/; <$fh> };
		close $fh;
		chomp $pid;
		
		if ( -d "/proc/$pid" ) {
			return 1;
		}
	}
	
	return;
}

