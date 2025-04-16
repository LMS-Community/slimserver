package Slim::Web::Time;

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

# LMS obtains the TimeZone by an API call to 'https://stats.lms-community.org'

use strict;

use HTTP::Status qw(RC_OK RC_NO_CONTENT RC_INTERNAL_SERVER_ERROR);
use Slim::Web::HTTP;
use Slim::Networking::SimpleAsyncHTTP;
use JSON::XS::VersionOneAndTwo;
use Slim::Utils::Log;

# The server/url that provides us with date/time data, including an Olson
# formatted TimeZone. The response is JSON formatted.
use constant TZGUESS_URL => 'https://stats.lms-community.org/api/time';

my $log = logger('network.http');


# 'init' is called by 'Slim::Web::HTTP:init'
sub init {
	Slim::Web::Pages->addRawFunction(qr{^/time/tz$}, \&tzAPIrequest);
}

# Holds the Timezone string retrieved from a successful API call.
# Although it may be '' if the string failed validation.
my $cachedAPIresult;

sub tzAPIrequest {
	my ($httpClient, $response) = @_;

	if (defined $cachedAPIresult) {
		# Did it pass validation ? Or do we have '' ?
		if ($cachedAPIresult) {
			$log->info("TimeZone query: Returning \"$cachedAPIresult\" to SqueezeOS device (from cache)");
			_sendHTTPresponse($httpClient, $response, RC_OK, $cachedAPIresult);
		}
		else {
			$log->error("TimeZone query: Cached timezone was invalid. Returning 204 response to SqueezeOS device");
			_sendHTTPresponse($httpClient, $response, RC_NO_CONTENT, '');
		}
		return;
	}

	# API call to retrieve date/time data
	Slim::Networking::SimpleAsyncHTTP->new(
		\&tzAPIsuccess,
		\&tzAPIerror,
		{
			timeout    => 10,
			httpClient => $httpClient,
			response   => $response,
		}
	)->get(TZGUESS_URL);
}


# Parses out the Olson TimeZone identifier, validates the result, and returns
# it to SqueezeOS. But returns a 500 (Internal server error) code if the API
# response is malformed, or a 204 (No content) code if validation of the tz
# string fails.

sub tzAPIsuccess {

	my $http       = shift;
	my $httpClient = $http->params('httpClient');
	my $response   = $http->params('response');

	# Server response should look like:
	# {"datetime":"2025-04-03T11:39:10.351+01:00","timezone":"Europe/London","offset":"GMT+1","offsetHours":1,"offsetMinutes":60,"isInDST":true}

	my $res = eval { from_json($http->content) };
	if ($@ || ref $res ne 'HASH') {
		$log->error($@ || 'Invalid JSON response: ' . $http->content);
		_sendHTTPresponse($httpClient, $response, RC_INTERNAL_SERVER_ERROR, '');
		return;
	}

	# '$tz' will hold the Olson formatted TimeZone to be returned.
	# Setting '$tz' to '' signals a validation failure, and triggers a
	# 204 (No content) response.

	my $tz = $res->{'timezone'};
	if (!defined $tz || ref $tz) {
		$log->error('Unexpected JSON response, expected a timezone string: ' . $http->content);
		_sendHTTPresponse($httpClient, $response, RC_INTERNAL_SERVER_ERROR, '');
		return;
	}

	$tz = "$tz"; # ensure $tz is a string scalar
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
	$cachedAPIresult = $tz;

	if ($tz) {
		$log->info("TimeZone query: Returning \"$tz\" to SqueezeOS device");
		_sendHTTPresponse($httpClient, $response, RC_OK, $tz);
	} else {
		$log->error("TimeZone query: Retrieved TimeZone \"$savedTz\" did not pass validation checks");
		_sendHTTPresponse($httpClient, $response, RC_NO_CONTENT, '');
	}
}


# Log the error and return a 500 code to SqueezeOS.

sub tzAPIerror {
	my $http       = shift;
	my $httpClient = $http->params('httpClient');
	my $response   = $http->params('response');
	$log->error("TimeZone query: Failed to get TimeZone from ", join("\n", $http->url, $http->error));
	_sendHTTPresponse($httpClient, $response, RC_INTERNAL_SERVER_ERROR, '');
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
