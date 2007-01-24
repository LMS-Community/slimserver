package Slim::Plugin::Favorites::Opml;

# Base class for editing opml files - front end to XMLin and XMLout

# $Id$

use strict;

use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

use XML::Simple;
use File::Basename;
use File::Spec::Functions qw(:ALL);
use File::Temp qw(tempfile);

my $log = logger('favorites');

my $nullopml = {
	'head' => {
		'title'          => string('NO_TITLE'),
		'expansionState' => {},
	},
	'version' => '1.0',
	'body'    => [
		{
			'outline' => [],
		}
	],
};

sub new {
	my $class = shift;
	my $name  = shift;

	my $ref = bless {}, $class;

	if ($name) {

		$ref->load($name);

	} else {

		$ref->{'opml'} = $nullopml;
	}

	return $ref;
}

sub load {
	my $class = shift;
    my $name  = shift;

	my $filename = $class->filename($name);

	$class->{'opml'} = undef;

	if (Slim::Music::Info::isRemoteURL($filename)) {

		$log->info("Fetching $name");

		my $http = Slim::Player::Protocols::HTTP->new( { 'url' => $filename, 'create' => 0, 'timeout' => 10 } );

		if (defined $http) {
			# NB this is not async at present - the following blocks the server user interface but not streaming
			$filename = \$http->content;
			$http->close;
		}
	}

	if (defined $filename) {

		$class->{'opml'} = eval { XMLin( $filename, forcearray => [ 'outline', 'body' ], SuppressEmpty => undef ) };

		if (defined $class->{'opml'}) {

			$log->info("Loaded OPML from $name");

			return $class->{'opml'};

		} else {

			$log->warn("Failed to load from $name ($!)");

		}
    }

	$class->{'opml'} = $nullopml;

	$class->{'error'} = 'loaderror';

    return $class->{'opml'};
}

sub save {
	my $class = shift;
	my $name  = shift;

	my $filename = $class->filename($name);

	# ensure server XML cache for this filename is removed - this needs to align with server XMLbrowsers
	my $cache = Slim::Utils::Cache->new();
	$cache->remove( Slim::Utils::Misc::fileURLFromPath($filename) . '_parsedXML' );

    my $dir = $filename ? dirname($filename) : undef;

	if (-w $dir) {

		my ($tmp, $tmpfilename) = tempfile(TEMPLATE => 'FavoritesTempXXXXX', DIR => $dir, SUFFIX => '.opml', UNLNK => 0, OPEN => 0);

		my $ret = eval { XMLout( $class->{'opml'}, OutputFile => $tmpfilename, XMLDecl => '<?xml version="1.0" encoding="UTF-8"?>',
								 KeyAttr => ['head', 'body'], SuppressEmpty => undef, Rootname =>"opml", NoSort => 0 ); };

		if (defined($ret)){

			$log->info( "OPML saved to file tempfile: $tmpfilename" );

			if ( -e $filename && !rename($filename, $filename . ".backup") ) {

				$log->warn("Failed to rename old $filename to backup");
			}

			if ( rename($tmpfilename, $filename)) {

				$log->info("Renamed $tmpfilename to $filename");

				$class->{'error'} = undef;

				return;

			} else {

				$log->warn("Failed for rename $tmpfilename to $filename");
			}
		}
	}

	$class->{'error'} = 'saveerror';
}

sub toplevel {
	return 	shift->{'opml'}->{'body'}[0]->{'outline'} ||= [];
}

sub title {
	my $class = shift;
	my $title = shift;

	return $class->{'opml'}->{'head'}->{'title'} unless $title;

	$class->{'opml'}->{'head'}->{'title'} = $title;
}

sub error {
	return shift->{'error'};
}

sub clearerror {
	delete shift->{'error'};
}

sub filename {
	my $class = shift;
	my $name  = shift;

	return $class->{'filename'} unless $name;

	if ($name =~ /^file\:\/\//) {
		$name = Slim::Utils::Misc::pathFromFileURL($name);
	} elsif (dirname($name) eq '.') {
		$name = catdir(Slim::Utils::Prefs::get("playlistdir"), $name);
	}

	return $class->{'filename'} = $name;
}

1;

