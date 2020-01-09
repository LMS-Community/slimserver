package Slim::Web::HTTP::CSRF;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use Digest::MD5;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use Slim::Web::HTTP;

my $log = logger('network.http');
my $prefs = preferences('server');

my %dangerousCommands;


sub getQueries {
	my ($class, $request, $csrfReqParams) = @_;

	my ($queryWithArgs, $queryToTest);
	
	if ($prefs->get('csrfProtectionLevel')) {
		
		$queryWithArgs = Slim::Utils::Misc::unescape($request->uri());

		# next lines are ugly hacks to remove any GET args
		$queryWithArgs =~ s|\?.*$||;
		$queryWithArgs .= '?';

		foreach my $n (sort keys %$csrfReqParams) {
			foreach my $val ( @{$csrfReqParams->{$n}} ) {
				$queryWithArgs .= Slim::Utils::Misc::escape($n) . '=' . Slim::Utils::Misc::escape($val) . '&';
			}
		}

		# scrub some harmless args
		$queryToTest = $queryWithArgs;
		$queryToTest =~ s/\bplayer=.*?\&//g;
		$queryToTest =~ s/\bplayerid=.*?\&//g;
		$queryToTest =~ s/\bajaxUpdate=\d\&//g;
		$queryToTest =~ s/\?\?/\?/;
	}
	
	return ($queryWithArgs, $queryToTest);
}


sub testCSRFToken {
	if ($prefs->get('csrfProtectionLevel')) {
		
		my ($class, $httpClient, $request, $response, $params, $queryWithArgs, $queryToTest, $providedPageAntiCSRFToken) = @_;

		foreach my $dregexp ( keys %dangerousCommands ) {
			if ($queryToTest =~ m|$dregexp| ) {
				if ( !$class->isRequestCSRFSafe($request, $response, $params, $providedPageAntiCSRFToken) ) {

					$log->error("Client requested dangerous function/arguments and failed CSRF Referer/token test, sending 403 denial");

					$class->throwCSRFError($httpClient, $request, $response, $params, $queryWithArgs);
					return;
				}
			}
		}
	}
	
	return 1;
}


# makePageToken: anti-CSRF token at the page level, e.g. token to
# protect use of /settings/server/basic.html
sub makePageToken {
	my ($class, $req) = @_;
	
	my $secret = $prefs->get('securitySecret');
	
	if ( (!defined($secret)) || ($secret !~ m|^[0-9a-f]{32}$|) ) {
		# invalid secret!
		# Prefs.pm should have set this!
		$log->warn("Server unable to verify CRSF auth code due to missing or invalid securitySecret server pref");
		return '';
	}
	
	# make hash of URI & secret
	# BUG: for CSRF protection level "high", perhaps there should be additional data used for this
	my $uri = Slim::Utils::Misc::unescape($req->uri());
	
	# strip the querystring, if any
	$uri =~ s/\?.*$//;
	my $hash = Digest::MD5->new;
	
	# hash based on server secret and URI
	$hash->add($uri);
	$hash->add($secret);
	return $hash->hexdigest();
}

