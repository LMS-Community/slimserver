package Slim::Plugin::Favorites::Playlist;


# Class to allow importing of playlist formats understood by Logitech Media Server into opml files

use File::Basename qw(dirname);
use File::Spec::Functions qw(catdir);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

use strict;

my $log = logger('favorites');

my $prefsServer = preferences('server');

sub read {
	my $class = shift;
	my $name  = shift;

	if ($name =~ /^file\:\/\//) {

		$name = Slim::Utils::Misc::pathFromFileURL($name);

	} elsif (dirname($name) eq '.') {

		$name = catdir(Slim::Utils::Misc::getPlaylistDir(), $name);
	}

	my $type = Slim::Music::Info::contentType($name);
	my $playlistClass = Slim::Formats->classForFormat($type);

	if (-r $name && $type && $playlistClass) {

		Slim::Formats->loadTagFormatForType($type);

		my $fh = FileHandle->new($name);

		my @results = Slim::Plugin::Favorites::PlaylistWrapper->read($fh, $playlistClass);

		close($fh);

		if ( main::INFOLOG && $log->is_info ) {
			$log->info(sprintf "Imported %d items from playlist %s", scalar @results, $name);
		}

		return \@results;

	} else {

		$log->warn("Unable to import from $name");

		return undef;
	}
}

1;


package Slim::Plugin::Favorites::PlaylistWrapper;

# subclass the normal server format classes to avoid loading any data into the database
# and return elements in the format of opml hash entries

our @ISA;

sub read {
	my $class         = shift;
	my $fh            = shift;
	my $playlistClass = shift;

	@ISA = ( $playlistClass );

	return $class->SUPER::read($fh);
}

sub _updateMetaData {
	my $class = shift;
	my $entry = shift;
	my $attib = shift;

	# return an opml entry in hash format
	return {
		'URL'  => $entry,
		'text' => $attib->{'TITLE'},
		'type' => 'audio',
	};
}

1;
