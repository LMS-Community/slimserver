package Slim::Web::Setup;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

our %setup = ();

sub initSetup {

	loadSettingsModules();
}

sub loadSettingsModules {

	my $base = catdir(qw(Slim Web Settings));

	# Pull in the settings modules. Lighter than Module::Pluggable, which
	# uses File::Find - and 2Mb of memory!
	for my $dir (@INC) {

		next if !-d catdir($dir, $base);

		for my $sub (qw(Player Server)) {

			opendir(DIR, catdir($dir, $base, $sub));

			while (my $file = readdir(DIR)) {

				next if $file !~ s/\.pm$//;

				my $class = join('::', splitdir($base), $sub, $file);

				eval "use $class";

				if (!$@) {

					$class->new;
				}
			}

			closedir(DIR);
		}

		last;
	}
}

sub skins {
	my $forUI = shift;
	
	my %skinlist = ();

	for my $templatedir (Slim::Web::HTTP::HTMLTemplateDirs()) {

		for my $dir (Slim::Utils::Misc::readDirectory($templatedir)) {

			# reject CVS, html, and .svn directories as skins
			next if $dir =~ /^(?:cvs|html|\.svn)$/i;
			next if $forUI && $dir =~ /^x/;
			next if !-d catdir($templatedir, $dir);

			# BUG 4171: Disable dead Default2 skin, in case it was left lying around
			next if $dir =~ /^(?:Default2)$/i;

			logger('network.http')->info("skin entry: $dir");

			if ($dir eq Slim::Web::HTTP::defaultSkin()) {
				$skinlist{$dir} = string('DEFAULT_SKIN');
			} elsif ($dir eq Slim::Web::HTTP::baseSkin()) {
				$skinlist{$dir} = string('BASE_SKIN');
			} else {
				$skinlist{$dir} = Slim::Utils::Misc::unescape($dir);
			}
		}
	}

	return %skinlist;
}

sub getCategoryPlugins {
	my $client        = shift;
	my $category      = shift || 'PLUGINS';
	my $pluginlistref = Slim::Utils::PluginManager::installedPlugins();

	no strict 'refs';

	for my $plugin (keys %{$pluginlistref}) {

		# get plugin's displayName if it's not available, yet
		if (!Slim::Utils::Strings::stringExists($pluginlistref->{$plugin})) {

			$pluginlistref->{$plugin} = Slim::Utils::PluginManager::canPlugin($plugin);
		}
		
		if (Slim::Utils::Strings::stringExists($pluginlistref->{$plugin})) {

			my $menu = 'PLUGINS';

			if (UNIVERSAL::can("Plugins::${plugin}", "addMenu")) {

				$menu = eval { &{"Plugins::${plugin}::addMenu"}() };

				# if there's a problem or a category does not exist, reset $menu
				$menu = 'PLUGINS' if ($@ || !exists $setup{$menu});
			}

			# only return the current category's plugins
			if ($menu eq $category) {

				$pluginlistref->{$plugin} = Slim::Utils::Strings::string($pluginlistref->{$plugin});

				next;
			}
		}

		delete $pluginlistref->{$plugin};
	}
	
	return $pluginlistref;
}

1;

__END__
