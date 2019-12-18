=head1 NAME

AnyEvent::Socket - useful IPv4 and IPv6 stuff.

=head1 SYNOPSIS

   use AnyEvent::Socket;
   
   tcp_connect "gameserver.deliantra.net", 13327, sub {
      my ($fh) = @_
         or die "gameserver.deliantra.net connect failed: $!";
   
      # enjoy your filehandle
   };
   
   # a simple tcp server
   tcp_server undef, 8888, sub {
      my ($fh, $host, $port) = @_;
   
      syswrite $fh, "The internet is full, $host:$port. Go away!\015\012";
   };

=head1 DESCRIPTION

This module implements various utility functions for handling internet
protocol addresses and sockets, in an as transparent and simple way as
possible.

All functions documented without C<AnyEvent::Socket::> prefix are exported
by default.

=over 4

=cut

package AnyEvent::Socket;

use Carp ();
use Errno ();
use Socket qw(AF_INET AF_UNIX SOCK_STREAM SOCK_DGRAM SOL_SOCKET SO_REUSEADDR);

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use AnyEvent::Util qw(guard fh_nonblocking AF_INET6);
use AnyEvent::DNS ();

use base 'Exporter';

our @EXPORT = qw(
   getprotobyname
   parse_hostport format_hostport
   parse_ipv4 parse_ipv6
   parse_ip parse_address
   format_ipv4 format_ipv6
   format_ip format_address
   address_family
   inet_aton
   tcp_server
   tcp_connect
);

our $VERSION = $AnyEvent::VERSION;

# used in cases where we may return immediately but want the
# caller to do stuff first
sub _postpone {
   my ($cb, @args) = (@_, $!);

   my $w; $w = AE::timer 0, 0, sub {
      undef $w;
      $! = pop @args;
      $cb->(@args);
   };
}

=item $ipn = parse_ipv4 $dotted_quad

