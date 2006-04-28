package Slim::Networking::SimpleAsyncHTTP;

# $Id$

# SlimServer Copyright (c) 2003-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# this class provides non-blocking http requests from SlimServer.
# That is, use this class for your http requests to ensure that
# SlimServer does not become unresponsive, or allow music to pause,
# while your code waits for a response

# This class is intended for plugins and other code needing simply to
# process the result of an http request.  If you have more complex
# needs, i.e. handle an http stream, or just interested in headers,
# take a look at HttpAsync.

# more documentation at end of file.

use strict;

use Slim::Networking::AsyncHTTP;
use Slim::Utils::Cache;
use Slim::Utils::Misc;

use HTTP::Date ();
use MIME::Base64 qw(encode_base64);

sub new {
	my $class    = shift;
	my $callback = shift;
	my $errorcb  = shift;
	my $params   = shift || {};

	my $self = {
		'cb'     => $callback,
		'ecb'    => $errorcb,
		'params' => $params,
	};

	return bless $self, $class;
}

sub params {
	my ($self, $key, $value) = @_;

	if (!defined($key)) {

		return $self->{'params'};

	} elsif ($value) {

		$self->{'params'}->{$key} = $value;

	} else {

		return $self->{'params'}->{$key};
	}
}

sub get {
	my $self = shift;

	$self->_createHTTPRequest('GET', @_);
}

sub post {
	my $self = shift;

	$self->_createHTTPRequest('POST', @_);
}

sub head {
	my $self = shift;
	
	$self->_createHTTPRequest('HEAD', @_);
}

