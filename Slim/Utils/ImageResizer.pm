package Slim::Utils::ImageResizer;

use strict;

use File::Spec::Functions qw(catdir);
use Scalar::Util qw(blessed);

use Slim::Utils::ArtworkCache;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

# UNIX domain socket for optional artwork resizing daemon, if this is
# present we will use async artwork resizing via the external daemon
use constant SOCKET_PATH    => '/tmp/sbs_artwork';
use constant SOCKET_TIMEOUT => 15;

my $prefs = preferences('server');
my $log   = logger('artwork');

my ($gdresizein, $gdresizeout, $gdresizeproc);

my $pending_requests = 0;
my $hasDaemon; 

sub hasDaemon {
	if (!defined $hasDaemon) {
		$hasDaemon = !main::SCANNER && !main::ISWINDOWS && -r SOCKET_PATH && -w _;
	}
	
	return $hasDaemon;
}

sub resize {
	my ($class, $file, $cachekey, $specs, $callback, $cache) = @_;
	
	my $isDebug = main::DEBUGLOG && $log->is_debug;
	
	# Check for callback, and that the gdresized daemon running and read/writable
	if (hasDaemon() && $callback) {
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
				main::DEBUGLOG && $isDebug && $log->debug("daemon failed to connect: $!");
				
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
				main::DEBUGLOG && $isDebug && $log->debug("daemon timed out");
				
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
					
					$callback && $callback->();
				},
			);
			
			$handle->push_write( pack('Z*Z*Z*Z*', $file, $specs, $cacheroot, $cachekey) . "\015\012" );
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

1;
