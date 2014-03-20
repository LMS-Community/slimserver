package Slim::Utils::PerlRunTime;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Slim::Utils::Log;

=head1 NAME

Slim::Utils::PerlRunTime

=head1 DESCRIPTION

Various Perl run time functions for inspecting variables & references.

=head1 METHODS

=head2 watchVariable( $var )

Watch a variable using L<Tie::Watch>

=cut

# Use Tie::Watch to keep track of a variable, and report when it changes.
=pod
sub watchVariable {
	my $var = shift;

	require Tie::Watch;

	# See the Tie::Watch manpage for more info.
	Tie::Watch->new(
		-variable => $var,
		-shadow   => 0,

		-clear    => sub {
			logBacktrace("In clear callback for $var!");
		},

		-destroy  => sub {
			logBacktrace("In destroy callback for $var!");
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
=cut

=head2 deparseCoderef( $coderef )

Use L<B::Deparse> to turn a $coderef into an approximation of the original code.

=cut

=pod
sub deparseCoderef {
	my $coderef = shift;

	require B::Deparse;

	my $deparse = B::Deparse->new('-si8T') || return 0;

	my $body = $deparse->coderef2text($coderef) || return 0;
	my $name = realNameForCodeRef($coderef);

	return "sub $name $body";
}
=cut

=head2 realNameForCodeRef( $coderef )

Use L<Devel::Peek> find the original name of a non-anonymous $coderef.

=cut

sub realNameForCodeRef {
	if (main::INFOLOG) {
		my $coderef = shift;
		
		require Devel::Peek;
	
		my $gv   = Devel::Peek::CvGV($coderef);
		my $name = join('::', *$gv{'PACKAGE'}, *$gv{'NAME'}) || 'ANON';
	
		return $name;
	} else {
		return 'method-name-unavailable';
	}
}

=head1 SEE ALSO

L<B::Deparse>, L<Devel::Peek>

=cut

1;

__END__
