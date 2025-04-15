package Slim::Web::SqueezeosTimezone;

# Implements a simple HTTP endpoint '/tz' that provides a SqueezeOS based
# player with a default, Olson formatted, TimeZone string. The player will
# make the request whenever its own TimeZone has not been initialized. This
# typically follows a factory reset, or during first set up.

# LMS is expected to respond by returning an Olson formatted TimeZone string,
# with a '200' (RC_OK) response code. If LMS fails to obtain a valid TimeZone
# it will simply return a '404' (RC_NOT_FOUND) response.

# LMS obtains the TimeZone by an API call to 'https://stats.lms-community.org'

use strict;

use HTTP::Status qw(RC_OK RC_NOT_FOUND);
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
	Slim::Web::Pages->addRawFunction(qr{^/tz$}, \&tzAPIrequest);
}


sub tzAPIrequest {
	my ($httpClient, $response) = @_;

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
# it to SqueezeOS. But a 404 error if validation fails.

sub tzAPIsuccess {

	my $http       = shift;
	my $httpClient = $http->params('httpClient');
	my $response   = $http->params('response');

	# Server response should look like:
	# {"datetime":"2025-04-03T11:39:10.351+01:00","timezone":"Europe/London","offset":"GMT+1","offsetHours":1,"offsetMinutes":60,"isInDST":true}

	my $res = eval { from_json($http->content) };
	if ($@ || ref $res ne 'HASH') {
		$log->error($@ || 'Invalid JSON response: ' . $http->content);
		$res = {}; # guarantee that $res will be a hash ref
	}

	# '$tz' will hold the Olson formatted TimeZone to be returned.
	# Setting '$tz' to '' signals a validation failure, and triggers a
	# 404 error response.

	my $tz = $res->{'timezone'};
	if (!defined $tz || ref $tz) {
		$log->error('Unexpected JSON response, expected a timezone string: ' . $http->content);
		$tz = ''; # guarantee that $tz will be a string scalar
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

	# Path components should contain only A-Z, a-z, '.', '-', and '_'.
	# And we need '/' (directory) to join the path components together.
	# Note:
	#  Some "legacy" and "etc" TimeZones may also contain 0-9 and '+', but
	#  we do not expect or support such oddities.

	$tz = '' if $tz =~ m{[^A-Za-z._\-/]} ; # reject if any characters outside that range

	# Additional restrictions
	$tz = '' if $tz =~ m{^/}; # leading '/' not allowed
	$tz = '' if $tz =~ m{/$}; # trailing '/' not allowed
	$tz = '' if $tz =~ m{//}; # no path component to be empty
	$tz = '' if $tz =~ m{ ^- | /- }x; # no path component to start with a hyphen

	# Path components that consist of singleton '.' or doubleton '..' are
	# not allowed for obvious reasons.
	# Other than that, the "theory" section of the tz distribution does
	# allow "dots" elsewhere in TimeZone identifiers, but discourages
	# them. That said, there are none defined at present, and almost
	# certainly won't be. So just exclude any TimeZone containing a dot.
	$tz = '' if $tz =~ m{\.}; # no path component to contain a '.'

	# The 'Factory' TimeZone should never be encountered. SqueezeOS uses
	# it to signal that the device's TimeZone has not been set.
	# The 'Etc/Unknown' TimeZone signals an 'Unknown or Invalid' TimeZone,
	# and is not defined in the tz database. SqueezeOS doesn't want it.
	$tz = '' if $tz eq 'Factory';
	$tz = '' if $tz eq 'Etc/Unknown';

	# Note:
	#  We do not guarantee to purge all invalid TimeZones with the above
	#  sanity checks.

	# All done, return result to SqueezeOS.
	# But a 404 error if TimeZone failed validation.
	unless ($tz eq '') {
		$response->code(RC_OK);
		$log->info("TimeZone query: Returning \"$tz\" to SqueezeOS device");
	} else {
		$response->code(RC_NOT_FOUND);
		$log->error("TimeZone query: Retrieved TimeZone \"$savedTz\" did not pass validation checks");
	}
	$response->content_type('text/plain;charset=UTF-8');
	$response->header('Connection' => 'close');
	Slim::Web::HTTP::addHTTPResponse(
		$httpClient, $response, \$tz,
	);
}


# Returns a 404 error to SqueezeOS.

sub tzAPIerror {
	my $http       = shift;
	my $httpClient = $http->params('httpClient');
	my $response   = $http->params('response');

	$log->error("TimeZone query: Failed to get TimeZone from ", join("\n", $http->url, $http->error));

	$response->code(RC_NOT_FOUND);
	$response->content_type('text/plain;charset=UTF-8');
	$response->header('Connection' => 'close');
	my $body = "";
	Slim::Web::HTTP::addHTTPResponse(
		$httpClient, $response, \$body,
	);
}

1;
