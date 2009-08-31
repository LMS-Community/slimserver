package DBIx::Class::Relationship::Base;

use strict;
use warnings;

use Scalar::Util ();
use base qw/DBIx::Class/;

=head1 NAME

DBIx::Class::Relationship::Base - Inter-table relationships

=head1 SYNOPSIS

=head1 DESCRIPTION

This class provides methods to describe the relationships between the
tables in your database model. These are the "bare bones" relationships
methods, for predefined ones, look in L<DBIx::Class::Relationship>.

=head1 METHODS

=head2 add_relationship

=over 4

=item Arguments: 'relname', 'Foreign::Class', $cond, $attrs

=back

  __PACKAGE__->add_relationship('relname', 'Foreign::Class', $cond, $attrs);

The condition needs to be an L<SQL::Abstract>-style representation of the
join between the tables. When resolving the condition for use in a C<JOIN>,
keys using the pseudo-table C<foreign> are resolved to mean "the Table on the
other side of the relationship", and values using the pseudo-table C<self>
are resolved to mean "the Table this class is representing". Other
restrictions, such as by value, sub-select and other tables, may also be
used. Please check your database for C<JOIN> parameter support.

For example, if you're creating a relationship from C<Author> to C<Book>, where
the C<Book> table has a column C<author_id> containing the ID of the C<Author>
row:

  { 'foreign.author_id' => 'self.id' }

will result in the C<JOIN> clause

  author me JOIN book book ON book.author_id = me.id

For multi-column foreign keys, you will need to specify a C<foreign>-to-C<self>
mapping for each column in the key. For example, if you're creating a
relationship from C<Book> to C<Edition>, where the C<Edition> table refers to a
publisher and a type (e.g. "paperback"):

  {
    'foreign.publisher_id' => 'self.publisher_id',
    'foreign.type_id'      => 'self.type_id',
  }

This will result in the C<JOIN> clause:

  book me JOIN edition edition ON edition.publisher_id = me.publisher_id
    AND edition.type_id = me.type_id

Each key-value pair provided in a hashref will be used as C<AND>ed conditions.
To add an C<OR>ed condition, use an arrayref of hashrefs. See the
L<SQL::Abstract> documentation for more details.

In addition to the
L<standard ResultSet attributes|DBIx::Class::ResultSet/ATTRIBUTES>,
the following attributes are also valid:

=over 4

=item join_type

Explicitly specifies the type of join to use in the relationship. Any SQL
join type is valid, e.g. C<LEFT> or C<RIGHT>. It will be placed in the SQL
command immediately before C<JOIN>.

=item proxy

An arrayref containing a list of accessors in the foreign class to create in
the main class. If, for example, you do the following:

  MyDB::Schema::CD->might_have(liner_notes => 'MyDB::Schema::LinerNotes',
    undef, {
      proxy => [ qw/notes/ ],
    });

Then, assuming MyDB::Schema::LinerNotes has an accessor named notes, you can do:

  my $cd = MyDB::Schema::CD->find(1);
  $cd->notes('Notes go here'); # set notes -- LinerNotes object is
                               # created if it doesn't exist

=item accessor

Specifies the type of accessor that should be created for the relationship.
Valid values are C<single> (for when there is only a single related object),
C<multi> (when there can be many), and C<filter> (for when there is a single
related object, but you also want the relationship accessor to double as
a column accessor). For C<multi> accessors, an add_to_* method is also
created, which calls C<create_related> for the relationship.

=item is_foreign_key_constraint

If you are using L<SQL::Translator> to create SQL for you and you find that it
is creating constraints where it shouldn't, or not creating them where it 
should, set this attribute to a true or false value to override the detection
of when to create constraints.

=item on_delete / on_update

