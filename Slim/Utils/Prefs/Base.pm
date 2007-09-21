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

use Scalar::Util qw(blessed);

use Slim::Utils::Log;

my $optimiseAccessors = 1;

my $log = logger('prefs');

=head2 get( $prefname )

Returns the current value of preference $prefname.

(A preference value may also be accessed using $prefname as an accessor method.)

=cut

sub get {
	shift->{'prefs'}->{ $_[0] };
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
	my $readonly  = $root->{'readonly'};
	my $namespace = $root->{'namespace'};
	my $clientid  = $class->{'clientid'} || '';

	if (!ref $new && defined $new && defined $old && $new eq $old) {
		# suppress set when scalar and no change
		return wantarray ? ($new, 1) : $new;
	}

	my $valid = $class->validate($pref, $new);

	if ($readonly) {

		logBacktrace(sprintf "attempt to set %s:%s:%s while namespace is readonly", $namespace, $clientid, $pref);

		return wantarray ? ($old, 0) : $old;
	}

	if ($valid && $pref !~ /^_/) {

		$log->debug( sub {
			sprintf(
				"setting %s:%s:%s to %s",
				$namespace, $clientid, $pref, defined $new ? Data::Dump::dump($new) : 'undef'
			)
		} );

		$class->{'prefs'}->{ $pref } = $new;
		
		$class->{'prefs'}->{ '_ts_' . $pref } = time();

		$root->save;

		if ($change && (!defined $old || !defined $new || $old ne $new || ref $new)) {

			$log->debug('executing on change function');

			$change->($pref, $new, $class->_obj);
		}

		Slim::Control::Request::notifyFromArray(
			$clientid ? Slim::Player::Client::getClient($clientid) : undef,
			['prefset', $namespace, $pref, $new]
		);

		return wantarray ? ($new, 1) : $new;

	} else {

		$log->warn( sub {
			sprintf(
				"attempting to set %s:%s:%s to %s - invalid value",
				$namespace, $clientid, $pref, defined $new ? Data::Dump::dump($new) : 'undef'
			)
		} );

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

	for my $pref (keys %$hash) {

		if (!exists $class->{'prefs'}->{ $pref }) {

			my $value = ref $hash->{ $pref } eq 'CODE' ? $hash->{ $pref }->() : $hash->{ $pref };

			$log->info( sub {
				"init " . $class->_root->{'namespace'} . ":" 
				. ($class->{'clientid'} || '') . ":" . $pref 
				. " to " . (defined $value ? Data::Dump::dump($value) : 'undef')
			} );

			$class->{'prefs'}->{ $pref } = $value;
			
			$class->{'prefs'}->{ '_ts_' . $pref } = time();
		}
	}

	$class->_root->save;
}

=head2 remove ( list )

Removes (deletes) all preferences in the list.

=cut

sub remove {
	my $class = shift;

	while (my $pref  = shift) {

		$log->info( sub {
			"removing " . $class->_root->{'namespace'} . ":" . ($class->{'clientid'} || '') . ":" . $pref
		} );

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

	if ($optimiseAccessors) {

		$log->debug( sub {
			  "creating accessor for " 
			. $class->_root->{'namespace'} . ":" 
			. ($class->{'clientid'} || '') . ":" . $pref
		} );

		no strict 'refs';
		*{ $AUTOLOAD } = sub { @_ == 1 ? shift->{'prefs'}->{ $pref } : shift->set($pref, shift) };
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
