package Class::DBI::Plugin;

use 5.006;
use strict;
use attributes ();

our $VERSION = 0.03;

# Code stolen from Simon Cozens (Maypole)
our %remember;
sub MODIFY_CODE_ATTRIBUTES { $remember{ $_[1] } = $_[2]; () }
sub FETCH_CODE_ATTRIBUTES  { $remember{ $_[1] } }

sub import
{
	my $class  = shift;
	my $caller = caller;
	no strict 'refs';
	for my $symname ( keys %{ "$class\::" } ) {
		local *sym = ${ "$class\::" }{ $symname };
		next unless defined &sym; # We're only in it for the subroutines
		&sym( $caller ), next
			if $symname eq 'init';
		*{ "$caller\::$symname" } = \&sym
			if grep { defined( $_ ) and $_ eq 'Plugged' } attributes::get( \&sym );
	}
}

1;
__END__

=head1 NAME

Class::DBI::Plugin - Abstract base class for Class::DBI plugins

=head1 SYNOPSIS

  use base 'Class::DBI::Plugin';
  
  sub init {
    my $class = shift;
    $class->set_sql( statement_name => ... );
    $class->add_trigger( ... );
    $class->columns( TEMP => ... );
  }
  
  sub method_name : Plugged {
    my $class = shift;
    $class->sql_statement_name( ... );
  }

  sub this_method_is_not_exported {}

=head1 DESCRIPTION

Class::DBI::Plugin is an abstract base class for Class::DBI plugins. Its
purpose is to make writing plugins easier. Writers of plugins should be able
to concentrate on the functionality their module provides, instead of having
to deal with the symbol table hackery involved when writing a plugin
module.
Only three things must be remembered:

=over

=item 1

All methods which are to exported are given the "Plugged" attribute. All other
methods are not exported to the plugged-in class.

=item 2

Method calls which are to be sent to the plugged-in class are put in the
init() method. Examples of these are set_sql(), add_trigger() and so on.

=item 3

The class parameter for the init() method and the "Plugged" methods is the
plugged-in class, not the plugin class.

=back

=head1 CAVEATS

So far this module only "sees" methods in the plugin module itself. If there
is a class between the base class and the plugin class in the inheritance
hierarchy, methods of this class will not be found. In other words, inherited
methods will not be found. If requested, I will implement this behaviour.

=head1 TODO

It may be useful for plugin users to be able to choose only the plugin methods
they are interested in, if there are more than one. This is not implemented yet.

=head1 SEE ALSO

=over

=item *

Class::DBI

=back

=head1 AUTHOR

Jean-Christophe Zeus, E<lt>mail@jczeus.comE<gt> with some help from Simon
Cozens. Many thanks to Mark Addison for the idea with the init() method, and
many thanks to Steven Quinney for the idea with the subroutine attributes.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2004 by Jean-Christophe Zeus

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
