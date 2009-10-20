package AnyEvent::TLS;

use Carp qw(croak);
use Scalar::Util ();

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use AnyEvent::Util ();

use Net::SSLeay;

=head1 NAME

AnyEvent::TLS - SSLv2/SSLv3/TLSv1 contexts for use in AnyEvent::Handle

=cut

our $VERSION = $AnyEvent::VERSION;

=head1 SYNOPSIS

   # via AnyEvent::Handle

   use AnyEvent;
   use AnyEvent::Handle;
   use AnyEvent::Socket;

   # simple https-client
   my $handle = new AnyEvent::Handle
      connect  => [$host, $port],
      tls      => "connect",
      tls_ctx  => { verify => 1, verify_peername => "https" },
      ...

   # simple ssl-server
   tcp_server undef, $port, sub {
      my ($fh) = @_;

      my $handle = new AnyEvent::Handle
         fh       => $fh,
         tls      => "accept",
         tls_ctx  => { cert_file => "my-server-keycert.pem" },
         ...

   # directly

   my $tls = new AnyEvent::TLS
      verify => 1,
      verify_peername => "ldaps",
      ca_file => "/etc/cacertificates.pem";

=head1 DESCRIPTION

This module is a helper module that implements TLS/SSL (Transport Layer
Security/Secure Sockets Layer) contexts. A TLS context is a common set of
configuration values for use in establishing TLS connections.

For some quick facts about SSL/TLS, see the section of the same name near
the end of the document.

A single TLS context can be used for any number of TLS connections that
wish to use the same certificates, policies etc.

Note that this module is inherently tied to L<Net::SSLeay>, as this
library is used to implement it. Since that perl module is rather ugly,
and OpenSSL has a rather ugly license, AnyEvent might switch TLS providers
at some future point, at which this API will change dramatically, at least
in the Net::SSLeay-specific parts (most constructor arguments should still
work, though).

Although this module does not require a specific version of Net::SSLeay,
many features will gradually stop working, or bugs will be introduced with
old versions (verification might succeed when it shouldn't - this is a
real security issue). Version 1.35 is recommended, 1.33 should work, 1.32
might, and older versions are yours to keep.

=head1 USAGE EXAMPLES

See the L<AnyEvent::Handle> manpage, NONFREQUENTLY ASKED QUESTIONS, for
some actual usage examples.

=head1 PUBLIC METHODS AND FUNCTIONS

=over 4

=cut

our $REF_IDX; # our session ex_data id

# create temp file, populate it, and returna  guard and filename
sub _tmpfile($) {
   require File::Temp;
   my ($fh, $path) = File::Temp::mkstemp ("aetlspemXXXXXX");
   my $guard = AnyEvent::Util::guard { unlink $path };

   syswrite $fh, $_[0];
   close $fh;

   ($path, $guard)
}

our %DH_PARAMS = (
   # These are the DH parameters from "Assigned Number for SKIP Protocols"
   # (http://www.skip-vpn.org/spec/numbers.html).
   # (or http://web.archive.org/web/20011212141438/http://www.skip-vpn.org/spec/numbers.html#params)
   # See there for how they were generated.
   # Note that g might not be a generator,
   # but this is not a problem since p is a safe prime.
   skip512 => "MEYCQQD1Kv884bEpQBgRjXyEpwpy1obEAxnIByl6ypUM2Zafq9AKUJsCRtMIPWak|XUGfnHy9iUsiGSa6q6Jew1XpKgVfAgEC",
   skip1024 => "MIGHAoGBAPSI/VhOSdvNILSd5JEHNmszbDgNRR0PfIizHHxbLY7288kjwEPwpVsY|jY67VYy4XTjTNP18F1dDox0YbN4zISy1Kv884bEpQBgRjXyEpwpy1obEAxnIByl6|ypUM2Zafq9AKUJsCRtMIPWakXUGfnHy9iUsiGSa6q6Jew1XpL3jHAgEC",
   skip2048 => "MIIBCAKCAQEA9kJXtwh/CBdyorrWqULzBej5UxE5T7bxbrlLOCDaAadWoxTpj0BV|89AHxstDqZSt90xkhkn4DIO9ZekX1KHTUPj1WV/cdlJPPT2N286Z4VeSWc39uK50|T8X8dryDxUcwYc58yWb/Ffm7/ZFexwGq01uejaClcjrUGvC/RgBYK+X0iP1YTknb|zSC0neSRBzZrM2w4DUUdD3yIsxx8Wy2O9vPJI8BD8KVbGI2Ou1WMuF040zT9fBdX|Q6MdGGzeMyEstSr/POGxKUAYEY18hKcKctaGxAMZyAcpesqVDNmWn6vQClCbAkbT|CD1mpF1Bn5x8vYlLIhkmuquiXsNV6TILOwIBAg==",
   skip4096 => "MIICCAKCAgEA+hRyUsFN4VpJ1O8JLcCo/VWr19k3BCgJ4uk+d+KhehjdRqNDNyOQ|l/MOyQNQfWXPeGKmOmIig6Ev/nm6Nf9Z2B1h3R4hExf+zTiHnvVPeRBhjdQi81rt|Xeoh6TNrSBIKIHfUJWBh3va0TxxjQIs6IZOLeVNRLMqzeylWqMf49HsIXqbcokUS|Vt1BkvLdW48j8PPv5DsKRN3tloTxqDJGo9tKvj1Fuk74A+Xda1kNhB7KFlqMyN98|VETEJ6c7KpfOo30mnK30wqw3S8OtaIR/maYX72tGOno2ehFDkq3pnPtEbD2CScxc|alJC+EL7RPk5c/tgeTvCngvc1KZn92Y//EI7G9tPZtylj2b56sHtMftIoYJ9+ODM|sccD5Piz/rejE3Ome8EOOceUSCYAhXn8b3qvxVI1ddd1pED6FHRhFvLrZxFvBEM9|ERRMp5QqOaHJkM+Dxv8Cj6MqrCbfC4u+ZErxodzuusgDgvZiLF22uxMZbobFWyte|OvOzKGtwcTqO/1wV5gKkzu1ZVswVUQd5Gg8lJicwqRWyyNRczDDoG9jVDxmogKTH|AaqLulO7R8Ifa1SwF2DteSGVtgWEN8gDpN3RBmmPTDngyF2DHb5qmpnznwtFKdTL|KWbuHn491xNO25CQWMtem80uKw+pTnisBRF/454n1Jnhub144YRBoN8CAQI=",

   # generated on a linux desktop with openssl using /dev/urandom - entropy_avail was >= 3600 each time
   # the 8192 bit key took 25 hours to generate :/
   schmorp1024 => "MIGHAoGBAN+GjqAhNxLesSuGfDzYe6HdexXtHuxe85umshfPHfnmLSkGWl/FE27+|v+50mwY5XaNnCmo1VvGju4iTKxWoZTGgslUSc8KX197XWAXIpab8ESyg442if9Kr|vSOuu0fopwvvTOgHK8mkEWI4joU5G4/MQy+pnC5NIEVBP4HtGiTrAgEC",
   schmorp1539 => "MIHHAoHBByJzpVGUsXysX8w/+uuXRUCL9exhAixoHkaJU5lf4noJUtp9F0yr/5rb|hF8M9mSZJ+RlPyB+Zt37GPp1WQDO1+/2yZJX9kHE3+h5JCRoR8PKc2G+ts9jhM7r|CnTQ0z0b6s12Pusf+UhQPwLust4JAYE/LPuTK8yFiVx5L2a+aZhGMVlYN/12SEtY|jRl3lGXdZj9g8E2PzTQbA9CGy5dGIvz/ENTzTVleKuQ+80bzpVEPjZL9tv43Zc+l|MFLzxuE5uwIBAg==",
   schmorp2048 => "MIIBCAKCAQEAhR5Fn9h3Tgnc+q4o3CMkZtre3lLUyDT+1bf3aiVOt22JdDQndZLc|FeKz8AqliB3UIgNExc6oDtuG4znKPgklfOnHv/a9tl1AYQbV+QFM/E0jYl6oG8tF|Epgxezt1GCivvtu64ql0s213wr64QffNMt3hva8lNqK1PXfqp13PzzLzAVsfghrv|fMAX7/bYm1T5fAJdcah6FeZkKof+mqbs8HtRjfvrUF2npEM2WdupFu190vcwABnN|TTJheXCWv2BF2f9EEr61q3OUhSNWIThtZP+NKe2bACm1PebT0drAcaxKoMz9LjKr|y5onGs0TOuQ7JmhtZL45Zr4LwBcyTucLUwIBAg==",
   schmorp4096 => "MIICCAKCAgEA5WwA5lQg09YRYqc/JILCd2AfBmYBkF19wmCEJB8G3JhTxv8EGvYk|xyP2ecKVUvHTG8Xw/qpW8nRqzPIyV8QRf6YFYSf33Qnx2xYhcnqOumU3nfC0SNOL|/w2q1BA9BbHtW4574P+6hOQx9ftRtbtZ2HPKBMRcAKGjpYZiKopv0+UAM4NpEC2p|bfajp7pyVLeb/Aqm/oWP3L63wPlY1SDp+XRzrOAKB+/uLGqEwV0bBaxxGL29BpOp|O2z1ALGXiDCcLs9WTn9WqUhWDzUN6fahm53rd7zxwpFCb6K2YhaK0peG95jzSUJ8|aoL0KgWuC6v5+gPJHRu0HrQIdfAdN4VchqYOKE46uNNkQl8VJGu4RjYB7lFBpRwO|g2HCsGMo2X7BRmA1st66fh+JOd1smXMZG/2ozTOooL+ixcx4spNneg4aQerWl5cb|nWXKtPCp8yPzt/zoNzL3Fon2Ses3sNgMos0M/ZbnigScDxz84Ms6V/X8Z0L4m/qX|mL42dP40tgvmgqi6BdsBzcIWeHlEcIhmGcsEBxxKEg7gjb0OjjvatpUCJhmRrGjJ|LtMkBR68qr42OBMN/PBB4KPOWNUqTauXZajfCwYdbpvV24ZhtkcRdw1zisyARBSh|aTKW/GV8iLsUzlYN27LgVEwMwnWQaoecW6eOTNKGUURC3In6XZSvVzsCAQI=",
   schmorp8192 => "MIIECAKCBAEA/SAEbRSSLenVxoInHiltm/ztSwehGOhOiUKfzDcKlRBZHlCC9jBl|S/aeklM6Ucg8E6J2bnfoh6CAdnE/glQOn6CifhZr8X/rnlL9/eP+r9m+aiAw4l0D|MBd8BondbEqwTZthMmLtx0SslnevsFAZ1Cj8WgmUNaSPOukvJ1N7aQ98U+E99Pw3|VG8ANBydXqLqW2sogS8FtZoMbVywcQuaGmC7M6i3Akxe3CCSIpR/JkEZIytREBSC|CH+x3oW/w+wHzq3w8DGB9hqz1iMXqDMiPIMSdXC0DaIPokLnd7X8u6N14yCAco2h|P0gspD3J8pS2FpUY8ZTVjzbVCjhNNmTryBZAxHSWBuX4xYcCHUtfGlUe/IGLSVE1|xIdFpZUfvlvAJjVq0/TtDMg3r2JSXrhQVlr8MPJwSApDVr5kOBHT/uABio4z+5yR|PAvundznfyo9GGAWhIA36GQqsxSQfoRTjWssFoR/cu+9aomRwwOLkvObu8nCVVLH|nLdKDk5cIR0TvNs9HZ6ZmkzL7ah7cPzEKl7U6eE6yZLVYMNecnPLS6PSAIG4gxcq|CVQrrZjQLfTDrJn0OGgpShX85RaDsuiRtp2bpDZ23YDqdwr4wRjvIargjqc2zcF+|jIb7dUS6ci7bVG/CGOQUuiMWAiXZ3a1f343SMf9A05/sf1xwnMeco6STBLZ3X+PA|4urU+grtpWaFtS/fPD2ILn8nrJ3WuSKKUeSnVM46mmJQsOkyn7z8l3jNLB17GYKo|qc+0UuU/2PM9qtZdZElSM/ACLV2vdCuaibop4B9UIP9z3F8kfZ72+zKxpGiE+Bo1|x8SfG8FQw90mYIx+qZzJ8MCvc2wh+l4wDX5KxrhwvcouE2tHQlwfDgv/DiIXp173|hAmUCV0+bPRW8IIJvBODdAWtJe9hNwxj1FFYmPA7l4wa3gXV4I6tb+iO1MbwVjZ/|116tD5MdCo3JuSisgPYCHfkQccwEO0FHEuBbmfN+fQimQ8H0dePP8XctwbkplsB+|aLT5hYKmva/j9smEswgyHglPwc3WvZ+2DgKk7A7DHi7a2gDwCRQlHaXtNWx3992R|dfNgkSeB1CvGSQoo95WpC9ZoqGmcSlVqdetDU8iglPmfYTKO8aIPA6TuTQ/lQ0IW|90LQmqP23FwnNFiyqX8+rztLq4KVkTyeHIQwig6vFxgD8N+SbZCW2PPiB72TVF2U|WePU8MRTv1OIGBUBajF49k28HnZPSGlILHtFEkYkbPvomcE5ENnoejwzjktOTS5d|/R3SIOvCauOzadtzwTYOXT78ORaR1KI1cm8DzkkwJTd/Rrk07Q5vnvnSJQMwFUeH|PwJIgWBQf/GZ/OsDHmkbYR2ZWDClbKw2mwIBAg==",
);

=item $tls = new AnyEvent::TLS key => value...

The constructor supports these arguments (all as key => value pairs).

=over 4

=item method => "SSLv2" | "SSLv3" | "TLSv1" | "any"

The protocol parser to use. C<SSLv2>, C<SSLv3> and C<TLSv1> will use
a parser for those protocols only (so will I<not> accept or create
connections with/to other protocol versions), while C<any> (the
default) uses a parser capable of all three protocols.

The default is to use C<"any"> but disable SSLv2. This has the effect of
sending a SSLv2 hello, indicating the support for SSLv3 and TLSv1, but not
actually negotiating an (insecure) SSLv2 connection.

Specifying a specific version is almost always wrong to use for a server
speaking to a wide variety of clients (e.g. web browsers), and often wrong
for a client. If you only want to allow a specific protocol version, use
the C<sslv2>, C<sslv3> or C<tlsv1> arguments instead.

For new services it is usually a good idea to enforce a C<TLSv1> method
from the beginning.

=item sslv2 => $enabled

Enable or disable SSLv2 (normally I<disabled>).

=item sslv3 => $enabled

Enable or disable SSLv3 (normally I<enabled>).

=item tlsv1 => $enabled

Enable or disable TLSv1 (normally I<enabled>).

=item verify => $enable

Enable or disable peer certificate checking (default is I<disabled>, which
is I<not recommended>).

This is the "master switch" for all verify-related parameters and
functions.

If it is disabled, then no peer certificate verification will be done
- the connection will be encrypted, but the peer certificate won't be
verified against any known CAs, or whether it is still valid or not. No
peername verification or custom verification will be done either.

If enabled, then the peer certificate (required in client mode, optional
in server mode, see C<verify_require_client_cert>) will be checked against
its CA certificate chain - that means there must be a signing chain from
the peer certificate to any of the CA certificates you trust locally, as
specified by the C<ca_file> and/or C<ca_path> and/or C<ca_cert> parameters
(or the system default CA repository, if all of those parameters are
missing - see also the L<AnyEvent> manpage for the description of
PERL_ANYEVENT_CA_FILE).

Other basic checks, such as checking the validity period, will also be
done, as well as optional peername/hostname/common name verification
C<verify_peername>.

An optional C<verify_cb> callback can also be set, which will be invoked
with the verification results, and which can override the decision.

=item verify_require_client_cert => $enable

Enable or disable mandatory client certificates (default is
I<disabled>). When this mode is enabled, then a client certificate will be
required in server mode (a server certificate is mandatory, so in client
mode, this switch has no effect).

=item verify_peername => $scheme | $callback->($tls, $cert, $peername)

TLS only protects the data that is sent - it cannot automatically verify
that you are really talking to the right peer. The reason is that
certificates contain a "common name" (and a set of possible alternative
"names") that need to be checked against the peername (usually, but not
always, the DNS name of the server) in a protocol-dependent way.

This can be implemented by specifying a callback that has to verify that
the actual C<$peername> matches the given certificate in C<$cert>.

Since this can be rather hard to implement, AnyEvent::TLS offers a variety
of predefined "schemes" (lifted from L<IO::Socket::SSL>) that are named
like the protocols that use them:

=over 4

=item ldap (rfc4513), pop3,imap,acap (rfc2995), nntp (rfc4642)

Simple wildcards in subjectAltNames are possible, e.g. *.example.org
matches www.example.org but not lala.www.example.org. If nothing from
subjectAltNames matches, it checks against the common name, but there are
no wildcards allowed.

=item http (rfc2818)

Extended wildcards in subjectAltNames are possible, e.g. *.example.org or
even www*.example.org. Wildcards in the common name are not allowed. The
common name will be only checked if no host names are given in
subjectAltNames.

=item smtp (rfc3207)

This RFC isn't very useful in determining how to do verification so it
just assumes that subjectAltNames are possible, but no wildcards are
possible anywhere.

=item [$check_cn, $wildcards_in_alt, $wildcards_in_cn]

You can also specify a scheme yourself by using an array reference with
three integers.

C<$check_cn> specifies if and how the common name field is used: C<0>
means it will be completely ignored, C<1> means it will only be used if
no host names have been found in the subjectAltNames, and C<2> means the
common name will always be checked against the peername.

C<$wildcards_in_alt> and C<$wildcards_in_cn> specify whether and where
wildcards (C<*>) are allowed in subjectAltNames and the common name,
respectively. C<0> means no wildcards are allowed, C<1> means they
are allowed only as the first component (C<*.example.org>), and C<2>
means they can be used anywhere (C<www*.example.org>), except that very
dangerous matches will not be allowed (C<*.org> or C<*>).

=back

You can specify either the name of the parent protocol (recommended,
e.g. C<http>, C<ldap>), the protocol name as usually used in URIs
(e.g. C<https>, C<ldaps>) or the RFC (not recommended, e.g. C<rfc2995>,
C<rfc3920>).

This verification will only be done when verification is enabled (C<<
verify => 1 >>).

=item verify_cb => $callback->($tls, $ref, $cn, $depth, $preverify_ok, $x509_store_ctx, $cert)

Provide a custom peer verification callback used by TLS sessions,
which is called with the result of any other verification (C<verify>,
C<verify_peername>).

This callback will only be called when verification is enabled (C<< verify
=> 1 >>).

C<$tls> is the C<AnyEvent::TLS> object associated with the session,
while C<$ref> is whatever the user associated with the session (usually
an L<AnyEvent::Handle> object when used by AnyEvent::Handle).

C<$depth> is the current verification depth - C<$depth = 0> means the
certificate to verify is the peer certificate, higher levels are its CA
certificate and so on. In most cases, you can just return C<$preverify_ok>
if the C<$depth> is non-zero:

   verify_cb => sub {
      my ($tls, $ref, $cn, $depth, $preverify_ok, $x509_store_ctx, $cert) = @_;

      return $preverify_ok
         if $depth;

      # more verification
   },

C<$preverify_ok> is true iff the basic verification of the certificates
was successful (a valid CA chain must exist, the certificate has passed
basic validity checks, peername verification succeeded).

C<$x509_store_ctx> is the Net::SSLeay::X509_CTX> object.

C<$cert> is the C<Net::SSLeay::X509> object representing the
peer certificate, or zero if there was an error. You can call
C<AnyEvent::TLS::certname $cert> to get a nice user-readable string to
identify the certificate.

The callback must return either C<0> to indicate failure, or C<1> to
indicate success.

=item verify_client_once => $enable

Enable or disable skipping the client certificate verification on
renegotiations (default is I<disabled>, the certificate will always be
checked). Only makes sense in server mode.

=item ca_file => $path

If this parameter is specified and non-empty, it will be the path to a
file with (server) CA certificates in PEM format that will be loaded. Each
certificate will look like:

   -----BEGIN CERTIFICATE-----
   ... (CA certificate in base64 encoding) ...
   -----END CERTIFICATE-----

You have to enable verify mode (C<< verify => 1 >>) for this parameter to
have any effect.

=item ca_path => $path

If this parameter is specified and non-empty, it will be
the path to a directory with hashed CA certificate files in
PEM format. When the ca certificate is being verified, the
certificate will be hashed and looked up in that directory (see
L<http://www.openssl.org/docs/ssl/SSL_CTX_load_verify_locations.html> for
details)

The certificates specified via C<ca_file> take precedence over the ones
found in C<ca_path>.

You have to enable verify mode (C<< verify => 1 >>) for this parameter to
have any effect.

=item ca_cert => $string

In addition or instead of using C<ca_file> and/or C<ca_path>, you can
also use C<ca_cert> to directly specify the CA certificates (there can be
multiple) in PEM format, in a string.

=item check_crl => $enable

Enable or disable certificate revocation list checking. If enabled, then
peer certificates will be checked against a list of revoked certificates
issued by the CA. The revocation lists will be expected in the C<ca_path>
directory.

certificate verification will fail if this is enabled but no revocation
list was found.

This requires OpenSSL >= 0.9.7b. Check the OpenSSL documentation for more
details.

=item key_file => $path

Path to the local private key file in PEM format (might be a combined
certificate/private key file).

The local certificate is used to authenticate against the peer - servers
mandatorily need a certificate and key, clients can use a certificate and
key optionally to authenticate, e.g. for log-in purposes.

The key in the file should look similar this:

   -----BEGIN RSA PRIVATE KEY-----
   ...header data
   ... (key data in base64 encoding) ...
   -----END RSA PRIVATE KEY-----

=item key => $string

The private key string in PEM format (see C<key_file>, only one of
C<key_file> or C<key> can be specified).

The idea behind being able to specify a string is to avoid blocking in
I/O. Unfortunately, Net::SSLeay fails to implement any interface to the
needed OpenSSL functionality, this is currently implemented by writing to
a temporary file.

=item cert_file => $path

The path to the local certificate file in PEM format (might be a combined
certificate/private key file, including chained certificates).

The local certificate (and key) are used to authenticate against the
peer - servers mandatorily need a certificate and key, clients can use
certificate and key optionally to authenticate, e.g. for log-in purposes.

The certificate in the file should look like this:

   -----BEGIN CERTIFICATE-----
   ... (certificate in base64 encoding) ...
   -----END CERTIFICATE-----

If the certificate file or string contain both the certificate and
private key, then there is no need to specify a separate C<key_file> or
C<key>.

Additional signing certifiates to send to the peer (in SSLv3 and newer)
can be specified by appending them to the certificate proper: the order
must be from issuer certificate over any intermediate CA certificates to
the root CA.

So the recommended ordering for a combined key/cert/chain file, specified
via C<cert_file> or C<cert> looks like this:

  certificate private key
  client/server certificate
  ca 1, signing client/server certficate
  ca 2, signing ca 1
  ...

=item cert => $string

The local certificate in PEM format (might be a combined
certificate/private key file). See C<cert_file>.

The idea behind being able to specify a string is to avoid blocking in
I/O. Unfortunately, Net::SSLeay fails to implement any interface to the
needed OpenSSL functionality, this is currently implemented by writing to
a temporary file.

=item cert_password => $string | $callback->($tls)

The certificate password - if the certificate is password-protected, then
you can specify its password here.

Instead of providing a password directly (which is not so recommended),
you can also provide a password-query callback. The callback will be
called whenever a password is required to decode a local certificate, and
is supposed to return the password.

=item dh_file => $path

Path to a file containing Diffie-Hellman parameters in PEM format, for
use in servers. See also C<dh> on how to specify them directly, or use a
pre-generated set.

Diffie-Hellman key exchange generates temporary encryption keys that
are not transferred over the connection, which means that even if the
certificate key(s) are made public at a later time and a full dump of the
connection exists, the key still cannot be deduced.

These ciphers are only available with SSLv3 and later (which is the
default with AnyEvent::TLS), and are only used in server/accept
mode. Anonymous DH protocols are usually disabled by default, and usually
not even compiled into the underlying library, as they provide no direct
protection against man-in-the-middle attacks. The same is true for the
common practise of self-signed certificates that you have to accept first,
of course.

=item dh => $string

Specify the Diffie-Hellman parameters in PEM format directly as a string
(see C<dh_file>), the default is C<schmorp1539> unless C<dh_file> was
specified.

AnyEvent::TLS supports supports a number of precomputed DH parameters,
since computing them is expensive. They are:

   # from "Assigned Number for SKIP Protocols"
   skip512, skip1024, skip2048, skip4096

   # from schmorp
   schmorp1024, schmorp1539, schmorp2048, schmorp4096, schmorp8192

The default was chosen as a trade-off between security and speed, and
should be secure for a few years. It is said that 2048 bit DH parameters
are safe till 2030, and DH parameters shorter than 900 bits are totally
insecure.

To disable DH protocols completely, specify C<undef> as C<dh> parameter.

=item dh_single_use => $enable

Enables or disables "use only once" mode when using Diffie-Hellman key
exchange. When enabled (default), each time a new key is exchanged a new
Diffie-Hellman key is generated, which improves security as each key is
only used once. When disabled, the key will be created as soon as the
AnyEvent::TLS object is created and will be reused.

All the DH parameters supplied with AnyEvent::TLS should be safe with
C<dh_single_use> switched off, but YMMV.

=item cipher_list => $string

The list of ciphers to use, as a string (example:
C<AES:ALL:!aNULL:!eNULL:+RC4:@STRENGTH>). The format
of this string and its default value is documented at
L<http://www.openssl.org/docs/apps/ciphers.html#CIPHER_STRINGS>.

=item session_ticket => $enable

Enables or disables RC5077 support (Session Resumption without Server-Side
State). The default is disabled for clients, as many (buggy) TLS/SSL
servers choke on it, but enabled for servers.

When enabled and supported by the server, a session ticket will be
provided to the client, which allows fast resuming of connections.

=item prepare => $coderef->($tls)

If this argument is present, then it will be called with the new
AnyEvent::TLS object after any other initialisation has bee done, in case
you wish to fine-tune something...

=cut

#=item trust => $trust
#
#Sets the expected (root) certificate use on this context, i.e. what 
#certificates to trust. The default is C<compat>, and the following strings
#are supported:
#
#   compat          any certifictae will do
#   ssl_client      only trust client certificates
#   ssl_server      only trust server certificates
#   email           only trust e-mail certificates
#   object_sign     only trust signing (CA) certificates
#   ocsp_sign       only trust ocsp signing certs
#   ocsp_request    only trust ocsp request certs

# purpose?

#TODO
# verify_depth?
# reuse_ctx
# session_cache_size
# session_cache

#=item debug => $level
#
#Enable or disable sending debugging output to STDERR. This is, as
#the name says, mostly for debugging. The default is taken from the
#C<PERL_ANYEVENT_TLS_DEBUG> environment variable.
#
#=cut

=back

=cut

sub init ();

#our %X509_TRUST = (
#   compat       => 1,
#   ssl_client   => 2,
#   ssl_server   => 3,
#   email        => 4,
#   object_sign  => 5,
#   ocsp_sign    => 6,
#   ocsp_request => 7,
#);

sub new {
   my ($class, %arg) = @_;

   init unless $REF_IDX;

   my $method = lc $arg{method} || "any";

   my $ctx = $method eq "any"    ? Net::SSLeay::CTX_new       ()
           : $method eq "sslv23" ? Net::SSLeay::CTX_new       () # deliberately undocumented
           : $method eq "sslv2"  ? Net::SSLeay::CTX_v2_new    ()
           : $method eq "sslv3"  ? Net::SSLeay::CTX_v3_new    ()
           : $method eq "tlsv1"  ? Net::SSLeay::CTX_tlsv1_new ()
           : croak "'$method' is not a valid AnyEvent::TLS method (must be one of SSLv2, SSLv3, TLSv1 or any)";

   my $self = bless { ctx => $ctx }, $class; # to make sure it's destroyed if we croak

   my $op = Net::SSLeay::OP_ALL ();

   $op |= Net::SSLeay::OP_NO_SSLv2      () unless $arg{sslv2};
   $op |= Net::SSLeay::OP_NO_SSLv3      () if exists $arg{sslv3} && !$arg{sslv3};
   $op |= Net::SSLeay::OP_NO_TLSv1      () if exists $arg{tlsv1} && !$arg{tlsv1};
   $op |= Net::SSLeay::OP_SINGLE_DH_USE () if !exists $arg{dh_single_use} || $arg{dh_single_use};

   Net::SSLeay::CTX_set_options ($ctx, $op);

   Net::SSLeay::CTX_set_cipher_list ($ctx, $arg{cipher_list})
      or croak "'$arg{cipher_list}' was not accepted as a valid cipher list by AnyEvent::TLS"
         if exists $arg{cipher_list};

   my ($dh_bio, $dh_file);

   if (exists $arg{dh_file}) {
      croak

      $dh_file = $arg{dh_file};

      $dh_bio = Net::SSLeay::BIO_new_file ($dh_file, "r")
         or croak "$dh_file: failed to open DH parameter file: $!";
   } else {
      $arg{dh} = "schmorp1539" unless exists $arg{dh};

      if (defined $arg{dh}) {
         $dh_file = "dh string";

         if ($arg{dh} =~ /^\w+$/) {
            $dh_file = "dh params $arg{dh}";
            $arg{dh} = "-----BEGIN DH PARAMETERS-----\n"
                     . $DH_PARAMS{$arg{dh}} . "\n"
                     . "-----END DH PARAMETERS-----";
            $arg{dh} =~ s/\|/\n/g;
         }

         $dh_bio = Net::SSLeay::BIO_new (Net::SSLeay::BIO_s_mem ());
         Net::SSLeay::BIO_write ($dh_bio, $arg{dh});
      }
   }

   if ($dh_bio) {
      my $dh = Net::SSLeay::PEM_read_bio_DHparams ($dh_bio);
      Net::SSLeay::BIO_free ($dh_bio);
      $dh or croak "$dh_file: failed to parse DH parameters - not PEM format?";
      my $rv = Net::SSLeay::CTX_set_tmp_dh ($ctx, $dh);
      Net::SSLeay::DH_free ($dh);
      $rv or croak "$dh_file: failed to set DH parameters";
   }

   if ($arg{verify}) {
      $self->{verify_mode} = Net::SSLeay::VERIFY_PEER ();

      $self->{verify_mode} |= Net::SSLeay::VERIFY_FAIL_IF_NO_PEER_CERT ()
         if $arg{verify_require_client_cert};

      $self->{verify_mode} |= Net::SSLeay::VERIFY_CLIENT_ONCE ()
         if $arg{verify_client_once};

   } else {
      $self->{verify_mode} = Net::SSLeay::VERIFY_NONE ();
   }

   $self->{verify_peername} = $arg{verify_peername}
      if exists $arg{verify_peername};

   $self->{verify_cb} = $arg{verify_cb}
      if exists $arg{verify_cb};

   $self->{session_ticket} = $arg{session_ticket}
      if exists $arg{session_ticket};

   $self->{debug} = $ENV{PERL_ANYEVENT_TLS_DEBUG}
      if exists $ENV{PERL_ANYEVENT_TLS_DEBUG};

   $self->{debug} = $arg{debug}
      if exists $arg{debug};

   my $pw = $arg{cert_password};
   Net::SSLeay::CTX_set_default_passwd_cb ($ctx, ref $pw ? $pw : sub { $pw });

   if ($self->{verify_mode}) {
      if (exists $arg{ca_file} or exists $arg{ca_path} or exists $arg{ca_cert}) {
         # either specified: use them
         if (exists $arg{ca_cert}) {
            my ($ca_file, $g1) = _tmpfile delete $arg{ca_cert};
            Net::SSLeay::CTX_load_verify_locations ($ctx, $ca_file, undef);
         }
         if (exists $arg{ca_file} or exists $arg{ca_path}) {
            Net::SSLeay::CTX_load_verify_locations ($ctx, $arg{ca_file}, $arg{ca_path});
         }
      } elsif (exists $ENV{PERL_ANYEVENT_CA_FILE} or exists $ENV{PERL_ANYEVENT_CA_PATH}) {
         Net::SSLeay::CTX_load_verify_locations (
            $ctx,
            $ENV{PERL_ANYEVENT_CA_FILE},
            $ENV{PERL_ANYEVENT_CA_PATH},
         );
      } else {
         # else fall back to defaults
         Net::SSLeay::CTX_set_default_verify_paths ($ctx);
      }
   }

   if (exists $arg{cert} or exists $arg{cert_file}) {
      my ($g1, $g2);

      if (exists $arg{cert}) {
         croak "specifying both cert_file and cert is not allowed"
            if exists $arg{cert_file};

        ($arg{cert_file}, $g1) = _tmpfile delete $arg{cert};
      }

      if (exists $arg{key} or exists $arg{key_file}) {
         if (exists $arg{key}) {
            croak "specifying both key_file and key is not allowed"
               if exists $arg{cert_file};
           ($arg{key_file}, $g2) = _tmpfile delete $arg{key};
         }
      } else {
         $arg{key_file} = $arg{cert_file};
      }

      Net::SSLeay::CTX_use_PrivateKey_file
            ($ctx, $arg{key_file}, Net::SSLeay::FILETYPE_PEM ())
         or croak "$arg{key_file}: failed to load local private key (key_file or key)";

      Net::SSLeay::CTX_use_certificate_chain_file ($ctx, $arg{cert_file})
         or croak "$arg{cert_file}: failed to use local certificate chain (cert_file or cert)";
   }

   if ($arg{check_crl}) {
      Net::SSLeay::OPENSSL_VERSION_NUMBER () >= 0x00090702f
         or croak "check_crl requires openssl v0.9.7b or higher";

      Net::SSLeay::X509_STORE_set_flags (
         Net::SSLeay::CTX_get_cert_store ($ctx),
         Net::SSLeay::X509_V_FLAG_CRL_CHECK ());
   }

   Net::SSLeay::CTX_set_read_ahead ($ctx, 1);

   $arg{prepare}->($self)
      if $arg{prepare};

   $self
}

=item $tls = new_from_ssleay AnyEvent::TLS $ctx

This constructor takes an existing L<Net::SSLeay> SSL_CTX object
(which is just an integer) and converts it into an C<AnyEvent::TLS>
object. This only works because AnyEvent::TLS is currently implemented
using Net::SSLeay. As this is such a horrible perl module and OpenSSL has
such an annoying license, this might change in the future, in which case
this method might vanish.

=cut

sub new_from_ssleay {
   my ($class, $ctx) = @_;

   bless { ctx => $ctx }, $class
}

=item $ctx = $tls->ctx

Returns the actual L<Net::SSLeay::CTX> object (just an integer).

=cut

sub ctx {
   $_[0]{ctx}
}

sub verify_hostname($$$);

sub _verify_hostname {
   my ($self, $cn, $cert) = @_;
   
   return 1
      unless defined $cn;

   return 1
      unless exists $self->{verify_peername} && "none" ne lc $self->{verify_peername};

   return $self->{verify_peername}->($self, $cn, $cert)
      if ref $self->{verify_peername} && "ARRAY" ne ref $self->{verify_peername};

   verify_hostname $cn, $cert, $self->{verify_peername}
}

sub verify {
   my ($self, $session, $ref, $cn, $preverify_ok, $x509_store_ctx) = @_;

   my $cert = $x509_store_ctx
      ? Net::SSLeay::X509_STORE_CTX_get_current_cert ($x509_store_ctx)
      : undef;
   my $depth = Net::SSLeay::X509_STORE_CTX_get_error_depth ($x509_store_ctx);

   $preverify_ok &&= $self->_verify_hostname ($cn, $cert)
      unless $depth;

   $preverify_ok = $self->{verify_cb}->($self, $ref, $cn, $depth, $preverify_ok, $x509_store_ctx, $cert)
      if $self->{verify_cb};

   $preverify_ok
}

#=item $ssl = $tls->_get_session ($mode[, $ref])
#
#Creates a new Net::SSLeay::SSL session object, puts it into C<$mode>
#(C<accept> or C<connect>) and optionally associates it with the given
#C<$ref>. If C<$mode> is already a C<Net::SSLeay::SSL> object, then just
#associate data with it.
#
#=cut

#our %REF_MAP;

sub _get_session($$;$$) {
   my ($self, $mode, $ref, $cn) = @_;

   my $session;

   if ($mode eq "accept") {
      $session = Net::SSLeay::new ($self->{ctx});
      Net::SSLeay::set_accept_state ($session);

      Net::SSLeay::set_options ($session, eval { Net::SSLeay::OP_NO_TICKET () })
         unless $self->{session_ticket} || !exists $self->{session_ticket};

   } elsif ($mode eq "connect") {
      $session = Net::SSLeay::new ($self->{ctx});
      Net::SSLeay::set_connect_state ($session);

      Net::SSLeay::set_options ($session, eval { Net::SSLeay::OP_NO_TICKET () })
         unless $self->{session_ticket};
   } else {
      croak "'$mode': unsupported TLS mode (must be either 'connect' or 'accept')"
   }

#   # associate data
#   Net::SSLeay::set_ex_data ($session, $REF_IDX, $ref+0);
#   Scalar::Util::weaken ($REF_MAP{$ref+0} = $ref)
#      if ref $ref;
   
   if ($self->{debug}) {
      #d# Net::SSLeay::set_info_callback ($session, 50000);
   }

   if ($self->{verify_mode}) {
      Scalar::Util::weaken $self;
      Scalar::Util::weaken $ref;

      # we have to provide a dummy callbacks as at least Net::SSLeay <= 1.35
      # try to call it even if specified as 0 or undef.
      Net::SSLeay::set_verify
         $session,
         $self->{verify_mode},
         sub { $self->verify ($session, $ref, $cn, @_) };
   }

   $session
}

sub _put_session($$) {
   my ($self, $session) = @_;

   # clear callback, if any
   # this leaks memoryin Net::SSLeay up to at least 1.35, but there
   # apparently is no other way.
   Net::SSLeay::set_verify $session, 0, undef;

#   # disassociate data
#   delete $REF_MAP{Net::SSLeay::get_ex_data ($session, $REF_IDX)};

   Net::SSLeay::free ($session);
}

#sub _ref($) {
#   $REF_MAP{Net::SSLeay::get_ex_data ($_[0], $REF_IDX)}
#}

sub DESTROY {
   my ($self) = @_;

   # better be safe than sorry with net-ssleay
   Net::SSLeay::CTX_set_default_passwd_cb ($self->{ctx});

   Net::SSLeay::CTX_free ($self->{ctx});
}

=item AnyEvent::TLS::init

AnyEvent::TLS does on-demand initialisation, and normally there is no need to call an initialise
function.

As initialisation might take some time (to read e.g. C</dev/urandom>), this
could be annoying in some highly interactive programs. In that case, you can
call C<AnyEvent::TLS::init> to make sure there will be no costly initialisation
later. It is harmless to call C<AnyEvent::TLS::init> multiple times.

=cut

sub init() {
   return if $REF_IDX;

   warn "AnyEvent::TLS: Net::SSLeay versions older than 1.33 might malfunction.\n"
      if $AnyEvent::VERBOSE && $Net::SSLeay::VERSION < 1.33;

   Net::SSLeay::load_error_strings ();
   Net::SSLeay::SSLeay_add_ssl_algorithms ();
   Net::SSLeay::randomize ();

   $REF_IDX = Net::SSLeay::get_ex_new_index (0, 0, 0, 0, 0)
      until $REF_IDX; # Net::SSLeay uses id #0 for it's own stuff without allocating it
}

=item $certname = AnyEvent::TLS::certname $x509

Utility function that returns a user-readable string identifying the X509
certificate object.

=cut

sub certname {
   $_[0]
      ? Net::SSLeay::X509_NAME_oneline (Net::SSLeay::X509_get_issuer_name ($_[0]))
        . Net::SSLeay::X509_NAME_oneline (Net::SSLeay::X509_get_subject_name ($_[0]))
      : undef
}

our %CN_SCHEME = (
   # each tuple is [$cn_wildcards, $alt_wildcards, $check_cn]
   # where *_wildcards is 0 for none allowed, 1 for allowed at beginning and 2 for allowed everywhere
   # and check_cn is 0 for do not check, 1 for check when no alternate dns names and 2 always
   # all of this is from IO::Socket::SSL

   rfc4513 => [0, 1, 2],
   rfc2818 => [0, 2, 1],
   rfc3207 => [0, 0, 2], # see IO::Socket::SSL, rfc seems unclear
   none    => [],        # do not check

   ldap    => "rfc4513",                    ldaps => "ldap",
   http    => "rfc2818",                    https => "http",
   smtp    => "rfc3207",                    smtps => "smtp",

   xmpp    => "rfc3920", rfc3920 => "http",
   pop3    => "rfc2595", rfc2595 => "ldap", pop3s => "pop3",
   imap    => "rfc2595", rfc2595 => "ldap", imaps => "imap",
   acap    => "rfc2595", rfc2595 => "ldap",
   nntp    => "rfc4642", rfc4642 => "ldap", nntps => "nntp",
   ftp     => "rfc4217", rfc4217 => "http", ftps  => "ftp" ,
);

sub match_cn($$$) {
   my ($name, $cn, $type) = @_;

   # remove leading and trailing garbage
   for ($name, $cn) {
      s/[\x00-\x1f]+$//;
      s/^[\x00-\x1f]+//;
   }

   my $pattern;

   ### IMPORTANT!
   # we accept only a single wildcard and only for a single part of the FQDN
   # e.g *.example.org does match www.example.org but not bla.www.example.org
   # The RFCs are in this regard unspecific but we don't want to have to
   # deal with certificates like *.com, *.co.uk or even *
   # see also http://nils.toedtmann.net/pub/subjectAltName.txt
   if ($type == 2 and $name =~m{^([^.]*)\*(.+)} ) {
      $pattern = qr{^\Q$1\E[^.]*\Q$2\E$}i;
   } elsif ($type == 1 and $name =~m{^\*(\..+)$} ) {
      $pattern = qr{^[^.]*\Q$1\E$}i;
   } else {
      $pattern = qr{^\Q$name\E$}i;
   }

   $cn =~ $pattern
}

# taken verbatim from IO::Socket::SSL, then changed to take advantage of
# AnyEvent utilities.
sub verify_hostname($$$) {
   my ($cn, $cert, $scheme) = @_;

   while (!ref $scheme) {
      $scheme = $CN_SCHEME{$scheme}
         or return 1;
   }

   my $cert_cn =
      Net::SSLeay::X509_NAME_get_text_by_NID (
         Net::SSLeay::X509_get_subject_name ($cert), Net::SSLeay::NID_commonName ());

   my @cert_alt = Net::SSLeay::X509_get_subjectAltNames ($cert);

   # rfc2460 - convert to network byte order
   my $ip = AnyEvent::Socket::parse_address $cn;

   my $alt_dns_count;

   while (my ($type, $name) = splice @cert_alt, 0, 2) {
      if ($type == Net::SSLeay::GEN_IPADD ()) {
         # $name is already packed format (inet_xton)
         return 1 if $ip eq $name;
      } elsif ($type == Net::SSLeay::GEN_DNS ()) {
         $alt_dns_count++;

         return 1 if match_cn $name, $cn, $scheme->[1];
      }
   }

   if ($scheme->[2] == 2
       || ($scheme->[2] == 1 && !$alt_dns_count)) {
      return 1 if match_cn $cert_cn, $cn, $scheme->[0];
   }

   0
}

=back

=head1 SSL/TLS QUICK FACTS

Here are some quick facts about TLS/SSL that might help you:

=over 4

=item * A certificate is the public key part, a key is the private key part.

While not strictly true, certificates are the things you can hand around
publicly as a kind of identity, while keys should really be kept private,
as proving that you have the private key is usually interpreted as being
the entity behind the certificate.

=item * A certificate is signed by a CA (Certificate Authority).

By signing, the CA basically claims that the certificate it signs
really belongs to the identity named in it, verified according to the
CA policies. For e.g. HTTPS, the CA usually makes some checks that the
hostname mentioned in the certificate really belongs to the company/person
that requested the signing and owns the domain.

=item * CAs can be certified by other CAs.

Or by themselves - a certificate that is signed by a CA that is itself
is called a self-signed certificate, a trust chain of length zero. When
you find a certificate signed by another CA, which is in turn signed by
another CA you trust, you have a trust chain of depth two.

=item * "Trusting" a CA means trusting all certificates it has signed.

If you "trust" a CA certificate, then all certificates signed by it are
automatically considered trusted as well.

=item * A successfully verified certificate means that you can be
reasonably sure that whoever you are talking with really is who he claims
he is.

By verifying certificates against a number of CAs that you trust (meaning
it is signed directly or indirectly by such a CA), you can find out that
the other side really is whoever he claims, according to the CA policies,
and your belief in the integrity of the CA.

=item * Verifying the certificate signature is not everything.

Even when the certificate is correct, it might belong to somebody else: if
www.attacker.com can make your computer believe that it is really called
www.mybank.com (by making your DNS server believe this for example),
then it could send you the certificate for www.attacker.com that your
software trusts because it is signed by a CA you trust, and intercept
all your traffic that you think goes to www.mybank.com. This works
because your software sees that the certificate is correctly signed (for
www.attacker.com) and you think you are talking to your bank.

To thwart this attack vector, peername verification should be used, which
basically checks that the certificate (for www.attacker.com) really
belongs to the host you are trying to talk to (www.mybank.com), which in
this example is not the case, as www.attacker.com (from the certificate)
doesn't match www.mybank.com (the hostname used to create the connection).

So peername verification is almost as important as checking the CA
signing. Unfortunately, every protocol implements this differently, if at
all...

=item * Switching off verification is sometimes reasonable.

You can switch off verification. You still get an encrypted connection
that is protected against eavesdropping and injection - you just lose
protection against man in the middle attacks, i.e. somebody else with
enough abilities to to intercept all traffic can masquerade herself as the
other side.

For many applications, switching off verification is entirely
reasonable. Downloading random stuff from websites using HTTPS for no
reason is such an application. Talking to your bank and entering TANs is
not such an application.

=item * A SSL/TLS server always needs a certificate/key pair to operate,
for clients this is optional.

Apart from (usually disabled) anonymous cipher suites, a server always
needs a certificate/key pair to operate.

Clients almost never use certificates, but if they do, they can be used
to authenticate the client, just as server certificates can be used to
authenticate the server.

=item * SSL version 2 is very insecure.

SSL version 2 is old and not only has it some security issues, SSLv2-only
implementations are usually buggy, too, due to their age.

=item * Sometimes, even losing your "private" key might not expose all your
data.

With Diffie-Hellman ephemeral key exchange, you can lose the DH parameters
(the "keys"), but all your connections are still protected. Diffie-Hellman
needs special set-up (done by default by AnyEvent::TLS).

=back

=head1 BUGS

To to the abysmal code quality of Net::SSLeay, this module will leak small
amounts of memory per TLS connection (currently at least one perl scalar).

=head1 AUTHORS

Marc Lehmann <schmorp@schmorp.de>.

Some of the API, documentation and implementation (verify_hostname),
and a lot of ideas/workarounds/knowledge have been taken from the
L<IO::Socket::SSL> module. Care has been taken to keep the API similar to
that and other modules, to the extent possible while providing a sensible
API for AnyEvent.

=cut

1

