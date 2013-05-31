package Slim::Utils::Prefs::Base;

# $Id$

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Utils::Prefs::Base

=head1 DESCRIPTION

Base class for preference objects implementing methods which can be used on global and client preferences.

=head1 METHODS

=cut

use strict;

use JSON::XS::VersionOneAndTwo;
use Scalar::Util qw(blessed);
use Storable;

use Slim::Utils::Log;

my $optimiseAccessors = 1;

my $log = logger('prefs');

# some prefs changes come in bursts - buffer DB updates on SN
my %delayedWrites = main::SLIM_SERVICE ? (
	volume => 1.000,  # buffer volume changes for a full second
	mute   => 1.000,
	power  => 1,
	currentSong   => 1,
	pandora_track => 5,
	sn_PluginData => 5,
	sn_songPluginData => 5,
	playingAtPowerOff => 1,
) : undef;

=head2 get( $prefname )

Returns the current value of preference $prefname.

(A preference value may also be accessed using $prefname as an accessor method.)

On SLIM_SERVICE, this pulls the value from the database if it doesn't already exist.

=cut

*get = main::SLIM_SERVICE ? \&get_SN : \&get_SC;

sub get_SC {
	$_[0]->{prefs}->{ $_[1] };
}

sub get_SN {
	if ( main::SLIM_SERVICE ) {
		my ( $class, $key ) = ( shift, shift );
	
		my $value = $class->{prefs}->{ $key };
		
		# Callers can force retrieval from the database
		my $force = shift;
	
		# Can override the model
		my $model = shift;

		if ( !defined $value || $force ) {
	
			if ( $class->{clientid} ) {
				# Prepend namespace to key if it's not 'server'
				my $nskey = $key;
				if ( $class->namespace ne 'server' ) {
					my $ns = $class->namespace;
					$ns =~ s/\./_/g;
					$nskey = $ns . '_' . $key;
				}
			
				$value = $class->getFromDB( $nskey, $model );

				$class->{prefs}->{ $key } = $value;
			}
		}
	
		# Special handling for disabledirsets when there is only one disabled item
		if ( $key eq 'disabledirsets' && !ref $value ) {
			$value = [ $value ];
		}
	
		# More special handling for alarm prefs, ugh
		elsif ( $key =~ /^alarm/ && !ref $value ) {
			if ( $key !~ /alarmfadeseconds|alarmsEnabled|alarmSnoozeSeconds|alarmTimeoutSeconds|alarmsaver/ ) {
				$value = [ $value ];
			}
		}
	
		if ( wantarray && ref $value eq 'ARRAY' ) {
			return @{$value};
		}
	
		return $value;
	}
}

=head2 getFromDB( $prefname )

SLIM_SERVICE only. Pulls a pref from the database.

=cut

sub getFromDB { if ( main::SLIM_SERVICE ) { # optimize out for SC
	my ( $class, $key, $model ) = @_;
	
	my $client = Slim::Player::Client::getClient( $class->{clientid} ) || return;
	
	my @prefs;
	
	if ( $model && $model eq 'UserPref' ) {
		@prefs = SDI::Service::Model::UserPref->search( {
			user => $client->playerData->userid,
			name => $key,
		} );
	}
	else {
		@prefs = SDI::Service::Model::PlayerPref->search( {
			player => $client->playerData,
			name   => $key,
		} );
	}
	
	my $count = scalar @prefs;
	my $value;
	
	if ( $count == 1 ) {
		# scalar pref or JSON pref
		$value = $prefs[0]->value;
		
		if ( !defined $value ) {
			# NULL in DB is indicates empty string
			$value = '';
		}	
		elsif ( $value =~ s/^json:// ) {
			$value = eval { from_json($value) };
			if ( $@ ) {
				$log->error( $client->id . " Bad JSON pref $key: $@" );
				$value = '';
			}
		}
	}
	elsif ( $count > 1 )  {
		# array pref
		$value = [];
		for my $pref ( @prefs ) {
			my $pv = $pref->value;
			if ( !defined $pv ) {
				$pv = '';
			}
			elsif ( $pv =~ s/^json:// ) {
				$pv = eval { from_json($pv) };
				if ( $@ ) {
					$log->error( $client->id . " Bad JSON pref $key: $@" );
					$pv = ''
				}
			}
			
			$value->[ $pref->idx ] = $pv;
		}
	}
	else {
		# nothing found
	}

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( sprintf( 
			"getFromDB: retrieved client pref %s-%s = %s",
			$client->id, $key, (defined($value) ? $value : 'undef')
		) );
	}
	
	return $value;
} }

