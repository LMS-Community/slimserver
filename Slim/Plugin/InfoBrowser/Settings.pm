package Slim::Plugin::InfoBrowser::Settings;

use strict;
use base qw(Slim::Web::Settings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;

use Slim::Plugin::Favorites::Opml;

my $prefs = preferences('plugin.infobrowser');
my $log   = logger('plugin.infobrowser');

my $plugin; # reference to main plugin

sub new {
	my $class = shift;
	$plugin   = shift;

	$class->SUPER::new;
}

sub name {
	return Slim::Web::HTTP::protectName('PLUGIN_INFOBROWSER');
}

sub page {
	return Slim::Web::HTTP::protectURI('plugins/InfoBrowser/settings/basic.html');
}

sub handler {
	my ($class, $client, $params) = @_;

	if ($params->{'reset'}) {
		$prefs->set('imported', {});
		$class->importNewMenuFiles('clear');
	}

	$params->{'opmlfile'} = $plugin->menuUrl;

	return $class->SUPER::handler($client, $params);
}

sub importNewMenuFiles {
	my $class = shift;
	my $clear = shift;

	my $imported = $prefs->get('imported');

	if (!defined $imported || $clear) {
		$imported = {};
		$clear = 'clear';
	}

	$log->info($clear ? "clearing old menu" : "searching for new menu files to import");

	my @files = ();
	my $iter  = File::Next::files({ 'file_filter' => sub { /\.opml$/ }, 'descend_filter' => sub { $_ ne 'HTML' } }, $plugin->searchDirs );

	while (my $file = $iter->()) {
		if ( !$imported->{ $file } ) {
			push @files, $file;
			$imported->{ $file } = 1;
		}
	}

	if (@files) {
		$class->_import($clear, \@files);
		$prefs->set('imported', $imported);
	}
}

sub _import {
	my $class = shift;
	my $clear = shift;
	my $files = shift;
	
	my $menuOpml = Slim::Plugin::Favorites::Opml->new({ 'url' => $plugin->menuUrl });

	if ($clear) {
		splice @{$menuOpml->toplevel}, 0;
	}

	for my $file (sort @$files) {

		$log->info("importing $file");
	
		my $import = Slim::Plugin::Favorites::Opml->new({ 'url' => $file });

		if ($import->title =~ /Default/) {
			# put these at the top of the list
			for my $entry (reverse @{$import->toplevel}) {
				unshift @{ $menuOpml->toplevel }, $entry;
			}
		} else {
			for my $entry (@{$import->toplevel}) {
				push @{ $menuOpml->toplevel }, $entry;
			}
		}
	}

	$menuOpml->save;
}

		
1;
