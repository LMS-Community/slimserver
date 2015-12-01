package Slim::Plugin::JiveExtras::Plugin;

# This plugin enables custom wallpapers and sound effects to be defined by the user
# These appear on the settings menu on jive.  The wallpaper/sound file is either
# a remote url or a local file which is servered via Slim::Web::Pages->addRawDownload

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;

if ( main::WEBUI ) {
	require Slim::Plugin::JiveExtras::Settings;
}

my $prefs = preferences('plugin.jiveextras');

my $serverprefs = preferences('server');

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin;

	if ( main::WEBUI ) {
		Slim::Plugin::JiveExtras::Settings->new;
	}

	Slim::Control::Jive::registerExtensionProvider('jiveextras', \&getExtensions);

	Slim::Web::Pages->addRawDownload('^jive(wallpaper|sound)/', \&downloadFile, 'binary');
}

sub getExtensions {
	my $args = shift;

	my $target = $args->{'target'};

	my @res = ();
	my $urlBase = Slim::Utils::Network::serverURL() . "/jive$args->{type}";

	for my $opt (@{ $prefs->get($args->{'type'}) || [] }) {

		next if ($opt->{'target'} && $opt->{'target'} ne $target);

		my $new = {
			'name'  => $opt->{'key'},
			'title' => $opt->{'name'},
		};

		# modify the url if it is for a local file to one which can be served by us
		if ($opt->{'url'} !~ /http:\/\//) {
			$new->{'url'}    = "$urlBase/$opt->{key}";
			$new->{'relurl'} = "/jive$args->{type}/$opt->{key}";
		} else {
			$new->{'url'} = $opt->{'url'};
		}

		push @res, $new;
	}

	$args->{'cb'}->( @{$args->{'pt'}}, \@res );
}

sub downloadFile {
	my $path = shift;

	my ($type, $key) = $path =~ /^jive(wallpaper|sound)\/(.*)/;

	for my $opt (@{ $prefs->get($type) || [] }) {

		if ($key eq $opt->{'key'}) {

			return Slim::Utils::Unicode::utf8off($opt->{'url'});
		}
	}
}

1;
