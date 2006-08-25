package DBIx::Class::Relationship;

use strict;
use warnings;

use base qw/DBIx::Class/;

__PACKAGE__->load_own_components(qw/
  Helpers
  Accessor
  CascadeActions
  ProxyMethods
  Base
/);

=head1 NAME

DBIx::Class::Relationship - Inter-table relationships

=head1 SYNOPSIS

  MyDB::Schema::Actor->has_many('actorroles' => 'MyDB::Schema::ActorRole',
                                'actor');
  MyDB::Schema::Role->has_many('actorroles' => 'MyDB::Schema::ActorRole',
                                'role');
  MyDB::Schema::ActorRole->belongs_to('role' => 'MyDB::Schema::Role');
  MyDB::Schema::ActorRole->belongs_to('actor' => 'MyDB::Schema::Actor');

  MyDB::Schema::Role->many_to_many('actors' => 'actorroles', 'actor');
  MyDB::Schema::Actor->many_to_many('roles' => 'actorroles', 'role');

  $schema->resultset('Actor')->roles();
  $schema->resultset('Role')->search_related('actors', { Name => 'Fred' });
  $schema->resultset('ActorRole')->add_to_roles({ Name => 'Sherlock Holmes'});

See L<DBIx::Class::Manual::Cookbook> for more.

=head1 DESCRIPTION

This class provides methods to set up relationships between the tables
in your database model. Relationships are the most useful and powerful
technique that L<DBIx::Class> provides. To create efficient database queries,
create relationships between any and all tables that have something in
common, for example if you have a table Authors:

  ID  | Name | Age
 ------------------
   1  | Fred | 30
   2  | Joe  | 32

and a table Books:

  ID  | Author | Name
 --------------------
   1  |      1 | Rulers of the universe
   2  |      1 | Rulers of the galaxy

Then without relationships, the method of getting all books by Fred goes like
this:

 my $fred = $schema->resultset('Author')->find({ Name => 'Fred' });
 my $fredsbooks = $schema->resultset('Book')->search({ Author => $fred->ID });
With a has_many relationship called "books" on Author (see below for details),
we can do this instead:

 my $fredsbooks = $schema->resultset('Author')->find({ Name => 'Fred' })->books;

Each relationship sets up an accessor method on the
L<DBIx::Class::Manual::Glossary/"Row"> objects that represent the items
of your table. From L<DBIx::Class::Manual::Glossary/"ResultSet"> objects,
the relationships can be searched using the "search_related" method.
In list context, each returns a list of Row objects for the related class,
in scalar context, a new ResultSet representing the joined tables is
returned. Thus, the calls can be chained to produce complex queries.
Since the database is not actually queried until you attempt to retrieve
the data for an actual item, no time is wasted producing them.

 my $cheapfredbooks = $schema->resultset('Author')->find({
   Name => 'Fred',
 })->books->search_related('prices', {
   Price => { '<=' => '5.00' },
 });

will produce a query something like:

 SELECT * FROM Author me
 LEFT JOIN Books books ON books.author = me.id
 LEFT JOIN Prices prices ON prices.book = books.id
 WHERE prices.Price <= 5.00

all without needing multiple fetches.

Only the helper methods for setting up standard relationship types
are documented here. For the basic, lower-level methods, and a description
of all the useful *_related methods that you get for free, see
L<DBIx::Class::Relationship::Base>.

=head1 METHODS

All helper methods take the following arguments:

  __PACKAGE__>$method_name('relname', 'Foreign::Class', $cond, $attrs);
  
Both C<$cond> and C<$attrs> are optional. Pass C<undef> for C<$cond> if
you want to use the default value for it, but still want to set C<$attrs>.
See L<DBIx::Class::Relationship::Base> for a list of valid attributes.

=head2 belongs_to

  # in a Book class (where Author has many Books)
  My::DBIC::Schema::Book->belongs_to(author => 'My::DBIC::Schema::Author');
  my $author_obj = $obj->author;
  $obj->author($new_author_obj);

Creates a relationship where the calling class stores the foreign class's
primary key in one (or more) of its columns. If C<$cond> is a column name
instead of a join condition hash, that is used as the name of the column
holding the foreign key. If C<$cond> is not given, the relname is used as
the column name.

