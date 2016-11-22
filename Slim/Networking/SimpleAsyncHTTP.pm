package Slim::Networking::SimpleAsyncHTTP;

# Logitech Media Server Copyright 2003-2016 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# this class provides non-blocking http requests from Logitech Media Server.
# That is, use this class for your http requests to ensure that
# Logitech Media Server does not become unresponsive, or allow music to pause,
# while your code waits for a response

# This class is intended for plugins and other code needing simply to
# process the result of an http request.  If you have more complex
# needs, i.e. handle an http stream, or just interested in headers,
# take a look at HttpAsync.

# more documentation at end of file.

use strict;

use base qw(Slim::Utils::Accessor);

use Slim::Networking::Async::HTTP;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use HTTP::Date ();
use HTTP::Request;

my $prefs = preferences('server');

my $log = logger('network.asynchttp');

__PACKAGE__->mk_accessor( rw => qw(
	cb ecb _params type url error code mess headers contentRef cacheTime cachedResponse
) );

BEGIN {
	my $hasZlib;
	
	sub hasZlib {
		return $hasZlib if defined $hasZlib;
		
		$hasZlib = 0;
		eval { 
			require Compress::Raw::Zlib;
			require IO::Compress::Gzip::Constants;
			$hasZlib = 1;
		};
	}
}

sub init {
=pod
	Slim::Networking::Slimproto::addHandler( HTTP => \&playerHTTPResponse );
	Slim::Networking::Slimproto::addHandler( HTTE => \&playerHTTPError );
=cut
}

sub new {
	my $class = shift;
	
	my $self = $class->SUPER::new();
	
	$self->cb(shift);
	$self->ecb(shift);
	$self->_params( shift || {} );
	
	return $self;
}

sub params {
	my ($self, $key, $value) = @_;

	if ( !defined $key ) {
		return $self->_params;
	}
	elsif ( $value ) {
		$self->_params->{$key} = $value;
	}
	else {
		return $self->_params->{$key};
	}
}

sub get { shift->_createHTTPRequest( GET => @_ ) }

sub post { shift->_createHTTPRequest( POST => @_ ) }

sub head { shift->_createHTTPRequest( HEAD => @_ ) }

