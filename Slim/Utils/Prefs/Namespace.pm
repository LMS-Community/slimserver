package Slim::Utils::Prefs::Namespace;

# $Id$

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Utils::Prefs::Namespace

=head1 DESCRIPTION

Class for implementing object to hold per namespace global perferences

=head1 METHODS

=cut

use strict;

use base qw(Slim::Utils::Prefs::Base);

use File::Spec::Functions qw(:ALL);
use YAML::Syck;

use Slim::Utils::Prefs::Client;
use Slim::Utils::Log;
use Slim::Utils::Unicode;

$YAML::Syck::ImplicitUnicode = 1;

my $log = logger('prefs');

# Simple validator functions which may be referenced by name in setValidate calls
my $simpleValidators = {
	#                   $_[0] = pref, $_[1] = value, $_[2] = params hash, $_[3] = old value, $_[4] = object (client) if appropriate
	'int'      => sub { $_[1] =~ /^-?\d+$/ },
	'num'      => sub { $_[1] =~ /^-?\.?\d+\.?\d*$/ },
	'array'    => sub { ref $_[1] eq 'ARRAY' },
	'hash'     => sub { ref $_[1] eq 'HASH' },
	'defined'  => sub { defined $_[1] },
	'false'    => sub { 0 },
	'file'     => sub { !$_[1] || -e $_[1] || -d Slim::Utils::Unicode::utf8encode_locale($_[1]) },
	'dir'      => sub {	!$_[1] || -d $_[1] || -d $_[1] || -d Slim::Utils::Unicode::utf8encode_locale($_[1]) },
	'intlimit' => sub { $_[1] =~ /^-?\d+$/ &&
						(!defined $_[2]->{'low'}  || $_[1] >= $_[2]->{'low'} ) &&
						(!defined $_[2]->{'high'} || $_[1] <= $_[2]->{'high'}) },
	'numlimit' => sub { $_[1] =~ /^-?\.?\d+\.?\d*$/ &&
						(!defined $_[2]->{'low'}  || $_[1] >= $_[2]->{'low'} ) &&
						(!defined $_[2]->{'high'} || $_[1] <= $_[2]->{'high'}) },
};

sub new {
	my $ref       = shift;
	my $namespace = shift;
	my $path      = shift;

	my $filename;

	# split namespace into dir and filename if appropriate
	if ($namespace =~ /(.*)\.(.*)/) {
		$path     = catdir($path, $1);
		$filename = catdir($path, "$2.prefs");
		mkdir $path unless -d $path;
	} else {
		$filename = catdir($path, "$namespace.prefs");
	}

	my $class = bless {
		'namespace' => $namespace,
		'file'      => $filename,
		'readonly'  => 0,
		'clients'   => {},
		'validators'=> {},
		'validparam'=> {},
		'onchange'  => {},
		'migratecb' => {},
		'utf8off'   => {},
	}, $ref;

	$class->{'prefs'} = $class->_load || {
		'_version'   => 0,
	};

	return $class;
}

sub _root { shift }

=head2 setValidate( $args, list )

Associates a validator function with the preferences listed by list.

$args may either be one of the following: 'int', 'num', 'array', 'hash', 'defined', 'false', 'file', 'dir'

or a hash containing the key 'validator' which specifies either 'intlimit' or 'numlimit' of a callback function.

In the case of a hash the hash is stored and passed to the validator function to provide parameters to the validation function.
The built in 'intlimit' and 'numlimit' use 'low' and/or 'high' parameters to perform range validation.

e.g. $prefs->setValidate({ 'validator' => 'intlimit', 'low' => 1 'high' => 10 }, 'pref1');

This ensures pref1 is only set to integer values between 1 and 10 (inclusive).

If callback function is specified for the validator it will be called with the following parameters:

$prefname, potential new value, params hash (as stored with setValidate), old value, undef or $client

=cut

sub setValidate {
	my $class  = shift;
	my $args   = shift;

	my ($validator, $params) = ref $args eq 'HASH' ? ($args->{'validator'}, $args) : ($args, undef);

	$validator = $simpleValidators->{ $validator } || $validator;

	unless (ref $validator eq 'CODE') {
		logError("invalid validator callback - not registering");
		return;
	}

	while (my $pref = shift) {

		if ( $log->isInitialized && $log->is_debug ) {
			$log->debug(sprintf "registering %s for $class->{'namespace'}:$pref", Slim::Utils::PerlRunTime::realNameForCodeRef($validator));
		}

		$class->{'validators'}->{ $pref } = $validator;
		$class->{'validparam'}->{ $pref } = $params if $params;
	}
}

=head2 setChange( $callback, list )

Associates callback function $callback with the preferences listed by list.

Callback functions will be called with the following parameters:

prefname, new value, undef or $client

=cut

sub setChange {
	my $class  = shift;
	my $change = shift;

	while (my $pref = shift) {

		if ( $log->isInitialized && $log->is_debug ) {
			$log->debug(sprintf "registering %s for $class->{'namespace'}:$pref", Slim::Utils::PerlRunTime::realNameForCodeRef($change));
		}
		
		$class->{'onchange'}->{ $pref } ||= [];

		push @{ $class->{'onchange'}->{ $pref } }, $change;
	}
}


=head2 setUtf8off( list )

