package Class::DBI::AbstractSearch;

use strict;
use vars qw($VERSION @EXPORT);
$VERSION = 0.05;

require Exporter;
*import = \&Exporter::import;
@EXPORT = qw(search_where);

use SQL::Abstract;

sub search_where {
    my $class = shift;
    my $where = (ref $_[0]) ? $_[0]          : { @_ };
    my $attr  = (ref $_[0]) ? $_[1]          : undef;
    my $order = ($attr)     ? delete($attr->{order_by}) : undef;

    # order is deprecated, but still backward compatible
    if ($attr && exists($attr->{order})) {
	$order = delete($attr->{order});
    }

    $class->can('retrieve_from_sql') or do {
	require Carp;
	Carp::croak("$class should inherit from Class::DBI >= 0.90");
    };
    my $sql = SQL::Abstract->new(%$attr);
    my($phrase, @bind) = $sql->where($where, $order);
    $phrase =~ s/^\s*WHERE\s*//i;
    return $class->retrieve_from_sql($phrase, @bind);
}

1;
__END__

=head1 NAME

Class::DBI::AbstractSearch - Abstract Class::DBI's SQL with SQL::Abstract

=head1 SYNOPSIS

  package CD::Music;
  use Class::DBI::AbstractSearch;

  package main;
  my @music = CD::Music->search_where(
      artist => [ 'Ozzy', 'Kelly' ],
      status => { '!=', 'outdated' },
  );

  my @misc = CD::Music->search_where(
      { artist => [ 'Ozzy', 'Kelly' ],
        status => { '!=', 'outdated' } },
      { order_by  => "reldate DESC" });

=head1 DESCRIPTION

Class::DBI::AbstractSearch is a Class::DBI plugin to glue
SQL::Abstract into Class::DBI.

=head1 METHODS

Using this module adds following methods into your data class.

=over 4

=item search_where

  $class->search_where(%where);

Takes a hash to specify WHERE clause. See L<SQL::Abstract> for hash
options.

  $class->search_where(\%where,\%attrs);

Takes hash reference to specify WHERE clause. See L<SQL::Abstract>
for hash options. Takes a hash reference to specify additional query
attributes. Class::DBI::AbstractSearch uses these attributes:

=over 4

=item *

B<order_by>

Array reference of fields that will be used to order the results of
your query.

=back

Any other attributes are passed to the SQL::Abstract constructor,
and can be used to control how queries are created.  For example,
to use 'AND' instead of 'OR' by default, use:

    $clsas->search_where(\%where, { logic => 'AND' });

=head1 AUTHOR

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt> with some help from
cdbi-talk mailing list, especially:

  Tim Bunce
  Simon Wilcox
  Tony Bowden

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Class::DBI>, L<SQL::Abstract>

=cut
