package DBIx::Class;

use strict;
use warnings;

use vars qw($VERSION);
use base qw/DBIx::Class::Componentised Class::Data::Accessor/;

sub mk_classdata { shift->mk_classaccessor(@_); }
sub component_base_class { 'DBIx::Class' }

# Always remember to do all digits for the version even if they're 0
# i.e. first release of 0.XX *must* be 0.XX000. This avoids fBSD ports
# brain damage and presumably various other packaging systems too

$VERSION = '0.07001';

sub MODIFY_CODE_ATTRIBUTES {
    my ($class,$code,@attrs) = @_;
    $class->mk_classdata('__attr_cache' => {})
      unless $class->can('__attr_cache');
    $class->__attr_cache->{$code} = [@attrs];
    return ();
}

sub _attr_cache {
    my $self = shift;
    my $cache = $self->can('__attr_cache') ? $self->__attr_cache : {};
    my $rest = eval { $self->next::method };
    return $@ ? $cache : { %$cache, %$rest };
}

1;

=head1 NAME

DBIx::Class - Extensible and flexible object <-> relational mapper.

=head1 SYNOPSIS

Create a schema class called DB/Main.pm:

  package DB::Main;
  use base qw/DBIx::Class::Schema/;

  __PACKAGE__->load_classes();

  1;

Create a table class to represent artists, who have many CDs, in DB/Main/Artist.pm:

  package DB::Main::Artist;
  use base qw/DBIx::Class/;

  __PACKAGE__->load_components(qw/PK::Auto Core/);
  __PACKAGE__->table('artist');
  __PACKAGE__->add_columns(qw/ artistid name /);
  __PACKAGE__->set_primary_key('artistid');
  __PACKAGE__->has_many(cds => 'DB::Main::CD');

  1;

A table class to represent a CD, which belongs to an artist, in DB/Main/CD.pm:

  package DB::Main::CD;
  use base qw/DBIx::Class/;

  __PACKAGE__->load_components(qw/PK::Auto Core/);
  __PACKAGE__->table('cd');
  __PACKAGE__->add_columns(qw/ cdid artist title year /);
  __PACKAGE__->set_primary_key('cdid');
  __PACKAGE__->belongs_to(artist => 'DB::Main::Artist');

  1;

Then you can use these classes in your application's code:

  # Connect to your database.
  use DB::Main;
  my $schema = DB::Main->connect($dbi_dsn, $user, $pass, \%dbi_params);

  # Query for all artists and put them in an array,
  # or retrieve them as a result set object.
  my @all_artists = $schema->resultset('Artist')->all;
  my $all_artists_rs = $schema->resultset('Artist');

  # Create a result set to search for artists.
  # This does not query the DB.
  my $johns_rs = $schema->resultset('Artist')->search(
    # Build your WHERE using an SQL::Abstract structure:
    { name => { like => 'John%' } }
  );

  # Execute a joined query to get the cds.
  my @all_john_cds = $johns_rs->search_related('cds')->all;

  # Fetch only the next row.
  my $first_john = $johns_rs->next;

  # Specify ORDER BY on the query.
  my $first_john_cds_by_title_rs = $first_john->cds(
    undef,
    { order_by => 'title' }
  );

  # Create a result set that will fetch the artist relationship
  # at the same time as it fetches CDs, using only one query.
  my $millennium_cds_rs = $schema->resultset('CD')->search(
    { year => 2000 },
    { prefetch => 'artist' }
  );

  my $cd = $millennium_cds_rs->next; # SELECT ... FROM cds JOIN artists ...
  my $cd_artist_name = $cd->artist->name; # Already has the data so no query

  my $new_cd = $schema->resultset('CD')->new({ title => 'Spoon' });
  $new_cd->artist($cd->artist);
  $new_cd->insert; # Auto-increment primary key filled in after INSERT
  $new_cd->title('Fork');

  $schema->txn_do(sub { $new_cd->update }); # Runs the update in a transaction

  $millennium_cds_rs->update({ year => 2002 }); # Single-query bulk update

=head1 DESCRIPTION

This is an SQL to OO mapper with an object API inspired by L<Class::DBI>
(and a compatibility layer as a springboard for porting) and a resultset API
that allows abstract encapsulation of database operations. It aims to make
representing queries in your code as perl-ish as possible while still
providing access to as many of the capabilities of the database as possible,
including retrieving related records from multiple tables in a single query,
JOIN, LEFT JOIN, COUNT, DISTINCT, GROUP BY and HAVING support.

DBIx::Class can handle multi-column primary and foreign keys, complex
queries and database-level paging, and does its best to only query the
database in order to return something you've directly asked for. If a
resultset is used as an iterator it only fetches rows off the statement
handle as requested in order to minimise memory usage. It has auto-increment
support for SQLite, MySQL, PostgreSQL, Oracle, SQL Server and DB2 and is
known to be used in production on at least the first four, and is fork-
and thread-safe out of the box (although your DBD may not be).

This project is still under rapid development, so features added in the
latest major release may not work 100% yet -- check the Changes if you run
into trouble, and beware of anything explicitly marked EXPERIMENTAL. Failing
test cases are *always* welcome and point releases are put out rapidly as
bugs are found and fixed.

Even so, we do our best to maintain full backwards compatibility for published
APIs, since DBIx::Class is used in production in a number of organisations.
The test suite is quite substantial, and several developer releases are
generally made to CPAN before the -current branch is merged back to trunk for
a major release.

The community can be found via:

  Mailing list: http://lists.rawmode.org/mailman/listinfo/dbix-class/

  SVN: http://dev.catalyst.perl.org/repos/bast/trunk/DBIx-Class/

  Wiki: http://dbix-class.shadowcatsystems.co.uk/

  IRC: irc.perl.org#dbix-class

=head1 WHERE TO GO NEXT

L<DBIx::Class::Manual::DocMap> lists each task you might want help on, and
the modules where you will find documentation.

=head1 AUTHOR

mst: Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 CONTRIBUTORS

abraxxa: Alexander Hartmaier <alex_hartmaier@hotmail.com>

andyg: Andy Grundman <andy@hybridized.org>

ank: Andres Kievsky

blblack: Brandon L. Black <blblack@gmail.com>

bluefeet: Aran Deltac <bluefeet@cpan.org>

LTJake: Brian Cassidy <bricas@cpan.org>

claco: Christopher H. Laco

clkao: CL Kao

typester: Daisuke Murase <typester@cpan.org>

dkubb: Dan Kubb <dan.kubb-cpan@onautopilot.com>

Numa: Dan Sully <daniel@cpan.org>

dwc: Daniel Westermann-Clark <danieltwc@cpan.org>

ningu: David Kamholz <dkamholz@cpan.org>

jesper: Jesper Krogh

castaway: Jess Robinson

quicksilver: Jules Bean

jguenther: Justin Guenther <jguenther@cpan.org>

captainL: Luke Saunders <luke.saunders@gmail.com>

draven: Marcus Ramberg <mramberg@cpan.org>

nigel: Nigel Metheringham <nigelm@cpan.org>

paulm: Paul Makepeace

phaylon: Robert Sedlacek <phaylon@dunkelheit.at>

sc_: Just Another Perl Hacker

konobi: Scott McWhirter

scotty: Scotty Allen <scotty@scottyallen.com>

sszabo: Stephan Szabo <sszabo@bigpanda.com>

zamolxes: Bogdan Lucaciu <bogdan@wiz.ro>

Todd Lipcon

wdh: Will Hawes

gphat: Cory G Watson <gphat@cpan.org>

dyfrgi: Michael Leuchtenmurg <michael@slashhome.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

