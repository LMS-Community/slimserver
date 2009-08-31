package DBIx::Class::Storage::DBI::ODBC::ACCESS;
use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;
use mro 'c3';

use DBI;

my $ERR_MSG_START = __PACKAGE__ . ' failed: ';

sub insert {
    my $self = shift;
    my ( $source, $to_insert ) = @_;

    my $bind_attributes = $self->source_bind_attributes( $source );
    my ( undef, $sth ) = $self->_execute( 'insert' => [], $source, $bind_attributes, $to_insert );

    #store the identity here since @@IDENTITY is connection global and this prevents
    #possibility that another insert to a different table overwrites it for this resultsource
    my $identity = 'SELECT @@IDENTITY';
    my $max_sth  = $self->{ _dbh }->prepare( $identity )
        or $self->throw_exception( $ERR_MSG_START . $self->{ _dbh }->errstr() );
    $max_sth->execute() or $self->throw_exception( $ERR_MSG_START . $max_sth->errstr );

    my $row = $max_sth->fetchrow_arrayref()
        or $self->throw_exception( $ERR_MSG_START . "$identity did not return any result." );

    $self->{ last_pk }->{ $source->name() } = $row;

    return $to_insert;
}

sub last_insert_id {
    my $self = shift;
    my ( $result_source ) = @_;

    return @{ $self->{ last_pk }->{ $result_source->name() } };
}

sub bind_attribute_by_data_type {
    my $self = shift;

    my ( $data_type ) = @_;

    return { TYPE => $data_type } if $data_type == DBI::SQL_LONGVARCHAR;

    return;
}

sub sqlt_type { 'ACCESS' }

1;

=head1 NAME

DBIx::Class::Storage::DBI::ODBC::ACCESS - Support specific to MS Access over ODBC

=head1 WARNING

I am not a DBI, DBIx::Class or MS Access guru. Use this module with that in
mind.

This module is currently considered alpha software and can change without notice.

=head1 DESCRIPTION

This class implements support specific to Microsoft Access over ODBC.

It is loaded automatically by by DBIx::Class::Storage::DBI::ODBC when it
detects a MS Access back-end.

=head1 SUPPORTED VERSIONS

This module have currently only been tested on MS Access 2003 using the Jet 4.0 engine.

As far as my knowledge it should work on MS Access 2000 or later, but that have not been tested.
Information about support for different version of MS Access is welcome.

=head1 IMPLEMENTATION NOTES

MS Access supports the @@IDENTITY function for retriving the id of the latest inserted row.
@@IDENTITY is global to the connection, so to support the possibility of getting the last inserted
id for different tables, the insert() function stores the inserted id on a per table basis.
last_insert_id() then just returns the stored value.

=head1 KNOWN ACCESS PROBLEMS

=over

=item Invalid precision value

This error message is received when trying to store more than 255 characters in a MEMO field.
The problem is (to my knowledge) an error in the MS Access ODBC driver. The problem is fixed
by setting the C<data_type> of the column to C<SQL_LONGVARCHAR> in C<add_columns>. 
C<SQL_LONGVARCHAR> is a constant in the C<DBI> module.

=back

=head1 IMPLEMENTED FUNCTIONS

=head2 bind_attribute_by_data_type

This function currently supports the SQL_LONGVARCHAR column type.

=head2 insert

=head2 last_insert_id

=head2 sqlt_type

=head1 BUGS

Most likely. Bug reports are welcome.

=head1 AUTHORS

Øystein Torget C<< <oystein.torget@dnv.com> >>

=head1 COPYRIGHT

You may distribute this code under the same terms as Perl itself.

Det Norske Veritas AS (DNV)

http://www.dnv.com

=cut

