use strict;
use warnings;

use Test::More;
use Time::HiRes ();

use lib '.', 'CPAN';
use HTTP::Date qw(time2str);
use HTTP::Response;

my $now = 1_700_000_000;
my @timers;
my @started;
my @errors;
my $clients = 0;

{
	package Slim::Utils::Log;
	use Exporter 'import';
	our @EXPORT = qw(logger);
	sub logger { bless {}, __PACKAGE__ }
	sub error { push @errors, $_[1] }
}

{
	package Slim::Utils::Timers;
	sub setTimer {
		my ($owner, $when, $callback) = @_;
		push @timers, [$when, $callback];
		return $timers[-1];
	}
}

{
	package Slim::Networking::SimpleAsyncHTTP;
	sub new {
		my ($class, $cb, $ecb, $params) = @_;
		$clients++;
		return bless { cb => $cb, ecb => $ecb, params => $params }, $class;
	}
	sub get { shift->_start('get', @_) }
	sub post { shift->_start('post', @_) }
	sub headers { $_[0]->{response}->headers if $_[0]->{response} }
	sub code { $_[0]->{response}->code if $_[0]->{response} }
	sub _start {
		my ($self, @args) = @_;
		push @started, [$self, @args];
		if (my $onStart = $self->{params}->{onStart}) {
			$onStart->($self);
		}
	}
}

$INC{'Slim/Utils/Log.pm'} = __FILE__;
$INC{'Slim/Utils/Timers.pm'} = __FILE__;
$INC{'Slim/Networking/SimpleAsyncHTTP.pm'} = __FILE__;
require Slim::Plugin::AudioScrobbler::API::AsyncHTTPQueue;

{
	no warnings qw(redefine prototype);
	*Time::HiRes::time = sub { $now };
}

sub advanceTime {
	$now += shift;
	while (@timers && $timers[0]->[0] <= $now) {
		my (undef, $callback) = @{ shift @timers };
		$callback->(undef);
	}
}

sub queueRequest {
	return Slim::Plugin::AudioScrobbler::API::AsyncHTTPQueue->new(@_);
}

subtest 'FIFO, deferred construction and stale Now Playing' => sub {
	my $params = { timeout => 30 };
	my @successArgs;
	my $validation = queueRequest(sub { @successArgs = @_ }, undef, $params);
	is($clients, 0, 'constructing the wrapper creates no HTTP client');
	$validation->get('https://example.test/validate-token', Authorization => 'Token test');
	my ($http, @args) = @{ $started[0] };
	is($http->{params}, $params, 'constructor params reach the HTTP client');
	is_deeply(\@args, ['get', 'https://example.test/validate-token', Authorization => 'Token test'], 'GET arguments are forwarded');

	my $isCurrent = 1;
	my $checks = 0;
	my $nowPlayingParams = { canSend => sub { $checks++; return $isCurrent } };
	my $cancelled = sub { fail('a stale request invoked a callback') };
	queueRequest($cancelled, $cancelled, $nowPlayingParams)->post('https://example.test/playing-now');
	my @postArgs = ('https://example.test/submit-listens', 'Content-Type' => 'application/json', '{"payload":[]}');
	queueRequest(sub {}, $cancelled)->post(@postArgs);
	queueRequest(sub {}, $cancelled)->get('https://example.test/queued-validation');
	is($clients, 1, 'pending requests create no HTTP clients while one is active');
	is($checks, 0, 'the queued predicate has not yet run');
	$http->{cb}->($http);
	is_deeply(\@successArgs, [$http], 'success callback receives the HTTP client');
	advanceTime(0.5);
	is($clients, 1, 'queue waits at least one second');
	$isCurrent = 0;
	advanceTime(0.5);
	is($clients, 2, 'only the scrobble creates a client after the cooldown');
	my ($scrobble, @sent) = @{ $started[-1] };
	is_deeply(\@sent, ['post', @postArgs], 'next request sends the original POST arguments');
	advanceTime(2);
	is($clients, 2, 'elapsed cooldown does not allow a second active request');
	$scrobble->{cb}->($scrobble);
	my ($queuedValidation, @validationArgs) = @{ $started[-1] };
	is($clients, 3, 'the next request starts when the active request completes');
	is_deeply(\@validationArgs, ['get', 'https://example.test/queued-validation'], 'eligible requests dispatch in FIFO order');
	$queuedValidation->{cb}->($queuedValidation);

	queueRequest($cancelled, $cancelled, $nowPlayingParams)->post('https://example.test/playing-now');
	advanceTime(1);
	is($checks, 2, 'both stale requests were checked once');
	is($clients, 3, 'an all-stale queue creates no clients');
	is(scalar @timers, 0, 'an all-stale queue leaves no dispatch timer');
	queueRequest(sub {}, $cancelled)->get('https://example.test/next');
	is($clients, 4, 'new work starts immediately after discarding the stale queue');
	is($checks, 2, 'discarded entries are absent when dispatch runs again');
	my $last = $started[-1]->[0];
	$last->{cb}->($last);
};

