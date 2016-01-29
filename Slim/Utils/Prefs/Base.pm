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

my $log = logger('prefs');

=head2 get( $prefname )

Returns the current value of preference $prefname.

(A preference value may also be accessed using $prefname as an accessor method.)

=cut

sub get {
	$_[0]->{prefs}->{ $_[1] };
}

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

	if ( $valid && $pref !~ /^_/ ) {

		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug(
				sprintf(
					"setting %s:%s:%s to %s",
					$namespace, $clientid, $pref, defined $new ? Data::Dump::dump($new) : 'undef'
				)
			);
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
		$class->{'prefs'}->{ '_ts_' . $pref } = time();

		$root->save;
		
		my $client = $clientid ? Slim::Player::Client::getClient($clientid) : undef;
		
		if ( !defined $old || !defined $new || $old ne $new || ref $new ) {
			my $obj = $class->_obj;
			for my $func ( @{$change} ) {
				if ( main::DEBUGLOG && $log->is_debug ) {
					$log->debug('executing on change function ' . Slim::Utils::PerlRunTime::realNameForCodeRef($func) );
				}
			
				$func->($pref, $new, $obj, $old);
			}
		}

		if ( !main::SCANNER ) {
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

sub _obj {}

=head2 init( Hash )

Initialises any preference values which currently do not exist.

Hash is of the format: { 'prefname' => 'initial value' }

=cut

sub init {
	my $class = shift;
	my $hash  = shift;
	my $migrationClass = shift;
	
	$class->{migrationClass} ||= $migrationClass;
	
	if ( $class->{migrationClass} ) {
		eval "use $class->{migrationClass}";
		if ($@) {
			$log->error("Unable to load migration class: $@");
		}
		else {
			$class->{migrationClass}->init($class, $hash);
		}
	}

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

			if ( main::INFOLOG && $log->is_info ) {
				$log->info(
					"init " . $class->_root->{'namespace'} . ":" 
					. ($class->{'clientid'} || '') . ":" . $pref 
					. " to " . (defined $value ? Data::Dump::dump($value) : 'undef')
				);
			}

			$class->{'prefs'}->{ $pref } = $value;
			$class->{'prefs'}->{ '_ts_' . $pref } = time();

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
		delete $class->{'prefs'}->{ '_ts_' . $pref };
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

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug(
			  "creating accessor for " 
			. $class->_root->{'namespace'} . ":" 
			. ($class->{'clientid'} || '') . ":" . $pref
		);
	}

	no strict 'refs';
	*{ $AUTOLOAD } = sub { @_ == 1 ? $_[0]->{'prefs'}->{ $pref } : $_[0]->set($pref, $_[1]) };

	return @_ == 0 ? $class->{'prefs'}->{ $pref } : $class->set($pref, shift);
}

=head2 SEE ALSO

L<Slim::Utils::Prefs::Base>
L<Slim::Utils::Prefs::Namespace>
L<Slim::Utils::Prefs::Client>
L<Slim::Utils::Preds::OldPrefs>

=cut

1;
