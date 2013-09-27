package Slim::Plugin::Base;

# $Id$

# Base class for plugins. Implement some basics.

use strict;
use Slim::Utils::Log;

if ( !main::SCANNER ) {
	require Slim::Buttons::Home;
}

use constant PLUGINMENU => 'PLUGINS';

my $WEIGHTS = {};

my $nonSNApps;

sub initPlugin {
	my $class = shift;
	my $args  = shift;

	my $name  = $class->getDisplayName;
	my $menu  = $class->playerMenu;
	my $mode  = $class->modeName;
	
	if ( $class->can('weight') ) {
		$WEIGHTS->{ $name } = $class->weight;
	}

	# This is a bit of a hack, but since Slim::Buttons::Common is such a
	# disaster, and has no concept of OO, we need to wrap 'setMode' (an
	# ambiguous function name if there ever was) in a closure so that it
	# can be called as class method.
	if ( !main::SCANNER && $class->can('setMode') && $mode ) {

		my $exitMode = $class->can('exitMode') ? sub { $class->exitMode(@_) } : undef;

		Slim::Buttons::Common::addMode($mode, $class->getFunctions, sub { $class->setMode(@_) }, $exitMode);

		my %params = (
			'useMode'   => $mode,
			'header'    => $name,
			'condition' => sub { $class->condition(shift); },
		);

		# Add toplevel info for the option of having a plugin at the top level.
		Slim::Buttons::Home::addMenuOption($name, \%params);

		# If a plugin does not define a playerMenu, don't add it to any menu
		if ( $menu ) {
			Slim::Buttons::Home::addSubMenu($menu, $name, \%params);

			# Add new submenus to Extras but only if they aren't main top-level menus
			my $topLevel = {
				HOME         => 1,
				BROWSE_MUSIC => 1,
				RADIO        => 1,
				SETTINGS     => 1,
			};
		
			if ( $menu ne PLUGINMENU && !$topLevel->{$menu} ) {
				Slim::Buttons::Home::addSubMenu(PLUGINMENU, $menu, Slim::Buttons::Home::getMenu("-$menu"));
			}
		}
	}

	if ( main::WEBUI ) {
		if ( $class->can('webPages') ) {
			$class->webPages;
		}
	}

	if ($class->_pluginDataFor('icon')) {
		Slim::Web::Pages->addPageLinks("icons", { $name => $class->_pluginDataFor('icon') });
	}

	if ($class->can('defaultMap') && !main::SCANNER) {

		Slim::Hardware::IR::addModeDefaultMapping($mode, $class->defaultMap);
	}

	# add 3rd party plugins which wish to be in the apps menu to nonSNApps list
	if ($class->can('menu') && $class->menu && $class->menu eq 'apps' && $class =~ /^Plugins::/) {
		$class->addNonSNApp();
	}
}

sub getDisplayName {
	my $class = shift;

	return $class->_pluginDataFor('name') || $class;
}

sub playerMenu {
	my $class = shift;

	return $class->_pluginDataFor('playerMenu') || PLUGINMENU;
}

sub modeName {
	my $class = shift;

	return $class;
}

sub condition {
	return 1;
}

sub _pluginDataFor {
	my $class = shift;
	my $key   = shift;

	my $pluginData = Slim::Utils::PluginManager->dataForPlugin($class);

	if ($pluginData && ref($pluginData) && $pluginData->{$key}) {
		return $pluginData->{$key};
	}

	return undef;
}

sub getFunctions {
	my $class = shift;

	return {};
}

sub getWeights { $WEIGHTS }

sub addWeight {
	my ($class, $name, $weight) = @_;
	$WEIGHTS->{$name} = $weight if $name && $weight;
}

sub addNonSNApp {
	my $class = shift;
	
	$nonSNApps ||= [];
	push @$nonSNApps, $class;
}

sub nonSNApps {
	return $nonSNApps
}

1;

__END__
