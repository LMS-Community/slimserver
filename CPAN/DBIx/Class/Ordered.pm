package DBIx::Class::Ordered;
use strict;
use warnings;
use base qw( DBIx::Class );

=head1 NAME

DBIx::Class::Ordered - Modify the position of objects in an ordered list.

=head1 SYNOPSIS

Create a table for your ordered data.

  CREATE TABLE items (
    item_id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    position INTEGER NOT NULL
  );

Optionally, add one or more columns to specify groupings, allowing you 
to maintain independent ordered lists within one table:

  CREATE TABLE items (
    item_id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    position INTEGER NOT NULL,
    group_id INTEGER NOT NULL
  );

Or even

  CREATE TABLE items (
    item_id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    position INTEGER NOT NULL,
    group_id INTEGER NOT NULL,
    other_group_id INTEGER NOT NULL
  );

In your Schema or DB class add "Ordered" to the top 
of the component list.

  __PACKAGE__->load_components(qw( Ordered ... ));

Specify the column that stores the position number for 
each row.

  package My::Item;
  __PACKAGE__->position_column('position');

If you are using one grouping column, specify it as follows:

  __PACKAGE__->grouping_column('group_id');

Or if you have multiple grouping columns:

  __PACKAGE__->grouping_column(['group_id', 'other_group_id']);

