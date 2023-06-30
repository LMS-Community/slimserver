package Slim::Utils::ImageResizer;

use strict;

use Config;
use File::Spec::Functions qw(catdir);
use MIME::Base64 qw(encode_base64);
use Scalar::Util qw(blessed);

use Slim::Utils::ArtworkCache;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

# UNIX domain socket for optional artwork resizing daemon, if this is
# present we will use async artwork resizing via the external daemon
use constant SOCKET_PATH    => '/tmp/sbs_artwork';
use constant SOCKET_TIMEOUT => 15;
use constant DAEMON_WATCHDOG_INTERVAL => 6;

my $prefs = preferences('server');
my $log   = logger('artwork');

my ($gdresizein, $gdresizeout, $gdresizeproc);

my $pending_requests = 0;
my ($hasDaemon, $daemon, @daemonArgs);

sub hasDaemon { if (!main::ISWINDOWS) {
	my ($class, $check) = @_;

	if (!defined $hasDaemon || $check) {
		$hasDaemon = (!main::SCANNER && !main::ISWINDOWS && -r SOCKET_PATH && -w _) or do {
			unlink SOCKET_PATH;
		};
	}

	return $hasDaemon;
} }

sub initDaemon { if (!main::ISWINDOWS) {
	startDaemon() if isDaemonEnabled();
	$prefs->setChange(\&_checkDaemonStatus, 'useLocalImageproxy');
} }

sub resize {
	my ($class, $file, $cachekey, $specs, $callback, $cache) = @_;

	my $isDebug = main::DEBUGLOG && $log->is_debug;

	# Check for callback, and that the gdresized daemon running and read/writable
	if (!main::ISWINDOWS && hasDaemon() && $callback) {
		require AnyEvent::Socket;
		require AnyEvent::Handle;

		# Get cache root for passing to daemon
		$cache      ||= Slim::Utils::ArtworkCache->new();
		my $cacheroot = $cache->getRoot();

		main::DEBUGLOG && $isDebug && $log->debug("Using gdresized daemon to resize (pending requests: $pending_requests)");

		$pending_requests++;

		# Daemon available, do an async resize
		AnyEvent::Socket::tcp_connect( 'unix/', SOCKET_PATH, sub {
			my $fh = shift || do {
				$log->error("daemon failed to connect: $!");
				$hasDaemon = undef;

				if ( --$pending_requests == 0 ) {
					main::DEBUGLOG && $isDebug && $log->debug("no more pending requests");
				}

				# Fallback to resizing the old way
				sync_resize($file, $cachekey, $specs, $callback, $cache);

				return;
			};

			my $handle;

			# Timer in case daemon craps out
			my $timeout = sub {
				$log->error("daemon timed out");

				$handle && $handle->destroy;

				if ( --$pending_requests == 0 ) {
					main::DEBUGLOG && $isDebug && $log->debug("no more pending requests");
				}

				# Fallback to resizing the old way
				sync_resize($file, $cachekey, $specs, $callback, $cache);
			};
			Slim::Utils::Timers::setTimer( undef, Time::HiRes::time() + SOCKET_TIMEOUT, $timeout );

			$handle = AnyEvent::Handle->new(
				fh       => $fh,
				on_read  => sub {},
				on_eof   => undef,
				on_error => sub {
					my $result = delete $_[0]->{rbuf};

					main::DEBUGLOG && $isDebug && $log->debug("daemon result: $result");

					$_[0]->destroy;

					Slim::Utils::Timers::killTimers(undef, $timeout);

					if ( --$pending_requests == 0 ) {
						main::DEBUGLOG && $isDebug && $log->debug("no more pending requests");
					}

					# tell caller that the data is passed in the cache
					$callback && $callback->(undef, undef, 1);
				},
			);

			main::INFOLOG && $log->is_info && $log->info(sprintf("file=%s, spec=%s, cacheroot=%s, cachekey=%s, imagedata=%s bytes\n", ref $file ? 'data' : $file, $specs, $cacheroot, $cachekey, (ref $file ? length($$file) : 0)));

			$handle->push_write( pack('Z* Z* Z* Z* Z*', ref $file ? 'data' : $file, $specs, $cacheroot, $cachekey, (ref $file ? encode_base64($$file, '') : '')) . "\015\012" );
		}, sub {
			# prepare callback, used to set the timeout
			return SOCKET_TIMEOUT;
		} );

		return;
	}
	else {
		# No daemon, resize synchronously in-process
		return sync_resize($file, $cachekey, $specs, $callback, $cache);
	}
}