# Parameters are passed to Net::HTTP::NB::formatRequest, meaning you
# can override default headers, and pass in content.
# Examples:
# $http->post("www.somewhere.net", 'conent goes here');
# $http->post("www.somewhere.net", 'Content-Type' => 'application/x-foo', 'Other-Header' => 'Other Value', 'conent goes here');
sub _createHTTPRequest {
	my $self = shift;
	my $type = shift;
	my $url  = shift;

	$self->type( $type );
	$self->url( $url );
	
	my $params = $self->_params;
	my $client = $params->{params}->{client};
		
	main::DEBUGLOG && $log->debug("${type}ing $url");
	
	# Check for cached response
	if ( $params->{cache} ) {
		
		my $cache = Slim::Utils::Cache->new();
		
		if ( my $data = $cache->get( _cacheKey($url, $client) ) ) {			
			$self->cachedResponse( $data );
			
			# If the data was cached within the past 5 minutes,
			# return it immediately without revalidation, to improve
			# UI experience
			if ( $data->{_no_revalidate} || time - $data->{_time} < 300 ) {
				
				main::DEBUGLOG && $log->debug("Using cached response [$url]");
				
				return $self->sendCachedResponse();
			}
		}
	}
	
	my $timeout 
		=  $params->{Timeout}
		|| $params->{timeout}
		|| $prefs->get('remotestreamtimeout');
		
	my $request = HTTP::Request->new( $type => $url );
	
	if ( @_ % 2 ) {
		$request->content( pop @_ );
	}
	
	# If cached, add If-None-Match and If-Modified-Since headers
	my $data = $self->cachedResponse;
	if ( $data && ref $data && $data->{headers} ) {
		# gzip encoded results come with a -gzip postfix which needs to be removed, or the etag would not match
		my $etag = $data->{headers}->header('ETag') || undef;
		$etag =~ s/-gzip// if $etag;

		# if the last_modified value is a UNIX timestamp, convert it
		my $lastModified = $data->{headers}->last_modified || undef;
		$lastModified = HTTP::Date::time2str($lastModified) if $lastModified && $lastModified !~ /\D/;

		unshift @_, (
			'If-None-Match'     => $etag,
			'If-Modified-Since' => $lastModified
		);
	}

	# request compressed data if we have zlib
	if ( hasZlib() && !$params->{saveAs} ) {
		unshift @_, (
			'Accept-Encoding' => 'deflate, gzip', # deflate is less overhead than gzip
		);
	}
	
	# Add Accept-Language header
	my $lang;
	if ( $client ) {
		$lang = $client->languageOverride(); # override from comet request
	}

	$lang ||= $prefs->get('language') || 'en';
		
	unshift @_, (
		'Accept-Language' => lc($lang),
	);
	
	if ( @_ ) {
		$request->header( @_ );
	}
	
=pod
	# Use the player for making the HTTP connection if requested
	if ( my $client = $params->{usePlayer} ) {
		# We still have to do DNS lookups in SC unless
		# we have an IP host
		if ( Slim::Utils::Network::ip_is_ipv4( $request->uri->host ) ) {
			sendPlayerRequest( $request->uri->host, $self, $client, $request );
		}
		else {
			my $dns = Slim::Networking::Async->new;
			$dns->open( {
				Host        => $request->uri->host,
				onDNS       => \&sendPlayerRequest,
				onError     => \&onError,
				passthrough => [ $self, $client, $request ],
			} );
		}
		return;
	}
=cut
	
	my $http = Slim::Networking::Async::HTTP->new;
	$http->send_request( {
		request     => $request,
		maxRedirect => $params->{maxRedirect},
		saveAs      => $params->{saveAs},
		Timeout     => $timeout,
		onError     => \&onError,
		onBody      => \&onBody,
		passthrough => [ $self ],
	} );
}

sub onError {
	my ( $http, $error, $self ) = @_;
	
	my $uri = $http->request->uri;
	
	# If we have a cached copy of this request, we can use it
	if ( $self->cachedResponse ) {

		$log->warn("Failed to connect to $uri, using cached copy. ($error)");
		
		return $self->sendCachedResponse();
	}
	else {
		$log->warn("Failed to connect to $uri ($error)");
	}
	
	$self->error( $error );

	main::PERFMON && (my $now = AnyEvent->time);
	
	$self->ecb->( $self, $error );

	main::PERFMON && $now && Slim::Utils::PerfMon->check('async', AnyEvent->time - $now, undef, $self->ecb);
	
	return;
}