If you are using L<SQL::Translator> to create SQL for you, you can use these
attributes to explicitly set the desired C<ON DELETE> or C<ON UPDATE> constraint 
type. If not supplied the SQLT parser will attempt to infer the constraint type by 
interrogating the attributes of the B<opposite> relationship. For any 'multi'
relationship with C<< cascade_delete => 1 >>, the corresponding belongs_to 
relationship will be created with an C<ON DELETE CASCADE> constraint. For any 
relationship bearing C<< cascade_copy => 1 >> the resulting belongs_to constraint
will be C<ON UPDATE CASCADE>. If you wish to disable this autodetection, and just
use the RDBMS' default constraint type, pass C<< on_delete => undef >> or 
C<< on_delete => '' >>, and the same for C<on_update> respectively.

=item is_deferrable

Tells L<SQL::Translator> that the foreign key constraint it creates should be
deferrable. In other words, the user may request that the constraint be ignored
until the end of the transaction. Currently, only the PostgreSQL producer
actually supports this.

=item add_fk_index

Tells L<SQL::Translator> to add an index for this constraint. Can also be
specified globally in the args to L<DBIx::Class::Schema/deploy> or
L<DBIx::Class::Schema/create_ddl_dir>. Default is on, set to 0 to disable.

=back

=head2 register_relationship

=over 4

=item Arguments: $relname, $rel_info

=back

Registers a relationship on the class. This is called internally by
DBIx::Class::ResultSourceProxy to set up Accessors and Proxies.

=cut

sub register_relationship { }

=head2 related_resultset

=over 4

=item Arguments: $relationship_name

=item Return Value: $related_resultset

=back

  $rs = $cd->related_resultset('artist');

Returns a L<DBIx::Class::ResultSet> for the relationship named
$relationship_name.

=cut

sub related_resultset {
  my $self = shift;
  $self->throw_exception("Can't call *_related as class methods")
    unless ref $self;
  my $rel = shift;
  my $rel_info = $self->relationship_info($rel);
  $self->throw_exception( "No such relationship ${rel}" )
    unless $rel_info;

  return $self->{related_resultsets}{$rel} ||= do {
    my $attrs = (@_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {});
    $attrs = { %{$rel_info->{attrs} || {}}, %$attrs };

    $self->throw_exception( "Invalid query: @_" )
      if (@_ > 1 && (@_ % 2 == 1));
    my $query = ((@_ > 1) ? {@_} : shift);

    my $source = $self->result_source;
    my $cond = $source->_resolve_condition(
      $rel_info->{cond}, $rel, $self
    );
    if ($cond eq $DBIx::Class::ResultSource::UNRESOLVABLE_CONDITION) {
      my $reverse = $source->reverse_relationship_info($rel);
      foreach my $rev_rel (keys %$reverse) {
        if ($reverse->{$rev_rel}{attrs}{accessor} eq 'multi') {
          $attrs->{related_objects}{$rev_rel} = [ $self ];
          Scalar::Util::weaken($attrs->{related_object}{$rev_rel}[0]);
        } else {
          $attrs->{related_objects}{$rev_rel} = $self;
          Scalar::Util::weaken($attrs->{related_object}{$rev_rel});
        }
      }
    }
    if (ref $cond eq 'ARRAY') {
      $cond = [ map {
        if (ref $_ eq 'HASH') {
          my $hash;
          foreach my $key (keys %$_) {
            my $newkey = $key !~ /\./ ? "me.$key" : $key;
            $hash->{$newkey} = $_->{$key};
          }
          $hash;
        } else {
          $_;
        }
      } @$cond ];
    } elsif (ref $cond eq 'HASH') {
      foreach my $key (grep { ! /\./ } keys %$cond) {
        $cond->{"me.$key"} = delete $cond->{$key};
      }
    }
    $query = ($query ? { '-and' => [ $cond, $query ] } : $cond);
    $self->result_source->related_source($rel)->resultset->search(
      $query, $attrs
    );
  };
}

=head2 search_related

  @objects = $rs->search_related('relname', $cond, $attrs);
  $objects_rs = $rs->search_related('relname', $cond, $attrs);

