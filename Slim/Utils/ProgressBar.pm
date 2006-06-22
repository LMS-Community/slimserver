package Slim::Utils::ProgressBar;

# $Id$
#
# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, version 2.

use strict;
use base qw(Class::Data::Inheritable);

sub init {
	my $class = shift;

	if (!$class->can('useProgressBar')) {

        	$class->mk_classdata('useProgressBar');
	}

	$class->useProgressBar(0);

	# Term::ProgressBar requires Class::MethodMaker, which is rather large and is
	# compiled. Many platforms have it already though..
	if ($::progress) {

		eval "use Term::ProgressBar";

		if (!$@ && -t STDOUT) {

			$class->useProgressBar(1);
		}
	}
}

sub scanProgressBar {
	my $class = shift;
	my $count = shift;

	if ($class->useProgressBar) {

		my $progress = Term::ProgressBar->new({
			'count' => $count,
			'ETA'   => 'linear',
		});

		$progress->minor(0);

		return $progress;
	}

	return undef;
}

1;

__END__
