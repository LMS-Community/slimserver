package Data::Page;
use Carp;
use strict;
use vars qw($VERSION);
$VERSION = '1.01';

=head1 NAME

Data::Page - help when paging through sets of results

=head1 SYNOPSIS

  use Data::Page;

  my $page = Data::Page->new($total_entries, $entries_per_page, $current_page);

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

=head1 METHODS

=head2 new

This is the constructor. It currently takes two mandatory arguments,
the total number of entries and the number of entries per page. It
also optionally takes the current page number (which defaults to 1).

  my $page = Data::Page->new($total_entries, $entries_per_page, $current_page);

  my $page = Data::Page->new(134, 10);

  my $page = Data::Page->new(134, 10, 5);

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = {};

  $self->{TOTAL_ENTRIES} = shift;
  $self->{ENTRIES_PER_PAGE} = shift;
  $self->{CURRENT_PAGE} = shift;

  bless($self, $class);

  croak("Fewer than one entry per page!") if $self->entries_per_page < 1;
  $self->{CURRENT_PAGE} = $self->first_page unless defined $self->current_page;
  $self->{CURRENT_PAGE} = $self->first_page if $self->current_page < $self->first_page;
  $self->{CURRENT_PAGE} = $self->last_page if $self->current_page > $self->last_page;

  return $self;
}


=head2 total_entries

This method returns the total number of entries.

  print "Entries:", $page->total_entries, "\n";

=cut

sub total_entries {
  my $self = shift;

  return $self->{TOTAL_ENTRIES};
}


=head2 entries_per_page

This method returns the total number of entries per page.

  print "Per page:", $page->entries_per_page, "\n";

=cut

sub entries_per_page {
  my $self = shift;

  return $self->{ENTRIES_PER_PAGE};
}


=head2 entries_on_this_page

This methods returns the number of entries on the current page.

  print "There are ", $page->entries_on_this_page, " entries displayed\n";

=cut

sub entries_on_this_page {
  my $self = shift;

  if ($self->total_entries == 0) {
    return 0;
  } else {
    return $self->last - $self->first + 1;
  }
}


=head2 current_page

This method returns the current page number.

  print "Page: ", $page->current_page, "\n";

=cut

sub current_page {
  my $self = shift;

  return $self->{CURRENT_PAGE};
}


=head2 first_page

This method returns the first page. This is put in for reasons of
symmetry with last_page, as it always returns 1.

  print "Pages range from: ", $page->first_page, "\n";

=cut

sub first_page {
  my $self = shift;

  return 1;
}


=head2 last_page

This method returns the total number of pages of information.

  print "Pages range to: ", $page->last_page, "\n";

=cut

sub last_page {
  my $self = shift;

  my $pages = $self->total_entries / $self->entries_per_page;
  
  return ($pages == int $pages
	  ? $pages
	  : 1 + int $pages);
}


=head2 first

This method returns the number of the first entry on the current page.

  print "Showing entries from: ", $page->first, "\n";

=cut

sub first {
  my $self = shift;

  if ($self->total_entries == 0) {
    return 0;
  } else {
    return (($self->current_page - 1) * $self->entries_per_page) + 1;
  }
}


=head2 last

This method returns the number of the last entry on the current page.

  print "Showing entries to: ", $page->last, "\n";

=cut

sub last {
  my $self = shift;

  if ($self->current_page == $self->last_page) {
    return $self->total_entries;
  } else {
    return ($self->current_page * $self->entries_per_page);
  }
}


=head2 previous_page

This method returns the previous page number, if one exists. Otherwise
it returns undefined.

  if ($page->previous_page) {
    print "Previous page number: ", $page->previous_page, "\n";
  }

=cut

sub previous_page {
  my $self = shift;

  $self->{CURRENT_PAGE} > 1 ? $self->{CURRENT_PAGE} - 1 : undef;
}


=head2 next_page

This method returns the next page number, if one exists. Otherwise
it returns undefined.

  if ($page->next_page) {
    print "Next page number: ", $page->next_page, "\n";
  }

=cut

sub next_page {
  my $self = shift;

  $self->{CURRENT_PAGE} < $self->last_page ? $self->{CURRENT_PAGE} + 1 : undef;
}

=head2 splice

This method takes in a listref, and returns only the values which are
on the current page.

  @visible_holidays = $page->splice(\@holidays);

=cut

# This method would probably be better named 'select' or 'slice' or
# something, because it doesn't modify the array the way
# CORE::splice() does.
sub splice {
  my ($self, $array) = @_;
  my $top = @$array > $self->last ? $self->last : @$array;
  return () if $top == 0; # empty
  return @{$array}[ $self->first - 1 .. $top - 1 ];
}

=head1 NOTES

It has been said before that this code is "too simple" for CPAN, but I
must disagree. I have seen people write this kind of code over and
over again and they always get it wrong. Perhaps now they will spend
more time getting the rest of their code right...

=head1 AUTHOR

Based on code originally by Leo Lapworth, with many changes added by
by Leon Brocard <acme@astray.com>.

=head1 COPYRIGHT

Copyright (C) 2000-2, Leon Brocard

This module is free software; you can redistribute it or modify it
under the same terms as Perl itself.

=cut

1;

__END__
