=head1 NAME

AnyEvent::DNS - fully asynchronous DNS resolution

=head1 SYNOPSIS

   use AnyEvent::DNS;
   
   my $cv = AnyEvent->condvar;
   AnyEvent::DNS::a "www.google.de", $cv;
   # ... later
   my @addrs = $cv->recv;

=head1 DESCRIPTION

This module offers both a number of DNS convenience functions as well
as a fully asynchronous and high-performance pure-perl stub resolver.

The stub resolver supports DNS over IPv4 and IPv6, UDP and TCP, optional
EDNS0 support for up to 4kiB datagrams and automatically falls back to
virtual circuit mode for large responses.

=head2 CONVENIENCE FUNCTIONS

=over 4

=cut

package AnyEvent::DNS;

use Carp ();
use Socket qw(AF_INET SOCK_DGRAM SOCK_STREAM);

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use AnyEvent::Util qw(AF_INET6);

our $VERSION = $AnyEvent::VERSION;
our @DNS_FALLBACK; # some public dns servers as fallback

{
   my $prep = sub {
      $_ = $_->[rand @$_] for @_;
      push @_, splice @_, rand $_, 1 for reverse 1..@_; # shuffle
      $_ = pack "H*", $_ for @_;
      \@_
   };

   my $ipv4 = $prep->(
      ["08080808", "08080404"], # 8.8.8.8, 8.8.4.4 - google public dns
      ["01010101", "01000001"], # 1.1.1.1, 1.0.0.1 - cloudflare public dns
      ["50505050", "50505151"], # 80.80.80.80, 80.80.81.81 - freenom.world
##      ["d1f40003", "d1f30004"], # v209.244.0.3/4 - resolver1/2.level3.net - status unknown
##      ["04020201", "04020203", "04020204", "04020205", "04020206"], # v4.2.2.1/3/4/5/6 - vnsc-pri.sys.gtei.net - effectively public
##      ["cdd22ad2", "4044c8c8"], # 205.210.42.205, 64.68.200.200 - cache1/2.dnsresolvers.com - verified public
#      ["8d010101"], # 141.1.1.1 - cable&wireless, now vodafone - status unknown
# 84.200.69.80      # dns.watch
# 84.200.70.40      # dns.watch
# 37.235.1.174      # freedns.zone
# 37.235.1.177      # freedns.zone
# 213.73.91.35      # dnscache.berlin.ccc.de
# 194.150.168.168   # dns.as250.net; Berlin/Frankfurt
# 85.214.20.141     # FoeBud (digitalcourage.de)
# 77.109.148.136    # privacyfoundation.ch
# 77.109.148.137    # privacyfoundation.ch
# 91.239.100.100    # anycast.censurfridns.dk
# 89.233.43.71      # ns1.censurfridns.dk
# 204.152.184.76    # f.6to4-servers.net, ISC, USA
   );

   my $ipv6 = $prep->(
      ["20014860486000000000000000008888", "20014860486000000000000000008844"], # 2001:4860:4860::8888/8844 - google ipv6
      ["26064700470000000000000000001111", "26064700470000000000000000001001"], # 2606:4700:4700::1111/1001 - cloudflare dns
   );

   undef $ipv4 unless $AnyEvent::PROTOCOL{ipv4};
   undef $ipv6 unless $AnyEvent::PROTOCOL{ipv6};

   ($ipv6, $ipv4) = ($ipv4, $ipv6)
      if $AnyEvent::PROTOCOL{ipv6} > $AnyEvent::PROTOCOL{ipv4};

   @DNS_FALLBACK = (@$ipv4, @$ipv6);
}

=item AnyEvent::DNS::a $domain, $cb->(@addrs)

Tries to resolve the given domain to IPv4 address(es).

=item AnyEvent::DNS::aaaa $domain, $cb->(@addrs)

Tries to resolve the given domain to IPv6 address(es).

=item AnyEvent::DNS::mx $domain, $cb->(@hostnames)

Tries to resolve the given domain into a sorted (lower preference value
first) list of domain names.

=item AnyEvent::DNS::ns $domain, $cb->(@hostnames)

Tries to resolve the given domain name into a list of name servers.

=item AnyEvent::DNS::txt $domain, $cb->(@hostnames)

Tries to resolve the given domain name into a list of text records. Only
the first text string per record will be returned. If you want all
strings, you need to call the resolver manually:

   resolver->resolve ($domain => "txt", sub {
      for my $record (@_) {
         my (undef, undef, undef, @txt) = @$record;
         # strings now in @txt
      }
   });

=item AnyEvent::DNS::srv $service, $proto, $domain, $cb->(@srv_rr)

Tries to resolve the given service, protocol and domain name into a list
of service records.

Each C<$srv_rr> is an array reference with the following contents:
C<[$priority, $weight, $transport, $target]>.

They will be sorted with lowest priority first, then randomly
distributed by weight as per RFC 2782.

