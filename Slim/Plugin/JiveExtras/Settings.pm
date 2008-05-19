package Slim::Plugin::JiveExtras::Settings;

use strict;

use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

use Slim::Control::Jive;

my $prefs = preferences('plugin.jiveextras');

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

sub new {
	my $class = shift;

	$class->SUPER::new;

	for my $optname (qw(wallpaper sound)) {

		for my $opt (@{$prefs->get($optname)}) {

			Slim::Control::Jive::registerDownload($optname, $opt->{'name'}, $opt->{'url'}, $opt->{'key'}, $opt->{'vers'});
		}
	}
}

sub handler {
	my ($class, $client, $params) = @_;

	if ($params->{'saveSettings'}) {

		for my $optname (qw(wallpaper sound)) {

			for my $opt (@{$prefs->get($optname)}) {

				Slim::Control::Jive::deleteDownload($optname, $opt->{'key'});
			}

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
						'url'  => Slim::Utils::Unicode::utf8off($params->{"$optname$i"}), # Bug: 8184 turn utf8off
						'key'  => "JiveExtras_$j.$ext",
						'vers' => undef,
					};

					Slim::Control::Jive::registerDownload($optname, $opt->{'name'}, $opt->{'url'}, $opt->{'key'}, $opt->{'vers'});

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

		for my $opt (@{$prefs->get($optname)}) {
			push @{$params->{$optname}}, $opt;
		}

		push @{$params->{$optname}}, {
			'name' => string('PLUGIN_JIVEEXTRAS_CUSTOM') . (scalar @{$params->{$optname}} + 1),
			'url'  => string('PLUGIN_JIVEEXTRAS_FILEORURL'),
		};

		# find the actual urls which the server servers for these (local files are changed to a url)
		$params->{$optname.'_served'} = [];

		my $request = Slim::Control::Request::executeRequest($client,['jive'.$optname.'s']);

		for my $i (0 .. $request->getResultLoopCount('item') - 1 ) {
			if ($request->getResultLoop('item', $i, 'file') =~ /JiveExtras_(\d*)/) {
				$params->{$optname.'_served'}->[$1] = $request->getResultLoop('item', $i, 'url');
			}
		}
	}

	return $class->SUPER::handler($client, $params);
}


1;
