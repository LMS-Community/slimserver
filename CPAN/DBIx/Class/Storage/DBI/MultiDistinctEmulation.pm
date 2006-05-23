package DBIx::Class::Storage::DBI::MultiDistinctEmulation;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;

sub _select {
  my ($self, $ident, $select, $condition, $attrs) = @_;

  # hack to make count distincts with multiple columns work in SQLite and Oracle
  if (ref $select eq 'ARRAY') { 
      @{$select} = map {$self->replace_distincts($_)} @{$select};
  } else { 
      $select = $self->replace_distincts($select);
  }

  return $self->next::method($ident, $select, $condition, $attrs);
}

sub replace_distincts {
    my ($self, $select) = @_;

    $select->{count}->{distinct} = join("||", @{$select->{count}->{distinct}}) 
	if (ref $select eq 'HASH' && $select->{count} && ref $select->{count} eq 'HASH' && 
	    $select->{count}->{distinct} && ref $select->{count}->{distinct} eq 'ARRAY');

    return $select;
}

1;

=head1 NAME 

DBIx::Class::Storage::DBI::MultiDistinctEmulation - Some databases can't handle count distincts with multiple cols. They should use base on this.

=head1 SYNOPSIS

=head1 DESCRIPTION

This class allows count distincts with multiple columns for retarded databases (Oracle and SQLite)

=head1 AUTHORS

Luke Saunders <luke.saunders@gmail.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