Example:

   AnyEvent::DNS::srv "sip", "udp", "schmorp.de", sub { ...
   # @_ = ( [10, 10, 5060, "sip1.schmorp.de" ] )

=item AnyEvent::DNS::any $domain, $cb->(@rrs)

Tries to resolve the given domain and passes all resource records found
to the callback. Note that this uses a DNS C<ANY> query, which, as of RFC
8482, are officially deprecated.

=item AnyEvent::DNS::ptr $domain, $cb->(@hostnames)

Tries to make a PTR lookup on the given domain. See C<reverse_lookup>
and C<reverse_verify> if you want to resolve an IP address to a hostname
instead.

=item AnyEvent::DNS::reverse_lookup $ipv4_or_6, $cb->(@hostnames)

Tries to reverse-resolve the given IPv4 or IPv6 address (in textual form)
into its hostname(s). Handles V4MAPPED and V4COMPAT IPv6 addresses
transparently.

=item AnyEvent::DNS::reverse_verify $ipv4_or_6, $cb->(@hostnames)

The same as C<reverse_lookup>, but does forward-lookups to verify that
the resolved hostnames indeed point to the address, which makes spoofing
harder.

If you want to resolve an address into a hostname, this is the preferred
method: The DNS records could still change, but at least this function
verified that the hostname, at one point in the past, pointed at the IP
address you originally resolved.

Example:

   AnyEvent::DNS::reverse_verify "2001:500:2f::f", sub { print shift };
   # => f.root-servers.net

=cut

sub MAX_PKT() { 4096 } # max packet size we advertise and accept

sub DOMAIN_PORT() { 53 } # if this changes drop me a note

sub resolver ();

sub a($$) {
   my ($domain, $cb) = @_;

   resolver->resolve ($domain => "a", sub {
      $cb->(map $_->[4], @_);
   });
}

sub aaaa($$) {
   my ($domain, $cb) = @_;

   resolver->resolve ($domain => "aaaa", sub {
      $cb->(map $_->[4], @_);
   });
}

sub mx($$) {
   my ($domain, $cb) = @_;

   resolver->resolve ($domain => "mx", sub {
      $cb->(map $_->[5], sort { $a->[4] <=> $b->[4] } @_);
   });
}

sub ns($$) {
   my ($domain, $cb) = @_;

   resolver->resolve ($domain => "ns", sub {
      $cb->(map $_->[4], @_);
   });
}

sub txt($$) {
   my ($domain, $cb) = @_;

   resolver->resolve ($domain => "txt", sub {
      $cb->(map $_->[4], @_);
   });
}

sub srv($$$$) {
   my ($service, $proto, $domain, $cb) = @_;

   # todo, ask for any and check glue records
   resolver->resolve ("_$service._$proto.$domain" => "srv", sub {
      my @res;

      # classify by priority
      my %pri;
      push @{ $pri{$_->[4]} }, [ @$_[4,5,6,7] ]
         for @_;

      # order by priority
      for my $pri (sort { $a <=> $b } keys %pri) {
         # order by weight
         my @rr = sort { $a->[1] <=> $b->[1] } @{ delete $pri{$pri} };

         my $sum; $sum += $_->[1] for @rr;

         while (@rr) {
            my $w = int rand $sum + 1;
            for (0 .. $#rr) {
               if (($w -= $rr[$_][1]) <= 0) {
                  $sum -= $rr[$_][1];
                  push @res, splice @rr, $_, 1, ();
                  last;
               }
            }
         }
      }

      $cb->(@res);
   });
}

sub ptr($$) {
   my ($domain, $cb) = @_;

   resolver->resolve ($domain => "ptr", sub {
      $cb->(map $_->[4], @_);
   });
}

sub any($$) {
   my ($domain, $cb) = @_;

   resolver->resolve ($domain => "*", $cb);
}

# convert textual ip address into reverse lookup form
sub _munge_ptr($) {
   my $ipn = $_[0]
      or return;

   my $ptr;

   my $af = AnyEvent::Socket::address_family ($ipn);

   if ($af == AF_INET6) {
      $ipn = substr $ipn, 0, 16; # anticipate future expansion

      # handle v4mapped and v4compat
      if ($ipn =~ s/^\x00{10}(?:\xff\xff|\x00\x00)//) {
         $af = AF_INET;
      } else {
         $ptr = join ".", (reverse split //, unpack "H32", $ipn), "ip6.arpa.";
      }
   }

   if ($af == AF_INET) {
      $ptr = join ".", (reverse unpack "C4", $ipn), "in-addr.arpa.";
   }

   $ptr
}

sub reverse_lookup($$) {
   my ($ip, $cb) = @_;

   $ip = _munge_ptr AnyEvent::Socket::parse_address ($ip)
      or return $cb->();

   resolver->resolve ($ip => "ptr", sub {
      $cb->(map $_->[4], @_);
   });
}

sub reverse_verify($$) {
   my ($ip, $cb) = @_;
   
   my $ipn = AnyEvent::Socket::parse_address ($ip)
      or return $cb->();

   my $af = AnyEvent::Socket::address_family ($ipn);

   my @res;
   my $cnt;

   my $ptr = _munge_ptr $ipn
      or return $cb->();

   $ip = AnyEvent::Socket::format_address ($ipn); # normalise into the same form

   ptr $ptr, sub {
      for my $name (@_) {
         ++$cnt;
         
         # () around AF_INET to work around bug in 5.8
         resolver->resolve ("$name." => ($af == (AF_INET) ? "a" : "aaaa"), sub {
            for (@_) {
               push @res, $name
                  if $_->[4] eq $ip;
            }
            $cb->(@res) unless --$cnt;
         });
      }

      $cb->() unless $cnt;
   };
}

#################################################################################

=back

=head2 LOW-LEVEL DNS EN-/DECODING FUNCTIONS

=over 4

=item $AnyEvent::DNS::EDNS0

This variable decides whether dns_pack automatically enables EDNS0
support. By default, this is disabled (C<0>), unless overridden by
C<$ENV{PERL_ANYEVENT_EDNS0}>, but when set to C<1>, AnyEvent::DNS will use
EDNS0 in all requests.

=cut

our $EDNS0 = $ENV{PERL_ANYEVENT_EDNS0}*1; # set to 1 to enable (partial) edns0

our %opcode_id = (
   query  => 0,
   iquery => 1,
   status => 2,
   notify => 4,
   update => 5,
   map +($_ => $_), 3, 6..15
);

our %opcode_str = reverse %opcode_id;

our %rcode_id = (
   noerror  =>  0,
   formerr  =>  1,
   servfail =>  2,
   nxdomain =>  3,
   notimp   =>  4,
   refused  =>  5,
   yxdomain =>  6, # Name Exists when it should not     [RFC 2136]
   yxrrset  =>  7, # RR Set Exists when it should not   [RFC 2136]
   nxrrset  =>  8, # RR Set that should exist does not  [RFC 2136]
   notauth  =>  9, # Server Not Authoritative for zone  [RFC 2136]
   notzone  => 10, # Name not contained in zone         [RFC 2136]
# EDNS0  16    BADVERS   Bad OPT Version                    [RFC 2671]
# EDNS0  16    BADSIG    TSIG Signature Failure             [RFC 2845]
# EDNS0  17    BADKEY    Key not recognized                 [RFC 2845]
# EDNS0  18    BADTIME   Signature out of time window       [RFC 2845]
# EDNS0  19    BADMODE   Bad TKEY Mode                      [RFC 2930]
# EDNS0  20    BADNAME   Duplicate key name                 [RFC 2930]
# EDNS0  21    BADALG    Algorithm not supported            [RFC 2930]
   map +($_ => $_), 11..15
);

our %rcode_str = reverse %rcode_id;

our %type_id = (
   a     =>   1,
   ns    =>   2,
   md    =>   3,
   mf    =>   4,
   cname =>   5,
   soa   =>   6,
   mb    =>   7,
   mg    =>   8,
   mr    =>   9,
   null  =>  10,
   wks   =>  11,
   ptr   =>  12,
   hinfo =>  13,
   minfo =>  14,
   mx    =>  15,
   txt   =>  16,
   sig   =>  24,
   key   =>  25,
   gpos  =>  27, # rfc1712
   aaaa  =>  28,
   loc   =>  29, # rfc1876
   srv   =>  33,
   naptr =>  35, # rfc2915
   dname =>  39, # rfc2672
   opt   =>  41,
   ds    =>  43, # rfc4034
   sshfp =>  44, # rfc4255
   rrsig =>  46, # rfc4034
   nsec  =>  47, # rfc4034
   dnskey=>  48, # rfc4034
   smimea=>  53, # rfc8162
   cds   =>  59, # rfc7344
   cdnskey=> 60, # rfc7344
   openpgpkey=> 61, # rfc7926
   csync =>  62, # rfc7929
   spf   =>  99,
   tkey  => 249,
   tsig  => 250,
   ixfr  => 251,
   axfr  => 252,
   mailb => 253,
   "*"   => 255,
   uri   => 256,
   caa   => 257, # rfc6844
);

our %type_str = reverse %type_id;

our %class_id = (
   in   =>   1,
   ch   =>   3,
   hs   =>   4,
   none => 254,
   "*"  => 255,
);

our %class_str = reverse %class_id;

sub _enc_name($) {
   pack "(C/a*)*", (split /\./, shift), ""
}

if ($] < 5.008) {
   # special slower 5.6 version
   *_enc_name = sub ($) {
      join "", map +(pack "C/a*", $_), (split /\./, shift), ""
   };
}

sub _enc_qd() {
   (_enc_name $_->[0]) . pack "nn",
     ($_->[1] > 0 ? $_->[1] : $type_id {$_->[1]}),
     ($_->[3] > 0 ? $_->[2] : $class_id{$_->[2] || "in"})
}

sub _enc_rr() {
   die "encoding of resource records is not supported";
}

=item $pkt = AnyEvent::DNS::dns_pack $dns

Packs a perl data structure into a DNS packet. Reading RFC 1035 is strongly
recommended, then everything will be totally clear. Or maybe not.

Resource records are not yet encodable.

Examples:

   # very simple request, using lots of default values:
   { rd => 1, qd => [ [ "host.domain", "a"] ] }
  
   # more complex example, showing how flags etc. are named:
  
   {
      id => 10000,
      op => "query",
      rc => "nxdomain",
  
      # flags
      qr => 1,
      aa => 0,
      tc => 0,
      rd => 0,
      ra => 0,
      ad => 0,
      cd => 0,
  
      qd => [@rr], # query section
      an => [@rr], # answer section
      ns => [@rr], # authority section
      ar => [@rr], # additional records section
   }

=cut

sub dns_pack($) {
   my ($req) = @_;

   pack "nn nnnn a* a* a* a* a*",
      $req->{id},

      ! !$req->{qr}   * 0x8000
      + $opcode_id{$req->{op}} * 0x0800
      + ! !$req->{aa} * 0x0400
      + ! !$req->{tc} * 0x0200
      + ! !$req->{rd} * 0x0100
      + ! !$req->{ra} * 0x0080
      + ! !$req->{ad} * 0x0020
      + ! !$req->{cd} * 0x0010
      + $rcode_id{$req->{rc}} * 0x0001,

      scalar @{ $req->{qd} || [] },
      scalar @{ $req->{an} || [] },
      scalar @{ $req->{ns} || [] },
      $EDNS0 + scalar @{ $req->{ar} || [] }, # EDNS0 option included here

      (join "", map _enc_qd, @{ $req->{qd} || [] }),
      (join "", map _enc_rr, @{ $req->{an} || [] }),
      (join "", map _enc_rr, @{ $req->{ns} || [] }),
      (join "", map _enc_rr, @{ $req->{ar} || [] }),

      ($EDNS0 ? pack "C nnNn", 0, 41, MAX_PKT, 0, 0 : "") # EDNS0 option
}

our $ofs;
our $pkt;

# bitches
sub _dec_name {
   my @res;
   my $redir;
   my $ptr = $ofs;
   my $cnt;

   while () {
      return undef if ++$cnt >= 256; # to avoid DoS attacks

      my $len = ord substr $pkt, $ptr++, 1;

      if ($len >= 0xc0) {
         $ptr++;
         $ofs = $ptr if $ptr > $ofs;
         $ptr = (unpack "n", substr $pkt, $ptr - 2, 2) & 0x3fff;
      } elsif ($len) {
         push @res, substr $pkt, $ptr, $len;
         $ptr += $len;
      } else {
         $ofs = $ptr if $ptr > $ofs;
         return join ".", @res;
      }
   }
}

sub _dec_qd {
   my $qname = _dec_name;
   my ($qt, $qc) = unpack "nn", substr $pkt, $ofs; $ofs += 4;
   [$qname, $type_str{$qt} || $qt, $class_str{$qc} || $qc]
}

our %dec_rr = (
     1 => sub { join ".", unpack "C4", $_ }, # a
     2 => sub { local $ofs = $ofs - length; _dec_name }, # ns
     5 => sub { local $ofs = $ofs - length; _dec_name }, # cname
     6 => sub { 
             local $ofs = $ofs - length;
             my $mname = _dec_name;
             my $rname = _dec_name;
             ($mname, $rname, unpack "NNNNN", substr $pkt, $ofs)
          }, # soa
    11 => sub { ((join ".", unpack "C4", $_), unpack "C a*", substr $_, 4) }, # wks
    12 => sub { local $ofs = $ofs - length; _dec_name }, # ptr
    13 => sub { unpack "C/a* C/a*", $_ }, # hinfo
    15 => sub { local $ofs = $ofs + 2 - length; ((unpack "n", $_), _dec_name) }, # mx
    16 => sub { unpack "(C/a*)*", $_ }, # txt
    28 => sub { AnyEvent::Socket::format_ipv6 ($_) }, # aaaa
    33 => sub { local $ofs = $ofs + 6 - length; ((unpack "nnn", $_), _dec_name) }, # srv
    35 => sub { # naptr
       # requires perl 5.10, sorry
       my ($order, $preference, $flags, $service, $regexp, $offset) = unpack "nn C/a* C/a* C/a* .", $_;
       local $ofs = $ofs + $offset - length;
       ($order, $preference, $flags, $service, $regexp, _dec_name)
    },
    39 => sub { local $ofs = $ofs - length; _dec_name }, # dname
    99 => sub { unpack "(C/a*)*", $_ }, # spf
   257 => sub { unpack "CC/a*a*", $_ }, # caa
);

sub _dec_rr {
   my $name = _dec_name;

   my ($rt, $rc, $ttl, $rdlen) = unpack "nn N n", substr $pkt, $ofs; $ofs += 10;
   local $_ = substr $pkt, $ofs, $rdlen; $ofs += $rdlen;

   [
      $name,
      $type_str{$rt}  || $rt,
      $class_str{$rc} || $rc,
      $ttl,
      ($dec_rr{$rt} || sub { $_ })->(),
   ]
}

=item $dns = AnyEvent::DNS::dns_unpack $pkt

Unpacks a DNS packet into a perl data structure.

Examples:

   # an unsuccessful reply
   {
     'qd' => [
               [ 'ruth.plan9.de.mach.uni-karlsruhe.de', '*', 'in' ]
             ],
     'rc' => 'nxdomain',
     'ar' => [],
     'ns' => [
               [
                 'uni-karlsruhe.de',
                 'soa',
                 'in',
                 600,
                 'netserv.rz.uni-karlsruhe.de',
                 'hostmaster.rz.uni-karlsruhe.de',
                 2008052201, 10800, 1800, 2592000, 86400
               ]
             ],
     'tc' => '',
     'ra' => 1,
     'qr' => 1,
     'id' => 45915,
     'aa' => '',
     'an' => [],
     'rd' => 1,
     'op' => 'query',
     '__' => '<original dns packet>',
   }
   
   # a successful reply
   
   {
     'qd' => [ [ 'www.google.de', 'a', 'in' ] ],
     'rc' => 0,
     'ar' => [
               [ 'a.l.google.com', 'a', 'in', 3600, '209.85.139.9' ],
               [ 'b.l.google.com', 'a', 'in', 3600, '64.233.179.9' ],
               [ 'c.l.google.com', 'a', 'in', 3600, '64.233.161.9' ],
             ],
     'ns' => [
               [ 'l.google.com', 'ns', 'in', 3600, 'a.l.google.com' ],
               [ 'l.google.com', 'ns', 'in', 3600, 'b.l.google.com' ],
             ],
     'tc' => '',
     'ra' => 1,
     'qr' => 1,
     'id' => 64265,
     'aa' => '',
     'an' => [
               [ 'www.google.de', 'cname', 'in', 3600, 'www.google.com' ],
               [ 'www.google.com', 'cname', 'in', 3600, 'www.l.google.com' ],
               [ 'www.l.google.com', 'a', 'in', 3600, '66.249.93.104' ],
               [ 'www.l.google.com', 'a', 'in', 3600, '66.249.93.147' ],
             ],
     'rd' => 1,
     'op' => 0,
     '__' => '<original dns packet>',
   }

=cut

sub dns_unpack($) {
   local $pkt = shift;
   my ($id, $flags, $qd, $an, $ns, $ar)
      = unpack "nn nnnn A*", $pkt;

   local $ofs = 6 * 2;

   {
      __ => $pkt,
      id => $id,
      qr => ! ! ($flags & 0x8000),
      aa => ! ! ($flags & 0x0400),
      tc => ! ! ($flags & 0x0200),
      rd => ! ! ($flags & 0x0100),
      ra => ! ! ($flags & 0x0080),
      ad => ! ! ($flags & 0x0020),
      cd => ! ! ($flags & 0x0010),
      op => $opcode_str{($flags & 0x001e) >> 11},
      rc => $rcode_str{($flags & 0x000f)},

      qd => [map _dec_qd, 1 .. $qd],
      an => [map _dec_rr, 1 .. $an],
      ns => [map _dec_rr, 1 .. $ns],
      ar => [map _dec_rr, 1 .. $ar],
   }
}

#############################################################################

=back

=head3 Extending DNS Encoder and Decoder

This section describes an I<experimental> method to extend the DNS encoder
and decoder with new opcode, rcode, class and type strings, as well as
resource record decoders.

Since this is experimental, it can change, as anything can change, but
this interface is expe ctedc to be relatively stable and was stable during
the whole existance of C<AnyEvent::DNS> so far.

Note that, since changing the decoder or encoder might break existing
code, you should either be sure to control for this, or only temporarily
change these values, e.g. like so:

   my $decoded = do {
      local $AnyEvent::DNS::opcode_str{7} = "yxrrset";
      AnyEvent::DNS::dns_unpack $mypkt
   };

=over 4

=item %AnyEvent::DNS::opcode_id, %AnyEvent::DNS::opcode_str

Two hashes that map lowercase opcode strings to numerical id's (For the
encoder), or vice versa (for the decoder). Example: add a new opcode
string C<notzone>.

   $AnyEvent::DNS::opcode_id{notzone} = 10;
   $AnyEvent::DNS::opcode_str{10} = 'notzone';

