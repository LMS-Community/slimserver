package Data::Page;
use Carp;
use strict;
use base 'Class::Accessor::Chained::Fast';
__PACKAGE__->mk_accessors(qw(total_entries entries_per_page current_page));

use vars qw($VERSION);
$VERSION = '2.00';

sub new {
  my $class = shift;
  my $self  = {};
  bless($self, $class);

  my ($total_entries, $entries_per_page, $current_page) = @_;
  $self->total_entries($total_entries       || 0);
  $self->entries_per_page($entries_per_page || 10);
  $self->current_page($current_page         || 1);
  return $self;
}

sub entries_per_page {
  my $self             = shift;
  my $entries_per_page = $_[0];
  if (@_) {
    croak("Fewer than one entry per page!") if $entries_per_page < 1;
    return $self->_entries_per_page_accessor(@_);
  }
  return $self->_entries_per_page_accessor();
}

sub current_page {
  my $self = shift;
  if (@_) {
    return $self->_current_page_accessor(@_);
  }
  return $self->first_page unless defined $self->_current_page_accessor;
  return $self->first_page if $self->_current_page_accessor < $self->first_page;
  return $self->last_page  if $self->_current_page_accessor > $self->last_page;
  return $self->_current_page_accessor();
}

sub total_entries {
  my $self = shift;
  if (@_) {
    return $self->_total_entries_accessor(@_);
  }
  return $self->_total_entries_accessor;
}

sub entries_on_this_page {
  my $self = shift;

  if ($self->total_entries == 0) {
    return 0;
  } else {
    return $self->last - $self->first + 1;
  }
}

sub first_page {
  my $self = shift;

  return 1;
}

sub last_page {
  my $self = shift;

  my $pages = $self->total_entries / $self->entries_per_page;
  my $last_page;

  if ($pages == int $pages) {
    $last_page = $pages;
  } else {
    $last_page = 1 + int($pages);
  }

  $last_page = 1 if $last_page < 1;
  return $last_page;
}

sub first {
  my $self = shift;

  if ($self->total_entries == 0) {
    return 0;
  } else {
    return (($self->current_page - 1) * $self->entries_per_page) + 1;
  }
}

sub last {
  my $self = shift;

  if ($self->current_page == $self->last_page) {
    return $self->total_entries;
  } else {
    return ($self->current_page * $self->entries_per_page);
  }
}

sub previous_page {
  my $self = shift;

  if ($self->current_page > 1) {
    return $self->current_page - 1;
  } else {
    return undef;
  }
}

sub next_page {
  my $self = shift;

  $self->current_page < $self->last_page ? $self->current_page + 1 : undef;
}

# This method would probably be better named 'select' or 'slice' or
# something, because it doesn't modify the array the way
# CORE::splice() does.
sub splice {
  my ($self, $array) = @_;
  my $top = @$array > $self->last ? $self->last : @$array;
  return () if $top == 0;    # empty
  return @{$array}[ $self->first - 1 .. $top - 1 ];
}

sub skipped {
  my $self = shift;

  my $skipped = $self->first - 1;
  return 0 if $skipped < 0;
  return $skipped;
}

1;

__END__

=head1 NAME

Data::Page - help when paging through sets of results

=head1 SYNOPSIS

  use Data::Page;

  my $page = Data::Page->new();
  $page->total_entries($total_entries);
  $page->entries_per_page($entries_per_page);
  $page->current_page($current_page);

  print "         First page: ", $page->first_page, "\n";
  print "          Last page: ", $page->last_page, "\n";
  print "First entry on page: ", $page->first, "\n";
  print " Last entry on page: ", $page->last, "\n";

=head1 DESCRIPTION

When searching through large amounts of data, it is often the case
that a result set is returned that is larger than we want to display
on one page. This results in wanting to page through various pages of
data. The maths behind this is unfortunately fiddly, hence this
module.

The main concept is that you pass in the number of total entries, the
number of entries per page, and the current page number. You can then
call methods to find out how many pages of information there are, and
what number the first and last entries on the current page really are.

For example, say we wished to page through the integers from 1 to 100
with 20 entries per page. The first page would consist of 1-20, the
second page from 21-40, the third page from 41-60, the fourth page
from 61-80 and the fifth page from 81-100. This module would help you
work this out.

=head1 METHODS

=head2 new

This is the constructor, which takes no arguments.

  my $page = Data::Page->new();

There is also an old, deprecated constructor, which currently takes
two mandatory arguments, the total number of entries and the number of
entries per page. It also optionally takes the current page number:

  my $page = Data::Page->new($total_entries, $entries_per_page, $current_page);

=head2 total_entries

This method get or sets the total number of entries:

  print "Entries:", $page->total_entries, "\n";

=head2 entries_per_page

This method gets or sets the total number of entries per page (which
defaults to 10):

  print "Per page:", $page->entries_per_page, "\n";

=head2 current_page

This method gets or sets the current page number (which defaults to 1):

  print "Page: ", $page->current_page, "\n";

=head2 entries_on_this_page

This methods returns the number of entries on the current page:

  print "There are ", $page->entries_on_this_page, " entries displayed\n";

=head2 first_page

This method returns the first page. This is put in for reasons of
symmetry with last_page, as it always returns 1:

  print "Pages range from: ", $page->first_page, "\n";

=head2 last_page

This method returns the total number of pages of information:

  print "Pages range to: ", $page->last_page, "\n";

=head2 first

This method returns the number of the first entry on the current page:

  print "Showing entries from: ", $page->first, "\n";

=head2 last

This method returns the number of the last entry on the current page:

  print "Showing entries to: ", $page->last, "\n";

=head2 previous_page

This method returns the previous page number, if one exists. Otherwise
it returns undefined:

  if ($page->previous_page) {
    print "Previous page number: ", $page->previous_page, "\n";
  }

=head2 next_page

This method returns the next page number, if one exists. Otherwise
it returns undefined:

  if ($page->next_page) {
    print "Next page number: ", $page->next_page, "\n";
  }

=head2 splice

This method takes in a listref, and returns only the values which are
on the current page:

  @visible_holidays = $page->splice(\@holidays);

=head2 skipped

This method is useful paging through data in a database using SQL
LIMIT clauses. It is simply $page->first - 1:

  $sth = $dbh->prepare(
    q{SELECT * FROM table ORDER BY rec_date LIMIT ?, ?}
  );
  $sth->execute($date, $page->skipped, $page->entries_per_page);

=head1 NOTES

It has been said before that this code is "too simple" for CPAN, but I
must disagree. I have seen people write this kind of code over and
over again and they always get it wrong. Perhaps now they will spend
more time getting the rest of their code right...

=head1 SEE ALSO

Related modules which may be of interest: L<Data::Pageset>,
L<Data::Page::Tied>, L<Data::SpreadPagination>.

=head1 AUTHOR

Based on code originally by Leo Lapworth, with many changes added by
by Leon Brocard <acme@astray.com>.

=head1 COPYRIGHT

Copyright (C) 2000-4, Leon Brocard

This module is free software; you can redistribute it or modify it
under the same terms as Perl itself.


