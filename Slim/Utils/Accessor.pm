package Slim::Utils::Accessor;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Utils::Accessor

=head1 DESCRIPTION

L<Slim::Utils::Accessor>

 Simple accessors for Logitech Media Server objects based on Class::Accessor::Faster by Marty Pauley
 In addition to simple scalar accessors provides methods to arrays and hashes by index/key as used by Client and Display objects

=cut

use strict;

use Scalar::Util qw(blessed weaken);

use Slim::Utils::Log;

my $log = logger('server');

BEGIN {
	my $hasXS;

	sub hasXS {
		return $hasXS if defined $hasXS;
	
		$hasXS = 0;
		eval {
			require Class::XSAccessor::Array;
			die if $Class::XSAccessor::Array::VERSION lt '1.05';
			$hasXS = 1;
		};
		
		if ( $@ ) {
			warn "NOTE: Class::XSAccessor 1.05+ not found, install it for better performance\n";
		}
	
		return $hasXS;
	}
}

my %slot;

sub new {
	my $class = shift;

	return bless [], $class;
}

=head2 mk_accessor( $type, [ $default ], @accessors )

 Creates accessor method for each element of @accessors based on the type defined in $type:

 'rw'     - accessors store / retrieve a simple scalar
 'ro'     - retrieve a simple scalar
 'weak'   - accessors store a weak reference to a scalar
 'array'  - accessors store / retrieve an array or element from an array
 'arraydefault' - accessors store / retrieve elements from an array (index defaults to $default)
 'hash'   - accessors store / retrieve elements of a hash

 Accessors for 'rw', 'ro' and 'weak' are of the format:

 $class->accessor( [ $value ] ) - returns stored value or sets to $value if $value present

 Accessors for 'array' and 'hash' are of the format:

 $class->accessor( $index/$key, [ $value ] ) - returns value stored at $index/$key or sets it if $value present

 Accessors for 'arraydefault' are of the format:

 $class->accessor( [ $index ], [ $value ] ) - returns value stored at index $index or $default if $index is not present,
 sets it if $value present

=cut

sub mk_accessor {
	my $class   = shift;
	my $type    = shift;
	my $default = shift if $type =~ /default/;
	my @fields  = @_;

	for my $field (@fields) {

		my $accessor;

		my $n = $class->_slot($field);

		if ($type eq 'rw') {
			
			if ( hasXS() ) {
				Class::XSAccessor::Array->import(
					class     => $class,
					accessors => { $field, $n }
				);
			}
			else {
				$accessor = sub {
					return $_[0]->[$n]                    if @_ == 1;
					return $_[0]->[$n] = $_[1]            if @_ == 2;
				};
			}

		} elsif ($type eq 'ro') {
			
			if ( hasXS() ) {
				Class::XSAccessor::Array->import(
					class   => $class,
					getters => { $field, $n }
				);
			}
			else {
				$accessor = sub {
					return $_[0]->[$n]                    if @_ == 1;
					$log->error("Attempt to set ro accessor $field");
					return $_[0]->[$n];
				};
			}

		} elsif ($type eq 'weak') {

			$accessor = sub {
				return $_[0]->[$n]                    if @_ == 1;
				$_[0]->[$n] = $_[1]                   if @_ == 2;
				weaken $_[0]->[$n];
			};

		} elsif ($type eq 'array') {

			$accessor = sub {
				return $_[0]->[$n]                    if @_ == 1;
				return $_[0]->[$n]->[ $_[1] ]         if @_ == 2;
				return $_[0]->[$n]->[ $_[1] ] = $_[2] if @_ == 3;
			};

		} elsif ($type eq 'arraydefault') {

			$accessor = sub {
				return $_[0]->[$n]->[ $default ]      if @_ == 1;
				return $_[0]->[$n]->[ $_[1] ]         if @_ == 2;
				return $_[0]->[$n]->[ $_[1] ] = $_[2] if @_ == 3;
			};

		} elsif ($type eq 'hash') {

			$accessor = sub {
				return $_[0]->[$n]                    if @_ == 1;
				return $_[0]->[$n]->{ $_[1] }         if @_ == 2;
				return $_[0]->[$n]->{ $_[1] } = $_[2] if @_ == 3;
			};

		} elsif ($type eq 'rw_bt') {
			
			$accessor = sub {
				return $_[0]->[$n]                    if @_ == 1;
				if (@_ == 2) {
					logBacktrace("$class ->$field set to $_[1]");
					return $_[0]->[$n] = $_[1];
				}
			};
		}

		if ($accessor) {
			no strict 'refs';
			*{"${class}::$field"} = $accessor;
		}
	}
}

=head2 init_accessor( $field1, $value1, $field2, $value2, ... )

 Initialise the accessor for each key, value pair.  Used to set ro accessor content and init array/hashes.

=cut

sub init_accessor {
	my $class = shift;

	my $baseclass = $class->_baseClass($class);

	while (my $key = shift) {
		my $val = shift;
		if (defined (my $n = $slot{$baseclass}->{$key})) {
			$class->[$n] = $val;
		} else {
			$log->error("accessor not created " . blessed($class) . "->$key");
		}
	}
}

sub _slot {
	my $class = shift;
	my $field = shift;
	
	my $baseclass = $class->_baseClass;

	my $n = $slot{$baseclass}->{$field};

	return $n if defined $n;

	$n = keys %{$slot{$baseclass}};

	$slot{$baseclass}->{$field} = $n;

	return $n;
}

# Find the base class excluding this package
# Used so we can allocate slots which don't clash for all classes that inherit from it
# Based on Class::ISA
sub _baseClass {
	my $class = shift;

	$class = blessed($class) || $class;

	my @in  = ($class);
	my @out = ();
	my $current;

	while (@in) {
		next unless defined($current = shift @in) && length($current);
		push @out, $current;
		no strict 'refs';
		unshift @in, @{"$current\::ISA"};
	}

	if ($out[-1] eq __PACKAGE__) {
		return $out[-2];
	}
	
	# more complex inheritance - admit defeat!
	# if we get here you would be better using Class::Accessor::Fast
	warn("Potential clash in accessor allocation in Slim::Utils::Accessor for $class");

	return $class;
}

=head1 SEE ALSO

=cut

1;
