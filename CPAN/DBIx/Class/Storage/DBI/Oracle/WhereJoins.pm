package DBIx::Class::Storage::DBI::Oracle::WhereJoins;

use strict;
use warnings;

use base qw( DBIx::Class::Storage::DBI::Oracle::Generic );
use mro 'c3';

__PACKAGE__->sql_maker_class('DBIx::Class::SQLAHacks::OracleJoins');

1;

__END__

=pod

=head1 NAME

DBIx::Class::Storage::DBI::Oracle::WhereJoins - Oracle joins in WHERE syntax
support (instead of ANSI).

=head1 PURPOSE

This module was originally written to support Oracle < 9i where ANSI joins
weren't supported at all, but became the module for Oracle >= 8 because
Oracle's optimising of ANSI joins is horrible.  (See:
http://scsys.co.uk:8001/7495)

=head1 SYNOPSIS

DBIx::Class should automagically detect Oracle and use this module with no
work from you.

=head1 DESCRIPTION

This class implements Oracle's WhereJoin support.  Instead of:

    SELECT x FROM y JOIN z ON y.id = z.id

It will write:

    SELECT x FROM y, z WHERE y.id = z.id

It should properly support left joins, and right joins.  Full outer joins are
not possible due to the fact that Oracle requires the entire query be written
to union the results of a left and right join, and by the time this module is
called to create the where query and table definition part of the sql query,
it's already too late.

=head1 METHODS

See L<DBIx::Class::SQLAHacks::OracleJoins> for implementation details.

=head1 BUGS

Does not support full outer joins.
Probably lots more.

=head1 SEE ALSO

=over

=item L<DBIx::Class::SQLAHacks>

=item L<DBIx::Class::SQLAHacks::OracleJoins>

=item L<DBIx::Class::Storage::DBI::Oracle::Generic>

=item L<DBIx::Class>

=back

=head1 AUTHOR

Justin Wheeler C<< <jwheeler@datademons.com> >>

=head1 CONTRIBUTORS

David Jack Olrik C<< <djo@cpan.org> >>

=head1 LICENSE

This module is licensed under the same terms as Perl itself.

=cut
