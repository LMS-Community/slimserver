package Class::DBI::Pager;

use strict;
use vars qw($VERSION $AUTOLOAD);
$VERSION = 0.05;

use Class::DBI 0.90;
use Data::Page;

sub import {
    my $class = shift;
    my $pkg   = caller(0);
    no strict 'refs';
    *{"$pkg\::pager"} = \&_pager;
}

sub _croak { require Carp; Carp::croak(@_); }

sub _pager {
    my($pkg, $entry, $curr) = @_;
    bless {
	pkg   => $pkg,
	entry => $entry,
	curr  => $curr,
	pager => undef,
    }, __PACKAGE__;
}

BEGIN {
    my @methods = qw(total_entries entries_per_page current_page entries_on_this_page
		     first_page last_page first last previous_page next_page);
    for my $method (@methods) {
	no strict 'refs';
	*$method = sub {
	    my $self = shift;
	    $self->{pager} or _croak("Can't call pager methods without searching");
	    $self->{pager}->$method(@_);
	};
    }
}

sub DESTROY { }

sub AUTOLOAD {
    my $self = shift;
    (my $method = $AUTOLOAD) =~ s/.*://;
    if (ref($self) && $self->{pkg}->can($method)) {
	my $iter  = $self->{pkg}->$method(@_);
	UNIVERSAL::isa($iter, 'Class::DBI::Iterator')
	    or _croak("$method doesn't return Class::DBI::Itertor");
	my $pager = $self->{pager} = Data::Page->new(
	    $iter->count, $self->{entry}, $self->{curr},
	);
	my @data = ($iter->data)[$pager->first-1 .. $pager->last-1];
	return $self->{pkg}->_ids_to_objects(\@data);
    }
    else {
	_croak(qq(Can't locate object method "$method" via package ) . ref($self) || $self);
    }
}

1;
__END__

=head1 NAME

Class::DBI::Pager - Pager utility for Class::DBI

=head1 SYNOPSIS

  package CD;
  use base qw(Class::DBI);
  __PACKAGE__->set_db(...);

  use Class::DBI::Pager;	# just use it

  # then, in client code!
  package main;

  use CD;
  my $pager = CD->pager(20, 1);     # ($items_per_page, $current_page)
  my @disks = $pager->retrieve_all;

=head1 DESCRIPTION

Class::DBI::Pager is a plugin for Class::DBI, which glues Data::Page
with Class::DBI. This module reduces your work a lot, for example when
you have to do something like:

  * retrieve objects from a database
  * display objects with 20 items per page

In addition, your work will be reduced more, when you use
Template-Toolkit as your templating engine. See L</"EXAMPLE"> for
details.

=head1 EXAMPLE

  # Controller: (MVC's C)
  my $query    = CGI->new;
  my $template = Template->new;

  my $pager    = Film->pager(20, $query->param('page') || 1);
  my $movies   = $pager->retrieve_all;
  $template->process($input, {
      movies => $movies,
      pager  => $pager,
  });

  # View: (MVC's V)
  Matched [% pager.total_entries %] items.

  [% WHILE (movie = movies.next) %]
  Title: [% movie.title | html %]
  [% END %]

  ### navigation like: [1] [2] [3]
  [% FOREACH num = [pager.first_page .. pager.last_page] %]
  [% IF num == pager.current_page %][[% num %]]
  [% ELSE %]<a href="display?page=[% num %]">[[% num %]]</a>[% END %]
  [% END %]

  ### navigation like: prev 20 | next 20
  [% IF pager.previous_page %]
  <a href="display?page=[% pager.previous_page %]">
  prev [% pager.entries_per_page %]</a> |
  [% END %]
  [% IF pager.next_page %]
  <a href="display?page=[% pager.next_page %]">
  next [% pager.entries_per_page %]</a>
  [% END %]

=head1 NOTE / TODO

This modules internally retrieves itertors, then creates C<Data::Page>
object for paging utility. Using SQL clauses C<LIMIT> and/or C<OFFSET>
with C<DBIx::Pager> might be more memory efficient.

=head1 AUTHOR

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt>

Original idea by Tomohiro Ikebe E<lt>ikebe@cpan.orgE<gt>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Class::DBI>, L<Data::Page>

=cut