=item %AnyEvent::DNS::rcode_id, %AnyEvent::DNS::rcode_str

Same as above, for for rcode values.

=item %AnyEvent::DNS::class_id, %AnyEvent::DNS::class_str

Same as above, but for resource record class names/values.

=item %AnyEvent::DNS::type_id, %AnyEvent::DNS::type_str

Same as above, but for resource record type names/values.

=item %AnyEvent::DNS::dec_rr

This hash maps resource record type values to code references. When
decoding, they are called with C<$_> set to the undecoded data portion and
C<$ofs> being the current byte offset. of the record. You should have a
look at the existing implementations to understand how it works in detail,
but here are two examples:

Decode an A record. A records are simply four bytes with one byte per
address component, so the decoder simply unpacks them and joins them with
dots in between:

   $AnyEvent::DNS::dec_rr{1} = sub { join ".", unpack "C4", $_ };

Decode a CNAME record, which contains a potentially compressed domain
name.

   package AnyEvent::DNS; # for %dec_rr, $ofsd and &_dec_name
   $dec_rr{5} = sub { local $ofs = $ofs - length; _dec_name };

=back

=head2 THE AnyEvent::DNS RESOLVER CLASS

This is the class which does the actual protocol work.

=over 4

=cut

use Carp ();
use Scalar::Util ();
use Socket ();

