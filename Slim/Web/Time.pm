package Slim::Web::Time;

# Lyrion Music Server Copyright 2025 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Implements a simple HTTP endpoint '/time/tz' that provides a SqueezeOS based
# player with a default, Olson formatted, TimeZone string. The player will
# make the request whenever its own TimeZone has not been initialized. This
# typically follows a factory reset, or during first set up.

# LMS is expected to respond by returning an Olson formatted TimeZone string,
# with a '200' (OK) response code. If LMS fails to obtain a valid TimeZone
# it will return one of a '204' (No content) or '500' (Internal server error)
# response.
# The SqueezeOS callback will not see an empty body even if it is a '200'
# response. So we don't do that.

# LMS obtains the TimeZone by an API call to 'https://api.lms-community.org'

use strict;

use HTTP::Status qw(RC_OK RC_NO_CONTENT RC_INTERNAL_SERVER_ERROR);
use JSON::XS::VersionOneAndTwo;

use Slim::Web::HTTP;
use Slim::Web::Pages;
use Slim::Utils::DateTime;
use Slim::Utils::Log;

my $log = logger('network.http');


# 'init' is called by 'Slim::Web::HTTP:init'
sub init {
	Slim::Web::Pages->addRawFunction(qr{^/time/tz$}, \&tzAPIrequest);
}

# Holds the Timezone string retrieved from a successful API call.
my $cachedTimeZone;

sub tzAPIrequest {
	my ($httpClient, $response) = @_;

	if ($cachedTimeZone) {
		$log->info("TimeZone query: Returning \"$cachedTimeZone\" to SqueezeOS device (from cache)");
		_sendHTTPresponse($httpClient, $response, RC_OK, $cachedTimeZone);
		return;
	}

	Slim::Utils::DateTime::getTZName(sub {
		my ($tz, $err) = @_;

		if ($err) {
			$log->error("TimeZone query: Failed to get TimeZone - $err");
			return _sendHTTPresponse($httpClient, $response, RC_INTERNAL_SERVER_ERROR, '');
		}

		return tzAPIsuccess($httpClient, $response, $tz);
	});
}


# Parses out the Olson TimeZone identifier, validates the result, and returns
# it to SqueezeOS. But returns a 500 (Internal server error) code if the API
# response is malformed, or a 204 (No content) code if validation of the tz
# string fails.

sub tzAPIsuccess {
	my ($httpClient, $response, $tz) = @_;

	if (!$tz || ref $tz) {
		$log->error('Unexpected JSON response, expected a timezone string: ' . $tz);
		_sendHTTPresponse($httpClient, $response, RC_INTERNAL_SERVER_ERROR, '');
		return;
	}

	# Trim any leading/trailing white space, should it be there.
	$tz =~ s/\A\s+|\s+\z//g;

	$log->info("TimeZone query: Retrieved TimeZone \"$tz\"");
	my $savedTz = $tz;

	# Sanity check on TimeZone string.

	# A TimeZone identifier is, essentially, a POSIX path with some
	# additional (more and less voluntary) restrictions. These are
	# indicated in the "theory" section of the tz distribution:
	#   https://github.com/eggert/tz/blob/main/theory.html

	# Identifier components should contain only A-Z, a-z, '-', and '_'.
	# And we need '/' to join the components together.
	# Examples: 'America/Argentina/Buenos_Aires', 'Europe/Zurich'.
	# Note:
	#  Some "legacy" and "etc" TimeZones may also contain 0-9 and '+', but
	#  we do not expect or support such oddities.

	if (
		$tz =~ m{[^A-Za-z_\-/]}  # reject if any characters outside that range
		|| $tz =~ m{^/}          # leading '/' not allowed
		|| $tz =~ m{/$}          # trailing '/' not allowed
		|| $tz =~ m{//}          # no component to be empty
		|| $tz =~ m{ ^- | /- }x  # no component to start with a hyphen
		|| $tz eq 'Factory'      # reserved for SqueezeOS use
		|| $tz eq 'Etc/Unknown'  # reserved - never a valid TimeZone
	) {
		$tz = ''
	}

	# Note:
	#  We do not guarantee to purge all invalid TimeZones with the above
	#  sanity checks.

	# All done, cache the result for re-use next time, and return result
	# to SqueezeOS.
	# But a 204 (No content) response if TimeZone failed validation.

	if ($tz) {
		$log->info("TimeZone query: Returning \"$tz\" to SqueezeOS device");
		$cachedTimeZone = $tz;
		return _sendHTTPresponse($httpClient, $response, RC_OK, $tz);
	} else {
		$log->error("TimeZone query: Retrieved TimeZone \"$savedTz\" did not pass validation checks");
		return _sendHTTPresponse($httpClient, $response, RC_NO_CONTENT, '');
	}
}


# Helper function to dispatch the HTTP response

sub _sendHTTPresponse {
	my ($httpClient, $response, $code, $body) = @_;

	$response->code($code);
	$response->content_type('text/plain;charset=UTF-8');
	$response->header('Connection' => 'close');
	Slim::Web::HTTP::addHTTPResponse(
		$httpClient, $response, \$body,
	);
}

1;