That's it, now you can change the position of your objects.

  #!/use/bin/perl
  use My::Item;
  
  my $item = My::Item->create({ name=>'Matt S. Trout' });
  # If using grouping_column:
  my $item = My::Item->create({ name=>'Matt S. Trout', group_id=>1 });
  
  my $rs = $item->siblings();
  my @siblings = $item->siblings();
  
  my $sibling;
  $sibling = $item->first_sibling();
  $sibling = $item->last_sibling();
  $sibling = $item->previous_sibling();
  $sibling = $item->next_sibling();
  
  $item->move_previous();
  $item->move_next();
  $item->move_first();
  $item->move_last();
  $item->move_to( $position );
  $item->move_to_group( 'groupname' );
  $item->move_to_group( 'groupname', $position );
  $item->move_to_group( {group_id=>'groupname', 'other_group_id=>'othergroupname'} );
  $item->move_to_group( {group_id=>'groupname', 'other_group_id=>'othergroupname'}, $position );

=head1 DESCRIPTION

This module provides a simple interface for modifying the ordered 
position of DBIx::Class objects.

=head1 AUTO UPDATE

All of the move_* methods automatically update the rows involved in 
the query.  This is not configurable and is due to the fact that if you 
move a record it always causes other records in the list to be updated.

=head1 METHODS

=head2 position_column

  __PACKAGE__->position_column('position');

Sets and retrieves the name of the column that stores the 
positional value of each record.  Defaults to "position".

=cut

__PACKAGE__->mk_classdata( 'position_column' => 'position' );

=head2 grouping_column

  __PACKAGE__->grouping_column('group_id');

This method specifies a column to limit all queries in 
this module by.  This effectively allows you to have multiple 
ordered lists within the same table.

=cut

__PACKAGE__->mk_classdata( 'grouping_column' );

=head2 null_position_value

  __PACKAGE__->null_position_value(undef);

This method specifies a value of L</position_column> which B<would
never be assigned to a row> during normal operation. When
a row is moved, its position is set to this value temporarily, so
that any unique constrainst can not be violated. This value defaults
to 0, which should work for all cases except when your positions do
indeed start from 0.

=cut

__PACKAGE__->mk_classdata( 'null_position_value' => 0 );

=head2 siblings

  my $rs = $item->siblings();
  my @siblings = $item->siblings();

Returns an B<ordered> resultset of all other objects in the same
group excluding the one you called it on.

The ordering is a backwards-compatibility artifact - if you need
a resultset with no ordering applied use L</_siblings>

=cut
sub siblings {
    my $self = shift;
    return $self->_siblings->search ({}, { order_by => $self->position_column } );
}

=head2 previous_siblings

  my $prev_rs = $item->previous_siblings();
  my @prev_siblings = $item->previous_siblings();

Returns a resultset of all objects in the same group
positioned before the object on which this method was called.

=cut
sub previous_siblings {
    my $self = shift;
    my $position_column = $self->position_column;
    my $position = $self->get_column ($position_column);
    return ( defined $position
        ? $self->_siblings->search ({ $position_column => { '<', $position } })
        : $self->_siblings
    );
}

=head2 next_siblings

  my $next_rs = $item->next_siblings();
  my @next_siblings = $item->next_siblings();

Returns a resultset of all objects in the same group
positioned after the object on which this method was called.

=cut
sub next_siblings {
    my $self = shift;
    my $position_column = $self->position_column;
    my $position = $self->get_column ($position_column);
    return ( defined $position
        ? $self->_siblings->search ({ $position_column => { '>', $position } })
        : $self->_siblings
    );
}

=head2 previous_sibling

  my $sibling = $item->previous_sibling();

Returns the sibling that resides one position back.  Returns 0
if the current object is the first one.

=cut

sub previous_sibling {
    my $self = shift;
    my $position_column = $self->position_column;

    my $psib = $self->previous_siblings->search(
        {},
        { rows => 1, order_by => { '-desc' => $position_column } },
    )->single;

    return defined $psib ? $psib : 0;
}

=head2 first_sibling

  my $sibling = $item->first_sibling();

Returns the first sibling object, or 0 if the first sibling 
is this sibling.

=cut

sub first_sibling {
    my $self = shift;
    my $position_column = $self->position_column;

    my $fsib = $self->previous_siblings->search(
        {},
        { rows => 1, order_by => { '-asc' => $position_column } },
    )->single;

    return defined $fsib ? $fsib : 0;
}

=head2 next_sibling

  my $sibling = $item->next_sibling();

Returns the sibling that resides one position forward. Returns 0
if the current object is the last one.

=cut

sub next_sibling {
    my $self = shift;
    my $position_column = $self->position_column;
    my $nsib = $self->next_siblings->search(
        {},
        { rows => 1, order_by => { '-asc' => $position_column } },
    )->single;

    return defined $nsib ? $nsib : 0;
}

=head2 last_sibling

  my $sibling = $item->last_sibling();

Returns the last sibling, or 0 if the last sibling is this 
sibling.

=cut

sub last_sibling {
    my $self = shift;
    my $position_column = $self->position_column;
    my $lsib = $self->next_siblings->search(
        {},
        { rows => 1, order_by => { '-desc' => $position_column } },
    )->single;

    return defined $lsib ? $lsib : 0;
}

# an optimised method to get the last sibling position without inflating a row object
sub _last_sibling_pos {
    my $self = shift;
    my $position_column = $self->position_column;

    my $cursor = $self->next_siblings->search(
        {},
        { rows => 1, order_by => { '-desc' => $position_column }, columns => $position_column },
    )->cursor;

    my ($pos) = $cursor->next;
    return $pos;
}

=head2 move_previous

  $item->move_previous();

Swaps position with the sibling in the position previous in
the list.  Returns 1 on success, and 0 if the object is
already the first one.

=cut

sub move_previous {
    my $self = shift;
    return $self->move_to ($self->_position - 1);
}

=head2 move_next

  $item->move_next();

Swaps position with the sibling in the next position in the
list.  Returns 1 on success, and 0 if the object is already
the last in the list.

=cut

sub move_next {
    my $self = shift;
    return 0 unless $self->next_siblings->count;
    return $self->move_to ($self->_position + 1);
}

=head2 move_first

  $item->move_first();

Moves the object to the first position in the list.  Returns 1
on success, and 0 if the object is already the first.

=cut

sub move_first {
    return shift->move_to( 1 );
}

=head2 move_last

  $item->move_last();

Moves the object to the last position in the list.  Returns 1
on success, and 0 if the object is already the last one.

=cut

sub move_last {
    my $self = shift;
    return $self->move_to( $self->_group_rs->count );
}

=head2 move_to

  $item->move_to( $position );

Moves the object to the specified position.  Returns 1 on
success, and 0 if the object is already at the specified
position.

=cut

sub move_to {
    my( $self, $to_position ) = @_;
    return 0 if ( $to_position < 1 );

    my $from_position = $self->_position;
    return 0 if ( $from_position == $to_position );

    my $position_column = $self->position_column;

    {
        my $guard = $self->result_source->schema->txn_scope_guard;

        my ($direction, @between);
        if ( $from_position < $to_position ) {
            $direction = -1;
            @between = map { $self->_position_value ($_) } ( $from_position + 1, $to_position );
        }
        else {
            $direction = 1;
            @between = map { $self->_position_value ($_) } ( $to_position, $from_position - 1 );
        }

        my $new_pos_val = $self->_position_value ($to_position);                              # record this before the shift

        # we need to null-position the moved row if the position column is part of a constraint
        if (grep { $_ eq $position_column } ( map { @$_ } (values %{{ $self->result_source->unique_constraints }} ) ) ) {
            $self->_ordered_internal_update({ $position_column => $self->null_position_value });
        }

        $self->_shift_siblings ($direction, @between);
        $self->_ordered_internal_update({ $position_column => $new_pos_val });

        $guard->commit;

        return 1;
    }
}

=head2 move_to_group

  $item->move_to_group( $group, $position );

Moves the object to the specified position of the specified
group, or to the end of the group if $position is undef.
1 is returned on success, and 0 is returned if the object is
already at the specified position of the specified group.

$group may be specified as a single scalar if only one 
grouping column is in use, or as a hashref of column => value pairs
if multiple grouping columns are in use.

=cut

sub move_to_group {
    my( $self, $to_group, $to_position ) = @_;

    $self->throw_exception ('move_to_group() expects a group specification')
        unless defined $to_group;

    # if we're given a string, turn it into a hashref
    unless (ref $to_group eq 'HASH') {
        my @gcols = $self->_grouping_columns;

        $self->throw_exception ('Single group supplied for a multi-column group identifier') if @gcols > 1;
        $to_group = {$gcols[0] => $to_group};
    }

    my $position_column = $self->position_column;

    return 0 if ( defined($to_position) and $to_position < 1 );
    if ($self->_is_in_group ($to_group) ) {
        return 0 if not defined $to_position;
        return $self->move_to ($to_position);
    }

    {
        my $guard = $self->result_source->schema->txn_scope_guard;

        # Move to end of current group to adjust siblings
        $self->move_last;

        $self->set_inflated_columns({ %$to_group, $position_column => undef });
        my $new_group_count = $self->_group_rs->count;

        if ( not defined($to_position) or $to_position > $new_group_count) {
            $self->set_column(
                $position_column => $new_group_count
                    ? $self->_next_position_value ( $self->_last_sibling_pos )
                    : $self->_initial_position_value
            );
        }
        else {
            my $bumped_pos_val = $self->_position_value ($to_position);
            my @between = ($to_position, $new_group_count);
            $self->_shift_siblings (1, @between);   #shift right
            $self->set_column( $position_column => $bumped_pos_val );
        }

        $self->_ordered_internal_update;

        $guard->commit;

        return 1;
    }
}

=head2 insert

Overrides the DBIC insert() method by providing a default 
position number.  The default will be the number of rows in 
the table +1, thus positioning the new record at the last position.

=cut

sub insert {
    my $self = shift;
    my $position_column = $self->position_column;

    unless ($self->get_column($position_column)) {
        my $lsib_pos = $self->_last_sibling_pos;
        $self->set_column(
            $position_column => (defined $lsib_pos
                ? $self->_next_position_value ( $lsib_pos )
                : $self->_initial_position_value
            )
        );
    }

    return $self->next::method( @_ );
}

=head2 update

Overrides the DBIC update() method by checking for a change
to the position and/or group columns.  Movement within a
group or to another group is handled by repositioning
the appropriate siblings.  Position defaults to the end
of a new group if it has been changed to undef.

=cut

sub update {
    my $self = shift;

    # this is set by _ordered_internal_update()
    return $self->next::method(@_) if $self->{_ORDERED_INTERNAL_UPDATE};

    my $upd = shift;
    $self->set_inflated_columns($upd) if $upd;
    my %changes = $self->get_dirty_columns;
    $self->discard_changes;

    my $position_column = $self->position_column;

    # if nothing group/position related changed - short circuit
    if (not grep { exists $changes{$_} } ($self->_grouping_columns, $position_column) ) {
        return $self->next::method( \%changes, @_ );
    }

    {
        my $guard = $self->result_source->schema->txn_scope_guard;

        # if any of our grouping columns have been changed
        if (grep { exists $changes{$_} } ($self->_grouping_columns) ) {

            # create new_group by taking the current group and inserting changes
            my $new_group = {$self->_grouping_clause};
            foreach my $col (keys %$new_group) {
                if (exists $changes{$col}) {
                    $new_group->{$col} = delete $changes{$col}; # don't want to pass this on to next::method
                }
            }

            $self->move_to_group(
                $new_group,
                (exists $changes{$position_column}
                    # The FIXME bit contradicts the documentation: when changing groups without supplying explicit
                    # positions in move_to_group(), we push the item to the end of the group.
                    # However when I was rewriting this, the position from the old group was clearly passed to the new one
                    # Probably needs to go away (by ribasushi)
                    ? delete $changes{$position_column}     # means there was a position change supplied with the update too
                    : $self->_position                      # FIXME!
                ),
            );
        }
        elsif (exists $changes{$position_column}) {
            $self->move_to(delete $changes{$position_column});
        }

        my @res;
        my $want = wantarray();
        if (not defined $want) {
            $self->next::method( \%changes, @_ );
        }
        elsif ($want) {
            @res = $self->next::method( \%changes, @_ );
        }
        else {
            $res[0] = $self->next::method( \%changes, @_ );
        }

        $guard->commit;
        return $want ? @res : $res[0];
    }
}

=head2 delete

Overrides the DBIC delete() method by first moving the object 
to the last position, then deleting it, thus ensuring the
integrity of the positions.

=cut

sub delete {
    my $self = shift;

    my $guard = $self->result_source->schema->txn_scope_guard;

    $self->move_last;

    my @res;
    my $want = wantarray();
    if (not defined $want) {
        $self->next::method( @_ );
    }
    elsif ($want) {
        @res = $self->next::method( @_ );
    }
    else {
        $res[0] = $self->next::method( @_ );
    }

    $guard->commit;
    return $want ? @res : $res[0];
}

=head1 METHODS FOR EXTENDING ORDERED

You would want to override the methods below if you use sparse
(non-linear) or non-numeric position values. This can be useful
if you are working with preexisting non-normalised position data,
or if you need to work with materialized path columns.

=head2 _position

  my $num_pos = $item->_position;

Returns the B<absolute numeric position> of the current object, with the
first object being at position 1, its sibling at position 2 and so on.
By default simply returns the value of L</position_column>.

=cut
sub _position {
    my $self = shift;

#    #the right way to do this
#    return $self->previous_siblings->count + 1;

    return $self->get_column ($self->position_column);
}

=head2 _position_value

  my $pos_value = $item->_position_value ( $pos )

Returns the B<value> of L</position_column> of the object at numeric
position C<$pos>. By default simply returns C<$pos>.

=cut
sub _position_value {
    my ($self, $pos) = @_;

#    #the right way to do this (not optimized)
#    my $position_column = $self->position_column;
#    return $self -> _group_rs
#                 -> search({}, { order_by => $position_column })
#                 -> slice ( $pos - 1)
#                 -> single
#                 -> get_column ($position_column);

    return $pos;
}

=head2 _initial_position_value

  __PACKAGE__->_initial_position_value(0);

This method specifies a B<value> of L</position_column> which is assigned
to the first inserted element of a group, if no value was supplied at
insertion time. All subsequent values are derived from this one by
L</_next_position_value> below. Defaults to 1.

=cut

__PACKAGE__->mk_classdata( '_initial_position_value' => 1 );

=head2 _next_position_value

  my $new_value = $item->_next_position_value ( $position_value )

Returns a position B<value> that would be considered C<next> with
regards to C<$position_value>. Can be pretty much anything, given
that C<< $position_value < $new_value >> where C<< < >> is the
SQL comparison operator (usually works fine on strings). The
default method expects C<$position_value> to be numeric, and
returns C<$position_value + 1>

=cut
sub _next_position_value {
    return $_[1] + 1;
}

=head2 _shift_siblings

  $item->_shift_siblings ($direction, @between)

Shifts all siblings with B<positions values> in the range @between
(inclusive) by one position as specified by $direction (left if < 0,
 right if > 0). By default simply increments/decrements each
L<position_column> value by 1, doing so in a way as to not violate
any existing constraints.

Note that if you override this method and have unique constraints
including the L<position_column> the shift is not a trivial task.
Refer to the implementation source of the default method for more
information.

=cut
sub _shift_siblings {
    my ($self, $direction, @between) = @_;
    return 0 unless $direction;

    my $position_column = $self->position_column;

    my ($op, $ord);
    if ($direction < 0) {
        $op = '-';
        $ord = 'asc';
    }
    else {
        $op = '+';
        $ord = 'desc';
    }

    my $shift_rs = $self->_group_rs-> search ({ $position_column => { -between => \@between } });

    # some databases (sqlite) are dumb and can not do a blanket
    # increment/decrement. So what we do here is check if the
    # position column is part of a unique constraint, and do a
    # one-by-one update if this is the case

    my $rsrc = $self->result_source;

    if (grep { $_ eq $position_column } ( map { @$_ } (values %{{ $rsrc->unique_constraints }} ) ) ) {

        my @pcols = $rsrc->primary_columns;
        my $cursor = $shift_rs->search ({}, { order_by => { "-$ord", $position_column }, columns => \@pcols } )->cursor;
        my $rs = $self->result_source->resultset;

        while (my @pks = $cursor->next ) {

          my $cond;
          for my $i (0.. $#pcols) {
            $cond->{$pcols[$i]} = $pks[$i];
          }

          $rs->search($cond)->update ({ $position_column => \ "$position_column $op 1" } );
        }
    }
    else {
        $shift_rs->update ({ $position_column => \ "$position_column $op 1" } );
    }
}

=head1 PRIVATE METHODS

These methods are used internally.  You should never have the 
need to use them.

=head2 _group_rs

This method returns a resultset containing all members of the row
group (including the row itself).

=cut
sub _group_rs {
    my $self = shift;
    return $self->result_source->resultset->search({$self->_grouping_clause()});
}

=head2 _siblings

Returns an unordered resultset of all objects in the same group
excluding the object you called this method on.

=cut
sub _siblings {
    my $self = shift;
    my $position_column = $self->position_column;
    return $self->_group_rs->search(
        { $position_column => { '!=' => $self->get_column($position_column) } },
    );
}

=head2 _grouping_clause

This method returns one or more name=>value pairs for limiting a search
by the grouping column(s).  If the grouping column is not
defined then this will return an empty list.

=cut
sub _grouping_clause {
    my( $self ) = @_;
    return map {  $_ => $self->get_column($_)  } $self->_grouping_columns();
}

=head2 _get_grouping_columns

Returns a list of the column names used for grouping, regardless of whether
they were specified as an arrayref or a single string, and returns ()
if there is no grouping.

=cut
sub _grouping_columns {
    my( $self ) = @_;
    my $col = $self->grouping_column();
    if (ref $col eq 'ARRAY') {
        return @$col;
    } elsif ($col) {
        return ( $col );
    } else {
        return ();
    }
}

=head2 _is_in_group

    $item->_is_in_group( {user => 'fred', list => 'work'} )

Returns true if the object is in the group represented by hashref $other

=cut
sub _is_in_group {
    my ($self, $other) = @_;
    my $current = {$self->_grouping_clause};

    no warnings qw/uninitialized/;

    return 0 if (
        join ("\x00", sort keys %$current)
            ne
        join ("\x00", sort keys %$other)
    );
    for my $key (keys %$current) {
        return 0 if $current->{$key} ne $other->{$key};
    }
    return 1;
}

=head2 _ordered_internal_update

This is a short-circuited method, that is used internally by this
module to update positioning values in isolation (i.e. without
triggering any of the positioning integrity code).

Some day you might get confronted by datasets that have ambiguous
positioning data (i.e. duplicate position values within the same group,
in a table without unique constraints). When manually fixing such data
keep in mind that you can not invoke L<DBIx::Class::Row/update> like
you normally would, as it will get confused by the wrong data before
having a chance to update the ill-defined row. If you really know what
you are doing use this method which bypasses any hooks introduced by
this module.

=cut

sub _ordered_internal_update {
    my $self = shift;
    local $self->{_ORDERED_INTERNAL_UPDATE} = 1;
    return $self->update (@_);
}

1;

__END__

=head1 CAVEATS

=head2 Race Condition on Insert

If a position is not specified for an insert than a position 
will be chosen based either on L</_initial_position_value> or
L</_next_position_value>, depending if there are already some
items in the current group. The space of time between the
necessary selects and insert introduces a race condition.
Having unique constraints on your position/group columns,
and using transactions (see L<DBIx::Class::Storage/txn_do>)
will prevent such race conditions going undetected.

=head2 Multiple Moves

Be careful when issueing move_* methods to multiple objects.  If 
you've pre-loaded the objects then when you move one of the objects 
the position of the other object will not reflect their new value 
until you reload them from the database - see
L<DBIx::Class::Row/discard_changes>.

There are times when you will want to move objects as groups, such 
as changeing the parent of several objects at once - this directly 
conflicts with this problem.  One solution is for us to write a 
ResultSet class that supports a parent() method, for example.  Another 
solution is to somehow automagically modify the objects that exist 
in the current object's result set to have the new position value.

=head2 Default Values

Using a database defined default_value on one of your group columns
could result in the position not being assigned correctly.

=head1 AUTHOR

 Original code framework
   Aran Deltac <bluefeet@cpan.org>

 Constraints support and code generalisation
   Peter Rabbitson <ribasushi@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