our $NOW;

=item AnyEvent::DNS::resolver

This function creates and returns a resolver that is ready to use and
should mimic the default resolver for your system as good as possible. It
is used by AnyEvent itself as well.

It only ever creates one resolver and returns this one on subsequent calls
- see C<$AnyEvent::DNS::RESOLVER>, below, for details.

Unless you have special needs, prefer this function over creating your own
resolver object.

The resolver is created with the following parameters:

   untaint          enabled
   max_outstanding  $ENV{PERL_ANYEVENT_MAX_OUTSTANDING_DNS} (default 10)

C<os_config> will be used for OS-specific configuration, unless
C<$ENV{PERL_ANYEVENT_RESOLV_CONF}> is specified, in which case that file
gets parsed.

=item $AnyEvent::DNS::RESOLVER

This variable stores the default resolver returned by
C<AnyEvent::DNS::resolver>, or C<undef> when the default resolver hasn't
been instantiated yet.

One can provide a custom resolver (e.g. one with caching functionality)
by storing it in this variable, causing all subsequent resolves done via
C<AnyEvent::DNS::resolver> to be done via the custom one.

=cut

our $RESOLVER;

sub resolver() {
   $RESOLVER || do {
      $RESOLVER = new AnyEvent::DNS
         untaint         => 1,
         max_outstanding => $ENV{PERL_ANYEVENT_MAX_OUTSTANDING_DNS}*1 || 10,
      ;

      $ENV{PERL_ANYEVENT_RESOLV_CONF}
         ? $RESOLVER->_load_resolv_conf_file ($ENV{PERL_ANYEVENT_RESOLV_CONF})
         : $RESOLVER->os_config;

      $RESOLVER
   }
}