=head2 exists( $prefname )

Returns whether preference $prefname exists.

=cut

sub exists {
	exists shift->{'prefs'}->{ $_[0] };
}

=head2 validate( $pref, $new )

Validates new value for a preference.

=cut

sub validate {
	my $class = shift;
	my $pref  = shift;
	my $new   = shift;

	my $old   = $class->{'prefs'}->{ $pref };
	my $root  = $class->_root;
	my $validator = $root->{'validators'}->{ $pref };

	return $validator ? $validator->($pref, $new, $root->{'validparam'}->{ $pref }, $old, $class->_obj) : 1;
}

=head2 set( $prefname, $value )

Sets preference $prefname to $value.

If a validator is set for this $prefname this is checked first.  If an on change callback is set this is called
after setting the preference.

NB preferences only store scalar values.  Hashes or Arrays should be stored as references.

(A preference may also be set $prefname as an accessor method.)

=cut

sub set {
	my $class = shift;
	my $pref  = shift;
	my $new   = shift;

	my $old   = $class->{'prefs'}->{ $pref };

	my $root  = $class->_root;
	my $change = $root->{'onchange'}->{ $pref };
	my $namespace = $root->{'namespace'};
	my $clientid  = $class->{'clientid'} || '';

	if (!ref $new && defined $new && defined $old && $new eq $old) {
		# suppress set when scalar and no change
		return wantarray ? ($new, 1) : $new;
	}

	my $valid = $class->validate($pref, $new);

	if ( $valid && ( main::SLIM_SERVICE || $pref !~ /^_/ ) ) {

		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug(
				sprintf(
					"setting %s:%s:%s to %s",
					$namespace, $clientid, $pref, defined $new ? Data::Dump::dump($new) : 'undef'
				)
			);
		}
		
		if ( main::SLIM_SERVICE ) {
			# If old pref was an array but new is not, force it to stay an array
			if ( ref $old eq 'ARRAY' && !ref $new ) {
				$new = [ $new ];
			}
		}

		if (main::ISWINDOWS && $root->{'filepathPrefs'}->{ $pref }) {
			if ( ref $new eq 'ARRAY' ) {
				$new = [ map { Win32::GetANSIPathName($_) } @{ $new } ]
			}
			else {
				$new = Win32::GetANSIPathName($new);
			}
		}

		$class->{'prefs'}->{ $pref } = $new;
		
		if ( !main::SLIM_SERVICE ) { # SN's timestamps are stored automatically
			$class->{'prefs'}->{ '_ts_' . $pref } = time();
		}

		$root->save;
		
		my $client = $clientid ? Slim::Player::Client::getClient($clientid) : undef;
		
		if ( !defined $old || !defined $new || $old ne $new || ref $new ) {
			
			if ( main::SLIM_SERVICE && blessed($client) && $client->playerData ) {
				# Skip param lets routines like initPersistedPrefs avoid writing right back to the db
				my $skip = shift || 0;

				if ( !$skip ) {
					# Save the pref to the db
					
					my $nspref = $pref;
					if ( $class->namespace ne 'server' ) {
						my $ns = $class->namespace;
						$ns =~ s/\./_/g;
						$nspref = $ns . '_' . $pref;
					}
					
					my $k = $client->id . $nspref;

					if ( my $delay = $delayedWrites{$nspref} ) {
						# need to use $client & $nspref as key or only the really last pref change for a client would apply
						Slim::Utils::Timers::killTimers( $k, \&_savePref );
						Slim::Utils::Timers::setTimer(
							$k,
							Time::HiRes::time() + $delay,
							\&_savePref,
							$client,
							$nspref,
							$new,
						);
					}
					else {
						_savePref($k, $client, $nspref, $new);
					}
				}
			}

			if ( (my $obj = $class->_obj) || !main::SLIM_SERVICE ) {
				for my $func ( @{$change} ) {
					if ( main::DEBUGLOG && $log->is_debug ) {
						$log->debug('executing on change function ' . Slim::Utils::PerlRunTime::realNameForCodeRef($func) );
					}
				
					$func->($pref, $new, $obj, $old);
				}
			}
		}

		if ( !main::SCANNER && !main::SLIM_SERVICE ) {
			# Don't spam Request queue during init
			if ( !$main::inInit ) {
				Slim::Control::Request::notifyFromArray(
					$clientid ? $client : undef,
					['prefset', $namespace, $pref, $new]
				);
			}
		}

		return wantarray ? ($new, 1) : $new;

	} else {

		if ( $log->is_warn ) {
			$log->warn(
				sprintf(
					"attempting to set %s:%s:%s to %s - invalid value",
					$namespace, $clientid, $pref, 
						main::DEBUGLOG ? (defined $new ? Data::Dump::dump($new) : 'undef') : ''
				)
			);
		}

		return wantarray ? ($old, 0) : $old;
	}
}

