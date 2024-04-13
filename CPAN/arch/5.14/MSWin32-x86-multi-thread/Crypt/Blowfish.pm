package Crypt::Blowfish;

require Exporter;
require DynaLoader;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

@ISA = qw(Exporter DynaLoader);
# @ISA = qw(Exporter DynaLoader Crypt::BlockCipher);

# Items to export into callers namespace by default
@EXPORT =	qw();

# Other items we are prepared to export if requested
@EXPORT_OK =	qw(
	blocksize keysize min_keysize max_keysize
	new encrypt decrypt
);

$VERSION = '2.14';
bootstrap Crypt::Blowfish $VERSION;

use strict;
use Carp;

sub usage
{
    my ($package, $filename, $line, $subr) = caller(1);
	$Carp::CarpLevel = 2;
	croak "Usage: $subr(@_)"; 
}


sub blocksize   {  8; } # /* byte my shiny metal.. */
sub keysize     {  0; } # /* we'll leave this at 8 .. for now. */
sub min_keysize {  8; }
sub max_keysize { 56; }  

sub new
{
	usage("new Blowfish key") unless @_ == 2;
	my $type = shift; my $self = {}; bless $self, $type;
	$self->{'ks'} = Crypt::Blowfish::init(shift);
	return $self;
}

sub encrypt
{
	usage("encrypt data[8 bytes]") unless @_ == 2;
	my ($self,$data) = @_;
	Crypt::Blowfish::crypt($data, $data, $self->{'ks'}, 0);
	return $data;
}

sub decrypt
{
	usage("decrypt data[8 bytes]") unless @_ == 2;
	my ($self,$data) = @_; 
	Crypt::Blowfish::crypt($data, $data, $self->{'ks'}, 1);
	return $data;
}

1;

__END__
#
# Parts Copyright (C) 1995, 1996 Systemics Ltd (http://www.systemics.com/)
# New Parts Copyright (C) 1999, 2001 W3Works, LLC (http://www.w3works.com/)
# All rights reserved.
#

=head1 NAME

Crypt::Blowfish - Perl Blowfish encryption module

=head1 SYNOPSIS

  use Crypt::Blowfish;
  my $cipher = new Crypt::Blowfish $key; 
  my $ciphertext = $cipher->encrypt($plaintext);
  my $plaintext  = $cipher->decrypt($ciphertext);

  You probably want to use this in conjunction with 
  a block chaining module like Crypt::CBC.

=head1 DESCRIPTION

Blowfish is capable of strong encryption and can use key sizes up
to 56 bytes (a 448 bit key).  You're encouraged to take advantage
of the full key size to ensure the strongest encryption possible
from this module.

Crypt::Blowfish has the following methods:

=over 4

 blocksize()
 keysize()
 encrypt()
 decrypt()

=back

=head1 FUNCTIONS

=over 4

=item blocksize

Returns the size (in bytes) of the block cipher.

Crypt::Blowfish doesn't return a key size due to its ability
to use variable-length keys.  More accurately, it shouldn't,
but it does anyway to play nicely with others. 

=item new

	my $cipher = new Crypt::Blowfish $key;

This creates a new Crypt::Blowfish BlockCipher object, using $key,
where $key is a key of C<keysize()> bytes (minimum of eight bytes).

=item encrypt

	my $cipher = new Crypt::Blowfish $key;
	my $ciphertext = $cipher->encrypt($plaintext);

This function encrypts $plaintext and returns the $ciphertext
where $plaintext and $ciphertext must be of C<blocksize()> bytes.
(hint:  Blowfish is an 8 byte block cipher)

=item decrypt

	my $cipher = new Crypt::Blowfish $key;
	my $plaintext = $cipher->decrypt($ciphertext);

This function decrypts $ciphertext and returns the $plaintext
where $plaintext and $ciphertext must be of C<blocksize()> bytes.
(hint:  see previous hint)

=back

=head1 EXAMPLE

	my $key = pack("H16", "0123456789ABCDEF");  # min. 8 bytes
	my $cipher = new Crypt::Blowfish $key;
	my $ciphertext = $cipher->encrypt("plaintex");	# SEE NOTES 
	print unpack("H16", $ciphertext), "\n";

=head1 PLATFORMS

	Please see the README document for platforms and performance
	tests.

=head1 NOTES

The module is capable of being used with Crypt::CBC.  You're
encouraged to read the perldoc for Crypt::CBC if you intend to
use this module for Cipher Block Chaining modes.  In fact, if
you have any intentions of encrypting more than eight bytes of
data with this, or any other block cipher, you're going to need
B<some> type of block chaining help.  Crypt::CBC tends to be
very good at this.  If you're not going to encrypt more than 
eight bytes, your data B<must> be B<exactly> eight bytes long.
If need be, do your own padding. "\0" as a null byte is perfectly
valid to use for this. 

=head1 SEE ALSO

Crypt::CBC,
Crypt::DES,
Crypt::IDEA

Bruce Schneier, I<Applied Cryptography>, 1995, Second Edition,
published by John Wiley & Sons, Inc.

=head1 COPYRIGHT

The implementation of the Blowfish algorithm was developed by,
and is copyright of, A.M. Kuchling.

Other parts of the perl extension and module are
copyright of Systemics Ltd ( http://www.systemics.com/ ). 

Code revisions, updates, and standalone release are copyright
1999-2010 W3Works, LLC.

=head1 AUTHOR

Original algorithm, Bruce Shneier.  Original implementation, A.M.
Kuchling.  Original Perl implementation, Systemics Ltd.  Current
maintenance by W3Works, LLC.

Current revision and maintainer:  Dave Paris <amused@pobox.com>

