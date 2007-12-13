package Slim::Schema::Storage;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Shim to get a backtrace out of throw_exception

use strict;
use base qw(DBIx::Class::Storage::DBI::mysql);

use Carp::Clan qw/DBIx::Class/;
use File::Slurp;
use File::Spec;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::MySQLHelper;
use Slim::Utils::Prefs;

sub dbh {
	my $self = shift;

	eval { $self->ensure_connected };

	# Try and bring up the database if we can't connect.
	if ($@ && $@ =~ /Connection failed/) {

		my $lockFile = File::Spec->catdir(preferences('server')->get('cachedir'), 'mysql.startup');

		if (!-f $lockFile) {

			write_file($lockFile, 'starting');

			logWarning("Unable to connect to the database - trying to bring it up!");

			$@ = '';

			if (Slim::Utils::MySQLHelper->init) {

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
