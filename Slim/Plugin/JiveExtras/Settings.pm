package Slim::Plugin::JiveExtras::Settings;

use strict;

use base qw(Slim::Web::Settings);

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

sub name {
	return 'PLUGIN_JIVEEXTRAS';
}

sub page {
	return 'plugins/JiveExtras/settings/basic.html';
}

sub handler {
	my ($class, $client, $params) = @_;

	if ($params->{'saveSettings'}) {

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

					$j++;
				}

				$i++;
			}
			
			$prefs->set($optname, \@opts);
		}
	}

	for my $optname (qw(wallpaper sound)) {

		$params->{$optname} = [];
		$params->{$optname.'_served'} = [];

		my $urlBase = 'http://' . Slim::Utils::Network::serverAddr() . ':' . $serverprefs->get('httpport') . "/jive$optname";

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

	return $class->SUPER::handler($client, $params);
}


1;
