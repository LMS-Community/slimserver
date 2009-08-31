package DBIx::Class::UTF8Columns;
use strict;
use warnings;
use base qw/DBIx::Class/;

BEGIN {

    # Perl 5.8.0 doesn't have utf8::is_utf8()
    # Yes, 5.8.0 support for Unicode is suboptimal, but things like RHEL3 ship with it.
    if ($] <= 5.008000) {
        require Encode;
    } else {
        require utf8;
    }
}

__PACKAGE__->mk_classdata( '_utf8_columns' );

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
    if (@_) {
        foreach my $col (@_) {
            $self->throw_exception("column $col doesn't exist")
                unless $self->has_column($col);
        }        
        return $self->_utf8_columns({ map { $_ => 1 } @_ });
    } else {
        return $self->_utf8_columns;
    }
}

=head1 EXTENDED METHODS

=head2 get_column

=cut

sub get_column {
    my ( $self, $column ) = @_;
    my $value = $self->next::method($column);

    my $cols = $self->_utf8_columns;
    if ( $cols and defined $value and $cols->{$column} ) {

        if ($] <= 5.008000) {
            Encode::_utf8_on($value) unless Encode::is_utf8($value);
        } else {
            utf8::decode($value) unless utf8::is_utf8($value);
        }
    }

    $value;
}

=head2 get_columns

=cut

sub get_columns {
    my $self = shift;
    my %data = $self->next::method(@_);

    foreach my $col (grep { defined $data{$_} } keys %{ $self->_utf8_columns || {} }) {

        if ($] <= 5.008000) {
            Encode::_utf8_on($data{$col}) unless Encode::is_utf8($data{$col});
        } else {
            utf8::decode($data{$col}) unless utf8::is_utf8($data{$col});
        }
    }

    %data;
}

=head2 store_column

=cut

sub store_column {
    my ( $self, $column, $value ) = @_;

    my $cols = $self->_utf8_columns;
    if ( $cols and defined $value and $cols->{$column} ) {

        if ($] <= 5.008000) {
            Encode::_utf8_off($value) if Encode::is_utf8($value);
        } else {
            utf8::encode($value) if utf8::is_utf8($value);
        }
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