sub _savePref { if ( main::SLIM_SERVICE ) {
	my ($k, $client, $pref, $value) = @_;

	if ( ref $value eq 'ARRAY' ) {
		SDI::Service::Model::PlayerPref->quick_update_array( $client->playerData, $pref, $value );
	}
	else {
		SDI::Service::Model::PlayerPref->quick_update( $client->playerData, $pref, $value );
	}
} }
					
# SLIM_SERVICE only, the bulkSet method
# sets all prefs passed in first, then runs all onchange handlers
# This avoids extra db queries when a change handler uses a pref not yet loaded

sub bulkSet { if ( main::SLIM_SERVICE ) { # optimize out for SC
	my ( $class, $prefs ) = @_;
	
	my $root = $class->_root;
	
	my @handlers;
	
	my $set = sub {
		my ( $pref, $new ) = @_;
		
		my @ret;
		
		my $valid = $class->validate($pref, $new);
		
		if ( $valid ) {
			my $old = $class->{prefs}->{ $pref };
			
			if ( ref $new eq 'ARRAY' ) {
				for ( @{$new} ) {
					if ( $_ && s/^json:// ) {
						utf8::encode($_);
						$_ = eval { from_json($_) };
						if ( $@ ) {
							$log->error( "Bad JSON pref $pref: $@" );
							$_ = '';
						}
					}
				}
			}
			elsif ( $new =~ s/^json:// ) {
				utf8::encode($new);
				$new = eval { from_json($new) };
				if ( $@ ) {
					$log->error( "Bad JSON pref $pref: $@" );
					$new = '';
				}
			}
			
			# If old pref was an array but new is not, force it to stay an array
			if ( ref $old eq 'ARRAY' && !ref $new ) {
				$new = [ $new ];
			}
			
			$class->{prefs}->{ $pref } = $new;
			
			# Return a change handler callback if necessary
			if ( !defined $old || !defined $new || $old ne $new || ref $new ) {
				if ( my $obj = $class->_obj ) {
					my $change = $root->{onchange}->{ $pref };
					for my $func ( @{$change} ) {
						push @ret, sub {
							main::DEBUGLOG && $log->is_debug && $log->debug(
								'executing on change function ' . Slim::Utils::PerlRunTime::realNameForCodeRef($func)
							);
							
							$func->( $pref, $new, $obj );
						};
					}
				}
			}
		}
		
		return @ret;
	};

	for my $key ( keys %{$prefs} ) {
		my @cb;
		if ( scalar @{ $prefs->{$key} } == 1 ) {
			# scalar pref
			@cb = $set->( $key, $prefs->{$key}->[0] );
		}
		else {
			# array pref
			@cb = $set->( $key, $prefs->{$key} );
		}
		for my $cb ( @cb ) {
			push @handlers, $cb if defined $cb;
		}
	}
	
	for my $func ( @handlers ) {
		eval { $func->(); };
		if ( main::DEBUGLOG && $@ && $log->is_debug ) {
			my $handler = Slim::Utils::PerlRunTime::realNameForCodeRef($func);
			$log->debug( "Error running bulkSet change handler $handler: $@" );
			Slim::Utils::Misc::bt();
		}
	}
} }

sub _obj {}

=head2 init( Hash )

Initialises any preference values which currently do not exist.

Hash is of the format: { 'prefname' => 'initial value' }

=cut

