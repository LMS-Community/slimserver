package Slim::Plugin::Base;

# $Id$

# Base class for plugins. Implement some basics.

use strict;
use Slim::Buttons::Home;
use Slim::Utils::Log;

use constant PLUGINMENU => 'PLUGINS';

sub initPlugin {
        my $class = shift;
	my $args  = shift;

	my $name  = $class->displayName;
	my $menu  = $class->playerMenu;

	# This is a bit of a hack, but since Slim::Buttons::Common is such a
	# disaster, and has no concept of OO, we need to wrap 'setMode' (an
	# ambiguous function name if there ever was) in a closure so that it
	# can be called as class method.
	if ($class->can('setMode')) {

		my $exitMode = $class->can('exitMode') ? sub { $class->exitMode(@_) } : undef;

	        Slim::Buttons::Common::addMode($class, $class->getFunctions, sub { $class->setMode(@_) }, $exitMode);
	}

        my %params = (
                'useMode' => $class,
                'header'  => $name,
        );

        # Add toplevel info for the option of having a plugin at the top level.
        Slim::Buttons::Home::addMenuOption($name, \%params);

        Slim::Buttons::Home::addSubMenu($menu, $name, \%params);

	if ($menu ne PLUGINMENU) {

        	Slim::Buttons::Home::addSubMenu(PLUGINMENU, $menu, Slim::Buttons::Home::getMenu("-$menu"));
	}

	#logWarning("Adding $name to menu $menu");

	if ($class->can('webPages')) {

		$class->webPages;
	}
}

sub displayName {
	my $class = shift;

	return $class->_pluginDataFor('name') || $class;
}

sub playerMenu {
	my $class = shift;

	return $class->_pluginDataFor('playerMenu') || PLUGINMENU;
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

sub setMode {
        my $client = shift;
        my $method = shift;

	return;
}

1;

__END__