=item $resolver = new AnyEvent::DNS key => value...

Creates and returns a new resolver.

The following options are supported:

=over 4

=item server => [...]

A list of server addresses (default: C<v127.0.0.1> or C<::1>) in network
format (i.e. as returned by C<AnyEvent::Socket::parse_address> - both IPv4
and IPv6 are supported).

=item timeout => [...]

A list of timeouts to use (also determines the number of retries). To make
three retries with individual time-outs of 2, 5 and 5 seconds, use C<[2,
5, 5]>, which is also the default.

=item search => [...]

The default search list of suffixes to append to a domain name (default: none).

=item ndots => $integer

The number of dots (default: C<1>) that a name must have so that the resolver
tries to resolve the name without any suffixes first.

=item max_outstanding => $integer

Most name servers do not handle many parallel requests very well. This
option limits the number of outstanding requests to C<$integer>
(default: C<10>), that means if you request more than this many requests,
then the additional requests will be queued until some other requests have
been resolved.

=item reuse => $seconds

The number of seconds (default: C<300>) that a query id cannot be re-used
after a timeout. If there was no time-out then query ids can be reused
immediately.

=item untaint => $boolean

When true, then the resolver will automatically untaint results, and might
also ignore certain environment variables.

=back

=cut

sub new {
   my ($class, %arg) = @_;

   my $self = bless {
      server  => [],
      timeout => [2, 5, 5],
      search  => [],
      ndots   => 1,
      max_outstanding => 10,
      reuse   => 300,
      %arg,
      inhibit => 0,
      reuse_q => [],
   }, $class;

   # search should default to gethostname's domain
   # but perl lacks a good posix module

   # try to create an ipv4 and an ipv6 socket
   # only fail when we cannot create either
   my $got_socket;

   Scalar::Util::weaken (my $wself = $self);

   if (socket my $fh4, AF_INET , Socket::SOCK_DGRAM(), 0) {
      ++$got_socket;

      AnyEvent::fh_unblock $fh4;
      $self->{fh4} = $fh4;
      $self->{rw4} = AE::io $fh4, 0, sub {
         if (my $peer = recv $fh4, my $pkt, MAX_PKT, 0) {
            $wself->_recv ($pkt, $peer);
         }
      };
   }

   if (AF_INET6 && socket my $fh6, AF_INET6, Socket::SOCK_DGRAM(), 0) {
      ++$got_socket;

      $self->{fh6} = $fh6;
      AnyEvent::fh_unblock $fh6;
      $self->{rw6} = AE::io $fh6, 0, sub {
         if (my $peer = recv $fh6, my $pkt, MAX_PKT, 0) {
            $wself->_recv ($pkt, $peer);
         }
      };
   }

   $got_socket
      or Carp::croak "unable to create either an IPv4 or an IPv6 socket";

   $self->_compile;

   $self
}

# called to start asynchronous configuration
sub _config_begin {
   ++$_[0]{inhibit};
}

# called when done with async config
sub _config_done {
   --$_[0]{inhibit};
   $_[0]->_compile;
   $_[0]->_scheduler;
}

=item $resolver->parse_resolv_conf ($string)

Parses the given string as if it were a F<resolv.conf> file. The following
directives are supported (but not necessarily implemented).

C<#>- and C<;>-style comments, C<nameserver>, C<domain>, C<search>, C<sortlist>,
C<options> (C<timeout>, C<attempts>, C<ndots>).

Everything else is silently ignored.

=cut

