package XS::Object::Magic;

use strict;
use warnings;

require 5.008001;
use parent qw(DynaLoader);

our $VERSION = '0.02';
$VERSION = eval $VERSION;

sub dl_load_flags { 0x01 }

__PACKAGE__->bootstrap($VERSION);

__PACKAGE__

__END__

=pod

=head1 NAME

XS::Object::Magic - Opaque, extensible XS pointer backed objects using C<sv_magic>

=head1 SYNOPSIS

	package MyObject;

	use XS::Object::Magic;

	sub new {
		my $class = shift;

		# create any object representation you like
		my $self = bless {}, $class;

		$self->build_struct;

		return $self;
	}


	# or using Moose

	package MyObject;
	use Moose;

	sub BUILD {
		shift->build_struct;
	}


	# then in XS

	MODULE = MyObject  PACKAGE = MyObject

	void build_struct (SV *self)
		PREINIT:
			my_struct_t *thingy;
		CODE:
			thingy = create_whatever();

			/* note that we dereference self first. This
			 * can be done using an XS typemap of course */
			xs_object_magic_attach_struct(aTHX_ SvRV(self), thingy);


	void foo (SV *self)
		PREINIT:
			my_struct_t *thingy = xs_object_magic_get_struct_rv(aTHX_ self)
		CODE:
			my_struct_foo(thingy); /* delegate to C api */


	/* using typemap */
	void foo (my_struct_t *thingy)
		CODE:
			my_struct_foo(thingy);

	/* or better yet */
	PREFIX = my_struct_

	void
	my_struct_foo (thingy)
		my_struct_t *thingy;

	
	/* don't forget a destructor */
	void
	DESTROY (my_struct_t *thingy)
		CODE:
			Safefree(thingy);

			/* note that xs_object_magic_get_struct() will
			 * still return a pointe which is now invalid */


=head1 DESCRPTION

This way of associating structs with Perl space objects is designed to supercede
Perl's builtin C<T_PTROBJ> with something that is designed to be:

=over 4

=item Extensible

The association of the pointer using C<sv_magicext> can be done on any data
type, so you can associate C structs with any representation type.

This means that you can add pointers to any object (hand coded, L<Moose> or
otherwise), while still having instance data in regular hashes.

=item Opaque

The C pointer is neither visible nor modifiable from Perl space.

This prevents accidental corruption which could lead to segfaults using
C<T_PTROBJ> (e.g. C<$$ptr_obj = 0>).

=back

=head1 C API

=over 4

=item void *xs_object_magic_get_struct_rv(aTHX_ SV *sv)

When called on the object reference it will check that the C<sv> is a reference,
dereference it and return the associated pointer using
C<xs_object_magic_get_struct>.

Basically the same as C<xs_object_magic_get_struct(aTHX_ SvRV(sv)> but croaks
if no magic was found.

Note that storing a C<NULL> pointer will B<not> cause an error.

=item void *xs_object_magic_get_struct(aTHX_ SV *sv)

Fetches the pointer associated with C<sv>.

Returns C<NULL> if no pointer is found. There is no way to distinguish this
from having a C<NULL> pointer.

=item MAGIC *xs_object_magic_get_mg (aTHX_ SV *sv)

Fetches the appropriate C<MAGIC> entry for the struct pointer storage from
C<sv>.

This lets you manipulate C<mg->mg_ptr> if you need to.

=item void xs_object_magic_attach_struct(aTHX_  SV *sv, void *ptr)

Associates C<ptr> with C<sv> by adding a magic entry to C<sv>.

=item SV *xs_object_magic_create(aTHX_ void *ptr, HV *stash)

Convenience function that creates a hash object blessed to C<stash> and
associates it with C<ptr>.

Can be used to easily create a constructor:

	SV *
	new(char *class)
		CODE:
			RETVAL = xs_object_magic_create(
				(void *)test_new(),
				gv_stashpv(class, 0)
			);
		OUTPUT: RETVAL

=back

=head1 TYPEMAP

The included typemap provides a C<T_PTROBJ_MG> entry which only supports the
C<INPUT> conversion.

This typemap entry lets you declare methods that are invoked directly on the
associated pointer. In your own typemap add an entry:

	TYPEMAP
	my_pointer_t *	T_PTROBJ_MG

and then you can use C<my_pointer_t> as the argument type of the invocant:

	I32
	method (self)
		my_pointer_t *self;
		CODE:
			...

Note that there is no C<OUTPUT> conversion. In order to return your object you
need to use C<ST(0)> or some other means of getting the invocant.

=head1 VERSION CONTROL

L<http://github.com/nothingmuch/xs-object-magic>

=head1 AUTHOR

Florian Ragwitz, Yuval Kogman

=head1 COPYRIGHT & LICENSE

	Copyright (c) 2009 Florian Ragwitz, Yuval Kogman. All rights reserved
	This program is free software; you can redistribute
	it and/or modify it under the same terms as Perl itself.

=cut