sub onBody {
	my ( $http, $self ) = @_;
	
	my $req = $http->request;
	my $res = $http->response;
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug(sprintf("status for %s is %s", $self->url, $res->status_line ));
	}
	
	$self->code( $res->code );
	$self->mess( $res->message );
	$self->headers( $res->headers );
	
	if ( !$http->saveAs ) {

		my $params = $self->_params;
		my $client = $params->{params}->{client};
	
		# Check if we are cached and got a "Not Modified" response
		if ( $self->cachedResponse && $res->code == 304) {
		
			main::DEBUGLOG && $log->debug("Remote file not modified, using cached content");
		
			# update the cache time so we get another 5 minutes with no revalidation
			my $cache = Slim::Utils::Cache->new();
			$self->cachedResponse->{_time} = time;
			my $expires = $self->cachedResponse->{_expires} || undef;
			$cache->set( _cacheKey($self->url, $client), $self->cachedResponse, $expires );
		
			return $self->sendCachedResponse();
		}
		
		$self->contentRef( $res->content_ref );
	
		# unzip if necessary
		if ( hasZlib() ) {
			
			if ( my $ce = $res->header('Content-Encoding') ) {

				my ($x, $status) = Compress::Raw::Zlib::Inflate->new( {
					-WindowBits => -Compress::Raw::Zlib::MAX_WBITS(),
				} );
				
				if ( $ce eq 'gzip' ) {
					_removeGzipHeader( $res->content_ref );
				}
					
				my $output = '';
				$status = $x->inflate( $res->content_ref, $output );
				
				# Formats::XML requires a scalar ref
				$self->contentRef( \$output );
			}
		}
		
		# cache the response if requested
		if ( $params->{cache} ) {
		
			if ( Slim::Utils::Misc::shouldCacheURL( $self->url ) ) {

				# By default, cached content can live for at most 1 day, this helps control the
				# size of the cache.  We use ETag/Last Modified to check for stale data during
				# this time.
				my $max = 60 * 60 * 24;
				my $expires;
				my $no_revalidate;
				
				if ( $params->{expires} ) {
					# An explicit expiration time from the caller
					$expires = $params->{expires};
				}
				else {			
					# If we see max-age or an Expires header, use them
					if ( my $cc = $res->header('Cache-Control') ) {
						if ( $cc =~ /max-age=(-?\d+)/i ) {
							$expires = $1;
						}
						
						if ( $cc =~ /no-cache|no-store|must-revalidate/i ) {
							$expires = 0;
						}
					}			
					elsif ( my $expire_date = $res->header('Expires') ) {
						$expires = HTTP::Date::str2time($expire_date) - time;
					}
				}
				
				# Don't cache for more than $max
				if ( $expires && $expires > $max ) {
					$expires = $max;
				}
				
				$self->cacheTime( $expires );
				
				# Only cache if we found an expiration time
				if ( $expires ) {
					if ( $expires < $max ) {
						# if we have an explicit expiration time, we can avoid revalidation
						$no_revalidate = 1;
					}

					$self->cacheResponse( $expires, $no_revalidate, $client );
				}
				else {
					if ( main::DEBUGLOG && $log->is_debug ) {
						$log->debug(sprintf("Not caching [%s], no expiration set and missing cache headers", $self->url));
					}
				}
			}
		}
	}
	
	main::DEBUGLOG && $log->debug("Done");

	main::PERFMON && (my $now = AnyEvent->time);
	
	$self->cb->( $self );

	main::PERFMON && $now && Slim::Utils::PerfMon->check('async', AnyEvent->time - $now, undef, $self->cb);

	return;
}

sub _cacheKey {
	my ( $url, $client ) = @_;
	
	my $cachekey = $url;
	
	if ($client) {
		$cachekey .= '-' . ($client->languageOverride || '');
	}
	
	return $cachekey;
}

sub cacheResponse {
	my ( $self, $expires, $norevalidate, $client ) = @_;

	if ( main::INFOLOG && $log->is_info ) {
		$log->info(sprintf("Caching [%s] for %d seconds", $self->url, $expires));
	}

	my $cache = Slim::Utils::Cache->new();
	
	my $data = {
		code     => $self->code,
		mess     => $self->mess,
		headers  => $self->headers,
		content  => $self->content,
		_time    => time,
		_expires => $expires,
		_no_revalidate => $norevalidate,
	};

	$cache->set( _cacheKey($self->url, $client), $data, $expires );
}

sub sendCachedResponse {
	my $self = shift;
	
	my $data = $self->cachedResponse;
	
	# populate the object with cached data			
	$self->code( $data->{code} );
	$self->mess( $data->{mess} );
	$self->headers( $data->{headers} );
	$self->contentRef( \$data->{content} );

	main::PERFMON && (my $now = AnyEvent->time);
	
	$self->cb->( $self );

	main::PERFMON && $now && Slim::Utils::PerfMon->check('async', AnyEvent->time - $now, undef, $self->cb);
	
	return;
}