Run a search on a related resultset. The search will be restricted to the
item or items represented by the L<DBIx::Class::ResultSet> it was called
upon. This method can be called on a ResultSet, a Row or a ResultSource class.

=cut

sub search_related {
  return shift->related_resultset(shift)->search(@_);
}

=head2 search_related_rs

  ( $objects_rs ) = $rs->search_related_rs('relname', $cond, $attrs);

This method works exactly the same as search_related, except that 
it guarantees a restultset, even in list context.

=cut

sub search_related_rs {
  return shift->related_resultset(shift)->search_rs(@_);
}

=head2 count_related

  $obj->count_related('relname', $cond, $attrs);

Returns the count of all the items in the related resultset, restricted by the
current item or where conditions. Can be called on a
L<DBIx::Class::Manual::Glossary/"ResultSet"> or a
L<DBIx::Class::Manual::Glossary/"Row"> object.

=cut

sub count_related {
  my $self = shift;
  return $self->search_related(@_)->count;
}

=head2 new_related

  my $new_obj = $obj->new_related('relname', \%col_data);

Create a new item of the related foreign class. If called on a
L<Row|DBIx::Class::Manual::Glossary/"Row"> object, it will magically 
set any foreign key columns of the new object to the related primary 
key columns of the source object for you.  The newly created item will 
not be saved into your storage until you call L<DBIx::Class::Row/insert>
on it.

=cut

sub new_related {
  my ($self, $rel, $values, $attrs) = @_;
  return $self->search_related($rel)->new($values, $attrs);
}

=head2 create_related

  my $new_obj = $obj->create_related('relname', \%col_data);

Creates a new item, similarly to new_related, and also inserts the item's data
into your storage medium. See the distinction between C<create> and C<new>
in L<DBIx::Class::ResultSet> for details.

=cut

sub create_related {
  my $self = shift;
  my $rel = shift;
  my $obj = $self->search_related($rel)->create(@_);
  delete $self->{related_resultsets}->{$rel};
  return $obj;
}

=head2 find_related

  my $found_item = $obj->find_related('relname', @pri_vals | \%pri_vals);

Attempt to find a related object using its primary key or unique constraints.
See L<DBIx::Class::ResultSet/find> for details.

=cut

sub find_related {
  my $self = shift;
  my $rel = shift;
  return $self->search_related($rel)->find(@_);
}

=head2 find_or_new_related

  my $new_obj = $obj->find_or_new_related('relname', \%col_data);

Find an item of a related class. If none exists, instantiate a new item of the
related class. The object will not be saved into your storage until you call
L<DBIx::Class::Row/insert> on it.

=cut

sub find_or_new_related {
  my $self = shift;
  my $obj = $self->find_related(@_);
  return defined $obj ? $obj : $self->new_related(@_);
}

=head2 find_or_create_related

  my $new_obj = $obj->find_or_create_related('relname', \%col_data);

Find or create an item of a related class. See
L<DBIx::Class::ResultSet/find_or_create> for details.

=cut

sub find_or_create_related {
  my $self = shift;
  my $obj = $self->find_related(@_);
  return (defined($obj) ? $obj : $self->create_related(@_));
}

=head2 update_or_create_related

  my $updated_item = $obj->update_or_create_related('relname', \%col_data, \%attrs?);

Update or create an item of a related class. See
L<DBIx::Class::ResultSet/update_or_create> for details.

=cut

sub update_or_create_related {
  my $self = shift;
  my $rel = shift;
  return $self->related_resultset($rel)->update_or_create(@_);
}

=head2 set_from_related

  $book->set_from_related('author', $author_obj);
  $book->author($author_obj);                      ## same thing

Set column values on the current object, using related values from the given
related object. This is used to associate previously separate objects, for
example, to set the correct author for a book, find the Author object, then
call set_from_related on the book.

