package Slim::Plugin::DnDPlay::FileManager;

use strict;

use Digest::MD5 qw(md5_hex);
use File::Next;
use File::Path qw(mkpath);
use File::Spec::Functions qw(catdir catfile);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

use constant CLEANUP_INTERVAL => 24 * 3600;

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
	my ($class, $file) = @_;
	
	my $filename = $class->cachedFileName($file);
	
	if ( !$filename ) {
		unlink $file->{tempfile};
		return;
	}
	
	rename $file->{tempfile}, $filename;

	my $url = Slim::Utils::Misc::fileURLFromPath($filename);
	
	my ($ext) = $filename =~ /\.(\w+)$/;
	$ext ||= 'unk';
	
	if ( Slim::Music::Info::isPlaylist($url, $ext) ) {
		main::DEBUGLOG && $log->debug("$url is a playlist, we won't make it volatile.");
	}
	else {
		$url =~ s/^file/tmp/;
	}
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Received audio file: $file->{name}; stored as $url");

	Slim::Utils::Timers::killTimers(0, \&_cleanup);
	Slim::Utils::Timers::setTimer(0, time() + CLEANUP_INTERVAL, \&_cleanup);
	
	return $url;
}

sub cachedFileName {
	my ($class, $file) = @_;

	return unless $file && $file->{name} && $file->{size} && $file->{timestamp};
	
	my ($key, $ext) = $class->cacheKey($file);

	return catfile($uploadFolder, "$key.$ext");
}

sub cacheKey {
	my ($class, $file) = @_;

	return unless $file && $file->{name} && $file->{size} && $file->{timestamp};

	my $name = Slim::Utils::Misc::escape($file->{name});

	my ($ext) = $file->{name} =~ /\.(\w+)$/;
	$ext    ||= Slim::Music::Info::mimeToType($file->{type});
	
	my $key = $file->{key} || md5_hex(join('::', $name, $file->{size}, $file->{timestamp}));
	
	return wantarray ? ($key, $ext) : $key;
}

sub getCachedOrLocalFileUrl {
	my ($class, $file) = @_;
	
	return unless $file && $file->{name} && $file->{size} && $file->{timestamp};
	
	my $filename = $class->cachedFileName($file);

	if ( -f $filename ) {
		my $url = Slim::Utils::Misc::fileURLFromPath($filename);
		$url =~ s/^file/tmp/;

		main::DEBUGLOG && $log->is_debug && $log->debug("Found cached file '$url' for " . Data::Dump::dump($file) );
		return $url;
	}

	# didn't find locally cached file - let's try the database instead
	my $dbh = Slim::Schema->dbh;
	
	# Filename encoding can be a pita - let's use a regex to work around it.
	# Filesize and timestamp are pretty unique, indexed and will provide for fast results anyway.
	my $sth = $dbh->prepare_cached( 'SELECT id FROM tracks WHERE filesize = ? AND timestamp = ? AND url REGEXP ? LIMIT 1' );

	# build regex based on URI escaped values
	my $filename = URI::Escape::uri_escape_utf8($file->{name});
	$filename =~ s/[\(\)'\^\$\[\]\+\*]/.*/g;
	$filename =~ s/(%[a-f\d]{2})+/.*/ig;
	
	$sth->execute( $file->{size}, $file->{timestamp}, $filename );
	
	my $results = $sth->fetchall_arrayref({});

	if ( $results && ref $results && (my $id = $results->[0]->{id}) ) {
		my $url = "db:track.id=$id";
		main::DEBUGLOG && $log->is_debug && $log->debug("Found indexed file $url for " . Data::Dump::dump($file) );
		return $url;
	}
}

sub _cleanup {
	Slim::Utils::Timers::killTimers(0, \&_cleanup);
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Starting upload folder cleanup...");
	
	# get a list of all tracks currently in use
	my $files = File::Next::files( Slim::Utils::OSDetect::dirsFor('prefs') );
	my %inUse;
	
	while ( defined ( my $file = $files->() ) ) {

		# only check player playlists of players which have been connected within the past few days
		if ( $file =~ /clientplaylist_.*?.m3u$/i && -M $file < 7 ) {

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

sub uploadFolder { $uploadFolder }

1;