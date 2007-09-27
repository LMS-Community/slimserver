package Slim::Networking::SimpleAsyncHTTP;

# $Id$

# SqueezeCenter Copyright (c) 2003-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# this class provides non-blocking http requests from SqueezeCenter.
# That is, use this class for your http requests to ensure that
# SqueezeCenter does not become unresponsive, or allow music to pause,
# while your code waits for a response

# This class is intended for plugins and other code needing simply to
# process the result of an http request.  If you have more complex
# needs, i.e. handle an http stream, or just interested in headers,
# take a look at HttpAsync.

# more documentation at end of file.

use strict;
use warnings;

use base 'Class::Data::Accessor';

use Slim::Networking::Async::HTTP;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use HTTP::Date ();
use HTTP::Request;

our $callbackTask = Slim::Utils::PerfMon->new('Async Callback', [0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.5, 1, 5]);

my $log = logger('network.asynchttp');

__PACKAGE__->mk_classaccessors( qw(
	cb ecb type url error code mess headers contentRef cachedResponse async
) );

BEGIN {
	my $hasZlib;
	
	sub hasZlib {
		return $hasZlib if defined $hasZlib;
		
		$hasZlib = 0;
		eval { 
			require Compress::Zlib;
			$hasZlib = 1;
		};
	}
}

sub new {
	my $class    = shift;
	my $callback = shift;
	my $errorcb  = shift;
	my $params   = shift || {};

	my $self = {
		cb     => $callback,
		ecb    => $errorcb,
		params => $params,
	};

	return bless $self, ref($class) || $class;
}