Turns off the utf8 flag for the preferences listed.  This is normally used for folder prefernces
which may otherwise have the utf8 flag set when read in from YAML.

This should be called as soon as a namespace is created before preferences are used to make sure
utf8 is turned off after reading in the namespace preference file.

Only supports global (non client) prefs.

See bug: 7507

=cut

sub setUtf8Off {
	my $class = shift;

	while (my $pref = shift) {

		if ( $log->isInitialized && $log->is_debug ) {
			$log->debug("setting utf8off for $class->{'namespace'}:$pref");
		}

		if ( $class->{'prefs'}->{ $pref } ) {
			$class->{'prefs'}->{ $pref } = Slim::Utils::Unicode::utf8off($class->{'prefs'}->{ $pref });
		}

		$class->{'utf8off'}->{ $pref } = 1;
	}
}


=head2 client( $client )

Returns a preference client object for client $client.  This is used to access client preferences for a namespace:

$prefs->client($client)->get('pref1');

=cut

sub client {
	my $class  = shift;
	my $client = shift;
	
	return $class->{'clients'}->{ $client->id } ||= Slim::Utils::Prefs::Client->new($class, $client);
}

=head2 allClients()

Returns a list of client preference objects for all clients stored in the namespace preference file.
This includes clients which are not attached and so allows reading of their preferences.

It does not migrate the preferences for these objects to the latest version and so should only be used
for read only access to stored preference values.

=cut

sub allClients {
	my $class = shift;

	my @clientPrefs = ();

	foreach my $key (keys %{$class->{'prefs'}}) {

		if ($key =~ /^$Slim::Utils::Prefs::Client::clientPreferenceTag:(.*)/) {
			push @clientPrefs, Slim::Utils::Prefs::Client->new($class, $1, 'nomigrate');
		}
	}

	return @clientPrefs;
}

sub _load {
	my $class = shift;

	my $prefs;

	if (-r $class->{'file'}) {

		$prefs = eval { LoadFile($class->{'file'}) };

		if ($@) {
			$log->info("can't read $class->{'file'} : $@");
		}

		foreach ( keys %{$class->{'utf8off'}} ) {
			$prefs->{$_} = Slim::Utils::Unicode::utf8off($prefs->{$_});
		}
	}

	return $prefs;
}

=head2 readonly( )

Sets this namespace to readonly.

=cut

sub readonly {
	my $class  = shift;
	my $flag   = shift;

	$class->{'readonly'} = 1;
}

=head2 save( )

Trigger saving of this namespace's preferences.  This is delayed by 10 seconds to batch up changes.

=cut

sub save {
	my $class = shift;
	
	if ( main::SLIM_SERVICE ) {
		# No prefs files on SN
		return;
	}

	return if ($class->{'writepending'});

	Slim::Utils::Timers::setTimer($class, time() + 10, \&savenow);

	$class->{'writepending'} = 1;
}

=head2 savenow( )

Save this namespace's preferences immediately.

=cut

sub savenow {
	my $class = shift;

	return unless ($class->{'writepending'});

	$log->info("saving prefs for $class->{'namespace'} to $class->{'file'}");

	eval {
		my $path = $class->{'file'} . '.tmp';

		open(OUT,'>:utf8', $path) or die "$!";
		print OUT Dump($class->{'prefs'});
		close OUT;

		if (-w $path) {
			rename($path, $class->{'file'});
		} else {
			unlink($path);
		}
	};

	if ($@) {
		logError("can't save $class->{'file'}: $@");
	}

	$class->{'writepending'} = 0;

	Slim::Utils::Timers::killTimers($class, \&savenow);
}

=head2 migrate( $version, $callback )

Potentially migrate this namespace to version $version.  If the current version number for this namespace is < $version then $callback
is executed.  If $callback returns true then the namespace version is set to $version.

The callback is executed with the namespace class as its only parameter.

=cut

sub migrate {
	my $class    = shift;
	my $version  = shift;
	my $callback = shift;

	if ($version > $class->{'prefs'}->{'_version'} && ref $callback eq 'CODE') {

		if ($callback->($class)) {

			$log->info("migrated prefs for $class->{'namespace'} to version $version");

			$class->{'prefs'}->{'_version'} = $version;

		} else {

			$log->warn("failed to migrate prefs for $class->{'namespace'} to version $version");
		}

		$class->save;
	}
}

=head2 migrateClient( $version, $callback )

Potentially migrate client preferences for this namespace to version $version.

If the current version number for new client for this namespace is < $version then $callback
is executed.  If $callback returns true then the client namespace version is set to $version.

The callback is excuted with the following parameters:

client preference class, $client object

NB dormant clients may not attach to the server for a while.  This mechanism allows multiple migrate
functions to be performed in order for such clients to bring them up to the latest version.

=cut

sub migrateClient {
	my $class    = shift;
	my $version  = shift;
	my $callback = shift;

	$log->isInitialized && $log->info("registering client migrate function for $class->{'namespace'} to version $version");

	$class->{'migratecb'}->{ $version } = $callback;
}

=head2 SEE ALSO

L<Slim::Utils::Prefs::Base>
L<Slim::Utils::Prefs::Namespace>
L<Slim::Utils::Prefs::Client>
L<Slim::Utils::Preds::OldPrefs>

=cut

1;