=pod
sub sendPlayerRequest {
	my ( $ip, $self, $client, $request ) = @_;
	
	# Set protocol
	$request->protocol( 'HTTP/1.0' );
	
	# Add headers
	my $headers = $request->headers;
	
	my $host = $request->uri->host;
	my $port = $request->uri->port;
	if ( $port != 80 ) {
		$host .= ':' . $port;
	}
	
	# Fix URI to be relative
	# XXX: Proxy support
	my $fullpath = $request->uri->path_query;
	$fullpath = "/$fullpath" unless $fullpath =~ /^\//;
	$request->uri( $fullpath );

	# Host doesn't use init_header so it will be changed if we're redirecting
	$headers->header( Host => $host );
	
	$headers->init_header( 'User-Agent'    => Slim::Utils::Misc::userAgentString() );
	$headers->init_header( Accept          => '*/*' );
	$headers->init_header( 'Cache-Control' => 'no-cache' );
	$headers->init_header( Connection      => 'close' );
	$headers->init_header( 'Icy-Metadata'  => 1 );
	
	if ( $request->content ) {
		$headers->init_header( 'Content-Length' => length( $request->content ) );
	}
	
	# Maintain state for http callback
	$client->httpState( {
		cb      => \&gotPlayerResponse,
		ip      => $ip,
		port    => $port,
		request => $request,
		self    => $self,
	} );
	
	my $requestStr = $request->as_string("\015\012");
	
	my $limit = $self->{params}->{limit} || 0;
	
	my $data = pack( 'NnCNn', Slim::Utils::Network::intip($ip), $port, 0, $limit, length($requestStr) );
	$data   .= $requestStr;
	
	$client->sendFrame( http => \$data );
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug(
			  "Using player " . $client->id 
			. " to send request to $ip:$port (limit $limit):\n" . $request->as_string
		);
	}
}

sub gotPlayerResponse {
	my ( $body_ref, $self, $request ) = @_;
	
	if ( length $$body_ref ) {
		# Buffer body chunks
		$self->{_body} .= $$body_ref;
		
		main::DEBUGLOG && $log->is_debug && $log->debug('Buffered ' . length($$body_ref) . ' bytes of player HTTP response');
	}
	else {
		# Response done
		# Turn the response into an HTTP::Response and handle as usual
		my $response = HTTP::Response->parse( delete $self->{_body} );

		# XXX: No support for redirects yet

		my $http = Slim::Networking::Async::HTTP->new();
		$http->request( $request );
		$http->response( $response );

		onBody( $http, $self );
	}
}

sub playerHTTPResponse {
	my ( $client, $data_ref ) = @_;
	
	my $state = $client->httpState;
	
	$state->{cb}->( $data_ref, $state->{self}, $state->{request} );		
}

sub playerHTTPError {
	my ( $client, $data_ref ) = @_;
	
	my $reason = unpack 'C', $$data_ref;
	
	# disconnection reasons
	my %reasons = (
		0   => 'Connection closed normally',              # TCP_CLOSE_FIN
		1   => 'Connection reset by local host',          # TCP_CLOSE_LOCAL_RST
		2   => 'Connection reset by remote host',         # TCP_CLOSE_REMOTE_RST
		3   => 'Connection is no longer able to work',    # TCP_CLOSE_UNREACHABLE
		4   => 'Connection timed out',                    # TCP_CLOSE_LOCAL_TIMEOUT
		255 => 'Connection in use',
	);
	
	my $error = $reasons{$reason};
	
	my $state = $client->httpState;
	my $self  = $state->{self};
	
	# Retry if connection was in use
	if ( $reason == 255 ) {
		main::DEBUGLOG && $log->is_debug && $log->debug( "Player HTTP connection was in use, retrying..." );
		
		Slim::Utils::Timers::setTimer(
			undef,
			Time::HiRes::time() + 0.5,
			sub {
				my $requestStr = $state->{request}->as_string("\015\012");

				my $limit = $self->{params}->{limit} || 0;

				my $data = pack( 'NnCNn', Slim::Utils::Network::intip( $state->{ip} ), $state->{port}, 0, $limit, length($requestStr) );
				$data   .= $requestStr;

				$client->sendFrame( http => \$data );
			},
		);
		
		return;
	}
	
	main::DEBUGLOG && $log->is_debug && $log->debug( "Player HTTP error: $error [$reason]" );
	
	$self->error( $error );
	
	$self->ecb->( $self, $error );
}
=cut

sub content { ${ shift->contentRef || \'' } }

sub close { }