sub params {
	my ($self, $key, $value) = @_;

	if ( !defined $key ) {
		return $self->{params};
	}
	elsif ( $value ) {
		$self->{params}->{$key} = $value;
	}
	else {
		return $self->{params}->{$key};
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

	$log->debug("${type}ing $url");
	
	# Check for cached response
	if ( $self->{params}->{cache} ) {
		
		my $cache = Slim::Utils::Cache->new();
		
		if ( my $data = $cache->get( $url ) ) {			
			$self->cachedResponse( $data );
			
			# If the data was cached within the past 5 minutes,
			# return it immediately without revalidation, to improve
			# UI experience
			if ( $data->{_no_revalidate} || time - $data->{_time} < 300 ) {
				
				$log->debug("Using cached response [$url]");
				
				return $self->sendCachedResponse();
			}
		}
	}
	
	my $timeout 
		=  $self->{params}->{Timeout}
		|| $self->{params}->{timeout}
		|| preferences('server')->get('remotestreamtimeout')
		|| 10;
		
	my $request = HTTP::Request->new( $type => $url );
	
	if ( @_ % 2 ) {
		$request->content( pop @_ );
	}
	
	# If cached, add If-None-Match and If-Modified-Since headers
	if ( my $data = $self->{cachedResponse} ) {			
		unshift @_, (
			'If-None-Match'     => $data->{headers}->header('ETag') || undef,
			'If-Modified-Since' => $data->{headers}->last_modified || undef,
		);
	}

	# request compressed data if we have zlib
	if ( hasZlib() && !$self->{params}->{saveAs} ) {
		unshift @_, (
			'Accept-Encoding' => 'gzip, deflate',
		);
	}
	
	if ( @_ ) {
		$request->header( @_ );
	}
	
	my $http = Slim::Networking::Async::HTTP->new;
	$http->send_request( {
		request     => $request,
		maxRedirect => $self->{params}->{maxRedirect},
		saveAs      => $self->{params}->{saveAs},
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

	$::perfmon && (my $now = Time::HiRes::time());
	
	$self->ecb->( $self, $error );

	$::perfmon && $now && $callbackTask->log(Time::HiRes::time() - $now, undef, $self->ecb);
	
	return;
}

sub onBody {
	my ( $http, $self ) = @_;
	
	my $req = $http->request;
	my $res = $http->response;
	
	if ( $log->is_debug ) {
		$log->debug(sprintf("status for %s is %s", $self->url, $res->status_line ));
	}
	
	$self->code( $res->code );
	$self->mess( $res->message );
	$self->headers( $res->headers );
	
	if ( !$http->saveAs ) {
	
		# Check if we are cached and got a "Not Modified" response
		if ( $self->cachedResponse && $res->code == 304) {
		
			$log->debug("Remote file not modified, using cached content");
		
			# update the cache time so we get another 5 minutes with no revalidation
			my $cache = Slim::Utils::Cache->new();
			$self->cachedResponse->{_time} = time;
			my $expires = $self->cachedResponse->{_expires} || undef;
			$cache->set( $self->url, $self->cachedResponse, $expires );
		
			return $self->sendCachedResponse();
		}
		
		$self->contentRef( $res->content_ref );
	
		# unzip if necessary
		if ( hasZlib() ) {

			if ( my $ce = $res->header('Content-Encoding') ) {

				if ( $ce eq 'gzip' ) {

					$log->debug("Decompressing gzip'ed content");

					# Formats::XML requires a scalar ref
					$self->contentRef( \Compress::Zlib::memGunzip( $res->content_ref ) );
				}
				elsif ( $ce eq 'deflate' ) {

					$log->debug("Decompressing deflated content");

					my $i = Compress::Zlib::inflateInit(
						-WindowBits => -Compress::Zlib::MAX_WBITS(),
					);

					my $output = $i->inflate( $res->content_ref );

					# Formats::XML requires a scalar ref
					$self->contentRef( \$output );
				}
			}
		}
		
		# cache the response if requested
		if ( $self->{params}->{cache} ) {
		
			if ( Slim::Utils::Misc::shouldCacheURL( $self->url ) ) {
		
				my $cache = Slim::Utils::Cache->new();
		
				my $data = {
					code    => $self->code,
					mess    => $self->mess,
					headers => $self->headers,
					content => $self->content,
					_time   => time,
				};
		
				# By default, cached content can live for at most 1 day, this helps control the
				# size of the cache.  We use ETag/Last Modified to check for stale data during
				# this time.
				my $max = 60 * 60 * 24;
				my $expires = $self->{params}->{expires} || $max;
				my $no_cache;
		
				if ( $expires >= $max ) {
			
					# If we see max-age or an Expires header, use them
					if ( my $cc = $res->header('Cache-Control') ) {
						if ( $cc =~ /no-cache|must-revalidate/ ) {
							$no_cache = 1;
						}
						elsif ( $cc =~ /max-age=(-?\d+)/ ) {
							$expires = $1;
						}
					}			
					elsif ( my $expire_date = $res->header('Expires') ) {
						$expires = HTTP::Date::str2time($expire_date) - time;
					}
		
					# If there is no ETag/Last Modified, don't cache
					if (   $expires >= $max
						&& !$res->last_modified
						&& !$res->header('ETag')
					) {

						$no_cache = 1;

						if ( $log->is_debug ) {
							$log->debug(sprintf("Not caching [%s], no expiration set and missing cache headers", $self->url));
						}
					}
				}
		
				if ( $expires < $max ) {
					# if we have an explicit expiration time, we can avoid revalidation
					$data->{_no_revalidate} = 1;
				}
		
				if ( !$no_cache ) {
					$data->{_expires} = $expires;
					$cache->set( $self->url, $data, $expires );
			
					if ( $log->is_info ) {
						$log->info(sprintf("Caching [%s] for %d seconds", $self->url, $expires));
					}
				}
			}
		}
	}
	
	$log->debug("Done");

	$::perfmon && (my $now = Time::HiRes::time());
	
	$self->cb->( $self );

	$::perfmon && $now && $callbackTask->log(Time::HiRes::time() - $now, undef, $self->cb);

	return;
}

sub sendCachedResponse {
	my $self = shift;
	
	my $data = $self->{cachedResponse};
	
	# populate the object with cached data			
	$self->code( $data->{code} );
	$self->mess( $data->{mess} );
	$self->headers( $data->{headers} );
	$self->contentRef( \$data->{content} );

	$::perfmon && (my $now = Time::HiRes::time());
	
	$self->cb->( $self );

	$::perfmon && $now && $callbackTask->log(Time::HiRes::time() - $now, undef, $self->cb);
	
	return;
}

sub content { ${ shift->contentRef || \'' } }

sub close { }

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

This class provides a way within the SqueezeCenter to make an http
request in an asynchronous, non-blocking way.  This is important
because the server will remain responsive and continue streaming audio
while your code waits for the response.

=cut
