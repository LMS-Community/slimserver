package Slim::Utils::Accessor;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Utils::Accessor

=head1 DESCRIPTION

L<Slim::Utils::Accessor>

 Simple accessors for SqueezeCenter objects based on Class::Accessor::Faster by Marty Pauley
 In addition to simple scalar accessors provides methods to arrays and hashes by index/key as used by Client and Display objects

=cut

use strict;

use Scalar::Util qw(weaken);

my %slot;

sub new {
	my $class = shift;

	return bless [], $class;
}

=head2 mk_accessor( $type, [ $default ], @accessors )

 Creates accessor method for each element of @accessors based on the type defined in $type:

 'scalar' - accessors store / retrieve a simple scalar
 'weak'   - accessors store a weak reference to a scalar
 'array'  - accessors store / retrieve an array or element from an array
 'arraydefault' - accessors store / retrieve elements from an array (index defaults to $default)
 'hash'   - accessors store / retrieve elements of a hash

 Accessors for 'scalar' and 'weak' are of the format:

 $class->accessor( [ $value ] ) - returns stored value or sets to $value if $value present

 Accessors for 'array' and 'hash' are of the format:

 $class->accessor( $index/$key, [ $value ] ) - returns value stored at $index/$key or sets it if $value present

 Accessors for 'arraydefault' are of the format:

 $class->accessor( [ $index ], [ $value ] ) - returns value stored at index $index or $default if $index is not present, sets it if $value present

=cut

sub mk_accessor {
	my $class   = shift;
	my $type    = shift;
	my $default = shift if $type =~ /default/;
	my @fields  = @_;

	for my $field (@fields) {

		my $accessor;

		my $n = $class->_slot($field);

		if ($type eq 'scalar') {

			$accessor = sub {
				return $_[0]->[$n]                    if @_ == 1;
				return $_[0]->[$n] = $_[1]            if @_ == 2;
			};

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

		}

		if ($accessor) {
			no strict 'refs';
			*{"${class}::$field"} = $accessor;
		}
	}
}

sub _slot {
	my $class = shift;
	my $field = shift;

    my $n = $slot{$class}->{$field};

    return $n if defined $n;

    $n = keys %{$slot{$class}};

    $slot{$class}->{$field} = $n;

    return $n;
}

=head1 SEE ALSO

=cut

1;