# From Compress::Zlib, to avoid having to include all
# of new Compress::Zlib and IO::* compress modules
sub _removeGzipHeader($)
{
    my $string = shift ;

    return Compress::Raw::Zlib::Z_DATA_ERROR() 
        if length($$string) < IO::Compress::Gzip::Constants::GZIP_MIN_HEADER_SIZE();

    my ($magic1, $magic2, $method, $flags, $time, $xflags, $oscode) = 
        unpack ('CCCCVCC', $$string);

    return Compress::Raw::Zlib::Z_DATA_ERROR()
        unless $magic1 == IO::Compress::Gzip::Constants::GZIP_ID1() and $magic2 == IO::Compress::Gzip::Constants::GZIP_ID2() and
           $method == Compress::Raw::Zlib::Z_DEFLATED() and !($flags & IO::Compress::Gzip::Constants::GZIP_FLG_RESERVED()) ;
    substr($$string, 0, IO::Compress::Gzip::Constants::GZIP_MIN_HEADER_SIZE()) = '' ;

    # skip extra field
    if ($flags & IO::Compress::Gzip::Constants::GZIP_FLG_FEXTRA())
    {
        return Compress::Raw::Zlib::Z_DATA_ERROR()
            if length($$string) < IO::Compress::Gzip::Constants::GZIP_FEXTRA_HEADER_SIZE();

        my ($extra_len) = unpack ('v', $$string);
        $extra_len += IO::Compress::Gzip::Constants::GZIP_FEXTRA_HEADER_SIZE();
        return Compress::Raw::Zlib::Z_DATA_ERROR()
            if length($$string) < $extra_len ;

        substr($$string, 0, $extra_len) = '';
    }

    # skip orig name
    if ($flags & IO::Compress::Gzip::Constants::GZIP_FLG_FNAME())
    {
        my $name_end = index ($$string, IO::Compress::Gzip::Constants::GZIP_NULL_BYTE());
        return Compress::Raw::Zlib::Z_DATA_ERROR()
           if $name_end == -1 ;
        substr($$string, 0, $name_end + 1) =  '';
    }

    # skip comment
    if ($flags & IO::Compress::Gzip::Constants::GZIP_FLG_FCOMMENT())
    {
        my $comment_end = index ($$string, IO::Compress::Gzip::Constants::GZIP_NULL_BYTE());
        return Compress::Raw::Zlib::Z_DATA_ERROR()
            if $comment_end == -1 ;
        substr($$string, 0, $comment_end + 1) = '';
    }

    # skip header crc
    if ($flags & IO::Compress::Gzip::Constants::GZIP_FLG_FHCRC())
    {
        return Compress::Raw::Zlib::Z_DATA_ERROR()
            if length ($$string) < IO::Compress::Gzip::Constants::GZIP_FHCRC_SIZE();
        substr($$string, 0, IO::Compress::Gzip::Constants::GZIP_FHCRC_SIZE()) = '';
    }
    
    return Compress::Raw::Zlib::Z_OK();
}

1;

__END__

=head1 NAME

Slim::Networking::SimpleAsyncHTTP - asynchronous non-blocking HTTP client

=head1 SYNOPSIS

use Slim::Networking::SimpleAsyncHTTP

sub exampleErrorCallback {
    my $http = shift;

    print("Oh no! An error!\n");
}

sub exampleCallback {
    my $http = shift;

    my $content = $http->content();

    my $data = $http->params('mydata');

    print("Got the content and my data.\n");
}


my $http = Slim::Networking::SimpleAsyncHTTP->new(
	\&exampleCallback,
	\&exampleErrorCallback, 
	{
		mydata'  => 'foo',
		cache    => 1,		# optional, cache result of HTTP request
		expires => '1h',	# optional, specify the length of time to cache
	}
);

# sometime after this call, our exampleCallback will be called with the result
$http->get("http://www.slimdevices.com");

# that's all folks.

=head1 DESCRIPTION

This class provides a way within the Logitech Media Server to make an http
request in an asynchronous, non-blocking way.  This is important
because the server will remain responsive and continue streaming audio
while your code waits for the response.

=cut
