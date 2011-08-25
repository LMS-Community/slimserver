package Digest::SHA1;

use strict;
use vars qw($VERSION @ISA @EXPORT_OK);

$VERSION = '2.13';

require Exporter;
*import = \&Exporter::import;
@EXPORT_OK = qw(sha1 sha1_hex sha1_base64 sha1_transform);

require DynaLoader;
@ISA=qw(DynaLoader);

eval {
    require Digest::base;
    push(@ISA, 'Digest::base');
};
if ($@) {
    my $err = $@;
    *add_bits = sub { die $err };
}

Digest::SHA1->bootstrap($VERSION);

1;
__END__

=head1 NAME

Digest::SHA1 - Perl interface to the SHA-1 algorithm

=head1 SYNOPSIS

 # Functional style
 use Digest::SHA1  qw(sha1 sha1_hex sha1_base64);

 $digest = sha1($data);
 $digest = sha1_hex($data);
 $digest = sha1_base64($data);
 $digest = sha1_transform($data);


 # OO style
 use Digest::SHA1;

 $sha1 = Digest::SHA1->new;

 $sha1->add($data);
 $sha1->addfile(*FILE);

 $sha1_copy = $sha1->clone;

 $digest = $sha1->digest;
 $digest = $sha1->hexdigest;
 $digest = $sha1->b64digest;
 $digest = $sha1->transform;

=head1 DESCRIPTION

The C<Digest::SHA1> module allows you to use the NIST SHA-1 message
digest algorithm from within Perl programs.  The algorithm takes as
input a message of arbitrary length and produces as output a 160-bit
"fingerprint" or "message digest" of the input.

In 2005, security flaws were identified in SHA-1, namely that a possible
mathematical weakness might exist, indicating that a stronger hash function
would be desirable.  The L<Digest::SHA> module implements the stronger
algorithms in the SHA family.

The C<Digest::SHA1> module provide a procedural interface for simple
use, as well as an object oriented interface that can handle messages
of arbitrary length and which can read files directly.

=head1 FUNCTIONS

The following functions can be exported from the C<Digest::SHA1>
module.  No functions are exported by default.

=over 4

=item sha1($data,...)

This function will concatenate all arguments, calculate the SHA-1
digest of this "message", and return it in binary form.  The returned
string will be 20 bytes long.

The result of sha1("a", "b", "c") will be exactly the same as the
result of sha1("abc").

=item sha1_hex($data,...)

Same as sha1(), but will return the digest in hexadecimal form.  The
length of the returned string will be 40 and it will only contain
characters from this set: '0'..'9' and 'a'..'f'.

=item sha1_base64($data,...)

Same as sha1(), but will return the digest as a base64 encoded string.
The length of the returned string will be 27 and it will only contain
characters from this set: 'A'..'Z', 'a'..'z', '0'..'9', '+' and
'/'.

Note that the base64 encoded string returned is not padded to be a
multiple of 4 bytes long.  If you want interoperability with other
base64 encoded sha1 digests you might want to append the redundant
string "=" to the result.

=item sha1_transform($data)

Implements the basic SHA1 transform on a 64 byte block. The $data
argument and the returned $digest are in binary form. This algorithm
is used in NIST FIPS 186-2

=back

=head1 METHODS

The object oriented interface to C<Digest::SHA1> is described in this
section.  After a C<Digest::SHA1> object has been created, you will add
data to it and finally ask for the digest in a suitable format.  A
single object can be used to calculate multiple digests.

The following methods are provided:

=over 4

=item $sha1 = Digest::SHA1->new

The constructor returns a new C<Digest::SHA1> object which encapsulate
the state of the SHA-1 message-digest algorithm.

If called as an instance method (i.e. $sha1->new) it will just reset the
state the object to the state of a newly created object.  No new
object is created in this case.

=item $sha1->reset

This is just an alias for $sha1->new.

=item $sha1->clone

This a copy of the $sha1 object. It is useful when you do not want to
destroy the digests state, but need an intermediate value of the
digest, e.g. when calculating digests iteratively on a continuous data
stream.  Example:

    my $sha1 = Digest::SHA1->new;
    while (<>) {
	$sha1->add($_);
	print "Line $.: ", $sha1->clone->hexdigest, "\n";
    }

=item $sha1->add($data,...)

The $data provided as argument are appended to the message we
calculate the digest for.  The return value is the $sha1 object itself.

All these lines will have the same effect on the state of the $sha1
object:

    $sha1->add("a"); $sha1->add("b"); $sha1->add("c");
    $sha1->add("a")->add("b")->add("c");
    $sha1->add("a", "b", "c");
    $sha1->add("abc");

=item $sha1->addfile($io_handle)

The $io_handle will be read until EOF and its content appended to the
message we calculate the digest for.  The return value is the $sha1
object itself.

The addfile() method will croak() if it fails reading data for some
reason.  If it croaks it is unpredictable what the state of the $sha1
object will be in. The addfile() method might have been able to read
the file partially before it failed.  It is probably wise to discard
or reset the $sha1 object if this occurs.

In most cases you want to make sure that the $io_handle is in
C<binmode> before you pass it as argument to the addfile() method.

=item $sha1->add_bits($data, $nbits)

=item $sha1->add_bits($bitstring)

This implementation of SHA-1 only supports byte oriented input so you
might only add bits as multiples of 8.  If you need bit level support
please consider using the C<Digest::SHA> module instead.  The
add_bits() method is provided here for compatibility with other digest
implementations.  See L<Digest> for description of the arguments that
add_bits() take.

=item $sha1->digest

Return the binary digest for the message.  The returned string will be
20 bytes long.

Note that the C<digest> operation is effectively a destructive,
read-once operation. Once it has been performed, the C<Digest::SHA1>
object is automatically C<reset> and can be used to calculate another
digest value.  Call $sha1->clone->digest if you want to calculate the
digest without reseting the digest state.

=item $sha1->hexdigest

Same as $sha1->digest, but will return the digest in hexadecimal
form. The length of the returned string will be 40 and it will only
contain characters from this set: '0'..'9' and 'a'..'f'.

=item $sha1->b64digest

Same as $sha1->digest, but will return the digest as a base64 encoded
string.  The length of the returned string will be 27 and it will only
contain characters from this set: 'A'..'Z', 'a'..'z', '0'..'9', '+'
and '/'.


The base64 encoded string returned is not padded to be a multiple of 4
bytes long.  If you want interoperability with other base64 encoded
SHA-1 digests you might want to append the string "=" to the result.

=back

=head1 SEE ALSO

L<Digest>, L<Digest::HMAC_SHA1>, L<Digest::SHA>, L<Digest::MD5>

http://www.itl.nist.gov/fipspubs/fip180-1.htm

http://en.wikipedia.org/wiki/SHA_hash_functions

=head1 COPYRIGHT

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

 Copyright 1999-2004 Gisle Aas.
 Copyright 1997 Uwe Hollerbach.

=head1 AUTHORS

Peter C. Gutmann,
Uwe Hollerbach <uh@alumni.caltech.edu>,
Gisle Aas <gisle@aas.no>

=cut
