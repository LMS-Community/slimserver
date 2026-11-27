package Slim::Plugin::AudioScrobbler::API::AsyncHTTPQueue;

# Lyrion Music Server Copyright 2024-2026 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use HTTP::Date qw(str2time);
use List::Util qw(max);
use Time::HiRes ();

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Timers;

my $log = logger('plugin.audioscrobbler');

my @requests;
my $requestActive;
my $dispatchTimer;
my $nextRequestAt = 0;

sub new {
	my ($class, $cb, $ecb, $params) = @_;
	return bless { cb => $cb, ecb => $ecb, params => $params || {} }, $class;
}

sub get { shift->_enqueue('get', @_) }

sub post { shift->_enqueue('post', @_) }

sub nextRequestAt { $nextRequestAt }

sub _enqueue {
	my ($self, $method, @args) = @_;
	push @requests, [$self, $method, @args];
	_dispatchRequest();
}

sub _dispatchRequest {
	return if $requestActive || $dispatchTimer || !@requests;

	if (Time::HiRes::time() < $nextRequestAt) {
		$dispatchTimer = Slim::Utils::Timers::setTimer(undef, $nextRequestAt, \&_dispatchTimer);
		return;
	}

	while (my $request = shift @requests) {
		my ($self, $method, @args) = @$request;
		my $params = $self->{params};
		my $canSend = $params->{canSend};
		next if $canSend && !$canSend->($params);

		$requestActive = 1;
		$nextRequestAt = Time::HiRes::time() + 1;

		my $starting = 1;
		my $completed;
		my $complete = sub {
			my ($callback, @args) = @_;
			my ($http, undef, $response) = @args;
			# On HTTP errors the response is supplied as a separate argument.
			_applyCooldown($response || $http);
			if ($callback) {
				eval { $callback->(@args); 1 } or $log->error("Queued HTTP callback failed: $@");
			}
			$completed = 1;
			_finishRequest() unless $starting;
		};

		my $http = Slim::Networking::SimpleAsyncHTTP->new(
			sub { $complete->($self->{cb}, @_) },
			sub { $complete->($self->{ecb}, @_) },
			$params,
		);
		$http->$method(@args);

		# Include HTTP setup time and any cooldown set by an inline callback.
		$nextRequestAt = max($nextRequestAt, Time::HiRes::time() + 1);
		$starting = 0;
		_finishRequest() if $completed;
		return;
	}
}

sub _dispatchTimer {
	undef $dispatchTimer;
	_dispatchRequest();
}

sub _finishRequest {
	$requestActive = 0;
	_dispatchRequest();
}

sub _parseNonNegativeInteger {
	my ($value) = @_;
	return unless defined $value && $value =~ /\A\s*([0-9]+)\s*\z/;
	my $number = 0 + $1;
	return if $number >= 'Inf';
	return $number;
}

sub _applyCooldown {
	my ($response) = @_;
	my $headers = $response->headers || return;
	my $now = Time::HiRes::time();
	my $retryAfter = $headers->header('Retry-After');
	my $delay = _parseNonNegativeInteger($retryAfter);
	my $retryAt = defined $delay ? $now + $delay : (str2time($retryAfter, 'GMT') // 0);
	my $remaining = _parseNonNegativeInteger($headers->header('X-RateLimit-Remaining'));

	if (($response->code || 0) == 429 || (defined $remaining && $remaining == 0)) {
		my $resetIn = _parseNonNegativeInteger($headers->header('X-RateLimit-Reset-In'));
		my $resetAt = $resetIn ? $now + $resetIn : (_parseNonNegativeInteger($headers->header('X-RateLimit-Reset')) // 0);
		$retryAt = max($retryAt, $resetAt);
		$retryAt = $now + 2 if $retryAt <= $now;
	}

	$nextRequestAt = max($nextRequestAt, $retryAt);
}

1;
