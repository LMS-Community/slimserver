package AnyEvent;

# XXX
# AnyEvent precompiles these at Make-time but that makes
# it platform-specific, so we have to do it differently at runtime
use Fcntl ();

eval "sub CYGWIN () {" . ($^O =~ /cygwin/i) . "}";
eval "sub WIN32 () {" . ($^O =~ /mswin32/i) . "}";

eval "sub F_SETFL () {" . eval { Fcntl::F_SETFL() } . "}";
eval "sub F_SETFD () {" . eval { Fcntl::F_SETFD() } . "}";
eval "sub O_NONBLOCK () {" . eval { Fcntl::O_NONBLOCK() } . "}";
eval "sub FD_CLOEXEC () {" . eval { Fcntl::FD_CLOEXEC() } . "}";

package AnyEvent::Util;

if (AnyEvent::WIN32) {
	eval "sub WSAEINVAL () { 10022 }";
	eval "sub WSAEWOULDBLOCK () { 10035 }";
	eval "sub WSAEINPROGRESS () { 10036 }";
}
else {
	eval "sub WSAEINVAL () { -1e+99 }";
	eval "sub WSAEWOULDBLOCK () { -1e+99 }";
	eval "sub WSAEINPROGRESS () { -1e+99 }";
}

my $af_inet6;

$af_inet6 ||= eval { require Socket ; Socket::AF_INET6 () };
$af_inet6 ||= eval { require Socket6; Socket6::AF_INET6() };

# uhoh
$af_inet6 ||= 10 if $^O =~ /linux/;
$af_inet6 ||= 23 if $^O =~ /cygwin/i;
$af_inet6 ||= 23 if AnyEvent::WIN32;
$af_inet6 ||= 24 if $^O =~ /openbsd|netbsd/;
$af_inet6 ||= 28 if $^O =~ /freebsd/;

eval "sub _AF_INET6 () {" . $af_inet6 . "}";

1;
