# $Id: WhiteHole.pm,v 1.4 2001/02/07 11:42:37 schwern Exp $

package Class::WhiteHole;

require 5;
use strict;
use vars qw(@ISA $VERSION $ErrorMsg);

$VERSION = '0.04';
@ISA = ();

# From 5.6.0's perldiag.
$ErrorMsg = qq{Can\'t locate object method "%s" via package "%s" }.
            qq{at %s line %d.\n};


=pod

=head1 NAME

Class::WhiteHole - base class to treat unhandled method calls as errors


=head1 SYNOPSIS

  package Bar;

  # DBI inherits from DynaLoader which inherits from AutoLoader
  # Bar wants to avoid this accidental inheritance of AutoLoader.
  use base qw(Class::WhiteHole DBI);


=head1 DESCRIPTION

Its possible to accidentally inherit an AUTOLOAD method.  Often this
will happen if a class somewhere in the chain uses AutoLoader or
defines one of their own.  This can lead to confusing error messages
when method lookups fail.

Sometimes you want to avoid this accidental inheritance.  In that
case, inherit from Class::WhiteHole.  All unhandled methods will
produce normal Perl error messages.


=head1 BUGS & CAVEATS

Be sure to have Class::WhiteHole before the class from which you're
inheriting AUTOLOAD in the ISA.  Usually you'll want Class::WhiteHole
to come first.

If your class inherits autoloaded routines this class may cause them
to stop working.  Choose wisely before using.

White holes are only a hypothesis and may not really exist.


=head1 COPYRIGHT

Copyright 2000 Michael G Schwern <schwern@pobox.com> all rights
reserved.  This program is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.


=head1 AUTHOR

Michael G Schwern <schwern@pobox.com>

=head1 SEE ALSO

L<Class::BlackHole>

=cut

sub AUTOLOAD {
    my($proto) = shift;
    my($class) = ref $proto || $proto;

    my($meth) = $Class::WhiteHole::AUTOLOAD =~ m/::([^:]+)$/;

    return if $meth eq 'DESTROY';

    my($callpack, $callfile, $callline) = caller;

    die sprintf $ErrorMsg, $meth, $class, $callfile, $callline;
}


1;