sub sync_resize {
	my ( $file, $cachekey, $specs, $callback, $cache ) = @_;

	require Slim::Utils::GDResizer;

	my $isDebug = main::DEBUGLOG && $log->is_debug;

	my ($ref, $format);

	my @spec = split(',', $specs);
	eval {
		($ref, $format) = Slim::Utils::GDResizer->gdresize(
			file      => $file,
			spec      => \@spec,
			cache     => $cache || Slim::Utils::ArtworkCache->new(),
			cachekey  => $cachekey,
			debug     => $isDebug,
		);
	};

	if ( main::DEBUGLOG && $isDebug && $@ ) {
		$file = '' if ref $file;
		$log->error("Error resizing $file: $@");
	}

	$callback && $callback->($ref, $format);

	return $@ ? 0 : 1;
}

sub isDaemonEnabled { if (!main::ISWINDOWS) {
	($prefs->get('useLocalImageproxy') || 0) == 2;
} }

sub startDaemon { if (!main::ISWINDOWS) {
	return if $daemon && $daemon->alive;

	$log->info("Starting daemon...");

	@daemonArgs = ();
	if (main::INFOLOG && $log->is_info) {
		unshift @daemonArgs, '--debug';
	}

	my $command = Slim::Utils::OSDetect::getOS->gdresized();

	if ($Config{'perlpath'} && -x $Config{'perlpath'}) {
		unshift @daemonArgs, $command;
		$command  = $Config{'perlpath'};
	}
	# pick up our custom Perl build if in use
	elsif (main::ISMAC && -x $^X && $^X !~ m|/usr/bin/perl|) {
		unshift @daemonArgs, $command;
		$command = $^X;
	}

	eval {
		$daemon = Proc::Background->new(
			{ 'die_upon_destroy' => 1 },
			$command,
			@daemonArgs
		);
	};

	if ($@) {
		$log->error("Failed to start resizing daemon: $@");
	}
	elsif (main::INFOLOG && $log->is_info) {
		$log->info('Started resizing daemon: pid ' . $daemon->pid);
	}

	_updateDaemonStatus();
	_checkDaemonStatus();
} }

sub stopDaemon { if (!main::ISWINDOWS) {
	$log->info("Stopping daemon...");
	Slim::Utils::Timers::killTimers( undef, \&_checkDaemonStatus );
	$daemon && $daemon->die;
	_updateDaemonStatus();
} }

sub _checkDaemonStatus { if (!main::ISWINDOWS) {
	Slim::Utils::Timers::killTimers( undef, \&_checkDaemonStatus );

	if ($daemon && $daemon->alive) {
		if (!isDaemonEnabled()) {
			stopDaemon();
			return;
		}
		# LMS thinks there's no daemon, but it's still running - restart it (but give it some time to start up)
		elsif (!hasDaemon() && time > $daemon->start_time + 2 * DAEMON_WATCHDOG_INTERVAL) {
			stopDaemon();
		}
		# restart if we changed logging options
		elsif ( (scalar grep /debug/i, @daemonArgs) ? !$log->is_info : $log->is_info ) {
			stopDaemon();
		}
	}

	if(!($daemon && $daemon->alive) && isDaemonEnabled()) {
		startDaemon();
	}

	Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + DAEMON_WATCHDOG_INTERVAL, \&_checkDaemonStatus);
} }

sub _updateDaemonStatus { if (!main::ISWINDOWS) {
	Slim::Utils::Timers::setTimer(1, time() + 5, \&hasDaemon);
} }

1;
