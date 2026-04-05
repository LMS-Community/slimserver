# SOCKS Proxy and SSH Tunneling

SSH tunnel with port forwarding allows per port TCP/UDP traffic to be "forwarded" from one end of the tunnel to the other and appear like it was initiated from the remote end of tunnel. For example, all traffic sent to port `5000` on the local machine can be forwarded to a remote machine on port `25000` and will appear to any client on the remote side as if it was locally coming from port `25000`.

SOCKS is a type of proxy server that works at the TCP level. It usually sits on port `1080` and forwards TCP traffic from there. Because it works at the TCP level (contrary to classical HTTP proxies), it can be coupled to SSH tunnels to create very convenient firewall passthrough and geo-locked services unlocking. This tunneling is not an all-or-nothing tunnel and allows each TCP request to be selectively forwarded or not.

You must first either use a public SOCKS server or create your own SOCKS/SSH pair, in which case you must have a local SOCKS server, a local SSH client, and a remote SSH server. On Linux, OpenSSH does everything: one local instance with dynamic port forwarding (`-D`) and a remote instance to a friend's network does the job. On Windows, you can use Bitvise Client & Server. There is plenty of internet literature on SOCKS/SSH that explains the concept much better than anything I could write :slightly_smiling_face:

```
HTTP request ------> SOCKS client ------||-----> SOCKS server ------> www.google.com
>www.google.com    >some.socks.com      ||     >www.google.com      >5000
>5000              >1080                ||     >5000                (from some.socks.com)

HTTP request ------> SOCKS client ----> SOCKS relay  (encrypted)   SOCKS server -----> www.google.com
>www.google.com    >192.168.0.1       >SSH client  -----||----> >SSH server          >5000
>5000              >1080              >some.ssh.com     ||      >www.google.com
                                      >23               ||      >5000 (from some.ssh.com)
```

One thing to notice with SOCKS5 is the lack of proper authentication mechanism, which means that if you have a username/password, they will be sent in clear to the server. SOCKS4 does not require authentication. That's why I prefer to have a local SOCKS server that creates an SSH tunnel to a remote end, but this means you must have a SSH remote end.

To use a SOCKS proxy for your HTTP requests, simply pass a hash named `socks` to [`Slim::Networking::SimpleAsyncHTTP::new`](Slim/Networking/SimpleAsyncHTTP.pm) or [`Slim::Networking::Async::HTTP::new`](Slim/Networking/Async/HTTP.pm) with the following content. See also [`IO::Socket::Socks`](https://metacpan.org/pod/IO::Socket::Socks):

```perl
my $http = Slim::Networking::SimpleAsyncHTTP->new(
    sub { # success CB },
    sub { # error CB },
    {
        socks => {
            ProxyAddr => '192.168.0.1',
            ProxyPort => 1080,
            Username  => 'user',
            Password  => 'password',
        }
    }
);

$http->get("http://www.google.com")

# or

my $http = Slim::Networking::Async::HTTP->new({
    socks => {
        ProxyAddr => '192.168.0.1',
        ProxyPort => 1080,
        Username  => 'user',
        Password  => 'password',
    }
});
$http->send_request({
    'request'     => HTTP::Request->new( GET => "http://www.google.com" ),
    'onHeaders'   => sub { },
    'onError'     => sub { },
    'passthrough' => [ $p1, $p2 ],
});
```

Note that `Username` and `Password` are optional. SOCKS version is set to 5 if they are set and to 4 otherwise. `ProxyPort` can be omitted and will be set to `1080`.

If the `socks` hash is set but `ProxyAddr` is missing, a regular [`Slim::Networking::SimpleAsyncHTTP`](Slim/Networking/SimpleAsyncHTTP.pm) or [`Slim::Networking::Async::HTTP`](Slim/Networking/Async/HTTP.pm) call will be made.