Tries to parse the given dotted quad IPv4 address and return it in
octet form (or undef when it isn't in a parsable format). Supports all
forms specified by POSIX (e.g. C<10.0.0.1>, C<10.1>, C<10.0x020304>,
C<0x12345678> or C<0377.0377.0377.0377>).

=cut

sub parse_ipv4($) {
   $_[0] =~ /^      (?: 0x[0-9a-fA-F]+ | 0[0-7]* | [1-9][0-9]* )
              (?:\. (?: 0x[0-9a-fA-F]+ | 0[0-7]* | [1-9][0-9]* ) ){0,3}$/x
      or return undef;

   @_ = map /^0/ ? oct : $_, split /\./, $_[0];

   # check leading parts against range
   return undef if grep $_ >= 256, @_[0 .. @_ - 2];

   # check trailing part against range
   return undef if $_[-1] >= 2 ** (8 * (4 - $#_));

   pack "N", (pop)
             + ($_[0] << 24)
             + ($_[1] << 16)
             + ($_[2] <<  8);
}

=item $ipn = parse_ipv6 $textual_ipv6_address

Tries to parse the given IPv6 address and return it in
octet form (or undef when it isn't in a parsable format).

Should support all forms specified by RFC 2373 (and additionally all IPv4
forms supported by parse_ipv4). Note that scope-id's are not supported
(and will not parse).

This function works similarly to C<inet_pton AF_INET6, ...>.

Example:

   print unpack "H*", parse_ipv6 "2002:5345::10.0.0.1";
   # => 2002534500000000000000000a000001

=cut

sub parse_ipv6($) {
   # quick test to avoid longer processing
   my $n = $_[0] =~ y/://;
   return undef if $n < 2 || $n > 8;

   my ($h, $t) = split /::/, $_[0], 2;

   unless (defined $t) {
      ($h, $t) = (undef, $h);
   }

   my @h = split /:/, $h;
   my @t = split /:/, $t;

   # check for ipv4 tail
   if (@t && $t[-1]=~ /\./) {
      return undef if $n > 6;

      my $ipn = parse_ipv4 pop @t
         or return undef;

      push @t, map +(sprintf "%x", $_), unpack "nn", $ipn;
   }

   # no :: then we need to have exactly 8 components
   return undef unless @h + @t == 8 || $_[0] =~ /::/;

   # now check all parts for validity
   return undef if grep !/^[0-9a-fA-F]{1,4}$/, @h, @t;

   # now pad...
   push @h, 0 while @h + @t < 8;

   # and done
   pack "n*", map hex, @h, @t
}

sub parse_unix($) {
   $_[0] eq "unix/"
      ? pack "S", AF_UNIX
      : undef

}

=item $ipn = parse_address $ip

Combines C<parse_ipv4> and C<parse_ipv6> in one function. The address
here refers to the host address (not socket address) in network form
(binary).

If the C<$text> is C<unix/>, then this function returns a special token
recognised by the other functions in this module to mean "UNIX domain
socket".

If the C<$text> to parse is a mapped IPv4 in IPv6 address (:ffff::<ipv4>),
then it will be treated as an IPv4 address. If you don't want that, you
have to call C<parse_ipv4> and/or C<parse_ipv6> manually.

Example:

   print unpack "H*", parse_address "10.1.2.3";
   # => 0a010203

=item $ipn = AnyEvent::Socket::aton $ip

Same as C<parse_address>, but not exported (think C<Socket::inet_aton> but
I<without> name resolution).

=cut

sub parse_address($) {
   for (&parse_ipv6) {
      if ($_) {
         s/^\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff//;
         return $_;
      } else {
         return &parse_ipv4 || &parse_unix
      }
   }
}

*aton = \&parse_address;

=item ($name, $aliases, $proto) = getprotobyname $name

Works like the builtin function of the same name, except it tries hard to
work even on broken platforms (well, that's windows), where getprotobyname
is traditionally very unreliable.

Example: get the protocol number for TCP (usually 6)

   my $proto = getprotobyname "tcp";

=cut

# microsoft can't even get getprotobyname working (the etc/protocols file
# gets lost fairly often on windows), so we have to hardcode some common
# protocol numbers ourselves.
our %PROTO_BYNAME;

$PROTO_BYNAME{tcp}  = Socket::IPPROTO_TCP () if defined &Socket::IPPROTO_TCP;
$PROTO_BYNAME{udp}  = Socket::IPPROTO_UDP () if defined &Socket::IPPROTO_UDP;
$PROTO_BYNAME{icmp} = Socket::IPPROTO_ICMP() if defined &Socket::IPPROTO_ICMP;

sub getprotobyname($) {
   my $name = lc shift;

   defined (my $proton = $PROTO_BYNAME{$name} || (getprotobyname $name)[2])
      or return;

   ($name, uc $name, $proton)
}

=item ($host, $service) = parse_hostport $string[, $default_service]

Splitting a string of the form C<hostname:port> is a common
problem. Unfortunately, just splitting on the colon makes it hard to
specify IPv6 addresses and doesn't support the less common but well
standardised C<[ip literal]> syntax.

This function tries to do this job in a better way, it supports the
following formats, where C<port> can be a numerical port number of a
service name, or a C<name=port> string, and the C< port> and C<:port>
parts are optional. Also, everywhere where an IP address is supported
a hostname or unix domain socket address is also supported (see
C<parse_unix>).

   hostname:port    e.g. "www.linux.org", "www.x.de:443", "www.x.de:https=443"
   ipv4:port        e.g. "198.182.196.56", "127.1:22"
   ipv6             e.g. "::1", "affe::1"
   [ipv4or6]:port   e.g. "[::1]", "[10.0.1]:80"
   [ipv4or6] port   e.g. "[127.0.0.1]", "[www.x.org] 17"
   ipv4or6 port     e.g. "::1 443", "10.0.0.1 smtp"

It also supports defaulting the service name in a simple way by using
C<$default_service> if no service was detected. If neither a service was
detected nor a default was specified, then this function returns the
empty list. The same happens when a parse error was detected, such as a
hostname with a colon in it (the function is rather conservative, though).

Example:

  print join ",", parse_hostport "localhost:443";
  # => "localhost,443"

  print join ",", parse_hostport "localhost", "https";
  # => "localhost,https"

  print join ",", parse_hostport "[::1]";
  # => "," (empty list)

=cut

sub parse_hostport($;$) {
   my ($host, $port);

   for ("$_[0]") { # work on a copy, just in case, and also reset pos

      # parse host, special cases: "ipv6" or "ipv6 port"
      unless (
         ($host) = /^\s* ([0-9a-fA-F:]*:[0-9a-fA-F:]*:[0-9a-fA-F\.:]*)/xgc
         and parse_ipv6 $host
      ) {
         /^\s*/xgc;

         if (/^ \[ ([^\[\]]+) \]/xgc) {
            $host = $1;
         } elsif (/^ ([^\[\]:\ ]+) /xgc) {
            $host = $1;
         } else {
            return;
         }
      }

      # parse port
      if (/\G (?:\s+|:) ([^:[:space:]]+) \s*$/xgc) {
         $port = $1;
      } elsif (/\G\s*$/gc && length $_[1]) {
         $port = $_[1];
      } else {
         return;
      }
   }

   # hostnames must not contain :'s
   return if $host =~ /:/ && !parse_ipv6 $host;

   ($host, $port)
}

=item $string = format_hostport $host, $port

Takes a host (in textual form) and a port and formats in unambigiously in
a way that C<parse_hostport> can parse it again. C<$port> can be C<undef>.

=cut

sub format_hostport($;$) {
   my ($host, $port) = @_;

   $port = ":$port"  if length $port;
   $host = "[$host]" if $host =~ /:/;

   "$host$port"
}

=item $sa_family = address_family $ipn

Returns the address family/protocol-family (AF_xxx/PF_xxx, in one value :)
of the given host address in network format.

=cut

sub address_family($) {
   4 == length $_[0]
      ? AF_INET
      : 16 == length $_[0]
         ? AF_INET6
         : unpack "S", $_[0]
}

=item $text = format_ipv4 $ipn

Expects a four octet string representing a binary IPv4 address and returns
its textual format. Rarely used, see C<format_address> for a nicer
interface.

=item $text = format_ipv6 $ipn

Expects a sixteen octet string representing a binary IPv6 address and
returns its textual format. Rarely used, see C<format_address> for a
nicer interface.

=item $text = format_address $ipn

Covnvert a host address in network format (e.g. 4 octets for IPv4 or 16
octets for IPv6) and convert it into textual form.

Returns C<unix/> for UNIX domain sockets.

This function works similarly to C<inet_ntop AF_INET || AF_INET6, ...>,
except it automatically detects the address type.

Returns C<undef> if it cannot detect the type.

If the C<$ipn> is a mapped IPv4 in IPv6 address (:ffff::<ipv4>), then just
the contained IPv4 address will be returned. If you do not want that, you
have to call C<format_ipv6> manually.

Example:

   print format_address "\x01\x02\x03\x05";
   => 1.2.3.5

=item $text = AnyEvent::Socket::ntoa $ipn

Same as format_address, but not exported (think C<inet_ntoa>).

=cut

sub format_ipv4($) {
   join ".", unpack "C4", $_[0]
}

sub format_ipv6($) {
   if ($_[0] =~ /^\x00\x00\x00\x00\x00\x00\x00\x00/) {
      if (v0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0 eq $_[0]) {
         return "::";
      } elsif (v0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.1 eq $_[0]) {
         return "::1";
      } elsif (v0.0.0.0.0.0.0.0.0.0.0.0 eq substr $_[0], 0, 12) {
         # v4compatible
         return "::" . format_ipv4 substr $_[0], 12;
      } elsif (v0.0.0.0.0.0.0.0.0.0.255.255 eq substr $_[0], 0, 12) {
         # v4mapped
         return "::ffff:" . format_ipv4 substr $_[0], 12;
      } elsif (v0.0.0.0.0.0.0.0.255.255.0.0 eq substr $_[0], 0, 12) {
         # v4translated
         return "::ffff:0:" . format_ipv4 substr $_[0], 12;
      }
   }

   my $ip = sprintf "%x:%x:%x:%x:%x:%x:%x:%x", unpack "n8", $_[0];

   # this is admittedly rather sucky
      $ip =~ s/(?:^|:) 0:0:0:0:0:0:0 (?:$|:)/::/x
   or $ip =~ s/(?:^|:)   0:0:0:0:0:0 (?:$|:)/::/x
   or $ip =~ s/(?:^|:)     0:0:0:0:0 (?:$|:)/::/x
   or $ip =~ s/(?:^|:)       0:0:0:0 (?:$|:)/::/x
   or $ip =~ s/(?:^|:)         0:0:0 (?:$|:)/::/x
   or $ip =~ s/(?:^|:)           0:0 (?:$|:)/::/x
   or $ip =~ s/(?:^|:)             0 (?:$|:)/::/x;

   $ip
}

sub format_address($) {
   if (4 == length $_[0]) {
      return &format_ipv4;
   } elsif (16 == length $_[0]) {
      return $_[0] =~ /^\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff(....)$/s
         ? format_ipv4 $1
         : &format_ipv6;
   } elsif (AF_UNIX == address_family $_[0]) {
      return "unix/"
   } else {
      return undef
   }
}

*ntoa = \&format_address;

=item inet_aton $name_or_address, $cb->(@addresses)

Works similarly to its Socket counterpart, except that it uses a
callback. Use the length to distinguish between ipv4 and ipv6 (4 octets
for IPv4, 16 for IPv6), or use C<format_address> to convert it to a more
readable format.

Note that C<resolve_sockaddr>, while initially a more complex interface,
resolves host addresses, IDNs, service names and SRV records and gives you
an ordered list of socket addresses to try and should be preferred over
C<inet_aton>.

Example.

   inet_aton "www.google.com", my $cv = AE::cv;
   say unpack "H*", $_
      for $cv->recv;
   # => d155e363
   # => d155e367 etc.

   inet_aton "ipv6.google.com", my $cv = AE::cv;
   say unpack "H*", $_
      for $cv->recv;
   # => 20014860a00300000000000000000068

=cut

sub inet_aton {
   my ($name, $cb) = @_;
   my $ipn;

   if ($ipn = &parse_ipv4) {
      $cb->($ipn);
   } elsif ($ipn = &parse_ipv6) {
      $cb->($ipn);
   } elsif ($name eq "localhost") { # rfc2606 et al.
      $cb->(v127.0.0.1, v0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.1);
   } else {
      require AnyEvent::DNS;

      my $ipv4 = $AnyEvent::PROTOCOL{ipv4};
      my $ipv6 = $AnyEvent::PROTOCOL{ipv6};

      my @res;

      my $cv = AE::cv {
         $cb->(map @$_, reverse @res);
      };

      $cv->begin;

      if ($ipv4) {
         $cv->begin;
         AnyEvent::DNS::a ($name, sub {
            $res[$ipv4] = [map &parse_ipv4, @_];
            $cv->end;
         });
      };

      if ($ipv6) {
         $cv->begin;
         AnyEvent::DNS::aaaa ($name, sub {
            $res[$ipv6] = [map &parse_ipv6, @_];
            $cv->end;
         });
      };

      $cv->end;
   }
}

BEGIN {
   *sockaddr_family = $Socket::VERSION >= 1.75
      ? \&Socket::sockaddr_family
      : # for 5.6.x, we need to do something much more horrible
        (Socket::pack_sockaddr_in 0x5555, "\x55\x55\x55\x55"
           | eval { Socket::pack_sockaddr_un "U" }) =~ /^\x00/
           ? sub { unpack "xC", $_[0] }
           : sub { unpack "S" , $_[0] };
}

# check for broken platforms with an extra field in sockaddr structure
# kind of a rfc vs. bsd issue, as usual (ok, normally it's a
# unix vs. bsd issue, a iso C vs. bsd issue or simply a
# correctness vs. bsd issue.)
my $pack_family = 0x55 == sockaddr_family ("\x55\x55")
                  ? "xC" : "S";

=item $sa = AnyEvent::Socket::pack_sockaddr $service, $host

Pack the given port/host combination into a binary sockaddr
structure. Handles both IPv4 and IPv6 host addresses, as well as UNIX
domain sockets (C<$host> == C<unix/> and C<$service> == absolute
pathname).

Example:

   my $bind = AnyEvent::Socket::pack_sockaddr 43, v195.234.53.120;
   bind $socket, $bind
      or die "bind: $!";

=cut

sub pack_sockaddr($$) {
   my $af = address_family $_[1];

   if ($af == AF_INET) {
      Socket::pack_sockaddr_in $_[0], $_[1]
   } elsif ($af == AF_INET6) {
      pack "$pack_family nL a16 L",
         AF_INET6,
         $_[0], # port
         0,     # flowinfo
         $_[1], # addr
         0      # scope id
   } elsif ($af == AF_UNIX) {
      Socket::pack_sockaddr_un $_[0]
   } else {
      Carp::croak "pack_sockaddr: invalid host";
   }
}

=item ($service, $host) = AnyEvent::Socket::unpack_sockaddr $sa

Unpack the given binary sockaddr structure (as used by bind, getpeername
etc.) into a C<$service, $host> combination.

For IPv4 and IPv6, C<$service> is the port number and C<$host> the host
address in network format (binary).

For UNIX domain sockets, C<$service> is the absolute pathname and C<$host>
is a special token that is understood by the other functions in this
module (C<format_address> converts it to C<unix/>).

=cut

# perl contains a bug (imho) where it requires that the kernel always returns
# sockaddr_un structures of maximum length (which is not, AFAICS, required
# by any standard). try to 0-pad structures for the benefit of those platforms.

my $sa_un_zero = eval { Socket::pack_sockaddr_un "" }; $sa_un_zero ^= $sa_un_zero;

sub unpack_sockaddr($) {
   my $af = sockaddr_family $_[0];

   if ($af == AF_INET) {
      Socket::unpack_sockaddr_in $_[0]
   } elsif ($af == AF_INET6) {
      unpack "x2 n x4 a16", $_[0]
   } elsif ($af == AF_UNIX) {
      ((Socket::unpack_sockaddr_un $_[0] ^ $sa_un_zero), pack "S", AF_UNIX)
   } else {
      Carp::croak "unpack_sockaddr: unsupported protocol family $af";
   }
}

=item resolve_sockaddr $node, $service, $proto, $family, $type, $cb->([$family, $type, $proto, $sockaddr], ...)

Tries to resolve the given nodename and service name into protocol families
and sockaddr structures usable to connect to this node and service in a
protocol-independent way. It works remotely similar to the getaddrinfo
posix function.

For internet addresses, C<$node> is either an IPv4 or IPv6 address, an
internet hostname (DNS domain name or IDN), and C<$service> is either
a service name (port name from F</etc/services>) or a numerical port
number. If both C<$node> and C<$service> are names, then SRV records
will be consulted to find the real service, otherwise they will be
used as-is. If you know that the service name is not in your services
database, then you can specify the service in the format C<name=port>
(e.g. C<http=80>).

For UNIX domain sockets, C<$node> must be the string C<unix/> and
C<$service> must be the absolute pathname of the socket. In this case,
C<$proto> will be ignored.

C<$proto> must be a protocol name, currently C<tcp>, C<udp> or
C<sctp>. The default is currently C<tcp>, but in the future, this function
might try to use other protocols such as C<sctp>, depending on the socket
type and any SRV records it might find.

C<$family> must be either C<0> (meaning any protocol is OK), C<4> (use
only IPv4) or C<6> (use only IPv6). The default is influenced by
C<$ENV{PERL_ANYEVENT_PROTOCOLS}>.

C<$type> must be C<SOCK_STREAM>, C<SOCK_DGRAM> or C<SOCK_SEQPACKET> (or
C<undef> in which case it gets automatically chosen to be C<SOCK_STREAM>
unless C<$proto> is C<udp>).

The callback will receive zero or more array references that contain
C<$family, $type, $proto> for use in C<socket> and a binary
C<$sockaddr> for use in C<connect> (or C<bind>).

The application should try these in the order given.

Example:

   resolve_sockaddr "google.com", "http", 0, undef, undef, sub { ... };

=cut

sub resolve_sockaddr($$$$$$) {
   my ($node, $service, $proto, $family, $type, $cb) = @_;

   if ($node eq "unix/") {
      return $cb->() if $family || $service !~ /^\//; # no can do

      return $cb->([AF_UNIX, defined $type ? $type : SOCK_STREAM, 0, Socket::pack_sockaddr_un $service]);
   }

   unless (AF_INET6) {
      $family != 6
         or return $cb->();

      $family = 4;
   }

   $cb->() if $family == 4 && !$AnyEvent::PROTOCOL{ipv4};
   $cb->() if $family == 6 && !$AnyEvent::PROTOCOL{ipv6};

   $family ||= 4 unless $AnyEvent::PROTOCOL{ipv6};
   $family ||= 6 unless $AnyEvent::PROTOCOL{ipv4};

   $proto ||= "tcp";
   $type  ||= $proto eq "udp" ? SOCK_DGRAM : SOCK_STREAM;

   my $proton = getprotobyname $proto
      or Carp::croak "$proto: protocol unknown";

   my $port;

   if ($service =~ /^(\S+)=(\d+)$/) {
      ($service, $port) = ($1, $2);
   } elsif ($service =~ /^\d+$/) {
      ($service, $port) = (undef, $service);
   } else {
      $port = (getservbyname $service, $proto)[2]
              or Carp::croak "$service/$proto: service unknown";
   }

   # resolve a records / provide sockaddr structures
   my $resolve = sub {
      my @target = @_;

      my @res;
      my $cv = AE::cv {
         $cb->(
            map $_->[2],
            sort {
               $AnyEvent::PROTOCOL{$b->[1]} <=> $AnyEvent::PROTOCOL{$a->[1]}
                  or $a->[0] <=> $b->[0]
            }
            @res
         )
      };

      $cv->begin;
      for my $idx (0 .. $#target) {
         my ($node, $port) = @{ $target[$idx] };

         if (my $noden = parse_address $node) {
            my $af = address_family $noden;

            if ($af == AF_INET && $family != 6) {
               push @res, [$idx, "ipv4", [AF_INET, $type, $proton,
                           pack_sockaddr $port, $noden]]
            }

            if ($af == AF_INET6 && $family != 4) {
               push @res, [$idx, "ipv6", [AF_INET6, $type, $proton,
                           pack_sockaddr $port, $noden]]
            }
         } else {
            # ipv4
            if ($family != 6) {
               $cv->begin;
               AnyEvent::DNS::a $node, sub {
                  push @res, [$idx, "ipv4", [AF_INET, $type, $proton,
                              pack_sockaddr $port, parse_ipv4 $_]]
                     for @_;
                  $cv->end;
               };
            }

            # ipv6
            if ($family != 4) {
               $cv->begin;
               AnyEvent::DNS::aaaa $node, sub {
                  push @res, [$idx, "ipv6", [AF_INET6, $type, $proton,
                              pack_sockaddr $port, parse_ipv6 $_]]
                     for @_;
                  $cv->end;
               };
            }
         }
      }
      $cv->end;
   };

   $node = AnyEvent::Util::idn_to_ascii $node
      if $node =~ /[^\x00-\x7f]/;

   # try srv records, if applicable
   if ($node eq "localhost") {
      $resolve->(["127.0.0.1", $port], ["::1", $port]);
   } elsif (defined $service && !parse_address $node) {
      AnyEvent::DNS::srv $service, $proto, $node, sub {
         my (@srv) = @_;

         if (@srv) {
            # the only srv record has "." ("" here) => abort
            $srv[0][2] ne "" || $#srv
               or return $cb->();

            # use srv records then
            $resolve->(
               map ["$_->[3].", $_->[2]],
                  grep $_->[3] ne ".",
                     @srv
            );
         } else {
            # no srv records, continue traditionally
            $resolve->([$node, $port]);
         }
      };
   } else {
      # most common case
      $resolve->([$node, $port]);
   }
}

=item $guard = tcp_connect $host, $service, $connect_cb[, $prepare_cb]

This is a convenience function that creates a TCP socket and makes a
100% non-blocking connect to the given C<$host> (which can be a DNS/IDN
hostname or a textual IP address, or the string C<unix/> for UNIX domain
sockets) and C<$service> (which can be a numeric port number or a service
name, or a C<servicename=portnumber> string, or the pathname to a UNIX
domain socket).

If both C<$host> and C<$port> are names, then this function will use SRV
records to locate the real target(s).

In either case, it will create a list of target hosts (e.g. for multihomed
hosts or hosts with both IPv4 and IPv6 addresses) and try to connect to
each in turn.

After the connection is established, then the C<$connect_cb> will be
invoked with the socket file handle (in non-blocking mode) as first and
the peer host (as a textual IP address) and peer port as second and third
arguments, respectively. The fourth argument is a code reference that you
can call if, for some reason, you don't like this connection, which will
cause C<tcp_connect> to try the next one (or call your callback without
any arguments if there are no more connections). In most cases, you can
simply ignore this argument.

   $cb->($filehandle, $host, $port, $retry)

If the connect is unsuccessful, then the C<$connect_cb> will be invoked
without any arguments and C<$!> will be set appropriately (with C<ENXIO>
indicating a DNS resolution failure).

The callback will I<never> be invoked before C<tcp_connect> returns, even
if C<tcp_connect> was able to connect immediately (e.g. on unix domain
sockets).

The file handle is perfect for being plugged into L<AnyEvent::Handle>, but
can be used as a normal perl file handle as well.

Unless called in void context, C<tcp_connect> returns a guard object that
will automatically abort connecting when it gets destroyed (it does not do
anything to the socket after the connect was successful).

Sometimes you need to "prepare" the socket before connecting, for example,
to C<bind> it to some port, or you want a specific connect timeout that
is lower than your kernel's default timeout. In this case you can specify
a second callback, C<$prepare_cb>. It will be called with the file handle
in not-yet-connected state as only argument and must return the connection
timeout value (or C<0>, C<undef> or the empty list to indicate the default
timeout is to be used).

Note that the socket could be either a IPv4 TCP socket or an IPv6 TCP
socket (although only IPv4 is currently supported by this module).

Note to the poor Microsoft Windows users: Windows (of course) doesn't
correctly signal connection errors, so unless your event library works
around this, failed connections will simply hang. The only event libraries
that handle this condition correctly are L<EV> and L<Glib>. Additionally,
AnyEvent works around this bug with L<Event> and in its pure-perl
backend. All other libraries cannot correctly handle this condition. To
lessen the impact of this windows bug, a default timeout of 30 seconds
will be imposed on windows. Cygwin is not affected.

Simple Example: connect to localhost on port 22.

   tcp_connect localhost => 22, sub {
      my $fh = shift
         or die "unable to connect: $!";
      # do something
   };

Complex Example: connect to www.google.com on port 80 and make a simple
GET request without much error handling. Also limit the connection timeout
to 15 seconds.

   tcp_connect "www.google.com", "http",
      sub {
         my ($fh) = @_
            or die "unable to connect: $!";

         my $handle; # avoid direct assignment so on_eof has it in scope.
         $handle = new AnyEvent::Handle
            fh     => $fh,
            on_error => sub {
               warn "error $_[2]\n";
               $_[0]->destroy;
            },
            on_eof => sub {
               $handle->destroy; # destroy handle
               warn "done.\n";
            };

         $handle->push_write ("GET / HTTP/1.0\015\012\015\012");

         $handle->push_read (line => "\015\012\015\012", sub {
            my ($handle, $line) = @_;

            # print response header
            print "HEADER\n$line\n\nBODY\n";

            $handle->on_read (sub {
               # print response body
               print $_[0]->rbuf;
               $_[0]->rbuf = "";
            });
         });
      }, sub {
         my ($fh) = @_;
         # could call $fh->bind etc. here

         15
      };

Example: connect to a UNIX domain socket.

   tcp_connect "unix/", "/tmp/.X11-unix/X0", sub {
      ...
   }

=cut

sub tcp_connect($$$;$) {
   my ($host, $port, $connect, $prepare) = @_;

   # see http://cr.yp.to/docs/connect.html for some tricky aspects
   # also http://advogato.org/article/672.html

   my %state = ( fh => undef );

   # name/service to type/sockaddr resolution
   resolve_sockaddr $host, $port, 0, 0, undef, sub {
      my @target = @_;

      $state{next} = sub {
         return unless exists $state{fh};

         my $target = shift @target
            or return (%state = (), _postpone $connect);

         my ($domain, $type, $proto, $sockaddr) = @$target;

         # socket creation
         socket $state{fh}, $domain, $type, $proto
            or return $state{next}();

         fh_nonblocking $state{fh}, 1;
         
         my $timeout = $prepare && $prepare->($state{fh});

         $timeout ||= 30 if AnyEvent::WIN32;

         $state{to} = AE::timer $timeout, 0, sub {
            $! = Errno::ETIMEDOUT;
            $state{next}();
         } if $timeout;

         # now connect       
         if (
            (connect $state{fh}, $sockaddr)
            || ($! == Errno::EINPROGRESS # POSIX
                || $! == Errno::EWOULDBLOCK
                # WSAEINPROGRESS intentionally not checked - it means something else entirely
                || $! == AnyEvent::Util::WSAEINVAL # not convinced, but doesn't hurt
                || $! == AnyEvent::Util::WSAEWOULDBLOCK)
         ) {
            $state{ww} = AE::io $state{fh}, 1, sub {
               # we are connected, or maybe there was an error
               if (my $sin = getpeername $state{fh}) {
                  my ($port, $host) = unpack_sockaddr $sin;

                  delete $state{ww}; delete $state{to};

                  my $guard = guard { %state = () };

                  $connect->(delete $state{fh}, format_address $host, $port, sub {
                     $guard->cancel;
                     $state{next}();
                  });
               } else {
                  if ($! == Errno::ENOTCONN) {
                     # dummy read to fetch real error code if !cygwin
                     sysread $state{fh}, my $buf, 1;

                     # cygwin 1.5 continously reports "ready' but never delivers
                     # an error with getpeername or sysread.
                     # cygwin 1.7 only reports readyness *once*, but is otherwise
                     # the same, which is atcually more broken.
                     # Work around both by using unportable SO_ERROR for cygwin.
                     $! = (unpack "l", getsockopt $state{fh}, Socket::SOL_SOCKET(), Socket::SO_ERROR()) || Errno::EAGAIN
                        if AnyEvent::CYGWIN && $! == Errno::EAGAIN;
                  }

                  return if $! == Errno::EAGAIN; # skip spurious wake-ups

                  delete $state{ww}; delete $state{to};

                  $state{next}();
               }
            };
         } else {
            $state{next}();
         }
      };

      $! = Errno::ENXIO;
      $state{next}();
   };

   defined wantarray && guard { %state = () }
}

=item $guard = tcp_server $host, $service, $accept_cb[, $prepare_cb]

Create and bind a stream socket to the given host, and port, set the
SO_REUSEADDR flag (if applicable) and call C<listen>. Unlike the name
implies, this function can also bind on UNIX domain sockets.

For internet sockets, C<$host> must be an IPv4 or IPv6 address (or
C<undef>, in which case it binds either to C<0> or to C<::>, depending
on whether IPv4 or IPv6 is the preferred protocol, and maybe to both in
future versions, as applicable).

To bind to the IPv4 wildcard address, use C<0>, to bind to the IPv6
wildcard address, use C<::>.

The port is specified by C<$service>, which must be either a service name or
a numeric port number (or C<0> or C<undef>, in which case an ephemeral
port will be used).

For UNIX domain sockets, C<$host> must be C<unix/> and C<$service> must be
the absolute pathname of the socket. This function will try to C<unlink>
the socket before it tries to bind to it. See SECURITY CONSIDERATIONS,
below.

For each new connection that could be C<accept>ed, call the C<<
$accept_cb->($fh, $host, $port) >> with the file handle (in non-blocking
mode) as first and the peer host and port as second and third arguments
(see C<tcp_connect> for details).

Croaks on any errors it can detect before the listen.

If called in non-void context, then this function returns a guard object
whose lifetime it tied to the TCP server: If the object gets destroyed,
the server will be stopped (but existing accepted connections will
continue).

If you need more control over the listening socket, you can provide a
C<< $prepare_cb->($fh, $host, $port) >>, which is called just before the
C<listen ()> call, with the listen file handle as first argument, and IP
address and port number of the local socket endpoint as second and third
arguments.

It should return the length of the listen queue (or C<0> for the default).

Note to IPv6 users: RFC-compliant behaviour for IPv6 sockets listening on
C<::> is to bind to both IPv6 and IPv4 addresses by default on dual-stack
hosts. Unfortunately, only GNU/Linux seems to implement this properly, so
if you want both IPv4 and IPv6 listening sockets you should create the
IPv6 socket first and then attempt to bind on the IPv4 socket, but ignore
any C<EADDRINUSE> errors.

Example: bind on some TCP port on the local machine and tell each client
to go away.

   tcp_server undef, undef, sub {
      my ($fh, $host, $port) = @_;

      syswrite $fh, "The internet is full, $host:$port. Go away!\015\012";
   }, sub {
      my ($fh, $thishost, $thisport) = @_;
      warn "bound to $thishost, port $thisport\n";
   };

Example: bind a server on a unix domain socket.

   tcp_server "unix/", "/tmp/mydir/mysocket", sub {
      my ($fh) = @_;
   };

=cut

sub tcp_server($$$;$) {
   my ($host, $service, $accept, $prepare) = @_;

   $host = $AnyEvent::PROTOCOL{ipv4} < $AnyEvent::PROTOCOL{ipv6} && AF_INET6
           ? "::" : "0"
      unless defined $host;

   my $ipn = parse_address $host
      or Carp::croak "AnyEvent::Socket::tcp_server: cannot parse '$host' as host address";

   my $af = address_family $ipn;

   my %state;

   # win32 perl is too stupid to get this right :/
   Carp::croak "tcp_server/socket: address family not supported"
      if AnyEvent::WIN32 && $af == AF_UNIX;

   socket $state{fh}, $af, SOCK_STREAM, 0
      or Carp::croak "tcp_server/socket: $!";

   if ($af == AF_INET || $af == AF_INET6) {
      setsockopt $state{fh}, SOL_SOCKET, SO_REUSEADDR, 1
         or Carp::croak "tcp_server/so_reuseaddr: $!"
            unless AnyEvent::WIN32; # work around windows bug

      unless ($service =~ /^\d*$/) {
         $service = (getservbyname $service, "tcp")[2]
                    or Carp::croak "$service: service unknown"
      }
   } elsif ($af == AF_UNIX) {
      unlink $service;
   }

   bind $state{fh}, pack_sockaddr $service, $ipn
      or Carp::croak "bind: $!";

   fh_nonblocking $state{fh}, 1;

   my $len;

   if ($prepare) {
      my ($service, $host) = unpack_sockaddr getsockname $state{fh};
      $len = $prepare && $prepare->($state{fh}, format_address $host, $service);
   }
   
   $len ||= 128;

   listen $state{fh}, $len
      or Carp::croak "listen: $!";

   $state{aw} = AE::io $state{fh}, 0, sub {
      # this closure keeps $state alive
      while ($state{fh} && (my $peer = accept my $fh, $state{fh})) {
         fh_nonblocking $fh, 1; # POSIX requires inheritance, the outside world does not

         my ($service, $host) = unpack_sockaddr $peer;
         $accept->($fh, format_address $host, $service);
      }
   };

   defined wantarray
      ? guard { %state = () } # clear fh and watcher, which breaks the circular dependency
      : ()
}

1;

=back

=head1 SECURITY CONSIDERATIONS

This module is quite powerful, with with power comes the ability to abuse
as well: If you accept "hostnames" and ports from untrusted sources,
then note that this can be abused to delete files (host=C<unix/>). This
is not really a problem with this module, however, as blindly accepting
any address and protocol and trying to bind a server or connect to it is
harmful in general.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

