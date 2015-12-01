package Slim::Plugin::JiveExtras::Settings;

use strict;

use base qw(Slim::Web::Settings);

use File::Slurp;

use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

use Slim::Control::Jive;

my $prefs = preferences('plugin.jiveextras');

my $serverprefs = preferences('server');

$prefs->init({
	wallpaper => [],
	sound     => [],
});

my %filetypes = (
	wallpaper => qr/\.(bmp|jpg|jpeg|png|BMP|JPG|JPEG|PNG)$|^http:\/\//,
	sound     => qr/\.(wav)$/,
);

my %sizes = (
	'240x320' => 'Controller',
	'320x240' => 'Squeezebox Radio',
	'480x272' => 'Squeezebox Touch',
	# FIXME add desktop squeezeplay here?
);

sub name {
	return 'PLUGIN_JIVEEXTRAS';
}

sub page {
	return 'plugins/JiveExtras/settings/basic.html';
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	if ($params->{'saveSettings'}) {

		my @callbacks;

		for my $optname (qw(wallpaper sound)) {

			my @opts;
			my $i = 0;
			my $j = 0;

			while (defined $params->{"${optname}_name$i"}) {

				if ( ($params->{"$optname$i"} ne '' || $params->{"$optname$i"} ne string('PLUGIN_JIVEEXTRAS_FILEORURL')) &&
					 ($params->{"$optname$i"} =~ /^http:\/\// || -r $params->{"$optname$i"}) &&
					  $params->{"$optname$i"} =~ $filetypes{$optname} ) {

					my $ext = $1 || 'unk';	 

					my $opt = {
						'name' => $params->{"${optname}_name$i"},
						'url'  => $params->{"$optname$i"},
						'key'  => "JiveExtras_$j.$ext",
					};

					push @opts, $opt;

					push @callbacks, $opt if $optname eq 'wallpaper';

					$j++;
				}

				$i++;
			}
			
			$prefs->set($optname, \@opts);
		}

		if (@callbacks) {

			my $cbData = { remaining => 0, sizes => {}, returned => 0, pt => [ $class, $client, $params, $callback, \@args ] };

			for my $opt (@callbacks) {
				$class->getImageSize($cbData, $opt);
			}

			if ($cbData->{'remaining'}) {
				# _addSettings will be called when last async callback completes
				$cbData->{'returned'} = 1;
				return;
			}

		}
	}

	_addSettings($class, $client, $params, $callback, \@args);
}

sub _addSettings {
	my ($class, $client, $params, $callback, $args) = @_;

	for my $optname (qw(wallpaper sound)) {

		$params->{$optname} = [];
		$params->{$optname.'_served'} = [];

		my $urlBase = Slim::Utils::Network::serverURL() . "/jive$optname";

		for my $opt (@{$prefs->get($optname)}) {
			my $url;

			if ($opt->{'url'} =~ /http:\/\//) {
				$url = $opt->{'url'};
			} else {
				$url = "$urlBase/$opt->{key}";
			}

			push @{$params->{$optname}}, $opt;
			push @{$params->{$optname.'_served'}}, $url;
		}

		push @{$params->{$optname}}, {
			'name' => string('PLUGIN_JIVEEXTRAS_CUSTOM') . (scalar @{$params->{$optname}} + 1),
			'url'  => string('PLUGIN_JIVEEXTRAS_FILEORURL'),
		};
	}

	$params->{'sizes'} = \%sizes;

	$callback->($client, $params, $class->SUPER::handler($client, $params), @$args);
}

sub getImageSize {
	my $class = shift;
	my $cbData = shift;
	my $opt = shift;

	$cbData->{'remaining'}++;

	if ($opt->{'url'} =~ /http:\/\//) {

		$cbData->{'async'} = 1;

		Slim::Networking::SimpleAsyncHTTP->new(
			\&_asyncImageCB, \&_asyncImageCB, { opt => $opt, cbdata => $cbData }
		   )->get($opt->{'url'});

	} else {

		my $content = read_file($opt->{'url'});

		_asyncImageCB(undef, { content => $content, opt => $opt, cbdata => $cbData });
	}
}

sub _asyncImageCB {
	my $http = shift;
	my $args = shift;

	my $opt    = $http ? $http->params('opt') : $args->{'opt'};
	my $cbdata = $http ? $http->params('cbdata') : $args->{'cbdata'};

	if (my $content = ($args->{'content'} || $http->content)) {

		eval {
		
			require Slim::Utils::GDResizer;

			my ($w, $h) = Slim::Utils::GDResizer->getSize(\$content);

			$cbdata->{'sizes'}->{ $opt->{'key'} } = "${w}x${h}";
			
		};

	}

	if (--$cbdata->{'remaining'} == 0) {

		my $wallpapers = $prefs->get('wallpaper');

		for my $opt (@{ $wallpapers }) {
			if ($cbdata->{'sizes'}->{ $opt->{'key'} } ) {
				$opt->{'target'} = $cbdata->{'sizes'}->{ $opt->{'key'} };
			}
		}
		
		$prefs->save('wallpaper', $wallpapers);

		if ($cbdata->{'returned'}) {

			_addSettings(@{$cbdata->{'pt'}});
		}
	}
}

1;
