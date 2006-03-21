package Slim::Utils::PerlRunTime;

# $Id$

# SlimServer Copyright (c) 2001-2005 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use B::Deparse;
use Devel::Peek;

# Use Tie::Watch to keep track of a variable, and report when it changes.
sub watchVariable {
	my $var = shift;

	require Tie::Watch;

	# See the Tie::Watch manpage for more info.
	Tie::Watch->new(
		-variable => $var,
		-shadow   => 0,

		-clear    => sub {
			msg("In clear callback for $var!\n");
			bt();
		},

		-destroy  => sub {
			msg("In destroy callback for $var!\n");
			bt();
		},

		-fetch   => sub {
			my ($self, $key) = @_;

			my $val  = $self->Fetch($key);
			my $args = $self->Args(-fetch);

			bt();
			msgf("In fetch callback, key=$key, val=%s, args=('%s')\n",
				$self->Say($val), ($args ? join("', '",  @$args) : 'undef')
			);

			return $val;
		},

		-store    => sub {
			my ($self, $key, $new_val) = @_;

			my $val  = $self->Fetch($key);
			my $args = $self->Args(-store);

			$self->Store($key, $new_val);

			bt();
			msgf("In store callback, key=$key, val=%s, new_val=%s, args=('%s')\n",
				$self->Say($val), $self->Say($new_val), ($args ? join("', '",  @$args) : 'undef')
			);

			return $new_val;
		},
	);
}

sub deparseCoderef {
	my $coderef = shift;

	my $deparse = B::Deparse->new('-si8T') || return 0;

	my $body = $deparse->coderef2text($coderef) || return 0;
	my $name = realNameForCodeRef($coderef);

	return "sub $name $body";
}

sub realNameForCodeRef {
	my $coderef = shift;

	my $gv   = Devel::Peek::CvGV($coderef);
	my $name = join('::', *$gv{'PACKAGE'}, *$gv{'NAME'}) || 'ANON';

	return $name;
}

1;

__END__
