package Class::DBI::Plugin::AbstractCount;

use strict;
use base 'Class::DBI::Plugin';
use SQL::Abstract;

our $VERSION = '0.03';

sub init
{
	my $class = shift;
	$class->set_sql( count_search_where => qq{
			SELECT COUNT(*)
			FROM __TABLE__
			%s
		} );
}

sub count_search_where : Plugged
{
	my $class = shift;
	my $where = ref( $_[0] )
		? $_[0]
		: { @_ };
	my $attr  = ref( $_[0] )
		? $_[1]
		: undef;
	delete $attr->{order_by};

	$class->can( 'retrieve_from_sql' ) or do
		{
			require Carp;
			Carp::croak( "$class should inherit from Class::DBI >= 0.90" );
		};

	my ( $phrase, @bind ) = SQL::Abstract
		-> new( %$attr )
		-> where( $where );
	$class
		-> sql_count_search_where( $phrase )
		-> select_val( @bind );
}

1;
__END__

=head1 NAME

Class::DBI::Plugin::AbstractCount - get COUNT(*) results with abstract SQL

=head1 SYNOPSIS

  use base 'Class::DBI';
  use Class::DBI::Plugin::AbstractCount;
  
  my $count = Music::Vinyl->count_search_where(
    { artist   => 'Frank Zappa'
    , title    => { like    => '%Shut Up 'n Play Yer Guitar%' }
    , released => { between => [ 1980, 1982 ] }
    });

=head1 DESCRIPTION

This Class::DBI plugin combines the functionality from
Class::DBI::Plugin::CountSearch (counting objects without having to use an
array or an iterator), and Class::DBI::AbstractSearch, which allows complex
where-clauses a la SQL::Abstract.

=head1 METHODS

=head2 count_search_where

Takes a hashref with the abstract where-clause. An additional attribute hashref
can be passed to influence the default behaviour: arrayrefs are OR'ed, hashrefs
are AND'ed.

=head1 TODO

More tests, more doc.

=head1 SEE ALSO

=over

=item SQL::Abstract for details about the where-clause and the attributes.

=item Class::DBI::AbstractSearch

=item Class::DBI::Plugin::CountSearch

=back

=head1 AUTHOR

Jean-Christophe Zeus, E<lt>mail@jczeus.comE<gt> with some help from
Tatsuhiko Myagawa and Todd Holbrook.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2004 by Jean-Christophe Zeus

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