sub isRequestCSRFSafe {
	my ($class, $request, $response, $params, $providedPageAntiCSRFToken) = @_;
	
	my $rc = 0;

	# XmlHttpRequest test for all the AJAX code in 7.x
	if ($request->header('X-Requested-With') && ($request->header('X-Requested-With') eq 'XMLHttpRequest') ) {
		# good enough
		return 1;
	}

	# referer test from SqueezeCenter 5.4.0 code
	if ($request->header('Referer') && defined($request->header('Referer')) && defined($request->header('Host')) ) {

		my ($host, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($request->header('Referer'));

		# if the Host request header lists no port, crackURL() reports it as port 80, so we should
		# pretend the Host header specified port 80 if it did not

		my $hostHeader = $request->header('Host');

		if ($hostHeader !~ m/:\d{1,}$/ ) { $hostHeader .= ":80"; }

		if ("$host:$port" ne $hostHeader) {

			if ( $log->is_warn ) {
				$log->warn("Invalid referer: [" . join(' ', ($request->method, $request->uri)) . "]");
			}

		} else {

			# looks good
			$rc = 1;
		}

	}

	if ( ! $rc ) {

		# need to also check if there's a valid "cauth" token
		if ( ! $class->isCsrfAuthCodeValid($request, $providedPageAntiCSRFToken) ) {

			$params->{'suggestion'} = "Invalid referrer and no valid cauth code.";

			if ( $log->is_warn ) {
				$log->warn("No valid CSRF auth code: [" . 
					join(' ', ($request->method, $request->uri, $request->header('X-Slim-CSRF')))
				. "]");
			}

		} else {

			# looks good
			$rc = 1;
		}
	}

	return $rc;
}

sub isCsrfAuthCodeValid {
	my ($class, $request, $providedPageAntiCSRFToken) = @_;
	
	my $csrfProtectionLevel = $prefs->get('csrfProtectionLevel');

	if (! defined($csrfProtectionLevel) ) {

		# Prefs.pm should have set this!
		$log->warn("Warning: Server unable to determine CRSF protection level due to missing server pref");

		return 0;
	}

	# no protection, so we don't care
	return 1 if ( !$csrfProtectionLevel);

	my $uri  = $request->uri();
	my $code = $request->header("X-Slim-CSRF");

	if ( ! defined($uri) ) {
		return 0;
	}

	my $secret = $prefs->get('securitySecret');

	if ( (!defined($secret)) || ($secret !~ m|^[0-9a-f]{32}$|) ) {

		# invalid secret!
		$log->warn("Server unable to verify CRSF auth code due to missing or invalid securitySecret server pref");

		return 0;
	}

	my $expectedCode = $secret;

	# calculate what the auth code should look like
	my $highHash   = Digest::MD5->new;
	my $mediumHash = Digest::MD5->new;

	# only the "HIGH" cauth code depends on the URI
	$highHash->add($uri);

	# both "HIGH" and "MEDIUM" depend on the securitySecret
	$highHash->add($secret);
	$mediumHash->add($secret);

	# a "HIGH" hash is always accepted
	return 1 if ( defined($code) && ($code eq $highHash->hexdigest()) );

	if ( $csrfProtectionLevel == 1 ) {

		# at "MEDIUM" level, we'll take the $mediumHash, too
		return 1 if ( defined($code) && ($code eq $mediumHash->hexdigest()) );
	}

	# how about a simple page token?
	if ( defined($providedPageAntiCSRFToken) ) {
		if ( $class->makePageToken($request) eq $providedPageAntiCSRFToken ) {
			return 1;
		}
	} 

	# the code is no good (invalid or MEDIUM hash presented when using HIGH protection)!
	return 0;

}



# CSRF: allow code to indicate it needs protection
#
# The HTML template for protected actions needs to embed an anti-CSRF token. The easiest way
# to do that is include the following once inside each <form>:
# 	<input type="hidden" name="pageAntiCSRFToken" value="[% pageAntiCSRFToken %]">
#
# To protect the settings within the module that handles that page, use the "protect" APIs:
# sub name {
# 	return Slim::Web::HTTP::CSRF->protectName('BASIC_SERVER_SETTINGS');
# }
# sub page {
# 	Slim::Web::HTTP::CSRF->protectURI('settings/server/basic.html');
# }
#
# protectURI: takes the same string that a function's page() method returns
sub protectURI {
	my ($class, $uri) = @_;
	
	my $regexp = "/${uri}\\b.*\\=";
	$dangerousCommands{$regexp} = 1;
	
	return $uri;
}

# protectName: takes the same string that a function's name() method returns
sub protectName {
	my ($class, $name) = @_;

	my $regexp = "\\bpage=${name}\\b";
	$dangerousCommands{$regexp} = 1;

	return $name;
}


# normal Logitech Media Server commands can be accessed with URLs like
#   http://localhost:9000/status.html?p0=pause&player=00%3A00%3A00%3A00%3A00%3A00
#   http://localhost:9000/status.html?command=pause&player=00%3A00%3A00%3A00%3A00%3A00
# Use the protectCommand() API to prevent CSRF attacks on commands -- including commands
# not intended for use via the web interface!
#
# protectCommand: takes an array of commands, e.g.
# protectCommand('play')			# protect any command with 'play' as the first command
# protectCommand('playlist', ['add', 'delete'])	# protect the "playlist add" and "playlist delete" commands
# protectCommand('mixer','volume','\d{1,}');	# protect changing the volume (3rd arg has digit) but allow "?" query in 3rd pos
sub protectCommand {
	my $class = shift;
	my @commands = @_;
	
	my $regexp = '';
	for (my $pos = 0; $pos < scalar(@commands); ++$pos) {
		
		my $rePart;
		
		if ( ref($commands[$pos]) eq 'ARRAY' ) {
			
			$rePart = '\b(';
			my $add = '';
			
			foreach my $c ( @{$commands[$pos]} ) {
				$rePart .= "${add}p${pos}=$c\\b";
				$add = '|';
			}
			
			$rePart .= ')';
		} 
		
		else {
			$rePart = "\\bp${pos}=$commands[$pos]\\b";
		}
		
		$regexp .= "${rePart}.*?";
	}
	
	$dangerousCommands{$regexp} = 1;
}

# protect: takes an exact regexp, in case you need more fine-grained protection
#
# Example querystring for server settings:
# /status.html?audiodir=/music&language=EN&page=BASIC_SERVER_SETTINGS&playlistdir=/playlists&rescan=&rescantype=1rescan&saveSettings=Save Settings&useAJAX=1&
sub protect {
	my $regexp = shift;
	$dangerousCommands{$regexp} = 1;
}


sub throwCSRFError {
	my ($class, $httpClient, $request, $response, $params, $queryWithArgs) = @_;

	# throw 403, we don't this from non-server pages
	# unless valid "cauth" token is present
	$params->{'suggestion'} = "Invalid Referer and no valid CSRF auth code.";

	my $protoHostPort = 'http://' . $request->header('Host');
	my $authURI = $class->makeAuthorizedURI($request->uri(), $queryWithArgs);
	my $authURL = $protoHostPort . $authURI;

	# add a long SGML comment so Internet Explorer displays the page
	my $msg = "<!--" . ( '.' x 500 ) . "-->\n<p>";

	$msg .= string('CSRF_ERROR_INFO'); 
	$msg .= "<br>\n<br>\n<A HREF=\"${authURI}\">${authURL}</A></p>";
	
	my $csrfProtectionLevel = $prefs->get('csrfProtectionLevel');
	
	if ( defined($csrfProtectionLevel) && $csrfProtectionLevel == 1 ) {
		$msg .= string('CSRF_ERROR_MEDIUM');
	}
	
	$params->{'validURL'} = $msg;
	
	# add the appropriate URL in a response header to make automated
	# re-requests easy? (WARNING: this creates a potential Cross Site
	# Tracing sort of vulnerability!

	# (see http://computercops.biz/article2165.html for info on XST)
	# If you enable this, also uncomment the text regarding this on the http.html docs
	#$response->header('X-Slim-Auth-URI' => $authURI);
	
	$response->code(RC_FORBIDDEN);
	$response->content_type('text/html');
	$response->header('Connection' => 'close');
	$response->content_ref(Slim::Web::HTTP::filltemplatefile('html/errors/403.html', $params));

	$httpClient->send_response($response);
	Slim::Web::HTTP::closeHTTPSocket($httpClient);	
}

sub makeAuthorizedURI {
	my ($class, $uri, $queryWithArgs) = @_;
	
	my $secret = $prefs->get('securitySecret');

	if ( (!defined($secret)) || ($secret !~ m|^[0-9a-f]{32}$|) ) {

		# invalid secret!
		$log->warn("Server unable to compute CRSF auth code URL due to missing or invalid securitySecret server pref");

		return undef;
	}

	my $csrfProtectionLevel = $prefs->get('csrfProtectionLevel');

	if (! defined($csrfProtectionLevel) ) {

		# Prefs.pm should have set this!
		$log->warn("Server unable to determine CRSF protection level due to missing server pref");

		return 0;
	}

	my $hash = Digest::MD5->new;

	if ( $csrfProtectionLevel == 2 ) {

		# different code for each different URI
		$hash->add($queryWithArgs);
	}

	$hash->add($secret);

	return $queryWithArgs . ';cauth=' . $hash->hexdigest();
}



1;