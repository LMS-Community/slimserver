package Slim::Plugin::DnDPlay::FileManager;

use strict;

use File::Next;
use File::Path qw(mkpath);
use File::Spec::Functions qw(catdir catfile);
use File::Temp qw(tempfile);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

use constant CLEANUP_INTERVAL => 3600;

my $log = logger('plugin.dndplay');
my $serverprefs = preferences('server');

my $uploadFolder;

sub init {
	my ($class) = @_;

	$uploadFolder = catdir($serverprefs->get('cachedir'), 'audioUploads');
	mkpath($uploadFolder);
	
	_cleanup();
}

sub getFileUrl {
	my ($class, $header, $dataRef) = @_;

	my ($filename) = $header =~ /filename="(.+?)"/si;
	my $ext = $filename =~ /\.(\w)$/;
	
	# if we don't have a file extension, try to get it from the content-type header
	if ( !$ext && (my ($ct) = $header =~ /Content-Type: (.*)/) ) {
		$ext = Slim::Music::Info::mimeToType($ct);
	}
	
	return unless $ext;
	
	my (undef, $file) = tempfile(
		DIR => $uploadFolder,
		SUFFIX => '.' . $ext,
		OPEN => 0
	);
			
	File::Slurp::write_file($file, {binmode => ':raw'}, $dataRef);

	my $url = Slim::Utils::Misc::fileURLFromPath($file);
	$url =~ s/^file/tmp/;
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Received audio file: $filename; stored as $url");

	Slim::Utils::Timers::killTimers(0, \&_cleanup);
	Slim::Utils::Timers::setTimer(0, time() + CLEANUP_INTERVAL, \&_cleanup);
	
	return $url;
}

sub _cleanup {
	Slim::Utils::Timers::killTimers(0, \&_cleanup);
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Starting upload folder cleanup...");
	
	# get a list of all tracks currently in use
	my $files = File::Next::files( Slim::Utils::OSDetect::dirsFor('prefs') );
	my %inUse;
	
	while ( defined ( my $file = $files->() ) ) {
		if ( $file =~ /clientplaylist_.*?.m3u$/i ) {
			foreach ( Slim::Formats::Playlists::M3U->read($file, undef, Slim::Utils::Misc::fileURLFromPath($file)) ) {
				my $url = $_->url;
				next unless $url && $url =~ s/^tmp:/file:/;
				
				$inUse{Slim::Utils::Misc::pathFromFileURL($url)}++;
			}

			main::idleStreams();
		}
	}
	
	main::idleStreams();

	# now verify for every file in our upload folder whether it's still in use - otherwise delete
	$files = File::Next::files( $uploadFolder );
	while ( defined ( my $file = $files->() ) ) {
		if ( !$inUse{$file} ) {
			unlink $file;
			delete $inUse{$file};
		}
	}	

	Slim::Utils::Timers::setTimer(0, time() + CLEANUP_INTERVAL, \&_cleanup) if keys %inUse;

	main::DEBUGLOG && $log->is_debug && $log->debug("Upload folder cleanup done!");
}

1;