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

sub new {
	my $class = shift;
	my $name  = shift;

	my $ref = bless {}, $class;

	$ref->load($name) if $name;

	return $ref;
}

sub load {
	my $class = shift;
    my $name  = shift;

	my $filename = $class->filename($name);

	$class->{'opml'} = undef;

    if (defined $filename) {

		$class->{'opml'} = eval { XMLin( $filename, forcearray => [ 'outline', 'body' ], SuppressEmpty => undef ) };

		if (defined $class->{'opml'}) {

			$log->info("Loaded OPML file $filename");

		} else {

			$log->warn("Failed to load OPML $filename ($!)");

			$class->{'error'} = 'loaderror';
		}
    }

	$class->{'opml'} ||= {
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

	$class->{'error'} = undef;

    return $class->{'opml'};
}

sub save {
	my $class = shift;
	my $name  = shift;

	my $filename = $class->filename($name);

	# ensure server XML cache for this filename is removed - this needs to align with server XMLbrowsers
	my $cache = Slim::Utils::Cache->new();
	$cache->remove( Slim::Utils::Misc::fileURLFromPath($filename) . '_parsedXML' );

    my $dir = dirname($filename);

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

sub filename {
	my $class = shift;
	my $name  = shift;

	return $class->{'filename'} unless $name;

	if ($name =~ /^file\:\/\/(.*)/) {
		$name = $1;
	} elsif (dirname($name) eq '.') {
		$name = catdir(Slim::Utils::Prefs::get("playlistdir"), $name);
	}

	return $class->{'filename'} = $name;
}

1;

