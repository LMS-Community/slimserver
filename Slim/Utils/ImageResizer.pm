package Slim::Utils::ImageResizer;

use strict;

use Scalar::Util qw(blessed);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $prefs = preferences('server');
my $log   = logger('artwork');

my ($gdresizein, $gdresizeout, $gdresizeproc);

sub resize {
	my ($class, $file, $cachekey, $specs, $callback) = @_;
	
	my $ret;
	
	if (1) {
		require Slim::Utils::GDResizer;
		
		my @spec = split(',', $specs);
		eval {
			Slim::Utils::GDResizer->gdresize(
				file      => $file,
				spec      => \@spec,
				cache     => Slim::Utils::Cache->new('Artwork'),
				cachekey  => $cachekey,
				debug     => main::DEBUGLOG && $log->is_debug,
				faster    => $prefs->get('resampleArtwork'),
			);
		};
		
		$ret =  ( $@ ) ? 0 : 1;
	}
	
	else {
		$ret = _gdresize($file, $specs, $cachekey);
	}
	
	if ($callback) {
		$callback->();
	}	
	
	return $ret;
}

sub _gdresize {
	my ($file, $spec, $cachekey) = @_;
	my $c  = pack('Z*Z*Z*', $file, $spec, $cachekey);
	my $cl = pack('CL', ord('R'), length($c));
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Command length ", length($c), ": $c");
	
	if (!defined $gdresizeproc || syswrite($gdresizeout, $cl, 5) != 5) {
		if (!defined $gdresizeproc || eof($gdresizein)) {
			$gdresizeproc = undef;
			_start_gdresized();
			
			# Try again
			syswrite($gdresizeout, $cl, 5) == 5 or return 0;
		}
	}
	
	syswrite($gdresizeout, $c, length($c)) == length($c) or return 0;
	
	my $result;
	sysread($gdresizein, $result, 1);
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Got result $result");
	
	if ($result && $result eq 'K') {
		return 1;
	} else {
		return 0;
	}
}

sub _start_gdresized {
	if (!defined $gdresizeproc) {
		require IPC::Open2;
		
		my $gdresize  = Slim::Utils::OSDetect::getOS->gdresized();
		
		my @cmd = (
			$gdresize,
			'--cacheroot', $prefs->get('librarycachedir'),
		);
		
		push @cmd, '--faster' if !$prefs->get('resampleArtwork');
		
		eval {
			if (main::DEBUGLOG && $log->is_debug) {
				push @cmd, '--debug';
				$log->debug( "  Running: " . join( " ", @cmd ) );
			}
			($gdresizeout, $gdresizein) = (undef, undef);
			$gdresizeproc = IPC::Open2::open2($gdresizein, $gdresizeout, @cmd) || die "Could not launch gdresized command\n";
		};
		
		if ( $@ ) {
			$log->error($@);
		} else {
			binmode($gdresizeout);
			binmode($gdresizein);
		}
	}
}


1;