# Parameters are passed to Net::HTTP::NB::formatRequest, meaning you
# can override default headers, and pass in content.
# Examples:
# $http->post("www.somewhere.net", 'conent goes here');
# $http->post("www.somewhere.net", 'Content-Type' => 'application/x-foo', 'Other-Header' => 'Other Value', 'conent goes here');
sub _createHTTPRequest {
	my $self = shift;
	my $type = shift;
	my $url  = shift;
	my @args = @_;

	$self->{'type'} = $type;
	$self->{'url'}  = $url;
	$self->{'args'} = \@args;

	$::d_http_async && msg("SimpleAsyncHTTP: ${type}ing $url\n");
	
	# start asynchronous get
	# we'll be called back when its done.
	my ($server, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($url);
	
	$self->{'server'}   = $server;
	$self->{'port'}     = $port;
	$self->{'path'}     = $path;
	$self->{'user'}     = $user;
	$self->{'password'} = $password;
	
	# Check for cached response
	if ( $self->{'params'}->{'cache'} ) {
		
		my $cache = Slim::Utils::Cache->new();
		
		if ( my $data = $cache->get( $self->{'url'} ) ) {			
			$self->{'cachedResponse'} = $data;
			
			# If the data was cached within the past 5 minutes,
			# return it immediately without revalidation, to improve
			# UI experience
			if ( $data->{_no_revalidate} || time - $data->{'_time'} < 300 ) {
				
				$::d_http_async && msgf("SimpleAsyncHTTP: Using cached response [%s]\n",
					$self->{'url'},
				);
				
				return $self->sendCachedResponse();
			}
		}
	}
	
	my $timeout 
		=  $self->{'params'}->{'Timeout'} 
		|| Slim::Utils::Prefs::get('remotestreamtimeout')
		|| 10;
	
	# This is now non-blocking
	my $http = Slim::Networking::AsyncHTTP->new(
		Host     => $server,
		PeerPort => $port,
		Timeout  => $timeout,
		
		errorCallback => \&errorCallback,
		writeCallback => \&writeCallback,
		callbackArgs  => [ $self ],
	);
}

sub errorCallback {
	my $http = shift;
	my $self = shift;

	my $server = $self->{'server'};
	my $port   = $self->{'port'};
	
	# If we have a cached copy of this request, we can use it
	if ( $self->{'cachedResponse'} ) {
		$::d_http_async && msg(
			"SimpleAsyncHTTP: Failed to connect to $server:$port, using cached copy.  Perl's error is '$!'.\n"
		);
		
		return $self->sendCachedResponse();
	}
	
	$self->{'error'} = "Failed to connect to $server:$port.  Perl's error is '$!'.\n";
	&{$self->{'ecb'}}($self);
	return;
}

sub writeCallback {
	my $http = shift;
	my $self = shift;
	
	# If cached, add If-None-Match and If-Modified-Since headers
	if ( my $data = $self->{'cachedResponse'} ) {			
		push @{ $self->{'args'} }, (
			'If-None-Match'     => $data->{'headers'}->{'ETag'} || undef,
			'If-Modified-Since' => $data->{'headers'}->{'Last-Modified'} || undef,
		);
	}

	# handle basic auth if username, password provided
	if ( $self->{'user'} || $self->{'password'} ) {
		push @{ $self->{'args'} }, (
			'Authorization' => 'Basic ' . encode_base64( $self->{'user'} . ":" . $self->{'password'} ),
		);
	}
	
	$http->write_request_async( 
		$self->{'type'} => $self->{'path'}, 
		@{ $self->{'args'} } 
	);
	
	$http->read_response_headers_async(\&headerCB, {
		'simple' => $self,
		'socket' => $http,
	});

	$self->{'socket'} = $http;
}

sub headerCB {
	my ($state, $error, $code, $mess, %h) = @_;
	
	# Don't leak the reference to ourselves.
	my $self = delete $state->{'simple'};
	my $http = delete $state->{'socket'};

	$::d_http_async && msgf("SimpleAsyncHTTP: status for %s is %s - fileno: %d\n", $self->{'url'}, ($mess || $code), fileno($http));

	# verbose debug
	#use Data::Dumper;
	#print Dumper(\%h);

	# handle http redirect
	my $location = $h{'Location'} || $h{'location'};

	if (defined $location) {

		$::d_http_async && msg("SimpleAsyncHTTP: redirecting to $location.  Original URL ". $self->{'url'} . "\n");

		$self->get($location);

		$http->close();

		return;
	}

	if ($error) {

		&{$self->{'ecb'}}($self);

	} else {
		
		# Check if we are cached and got a "Not Modified" response
		if ( $self->{'cachedResponse'} && $code == 304) {
			
			$::d_http_async && msg("SimpleAsyncHTTP: Remote file not modified, using cached content\n");
			
			# update the cache time so we get another 5 minutes with no revalidation
			my $cache = Slim::Utils::Cache->new();
			$self->{'cachedResponse'}->{'_time'} = time;
			my $expires = $self->{'cachedResponse'}->{'_expires'} || undef;
			$cache->set( $self->{'url'}, $self->{'cachedResponse'}, $expires );
			
			return $self->sendCachedResponse();
		}

		$self->{'code'}    = $code;
		$self->{'mess'}    = $mess;
		$self->{'headers'} = \%h;

		# headers read OK, get the body
		$http->read_entity_body_async(\&bodyCB, {
			'simple' => $self,
			'socket' => $http
		});
	}
}

sub bodyCB {
	my ($state, $error, $content) = @_;

	# Don't leak the reference to ourselves.
	my $self = delete $state->{'simple'};
	my $http = delete $state->{'socket'};

	if ($error) {

		&{$self->{'ecb'}}($self);

	} else {

		$self->{'content'} = \$content;
		
		# cache the response if requested
		if ( $self->{'params'}->{'cache'} ) {
			
			my $cache = Slim::Utils::Cache->new();
			
			my $data = {
				code    => $self->{'code'},
				mess    => $self->{'mess'},
				headers => $self->{'headers'},
				content => \$content,
				_time   => time,
			};
			
			# By default, cached content never expires
			# The ETag/Last Modified code will handle stale data
			my $expires = $self->{'params'}->{'expires'} || undef;
					
			my $no_cache;
			
			if ( !$expires ) {
				
				# If we see max-age or an Expires header, use them
				if ( my $cc = $self->{'headers'}->{'Cache-Control'} ) {
					if ( $cc =~ /no-cache|must-revalidate/ ) {
						$no_cache = 1;
					}
					elsif ( $cc =~ /max-age=(-?\d+)/ ) {
						$expires = $1;
					}
				}			
				elsif ( my $expire_date = $self->{'headers'}->{'Expires'} ) {
					$expires = HTTP::Date::str2time($expire_date) - time;
				}
			
				# If there is no ETag/Last Modified, don't cache
				if (   !$expires
					&& !$self->{'headers'}->{'Last-Modified'} 
					&& !$self->{'headers'}->{'ETag'}
				) {
					$no_cache = 1;
					$::d_http_async && msgf("SimpleAsyncHTTP: Not caching [%s], no expiration set and missing cache headers\n",
						$self->{'url'},
					);
				}
			}
			
			if ( defined $expires && $expires > 0) {
				# if we have an explicit expiration time, we can avoid revalidation
				$data->{'_no_revalidate'} = 1;
			}
			
			if ( !$no_cache && $expires > 0 ) {
				$data->{'_expires'} = $expires;
				$cache->set( $self->{'url'}, $data, $expires );
				
				$::d_http_async && msgf("SimpleAsyncHTTP: Caching [%s] for %d seconds\n",
					$self->{'url'},
					$expires,
				);
			}
		}

		&{$self->{'cb'}}($self);
	}

	$self->close;
}

sub sendCachedResponse {
	my $self = shift;
	
	my $data = $self->{'cachedResponse'};
	
	# populate the object with cached data			
	$self->{'code'}    = $data->{'code'};
	$self->{'mess'}    = $data->{'mess'};
	$self->{'headers'} = $data->{'headers'};
	$self->{'content'} = $data->{'content'};
		
	&{$self->{'cb'}}($self);
	return;
}

sub content {
	my $self = shift;

	return ${$self->{'content'}};
}

sub contentRef {
	my $self = shift;

	return $self->{'content'};
}

sub headers {
	my $self = shift;

	return $self->{'headers'};
}

sub url {
	my $self = shift;

	return $self->{'url'};
}

sub error {
	my $self = shift;

	return $self->{'error'};
}

sub close {
	my $self = shift;

	if (defined $self->{'socket'} && fileno($self->{'socket'})) {

		$self->{'socket'}->close;
	}
}

sub DESTROY {
	my $self = shift;

	$::d_http_async && msgf("SimpleAsyncHTTP(%s) destroy called.\n", $self->url);

	$self->close;
}

1;

__END__

=head NAME

Slim::Networking::SimpleAsyncHTTP - asynchronous non-blocking HTTP client

=head SYNOPSIS

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

This class provides a way within the SlimServer to make an http
request in an asynchronous, non-blocking way.  This is important
because the server will remain responsive and continue streaming audio
while your code waits for the response.

=cut