This is called internally when you pass existing objects as values to
L<DBIx::Class::ResultSet/create>, or pass an object to a belongs_to acessor.

The columns are only set in the local copy of the object, call L</update> to
set them in the storage.

=cut

sub set_from_related {
  my ($self, $rel, $f_obj) = @_;
  my $rel_info = $self->relationship_info($rel);
  $self->throw_exception( "No such relationship ${rel}" ) unless $rel_info;
  my $cond = $rel_info->{cond};
  $self->throw_exception(
    "set_from_related can only handle a hash condition; the ".
    "condition for $rel is of type ".
    (ref $cond ? ref $cond : 'plain scalar')
  ) unless ref $cond eq 'HASH';
  if (defined $f_obj) {
    my $f_class = $rel_info->{class};
    $self->throw_exception( "Object $f_obj isn't a ".$f_class )
      unless Scalar::Util::blessed($f_obj) and $f_obj->isa($f_class);
  }
  $self->set_columns(
    $self->result_source->_resolve_condition(
       $rel_info->{cond}, $f_obj, $rel));
  return 1;
}

=head2 update_from_related

  $book->update_from_related('author', $author_obj);

The same as L</"set_from_related">, but the changes are immediately updated
in storage.

=cut

sub update_from_related {
  my $self = shift;
  $self->set_from_related(@_);
  $self->update;
}

=head2 delete_related

  $obj->delete_related('relname', $cond, $attrs);

Delete any related item subject to the given conditions.

=cut

sub delete_related {
  my $self = shift;
  my $obj = $self->search_related(@_)->delete;
  delete $self->{related_resultsets}->{$_[0]};
  return $obj;
}

=head2 add_to_$rel

B<Currently only available for C<has_many>, C<many-to-many> and 'multi' type
relationships.>

=over 4

=item Arguments: ($foreign_vals | $obj), $link_vals?

=back

  my $role = $schema->resultset('Role')->find(1);
  $actor->add_to_roles($role);
      # creates a My::DBIC::Schema::ActorRoles linking table row object

  $actor->add_to_roles({ name => 'lead' }, { salary => 15_000_000 });
      # creates a new My::DBIC::Schema::Role row object and the linking table
      # object with an extra column in the link

Adds a linking table object for C<$obj> or C<$foreign_vals>. If the first
argument is a hash reference, the related object is created first with the
column values in the hash. If an object reference is given, just the linking
table object is created. In either case, any additional column values for the
linking table object can be specified in C<$link_vals>.

=head2 set_$rel

B<Currently only available for C<many-to-many> relationships.>

=over 4

=item Arguments: (\@hashrefs | \@objs), $link_vals?

=back

  my $actor = $schema->resultset('Actor')->find(1);
  my @roles = $schema->resultset('Role')->search({ role => 
     { '-in' => ['Fred', 'Barney'] } } );

  $actor->set_roles(\@roles);
     # Replaces all of $actor's previous roles with the two named

  $actor->set_roles(\@roles, { salary => 15_000_000 });
     # Sets a column in the link table for all roles


Replace all the related objects with the given reference to a list of
objects. This does a C<delete> B<on the link table resultset> to remove the
association between the current object and all related objects, then calls
C<add_to_$rel> repeatedly to link all the new objects.

Note that this means that this method will B<not> delete any objects in the
table on the right side of the relation, merely that it will delete the link
between them.

Due to a mistake in the original implementation of this method, it will also
accept a list of objects or hash references. This is B<deprecated> and will be
removed in a future version.

=head2 remove_from_$rel

B<Currently only available for C<many-to-many> relationships.>

=over 4

=item Arguments: $obj

=back

  my $role = $schema->resultset('Role')->find(1);
  $actor->remove_from_roles($role);
      # removes $role's My::DBIC::Schema::ActorRoles linking table row object

Removes the link between the current object and the related object. Note that
the related object itself won't be deleted unless you call ->delete() on
it. This method just removes the link between the two objects.

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
