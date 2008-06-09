package Slim::Plugin::MyRadio::Plugin;

use strict;
use base qw(Slim::Plugin::OPMLBased);

use File::Spec::Functions qw(:ALL);

use Slim::Plugin::Favorites::Plugin;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log   = logger('server.plugins');
my $prefs = preferences('server');

my $menuUrl;

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(
		feed => $class->menuUrl,
		tag  => 'myradio',
		menu => 'radios'
	);
}

sub getDisplayName {
	return 'PLUGIN_MYRADIO';
}

sub webPages {
	my $class = shift;

	my $title = $class->getDisplayName();
	my $url   = 'plugins/' . $class->tag() . '/index.html';
	
	Slim::Web::Pages->addPageLinks( $class->menu(), { $title => $url });

	# use the favorites handler but force the url to our opml file
	Slim::Web::HTTP::addPageFunction( $url, sub {

		if (ref $_[1] eq 'HASH') {
			$_[1]->{'new'}      = $class->menuUrl;
			$_[1]->{'autosave'} = 1;
			Slim::Plugin::Favorites::Plugin::indexHandler(@_);
		}
	} );
}

sub menuUrl {
	my $class = shift;

	return $menuUrl if $menuUrl;

	my $dir = $prefs->get('playlistdir');

	if (!$dir || !-w $dir) {
		$dir = $prefs->get('cachedir');
	}

	my $file = catdir($dir, "myradio.opml");

	$menuUrl = Slim::Utils::Misc::fileURLFromPath($file);

	if (-r $file) {

		if (-w $file) {
			$log->info("myradio menu file: $file");

		} else {
			$log->warn("unable to write to myradio menu file: $file");
		}

	} else {

		$log->info("creating myradio menu file: $file");

		my $newopml = Slim::Plugin::Favorites::Opml->new;
		$newopml->title(Slim::Utils::Strings::string('PLUGIN_MYRADIO'));
		$newopml->save($file);
	}

	return $menuUrl;
}


1;
