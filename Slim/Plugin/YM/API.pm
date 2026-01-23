package Slim::Plugin::YM::API;

use strict;

use JSON::XS::VersionOneAndTwo;

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;

use constant API_URL => 'https://api.music.yandex.net';

my $log = logger('plugin.ym');

sub accountStatus {
	my ($class, $token, $cb) = @_;

	return $cb->() unless $token;

	my $url = API_URL . '/account/status';
	my $headers = [
		'Authorization', "OAuth $token",
		'Accept', 'application/json',
	];

	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $response = shift;
			my $result = eval { from_json($response->content) };

			if ($@) {
				$log->error("Error parsing Yandex Music response: $@");
				return $cb->();
			}

			my $account = $result->{result}->{account} || {};
			my $name = $account->{displayName} || $account->{login} || $account->{uid};

			return $cb->({
				account => $account,
				account_name => $name,
			});
		},
		sub {
			my ($http, $error) = @_;
			$log->error("Yandex Music request failed: $error ($url)");
			$cb->();
		},
		{
			timeout => 15,
		},
	);

	$http->get($url, @$headers);
}

1;