If the relationship is optional - i.e. the column containing the foreign
key can be NULL - then the belongs_to relationship does the right
thing - so in the example above C<$obj-E<gt>author> would return C<undef>.
However in this case you would probably want to set the C<join_type>
attribute so that a C<LEFT JOIN> is done, which makes complex
resultsets involving C<join> or C<prefetch> operations work correctly.
The modified declaration is shown below:

  # in a Book class (where Author has_many Books)
  __PACKAGE__->belongs_to(author => 'My::DBIC::Schema::Author',
                          'author', {join_type => 'left'});


Cascading deletes are off by default on a C<belongs_to>
relationship. To turn them on, pass C<< cascade_delete => 1 >>
in the $attr hashref.

NOTE: If you are used to L<Class::DBI> relationships, this is the equivalent
of C<has_a>.

=head2 has_many

  # in an Author class (where Author has_many Books)
  My::DBIC::Schema::Author->has_many(books => 'My::DBIC::Schema::Book', 'author');
  my $booklist = $obj->books;
  my $booklist = $obj->books({
    name => { LIKE => '%macaroni%' },
    { prefetch => [qw/book/],
  });
  my @book_objs = $obj->books;
  my $books_rs = $obj->books;
  ( $books_rs ) = $obj->books_rs;

  $obj->add_to_books(\%col_data);

Creates a one-to-many relationship, where the corresponding elements of the
foreign class store the calling class's primary key in one (or more) of its
columns. You should pass the name of the column in the foreign class as the
C<$cond> argument, or specify a complete join condition.

Three methods are created when you create a has_many relationship.  The first
method is the expected accessor method.  The second is almost exactly the same
as the accessor method but "_rs" is added to the end of the method name.  This
method works just like the normal accessor, except that it returns a resultset
no matter what, even in list context. The third method, named
C<< add_to_<relname> >>, will also be added to your Row items; this allows
you to insert new related items, using the same mechanism as in
L<DBIx::Class::Relationship::Base/"create_related">.

If you delete an object in a class with a C<has_many> relationship, all
the related objects will be deleted as well.  To turn this behaviour off,
pass C<< cascade_delete => 0 >> in the C<$attr> hashref. However, any
database-level cascade or restrict will take precedence over a
DBIx-Class-based cascading delete.

=head2 might_have

  My::DBIC::Schema::Author->might_have(pseudonym =>
                                       'My::DBIC::Schema::Pseudonyms');
  my $pname = $obj->pseudonym; # to get the Pseudonym object

Creates an optional one-to-one relationship with a class, where the foreign
class stores our primary key in one of its columns. Defaults to the primary
key of the foreign class unless C<$cond> specifies a column or join condition.

If you update or delete an object in a class with a C<might_have>
relationship, the related object will be updated or deleted as well. To
turn off this behavior, add C<< cascade_delete => 0 >> to the C<$attr>
hashref. Any database-level update or delete constraints will override
this behavior.

=head2 has_one

  My::DBIC::Schema::Book->has_one(isbn => 'My::DBIC::Schema::ISBN');
  my $isbn_obj = $obj->isbn;

Creates a one-to-one relationship with another class. This is just like
C<might_have>, except the implication is that the other object is always
present. The only difference between C<has_one> and C<might_have> is that
C<has_one> uses an (ordinary) inner join, whereas C<might_have> uses a
left join.


=head2 many_to_many

=over 4

=item Arguments: $accessor_name, $link_rel_name, $foreign_rel_name

=back

  My::DBIC::Schema::Actor->has_many( actor_roles =>
                                     'My::DBIC::Schema::ActorRoles',
                                     'actor' );
  My::DBIC::Schema::ActorRoles->belongs_to( role =>
                                            'My::DBIC::Schema::Role' );
  My::DBIC::Schema::ActorRoles->belongs_to( actor =>
                                            'My::DBIC::Schema::Actor' );

  My::DBIC::Schema::Actor->many_to_many( roles => 'actor_roles',
                                         'role' );

Creates accessors bridging two relationships; not strictly a relationship in
its own right, although the accessor will return a resultset or collection of
objects just as a has_many would.

To use many_to_many, existing relationships from the original table to the link
table, and from the link table to the end table must already exist, these
relation names are then used in the many_to_many call.

=cut

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

