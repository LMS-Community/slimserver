package Slim::Schema::Storage;

# $Id$

# Squeezebox Server Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Shim to get a backtrace out of throw_exception

use strict;
use vars qw(@ISA);

use Slim::Utils::OSDetect;
my $sqlHelperClass;

BEGIN {
	$sqlHelperClass = Slim::Utils::OSDetect->getOS()->sqlHelperClass();
	
	my $storageClass = $sqlHelperClass->storageClass();
	eval "use $storageClass";
	die $@ if $@;
	
	push @ISA, $storageClass;
}

use Carp::Clan qw/DBIx::Class/;
use File::Slurp;
use File::Spec;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

sub dbh {
	my $self = shift;

	# Make sure we're connected unless we are already shutting down
	unless ( $main::stop ) {
		eval { $self->ensure_connected };
	}

	# Try and bring up the database if we can't connect.
	if ($@ && $@ =~ /Connection failed/) {

		my $lockFile = File::Spec->catdir(preferences('server')->get('librarycachedir'), 'mysql.startup');

		if (!-f $lockFile) {

			write_file($lockFile, 'starting');

			logWarning("Unable to connect to the database - trying to bring it up!");

			$@ = '';

			if ( $sqlHelperClass && $sqlHelperClass->init( $self->_dbh ) ) {

				eval { $self->ensure_connected };

				if ($@) {
					logError("Unable to connect to the database - even tried restarting it twice!");
					logError("Check the event log for errors on Windows. Fatal. Exiting.");
					exit;
				}
			}

			unlink($lockFile);
		}

	} elsif ($@) {

		return $self->throw_exception($@);
	}

	return $self->_dbh;
}

sub throw_exception {
	my ($self, $msg) = @_;

	logBacktrace($msg);

	# Need to propagate the real error so that DBIx::Class::Storage will
	# do the right thing and reconnect to the DB.
	croak($msg);
}

1;

__END__
