package Slim::Networking::SimpleSyncHTTP;

# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# this class provides blocking http requests from Logitech Media Server.

# DO NOT USE this class in the server. It's supposed to be used in the scanner only.

use strict;

use base qw(Slim::Networking::SimpleHTTP::Base);

use File::Spec::Functions qw(catdir);
use HTTP::Cookies;
use LWP::UserAgent;

BEGIN {
	my $hasSSL;

	sub hasSSL {
		return $hasSSL if defined $hasSSL;

		$hasSSL = 0;

		eval {
			require IO::Socket::SSL;

			# our old LWP::UserAgent doesn't support ssl_opts yet
			IO::Socket::SSL::set_defaults(
				SSL_verify_mode => Net::SSLeay::VERIFY_NONE()
			) if preferences('server')->get('insecureHTTPS');

			$hasSSL = 1;
		};

		return $hasSSL;
	}
}

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log = logger('network.http');

__PACKAGE__->mk_accessor( rw => qw(
	_params _log type url error code mess headers contentRef cacheTime cachedResponse
) );

my $cookieJar;

sub new {
	my ($class, $params) = @_;

	!main::SCANNER && logBacktrace('DO NOT USE SYNCHRONOUS CALLS IN THE SERVER! Use SimpleAsyncHTTP instead!');

	my $self = $class->SUPER::new();
	$params ||= {};

	$self->_params($params);
	$self->_log($log);

	# $cookieJar = HTTP::Cookies->new( file => catdir(preferences('server')->get('cachedir'), 'cookies.dat'), autosave => 1 );

	return $self;
}

sub get { shift->_createHTTPRequest( GET => @_ ) }

sub _createHTTPRequest {
	my $self = shift;

	my $url = $self->url($_[1]);

	if ($url =~ /^https/ && ! $self->hasSSL()) {
		$log->warn("No HTTPS support built in, but https URL required: $url");
	}

	my $params = $self->_params;

	my ($request, $timeout) = $self->SUPER::_createHTTPRequest(@_);

	# in case of a cached response we'd return without any response data
	return $self unless $request && $timeout;

	my $ua = LWP::UserAgent->new(
		agent   => Slim::Utils::Misc::userAgentString(),
		timeout => $timeout || 10,
		cookie_jar => $cookieJar,
	);

	my $res = $ua->request($request);

	$self->code( $res->code );
	$self->mess( $res->message );
	$self->headers( $res->headers );

	if ($res->is_success || $res->is_redirect) {
		# Check if we are cached and got a "Not Modified" response
		if ( my $response = $self->isNotModifiedResponse($res) ) {
			$self->sendCachedResponse();
			return $self;
		}

		$self->processResponse($res);
	}
	else {
		my $error = $res->message;

		# If we have a cached copy of this request, we can use it
		if ( $self->cachedResponse ) {

			$log->warn("Failed to connect to $url, using cached copy. ($error)");

			$self->sendCachedResponse();
			return $self;
		}
		else {
			$log->warn("Failed to connect to $url ($error)");
		}

		$self->error( $error );
	}

	return $self;
}

sub sendCachedResponse {
	my $self = shift;
	$self->prepareCachedResponse();
	return;
}

sub content { ${ shift->contentRef || \'' } }

sub is_success {
	$_[0]->code =~ /^2\d\d/;
}

1;