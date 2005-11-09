package UNIVERSAL::moniker;
$UNIVERSAL::moniker::VERSION = '0.08';

=head1 NAME

UNIVERSAL::moniker

=head1 SYNOPSIS

  use UNIVERSAL::moniker;

=head1 DESCRIPTION

Class names in Perl often don't sound great when spoken, or look good when
written in prose.  For this reason, we tend to say things like "customer" or
"basket" when we are referring to C<My::Site::User::Customer> or
C<My::Site::Shop::Basket>.  We thought it would be nice if our classes knew what
we would prefer to call them.

This module will add a C<moniker> (and C<plural_moniker>) method to
C<UNIVERSAL>, and so to every class or module.

=head2 moniker

  $ob->moniker;

Returns the moniker for $ob.
So, if $ob->isa("Big::Scary::Animal"), C<moniker> will return "animal".

=head2 plural_moniker

  $ob->plural_moniker;

Returns the plural moniker for $ob.
So, if $ob->isa("Cephalopod::Octopus"), C<plural_moniker> will return "octopuses".

(You need to install Lingua::EN::Inflect for this to work.)

=cut

package UNIVERSAL;

sub moniker {
    (ref( $_[0] ) || $_[0]) =~ /([^:]+)$/;
    return lc $1;
}

sub plural_moniker {
    CORE::require Lingua::EN::Inflect;
	return Lingua::EN::Inflect::PL($_[0]->moniker);
}

=head1 AUTHORS

Marty Pauley <marty+perl@kasei.com>,
Tony Bowden <tony@kasei.com>,
Elizabeth Mattijsen <liz@dijkmat.nl>

(Yes, 3 authors for such a small module!)

=head1 COPYRIGHT

  Copyright (C) 2004 Kasei

  This program is free software; you can redistribute it under the same terms as
  Perl.

  This program is distributed in the hope that it will be useful, but WITHOUT
  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
  FOR A PARTICULAR PURPOSE.

=cut


1;
