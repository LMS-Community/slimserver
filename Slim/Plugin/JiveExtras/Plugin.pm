package Slim::Plugin::JiveExtras::Plugin;

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Plugin::JiveExtras::Settings;

sub initPlugin {
	my $class = shift;

	Slim::Plugin::JiveExtras::Settings->new;

	$class->SUPER::initPlugin;
}

1;
