package Class::DBI::Iterator;

=head1 NAME

Class::DBI::Iterator - Iterate over Class::DBI search results

=head1 SYNOPSIS

	my $it = My::Class->search(foo => 'bar');

	my $results = $it->count;

	my $first_result = $it->first;
	while ($it->next) { ... }

	my @slice = $it->slice(10,19);
	my $slice = $it->slice(10,19);

	$it->reset;

	$it->delete_all;

=head1 DESCRIPTION

Any Class::DBI search (including a has_many method) which returns multiple
objects can be made to return an iterator instead simply by executing
the search in scalar context.

Then, rather than having to fetch all the results at the same time, you
can fetch them one at a time, potentially saving a considerable amount
of processing time and memory.

=head1 CAVEAT

Note that there is no provision for the data changing (or even being
deleted) in the database inbetween performing the search and retrieving
the next result.

=cut

use strict;
use overload
	'0+'     => 'count',
	fallback => 1;

sub new {
	my ($me, $them, $data, @mapper) = @_;
	bless {
		_class  => $them,
		_data   => $data,
		_mapper => [@mapper],
		_place  => 0,
		},
		ref $me || $me;
}

sub set_mapping_method {
	my ($self, @mapper) = @_;
	$self->{_mapper} = [@mapper];
	$self;
}

sub class  { shift->{_class} }
sub data   { @{ shift->{_data} } }
sub mapper { @{ shift->{_mapper} } }

sub count {
	my $self = shift;
	$self->{_count} ||= scalar $self->data;
}

sub next {
	my $self = shift;
	my $use  = $self->{_data}->[ $self->{_place}++ ] or return;
	my @obj  = ($self->class->construct($use));
	foreach my $meth ($self->mapper) {
		@obj = map $_->$meth(), @obj;
	}
	warn "Discarding extra inflated objects" if @obj > 1;
	return $obj[0];
}

sub first {
	my $self = shift;
	$self->reset;
	return $self->next;
}

sub slice {
	my ($self, $start, $end) = @_;
	$end ||= $start;
	$self->{_place} = $start;
	my @return;
	while ($self->{_place} <= $end) {
		push @return, $self->next || last;
	}
	return @return if wantarray;

	my $slice = $self->new($self->class, \@return, $self->mapper,);
	return $slice;
}

sub delete_all {
	my $self = shift;
	my $count = $self->count or return;
	$self->first->delete;    # to reset counter
	while (my $obj = $self->next) {
		$obj->delete;
	}
	$self->{_data} = [];
	1;
}

sub reset { shift->{_place} = 0 }

1;