subtest 'HTTP 429 delays the next request and forwards error arguments' => sub {
	advanceTime(1);
	my $before = $clients;
	my @errorArgs;
	my $nextRequestAt;
	queueRequest(sub {}, sub {
		@errorArgs = @_;
		$nextRequestAt = Slim::Plugin::AudioScrobbler::API::AsyncHTTPQueue->nextRequestAt;
	})->post('https://example.test/limited');
	my $http = $started[-1]->[0];
	queueRequest(sub {})->get('https://example.test/after-limit');
	my $response = HTTP::Response->new(429, 'Too Many Requests', ['Retry-After' => 2, 'X-RateLimit-Reset-In' => 4]);
	$http->{ecb}->($http, '429 Too Many Requests', $response);
	is_deeply(\@errorArgs, [$http, '429 Too Many Requests', $response], 'error callback receives the client, error and response');
	is($nextRequestAt, $now + 4, 'cooldown is applied before notifying the caller');
	advanceTime(3);
	is($clients, $before + 1, 'the longer rate limit still blocks dispatch');
	advanceTime(1);
	is($clients, $before + 2, 'dispatch resumes at the rate limit deadline');
	my $last = $started[-1]->[0];
	$last->{cb}->($last);
};

subtest 'successful response with an exhausted rate limit' => sub {
	advanceTime(1);
	my $before = $clients;
	queueRequest(sub {})->post('https://example.test/remaining');
	my $http = $started[-1]->[0];
	queueRequest(sub {})->get('https://example.test/after-reset');
	$http->{response} = HTTP::Response->new(200, 'OK', [
		'X-RateLimit-Remaining' => 0,
		'X-RateLimit-Reset' => $now + 3,
		'Retry-After' => time2str($now + 5),
	]);
	$http->{cb}->($http);
	advanceTime(4);
	is($clients, $before + 1, 'HTTP-date Retry-After can extend the absolute reset');
	advanceTime(1);
	is($clients, $before + 2, 'dispatch resumes at the HTTP-date deadline');
	my $last = $started[-1]->[0];
	$last->{cb}->($last);
};

subtest 'inline completion and callback exceptions' => sub {
	advanceTime(1);
	my $before = $clients;
	queueRequest(sub {
		queueRequest(sub {})->get('https://example.test/after-inline');
		die "callback failed\n";
	}, undef, { onStart => sub {
		my ($http) = @_;
		$http->{cb}->($http);
		is(scalar @timers, 0, 'no dispatch timer is scheduled until HTTP setup finishes');
		$now += 2;
	} })->get('https://example.test/inline');
	like($errors[-1], qr/callback failed/, 'callback exception is logged');
	advanceTime(0.5);
	is($clients, $before + 1, 'minimum spacing includes the inline request setup time');
	advanceTime(0.5);
	is($clients, $before + 2, 'the queue advances after the failed inline callback');
	my $last = $started[-1]->[0];
	$last->{cb}->($last);
};

done_testing();
