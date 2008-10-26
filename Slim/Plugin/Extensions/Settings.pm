package Slim::Plugin::Extensions::Settings;

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $prefs = preferences('plugin.extensions');

$prefs->init({ 'repos' => [] });

sub name {
	return Slim::Web::HTTP::protectName('PLUGIN_EXTENSIONS');
}

sub page {
	return Slim::Web::HTTP::protectURI('plugins/Extensions/settings/basic.html');
}

sub handler {
	my ($class, $client, $params) = @_;

	if ($params->{'saveSettings'}) {

		my @new = grep { $_ =~ /^http:\/\/.*\.xml/ } (ref $params->{'repos'} eq 'ARRAY' ? @{$params->{'repos'}} : $params->{'repos'});

		my %current = map { $_ => 1 } @{ $prefs->get('repos') || [] };
		my %new     = map { $_ => 1 } @new;

		for my $repo (keys %new) {
			if (!$current{$repo}) {
				Slim::Plugin::Extensions::Plugin::addRepo($repo);
			}
		}
		for my $repo (keys %current) {
			if (!$new{$repo}) {
				Slim::Plugin::Extensions::Plugin::removeRepo($repo);
			}
		}

		$prefs->set('repos', \@new);
	}

	my @repos = ( @{$prefs->get('repos')}, '' );

	$params->{'repos'} = \@repos;

	return $class->SUPER::handler($client, $params);
}

1;
