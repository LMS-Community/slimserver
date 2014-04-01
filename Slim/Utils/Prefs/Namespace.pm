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
use YAML::XS;

use Slim::Utils::OSDetect;
use Slim::Utils::Prefs::Client;
use Slim::Utils::Log;
use Slim::Utils::Unicode;

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
	'file'     => sub { !$_[1] || -f $_[1] || (main::ISWINDOWS && -f Win32::GetANSIPathName($_[1])) || -f Slim::Utils::Unicode::encode_locale($_[1]) },
	'dir'      => sub { !$_[1] || -d $_[1] || (main::ISWINDOWS && -d Win32::GetANSIPathName($_[1])) || -d Slim::Utils::Unicode::encode_locale($_[1]) },
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
		# Work around a weird win32 bug where path can be constructed wrong
		my ($one, $two) = ($1, $2);

		$path     = catdir($path, $one);
		$filename = catdir($path, "$two.prefs");
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
		'filepathPrefs' => {},
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

		if ( main::DEBUGLOG && $log->isInitialized && $log->is_debug ) {
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

	my $first = 1;
	while (my $pref = shift) {

		if ( main::DEBUGLOG && $log->isInitialized && $log->is_debug ) {
			$log->debug(sprintf "registering %s for $class->{'namespace'}:$pref", Slim::Utils::PerlRunTime::realNameForCodeRef($change));
		}
		
		$class->{'onchange'}->{ $pref } ||= [];

		if ($first) {
			# (Trys to) insist to be called first
			unshift @{ $class->{'onchange'}->{ $pref } }, $change;
		} else {
			push @{ $class->{'onchange'}->{ $pref } }, $change;
		}
		
		$first = 0;
	}
}


=head2 setFilepaths( list )

Do some prefs manipulation for values storing a file or folder path.

Only supports global (non client) prefs.

See bug: 7507

=cut

sub setFilepaths {
	my $class = shift;

	return unless main::ISWINDOWS;

	while (my $pref = shift) {

		if ( main::DEBUGLOG && $log->isInitialized && $log->is_debug ) {
			$log->debug("setting filepathPrefs for $class->{'namespace'}:$pref");
		}

		if ( $class->{'prefs'}->{ $pref } ) {
			if ( ref $class->{'prefs'}->{ $pref } eq 'ARRAY' ) {
				$class->{'prefs'}->{ $pref } = [ map { Win32::GetANSIPathName($_) } @{ $class->{'prefs'}->{ $pref } } ]
			}
			else {
				$class->{'prefs'}->{ $pref } = Win32::GetANSIPathName($class->{'prefs'}->{ $pref });
			}
		}

		$class->{'filepathPrefs'}->{ $pref } = 1;
	}
}


=head2 client( $client )

Returns a preference client object for client $client.  This is used to access client preferences for a namespace:

$prefs->client($client)->get('pref1');

=cut

sub client {
	# opimised due to frequency of being called
	return unless $_[1];

	if ( my $client = $_[0]->{'clients'}->{ $_[1]->id } ) {
		return $client;
	}
	
	my $cprefs = Slim::Utils::Prefs::Client->new($_[0], $_[1]);
	
	# This avoids an infinite loop if migration callbacks happen to call $prefs->client($client)
	$_[0]->{'clients'}->{ $_[1]->id } = $cprefs;
	
	$cprefs->migrate($_[1]);
	
	return $cprefs;
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

		$prefs = eval { YAML::XS::LoadFile($class->{'file'}) };

		if ($@) {
			# log4perl is not yet initialized
			warn("Unable to read prefs from $class->{'file'} : $@\n");
		}

		$class->setFilepaths(keys %{$class->{'filepathPrefs'}});
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

	return if ($class->{'writepending'});
	
	return if $class->{readonly} || main::SCANNER;

	Slim::Utils::Timers::setTimer($class, time() + 10, \&savenow);

	$class->{'writepending'} = 1;
}

=head2 savenow( )

Save this namespace's preferences immediately.

=cut

sub savenow {
	my $class = shift;

	return unless ($class->{'writepending'});

	main::INFOLOG && $log->info("saving prefs for $class->{'namespace'} to $class->{'file'}");

	eval {
		my $path = $class->{'file'} . '.tmp';

		open OUT, '>', $path or die "$!";
		print OUT YAML::XS::Dump($class->{'prefs'});
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
		
		require Slim::Utils::Prefs::OldPrefs;
		
		if ($callback->($class)) {

			main::INFOLOG && $log->info("migrated prefs for $class->{'namespace'} to version $version");

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

	main::INFOLOG && $log->isInitialized && $log->info("registering client migrate function for $class->{'namespace'} to version $version");

	$class->{'migratecb'}->{ $version } = $callback;
}

=head2 SEE ALSO

L<Slim::Utils::Prefs::Base>
L<Slim::Utils::Prefs::Namespace>
L<Slim::Utils::Prefs::Client>
L<Slim::Utils::Preds::OldPrefs>

=cut

1;
