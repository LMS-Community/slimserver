package DBIx::Class::UTF8Columns;
use strict;
use warnings;
use base qw/DBIx::Class/;

use Encode;

__PACKAGE__->mk_classdata( force_utf8_columns => [] );

=head1 NAME

DBIx::Class::UTF8Columns - Force UTF8 (Unicode) flag on columns

=head1 SYNOPSIS

    package Artist;
    __PACKAGE__->load_components(qw/UTF8Columns Core/);
    __PACKAGE__->utf8_columns(qw/name description/);
    
    # then belows return strings with utf8 flag
    $artist->name;
    $artist->get_column('description');

=head1 DESCRIPTION

This module allows you to get columns data that have utf8 (Unicode) flag.

=head1 SEE ALSO

L<Template::Stash::ForceUTF8>, L<DBIx::Class::UUIDColumns>.

=head1 METHODS

=head2 utf8_columns

=cut

sub utf8_columns {
    my $self = shift;
    for (@_) {
        $self->throw_exception("column $_ doesn't exist")
            unless $self->has_column($_);
    }
    $self->force_utf8_columns( \@_ );
}

=head1 EXTENDED METHODS

=head2 get_column

=cut

sub get_column {
    my ( $self, $column ) = @_;
    my $value = $self->next::method($column);

    if ( { map { $_ => 1 } @{ $self->force_utf8_columns } }->{$column} ) {
        Encode::_utf8_on($value) unless Encode::is_utf8($value);
    }

    $value;
}

=head2 get_columns

=cut

sub get_columns {
    my $self = shift;
    my %data = $self->next::method(@_);

    for (@{ $self->force_utf8_columns }) {
        Encode::_utf8_on($data{$_}) if $data{$_} and !Encode::is_utf8($_);
    }

    %data;
}

=head2 store_column

=cut

sub store_column {
    my ( $self, $column, $value ) = @_;

    if ( { map { $_ => 1 } @{ $self->force_utf8_columns } }->{$column} ) {
        Encode::_utf8_off($value) if Encode::is_utf8($value);
    }

    $self->next::method( $column, $value );
}

=head1 AUTHOR

Daisuke Murase <typester@cpan.org>

=head1 COPYRIGHT

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut

1;

