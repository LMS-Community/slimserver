package Slim::Plugin::Favorites::Opml;

# Base class for editing opml files - front end to XMLin and XMLout


use strict;

use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Music::Info;
use Slim::Utils::Prefs;

use XML::Simple;
use File::Basename;
use File::Spec::Functions qw(:ALL);
use File::Temp qw(tempfile);
use Storable;

my $log = logger('favorites');

my $prefsServer = preferences('server');

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
	my $args  = shift;

	my $ref = bless {}, $class;

	if ($args) {

		$ref->load($args);

	} else {

		$ref->{'opml'} = Storable::dclone($nullopml);
	}

	return $ref;
}

sub load {
	my $class = shift;
	my $args  = shift;

	my $url      = $args->{'url'};
	my $content  = $args->{'content'};
	my $remote   = exists $args->{'content'};

	my $filename = $class->filename($url);

	$class->{'opml'} = undef;

	if (!$remote || $content) {

		$class->{'opml'} = eval { XMLin( $content || $filename, forcearray => [ 'outline', 'body' ], SuppressEmpty => undef ) };

		if (defined $class->{'opml'}) {

			main::INFOLOG && $log->info("Loaded OPML from $filename");

			return $class->{'opml'};

		} else {

			$log->warn("Failed to load from $filename ($@)");
		}
	}

	$class->{'opml'} = Storable::dclone($nullopml);

	$class->{'error'} = $remote ? 'remoteloaderror' : 'loaderror';

    return $class->{'opml'};
}

sub save {
	my $class = shift;
	my $name  = shift;

	my $filename = $class->filename($name);

	# ensure server XML cache for this filename is removed - this needs to align with server XMLbrowsers
	my $cache = Slim::Utils::Cache->new();
	$cache->remove( $class->fileurl . '_parsedXML' );

    my $dir = $filename ? dirname($filename) : undef;

	if (-w $dir) {

		my ($tmp, $tmpfilename) = tempfile(TEMPLATE => 'FavoritesTempXXXXX', DIR => $dir, SUFFIX => '.opml', UNLNK => 0, OPEN => 0);

		my $ret = eval { XMLout( $class->{'opml'}, OutputFile => $tmpfilename, XMLDecl => '<?xml version="1.0" encoding="UTF-8"?>',
								 KeyAttr => ['head', 'body'], SuppressEmpty => undef, Rootname =>"opml", NoSort => 0 ); };

		if (defined($ret)){

			main::INFOLOG && $log->info( "OPML saved to file tempfile: $tmpfilename" );

			if ( -e $filename && !rename($filename, $filename . ".backup") ) {

				$log->warn("Failed to rename old $filename to backup");
			}

			if ( rename($tmpfilename, $filename)) {

				main::INFOLOG && $log->info("Renamed $tmpfilename to $filename");

				$class->{'error'} = undef;

				return;

			} else {

				$log->warn("Failed for rename $tmpfilename to $filename");
			}
		}
	
	} else {

		$log->warn("Unable to write opml file $filename - directory $dir is not writable");
	}

	$class->{'error'} = 'saveerror';
}

sub title {
	my $class = shift;
	my $title = shift;

	return $class->{'opml'}->{'head'}->{'title'} unless $title;

	$class->{'opml'}->{'head'}->{'title'} = $title;
}

sub filename {
	my $class = shift;
	my $name  = shift;

	return $class->{'filename'} unless $name;

	if ( Slim::Music::Info::isFileURL($name) ) {

		$name = Slim::Utils::Misc::pathFromFileURL($name);

	} elsif ( !Slim::Music::Info::isURL($name) && dirname($name) eq '.' && Slim::Utils::Misc::getPlaylistDir() ) {

		$name = catdir(Slim::Utils::Misc::getPlaylistDir(), $name);
	}

	return $class->{'filename'} = $name;
}

sub fileurl {
	my $class = shift;

	return Slim::Utils::Misc::fileURLFromPath( $class->filename );
}

sub toplevel {
	return 	shift->{'opml'}->{'body'}[0]->{'outline'} ||= [];
}

sub error {
	return shift->{'error'};
}

sub clearerror {
	delete shift->{'error'};
}

sub level {
	my $class    = shift;
	my $index    = shift;
	my $contains = shift; # return the level containing the index rather than level for index

	my @ind;
	my @prefix;
	my $pos = $class->toplevel;

	if (ref $index eq 'ARRAY') {
		@ind = @$index;
	} else {
		@ind = split(/\./, $index);
	}

	my $count = scalar @ind - ($contains && scalar @ind && 1);

	while ($count && exists $pos->[$ind[0]]->{'outline'}) {
		push @prefix, $ind[0];
		$pos = $pos->[shift @ind]->{'outline'};
		$count--;
	}

	unless ($count) {
		if ($contains && $pos->[ $ind[0] ]) {
			return $pos, $ind[0], @prefix;
		} else {
			return $pos, undef, @prefix;
		}
	}

	return undef, undef, undef;
}

sub entry {
	my $class    = shift;
	my $index    = shift;

	my @ind;
	my $pos = $class->{'opml'}->{'body'}[0];

	if (ref $index eq 'ARRAY') {
		@ind = @$index;
	} else {
		@ind = split(/\./, $index);
	}

	while (@ind && ref $pos->{'outline'}->[ $ind[0] ] eq 'HASH') {
		$pos = $pos->{'outline'}->[shift @ind];
	}

	return @ind ? undef : $pos;
}

sub xmlbrowser {
	my $class = shift;

	# Always create a new hash for xmlbrowser as it now modifies the hash
	return Slim::Formats::XML::parseOPML ( {
		'head' => {
			'title' => $class->title,
		},
		'body' => {
			'outline' => Storable::dclone($class->toplevel),
		}
	} );
}

1;