sub init {
	my $class = shift;
	my $hash  = shift;

	my $changed = 0;

	for my $pref (keys %$hash) {

		# Initialize the value if it doesn't exist, or exists as an undef value
		if (!exists $class->{'prefs'}->{ $pref } || !defined $class->{'prefs'}->{ $pref }) {

			my $value;

			if (ref $hash->{ $pref } eq 'CODE') {

				$value = $hash->{ $pref }->( $class->_obj );

			} elsif (ref $hash->{ $pref }) {

				# dclone data structures to ensure each client gets its own copy
				$value = Storable::dclone($hash->{ $pref });

			} else {

				$value = $hash->{ $pref };
			}

			if ( main::DEBUGLOG && $log->is_info ) {
				$log->info(
					"init " . $class->_root->{'namespace'} . ":" 
					. ($class->{'clientid'} || '') . ":" . $pref 
					. " to " . (defined $value ? Data::Dump::dump($value) : 'undef')
				);
			}

			$class->{'prefs'}->{ $pref } = $value;
			
			if ( !main::SLIM_SERVICE ) { # SN's timestamps are stored automatically
				$class->{'prefs'}->{ '_ts_' . $pref } = time();
			}

			$changed = 1;
		}
	}

	$class->_root->save if $changed;
}

=head2 remove ( list )

Removes (deletes) all preferences in the list.

=cut

sub remove {
	my $class = shift;

	while (my $pref  = shift) {

		if ( main::INFOLOG && $log->is_info ) {
			$log->info(
				"removing " . $class->_root->{'namespace'} . ":" . ($class->{'clientid'} || '') . ":" . $pref
			);
		}

		delete $class->{'prefs'}->{ $pref };
		
		if ( !main::SLIM_SERVICE ) {
			delete $class->{'prefs'}->{ '_ts_' . $pref };
		}
		
		if ( main::SLIM_SERVICE && $class->{clientid} ) {
			# Remove the pref from the database
			my $client = Slim::Player::Client::getClient( $class->{clientid} );
			if ( $client->playerData ) {
				SDI::Service::Model::PlayerPref->sql_clear_array->execute(
					$client->playerData->id,
					$pref,
				);
			}
		}
	}

	$class->_root->save;
}

=head2 all ( )

Returns all preferences at this level (all global prefernces in a namespace, or all client preferences in a namespace).

=cut

sub all {
	my $class = shift;

	my %prefs = %{$class->{'prefs'}};

	for my $pref (keys %prefs) {
		delete $prefs{$pref} if $pref =~ /^\_/;
	}

	return \%prefs;
}

=head2 clear ( )

Clears all preferences. SLIM_SERVICE only.

=cut

sub clear { if ( main::SLIM_SERVICE ) { # optimize out for SC
	my $class = shift;
	
	for my $pref ( keys %{ $class->{prefs} } ) {
		delete $class->{prefs}->{$pref};
	}
} }

=head2 hasValidator( $pref )

Returns whether preference $pref has a validator function defined.

=cut

sub hasValidator {
	my $class = shift;
	my $pref  = shift;

	return $class->_root->{'validators'}->{ $pref }  ? 1 : 0;
}

=head2 namespace( )

Returns namespace for this preference object.

=cut

sub namespace {
	my $class = shift;

	return $class->_root->{'namespace'};
}

=head2 timestamp( $pref )

Returns last-modified timestamp for this preference

=cut

sub timestamp {
	my ( $class, $pref, $wipe ) = @_;
	
	if ( main::SLIM_SERVICE ) {
		return 0;
	}
	
	if ( $wipe ) {
		$class->{'prefs'}->{ '_ts_' . $pref } = -1;
	}
	
	return $class->{'prefs'}->{ '_ts_' . $pref } ||= 0;
}

sub AUTOLOAD {
	my $class = shift;

	my $package = blessed($class);

	our $AUTOLOAD;

	my ($pref) = $AUTOLOAD =~ /$package\:\:(.*)/;

	return if (!$pref || $pref eq 'DESTROY');

	if ($optimiseAccessors) {

		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug(
				  "creating accessor for " 
				. $class->_root->{'namespace'} . ":" 
				. ($class->{'clientid'} || '') . ":" . $pref
			);
		}

		no strict 'refs';
		*{ $AUTOLOAD } = sub { @_ == 1 ? $_[0]->{'prefs'}->{ $pref } : $_[0]->set($pref, $_[1]) };
	}

	return @_ == 0 ? $class->{'prefs'}->{ $pref } : $class->set($pref, shift);
}

=head2 SEE ALSO

L<Slim::Utils::Prefs::Base>
L<Slim::Utils::Prefs::Namespace>
L<Slim::Utils::Prefs::Client>
L<Slim::Utils::Preds::OldPrefs>

=cut

1;