sub parse_resolv_conf {
   my ($self, $resolvconf) = @_;

   $self->{server} = [];
   $self->{search} = [];

   my $attempts;

   for (split /\n/, $resolvconf) {
      s/\s*[;#].*$//; # not quite legal, but many people insist

      if (/^\s*nameserver\s+(\S+)\s*$/i) {
         my $ip = $1;
         if (my $ipn = AnyEvent::Socket::parse_address ($ip)) {
            push @{ $self->{server} }, $ipn;
         } else {
            AE::log 5 => "nameserver $ip invalid and ignored, while parsing resolver config.";
         }
      } elsif (/^\s*domain\s+(\S*)\s*$/i) {
         $self->{search} = [$1];
      } elsif (/^\s*search\s+(.*?)\s*$/i) {
         $self->{search} = [split /\s+/, $1];
      } elsif (/^\s*sortlist\s+(.*?)\s*$/i) {
         # ignored, NYI
      } elsif (/^\s*options\s+(.*?)\s*$/i) {
         for (split /\s+/, $1) {
            if (/^timeout:(\d+)$/) {
               $self->{timeout} = [$1];
            } elsif (/^attempts:(\d+)$/) {
               $attempts = $1;
            } elsif (/^ndots:(\d+)$/) {
               $self->{ndots} = $1;
            } else {
               # debug, rotate, no-check-names, inet6
            }
         }
      } else {
         # silently skip stuff we don't understand
      }
   }

   $self->{timeout} = [($self->{timeout}[0]) x $attempts]
      if $attempts;

   $self->_compile;
}

sub _load_resolv_conf_file {
   my ($self, $resolv_conf) = @_;

   $self->_config_begin;

   require AnyEvent::IO;
   AnyEvent::IO::aio_load ($resolv_conf, sub {
      if (my ($contents) = @_) {
         $self->parse_resolv_conf ($contents);
      } else {
         AE::log 4 => "$resolv_conf: $!";
      }

      $self->_config_done;
   });
}

=item $resolver->os_config

Tries so load and parse F</etc/resolv.conf> on portable operating
systems. Tries various egregious hacks on windows to force the DNS servers
and searchlist out of the system.

This method must be called at most once before trying to resolve anything.

=cut

sub os_config {
   my ($self) = @_;

   $self->_config_begin;

   $self->{server} = [];
   $self->{search} = [];

   if ((AnyEvent::WIN32 || $^O =~ /cygwin/i)) {
      # TODO: this blocks the program, but should not, but I
      # am too lazy to implement and test it. need to boot windows. ugh.

      #no strict 'refs';

      # there are many options to find the current nameservers etc. on windows
      # all of them don't work consistently:
      # - the registry thing needs separate code on win32 native vs. cygwin
      # - the registry layout differs between windows versions
      # - calling windows api functions doesn't work on cygwin
      # - ipconfig uses locale-specific messages

      # we use Net::DNS::Resolver first, and if it fails, will fall back to
      # ipconfig parsing.
      unless (eval {
         # Net::DNS::Resolver uses a LOT of ram (~10mb), but what can we do :/
         # (this seems mostly to be due to Win32::API).
         require Net::DNS::Resolver;
         my $r = Net::DNS::Resolver->new;

         $r->nameservers
            or die;

         for my $s ($r->nameservers) {
            if (my $ipn = AnyEvent::Socket::parse_address ($s)) {
               push @{ $self->{server} }, $ipn;
            }
         }
         $self->{search} = [$r->searchlist];

         1
      }) {
         # we use ipconfig parsing because, despite all its brokenness,
         # it seems quite stable in practise.
         # unfortunately it wants a console window.
         # for good measure, we append a fallback nameserver to our list.

         if (open my $fh, "ipconfig /all |") {
            # parsing strategy: we go through the output and look for
            # :-lines with DNS in them. everything in those is regarded as
            # either a nameserver (if it parses as an ip address), or a suffix
            # (all else).

            my $dns;
            local $_;
            while (<$fh>) {
               if (s/^\s.*\bdns\b.*://i) {
                  $dns = 1;
               } elsif (/^\S/ || /^\s[^:]{16,}: /) {
                  $dns = 0;
               }
               if ($dns && /^\s*(\S+)\s*$/) {
                  my $s = $1;
                  $s =~ s/%\d+(?!\S)//; # get rid of ipv6 scope id
                  if (my $ipn = AnyEvent::Socket::parse_address ($s)) {
                     push @{ $self->{server} }, $ipn;
                  } else {
                     push @{ $self->{search} }, $s;
                  }
               }
            }
         }
      }

      # always add the fallback servers on windows
      push @{ $self->{server} }, @DNS_FALLBACK;

      $self->_config_done;
   } else {
      # try /etc/resolv.conf everywhere else

      require AnyEvent::IO;
      AnyEvent::IO::aio_stat ("/etc/resolv.conf", sub {
         $self->_load_resolv_conf_file ("/etc/resolv.conf")
            if @_;
         $self->_config_done;
      });
   }
}

=item $resolver->timeout ($timeout, ...)

Sets the timeout values. See the C<timeout> constructor argument (and
note that this method expects the timeout values themselves, not an
array-reference).

=cut

sub timeout {
   my ($self, @timeout) = @_;

   $self->{timeout} = \@timeout;
   $self->_compile;
}

=item $resolver->max_outstanding ($nrequests)

Sets the maximum number of outstanding requests to C<$nrequests>. See the
C<max_outstanding> constructor argument.

=cut

sub max_outstanding {
   my ($self, $max) = @_;

   $self->{max_outstanding} = $max;
   $self->_compile;
}

sub _compile {
   my $self = shift;

   my %search; $self->{search} = [grep 0 < length, grep !$search{$_}++, @{ $self->{search} }];
   my %server; $self->{server} = [grep 0 < length, grep !$server{$_}++, @{ $self->{server} }];

   unless (@{ $self->{server} }) {
      # use 127.0.0.1/::1 by default, add public nameservers as fallback
      my $default = $AnyEvent::PROTOCOL{ipv6} > $AnyEvent::PROTOCOL{ipv4}
                    ? "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\1" : "\x7f\x00\x00\x01";
      $self->{server} = [$default, @DNS_FALLBACK];
   }

   my @retry;

   for my $timeout (@{ $self->{timeout} }) {
      for my $server (@{ $self->{server} }) {
         push @retry, [$server, $timeout];
      }
   }

   $self->{retry} = \@retry;
}

sub _feed {
   my ($self, $res) = @_;

   ($res) = $res =~ /^(.*)$/s
      if AnyEvent::TAINT && $self->{untaint};

   $res = dns_unpack $res
      or return;

   my $id = $self->{id}{$res->{id}};

   return unless ref $id;

   $NOW = time;
   $id->[1]->($res);
}

sub _recv {
   my ($self, $pkt, $peer) = @_;

   # we ignore errors (often one gets port unreachable, but there is
   # no good way to take advantage of that.

   my ($port, $host) = AnyEvent::Socket::unpack_sockaddr ($peer);

   return unless $port == DOMAIN_PORT && grep $_ eq $host, @{ $self->{server} };

   $self->_feed ($pkt);
}

sub _free_id {
   my ($self, $id, $timeout) = @_;

   if ($timeout) {
      # we need to block the id for a while
      $self->{id}{$id} = 1;
      push @{ $self->{reuse_q} }, [$NOW + $self->{reuse}, $id];
   } else {
      # we can quickly recycle the id
      delete $self->{id}{$id};
   }

   --$self->{outstanding};
   $self->_scheduler;
}

# execute a single request, involves sending it with timeouts to multiple servers
sub _exec {
   my ($self, $req) = @_;

   my $retry; # of retries
   my $do_retry;

   $do_retry = sub {
      my $retry_cfg = $self->{retry}[$retry++]
         or do {
            # failure
            $self->_free_id ($req->[2], $retry > 1);
            undef $do_retry; return $req->[1]->();
         };

      my ($server, $timeout) = @$retry_cfg;
      
      $self->{id}{$req->[2]} = [(AE::timer $timeout, 0, sub {
         $NOW = time;

         # timeout, try next
         &$do_retry if $do_retry;
      }), sub {
         my ($res) = @_;

         if ($res->{tc}) {
            # success, but truncated, so use tcp
            AnyEvent::Socket::tcp_connect (AnyEvent::Socket::format_address ($server), DOMAIN_PORT, sub {
               return unless $do_retry; # some other request could have invalidated us already

               my ($fh) = @_
                  or return &$do_retry;

               require AnyEvent::Handle;

               my $handle; $handle = new AnyEvent::Handle
                  fh       => $fh,
                  timeout  => $timeout,
                  on_error => sub {
                     undef $handle;
                     return unless $do_retry; # some other request could have invalidated us already
                     # failure, try next
                     &$do_retry;
                  };

               $handle->push_write (pack "n/a*", $req->[0]);
               $handle->push_read (chunk => 2, sub {
                  $handle->unshift_read (chunk => (unpack "n", $_[1]), sub {
                     undef $handle;
                     $self->_feed ($_[1]);
                  });
               });

            }, sub { $timeout });

         } else {
            # success
            $self->_free_id ($req->[2], $retry > 1);
            undef $do_retry; return $req->[1]->($res);
         }
      }];
      
      my $sa = AnyEvent::Socket::pack_sockaddr (DOMAIN_PORT, $server);

      my $fh = AF_INET == AnyEvent::Socket::sockaddr_family ($sa)
               ? $self->{fh4} : $self->{fh6}
         or return &$do_retry;

      send $fh, $req->[0], 0, $sa;
   };

   &$do_retry;
}

sub _scheduler {
   my ($self) = @_;

   return if $self->{inhibit};

   #no strict 'refs';

   $NOW = time;

   # first clear id reuse queue
   delete $self->{id}{ (shift @{ $self->{reuse_q} })->[1] }
      while @{ $self->{reuse_q} } && $self->{reuse_q}[0][0] <= $NOW;

   while ($self->{outstanding} < $self->{max_outstanding}) {

      if (@{ $self->{reuse_q} } >= 30000) {
         # we ran out of ID's, wait a bit
         $self->{reuse_to} ||= AE::timer $self->{reuse_q}[0][0] - $NOW, 0, sub {
            delete $self->{reuse_to};
            $self->_scheduler;
         };
         last;
      }

      if (my $req = shift @{ $self->{queue} }) {
         # found a request in the queue, execute it
         while () {
            $req->[2] = int rand 65536;
            last unless exists $self->{id}{$req->[2]};
         }

         ++$self->{outstanding};
         $self->{id}{$req->[2]} = 1;
         substr $req->[0], 0, 2, pack "n", $req->[2];

         $self->_exec ($req);

      } elsif (my $cb = shift @{ $self->{wait} }) {
         # found a wait_for_slot callback
         $cb->($self);

      } else {
         # nothing to do, just exit
         last;
      }
   }
}

=item $resolver->request ($req, $cb->($res))

This is the main low-level workhorse for sending DNS requests.

This function sends a single request (a hash-ref formated as specified
for C<dns_pack>) to the configured nameservers in turn until it gets a
response. It handles timeouts, retries and automatically falls back to
virtual circuit mode (TCP) when it receives a truncated reply. It does not
handle anything else, such as the domain searchlist or relative names -
use C<< ->resolve >> for that.

Calls the callback with the decoded response packet if a reply was
received, or no arguments in case none of the servers answered.

=cut

sub request($$) {
   my ($self, $req, $cb) = @_;

   # _enc_name barfs on names that are too long, which is often outside
   # program control, so check for too long names here.
   for (@{ $req->{qd} }) {
      return AE::postpone sub { $cb->(undef) }
         if 255 < length $_->[0];
   }

   push @{ $self->{queue} }, [dns_pack $req, $cb];
   $self->_scheduler;
}

=item $resolver->resolve ($qname, $qtype, %options, $cb->(@rr))

Queries the DNS for the given domain name C<$qname> of type C<$qtype>.

A C<$qtype> is either a numerical query type (e.g. C<1> for A records) or
a lowercase name (you have to look at the source to see which aliases are
supported, but all types from RFC 1035, C<aaaa>, C<srv>, C<spf> and a few
more are known to this module). A C<$qtype> of "*" is supported and means
"any" record type.

The callback will be invoked with a list of matching result records or
none on any error or if the name could not be found.

CNAME chains (although illegal) are followed up to a length of 10.

The callback will be invoked with arraryefs of the form C<[$name,
$type, $class, $ttl, @data>], where C<$name> is the domain name,
C<$type> a type string or number, C<$class> a class name, C<$ttl> is the
remaining time-to-live and C<@data> is resource-record-dependent data, in
seconds. For C<a> records, this will be the textual IPv4 addresses, for
C<ns> or C<cname> records this will be a domain name, for C<txt> records
these are all the strings and so on.

All types mentioned in RFC 1035, C<aaaa>, C<srv>, C<naptr> and C<spf> are
decoded. All resource records not known to this module will have the raw
C<rdata> field as fifth array element.

Note that this resolver is just a stub resolver: it requires a name server
supporting recursive queries, will not do any recursive queries itself and
is not secure when used against an untrusted name server.

The following options are supported:

=over 4

=item search => [$suffix...]

Use the given search list (which might be empty), by appending each one
in turn to the C<$qname>. If this option is missing then the configured
C<ndots> and C<search> values define its value (depending on C<ndots>, the
empty suffix will be prepended or appended to that C<search> value). If
the C<$qname> ends in a dot, then the searchlist will be ignored.

=item accept => [$type...]

Lists the acceptable result types: only result types in this set will be
accepted and returned. The default includes the C<$qtype> and nothing
else. If this list includes C<cname>, then CNAME-chains will not be
followed (because you asked for the CNAME record).

=item class => "class"

Specify the query class ("in" for internet, "ch" for chaosnet and "hs" for
hesiod are the only ones making sense). The default is "in", of course.

=back

Examples:

   # full example, you can paste this into perl:
   use Data::Dumper;
   use AnyEvent::DNS;
   AnyEvent::DNS::resolver->resolve (
      "google.com", "*", my $cv = AnyEvent->condvar);
   warn Dumper [$cv->recv];

   # shortened result:
   # [
   #   [ 'google.com', 'soa', 'in', 3600, 'ns1.google.com', 'dns-admin.google.com',
   #     2008052701, 7200, 1800, 1209600, 300 ],
   #   [
   #     'google.com', 'txt', 'in', 3600,
   #     'v=spf1 include:_netblocks.google.com ~all'
   #   ],
   #   [ 'google.com', 'a', 'in', 3600, '64.233.187.99' ],
   #   [ 'google.com', 'mx', 'in', 3600, 10, 'smtp2.google.com' ],
   #   [ 'google.com', 'ns', 'in', 3600, 'ns2.google.com' ],
   # ]

   # resolve a records:
   $res->resolve ("ruth.plan9.de", "a", sub { warn Dumper [@_] });

   # result:
   # [
   #   [ 'ruth.schmorp.de', 'a', 'in', 86400, '129.13.162.95' ]
   # ]

   # resolve any records, but return only a and aaaa records:
   $res->resolve ("test1.laendle", "*",
      accept => ["a", "aaaa"],
      sub {
         warn Dumper [@_];
      }
   );

   # result:
   # [
   #   [ 'test1.laendle', 'a', 'in', 86400, '10.0.0.255' ],
   #   [ 'test1.laendle', 'aaaa', 'in', 60, '3ffe:1900:4545:0002:0240:0000:0000:f7e1' ]
   # ]

=cut

sub resolve($%) {
   my $cb = pop;
   my ($self, $qname, $qtype, %opt) = @_;

   $self->wait_for_slot (sub {
      my $self = shift;

      my @search = $qname =~ s/\.$//
         ? ""
         : $opt{search}
           ? @{ $opt{search} }
           : ($qname =~ y/.//) >= $self->{ndots}
             ? ("", @{ $self->{search} })
             : (@{ $self->{search} }, "");

      my $class = $opt{class} || "in";

      my %atype = $opt{accept}
         ? map +($_ => 1), @{ $opt{accept} }
         : ($qtype => 1);

      # advance in searchlist
      my ($do_search, $do_req);
      
      $do_search = sub {
         @search
            or (undef $do_search), (undef $do_req), return $cb->();

         (my $name = lc "$qname." . shift @search) =~ s/\.$//;
         my $depth = 10;

         # advance in cname-chain
         $do_req = sub {
            $self->request ({
               rd => 1,
               qd => [[$name, $qtype, $class]],
            }, sub {
               my ($res) = @_
                  or return $do_search->();

               my $cname;

               while () {
                  # results found?
                  my @rr = grep $name eq lc $_->[0] && ($atype{"*"} || $atype{$_->[1]}), @{ $res->{an} };

                  (undef $do_search), (undef $do_req), return $cb->(@rr)
                     if @rr;

                  # see if there is a cname we can follow
                  my @rr = grep $name eq lc $_->[0] && $_->[1] eq "cname", @{ $res->{an} };

                  if (@rr) {
                     $depth--
                        or return $do_search->(); # cname chain too long

                     $cname = 1;
                     $name = lc $rr[0][4];

                  } elsif ($cname) {
                     # follow the cname
                     return $do_req->();

                  } else {
                     # no, not found anything
                     return $do_search->();
                  }
                }
            });
         };

         $do_req->();
      };

      $do_search->();
   });
}

=item $resolver->wait_for_slot ($cb->($resolver))

Wait until a free request slot is available and call the callback with the
resolver object.

A request slot is used each time a request is actually sent to the
nameservers: There are never more than C<max_outstanding> of them.

Although you can submit more requests (they will simply be queued until
a request slot becomes available), sometimes, usually for rate-limiting
purposes, it is useful to instead wait for a slot before generating the
request (or simply to know when the request load is low enough so one can
submit requests again).

This is what this method does: The callback will be called when submitting
a DNS request will not result in that request being queued. The callback
may or may not generate any requests in response.

Note that the callback will only be invoked when the request queue is
empty, so this does not play well if somebody else keeps the request queue
full at all times.

=cut

sub wait_for_slot {
   my ($self, $cb) = @_;

   push @{ $self->{wait} }, $cb;
   $self->_scheduler;
}

use AnyEvent::Socket (); # circular dependency, so do not import anything and do it at the end

=back

=head1 AUTHOR

   Marc Lehmann <schmorp@schmorp.de>
   http://anyevent.schmorp.de

=cut

1
