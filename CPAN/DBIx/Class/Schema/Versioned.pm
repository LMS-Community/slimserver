package # Hide from PAUSE
  DBIx::Class::Version::Table;
use base 'DBIx::Class';
use strict;
use warnings;

__PACKAGE__->load_components(qw/ Core/);
__PACKAGE__->table('dbix_class_schema_versions');

__PACKAGE__->add_columns
    ( 'version' => {
        'data_type' => 'VARCHAR',
        'is_auto_increment' => 0,
        'default_value' => undef,
        'is_foreign_key' => 0,
        'name' => 'version',
        'is_nullable' => 0,
        'size' => '10'
        },
      'installed' => {
          'data_type' => 'VARCHAR',
          'is_auto_increment' => 0,
          'default_value' => undef,
          'is_foreign_key' => 0,
          'name' => 'installed',
          'is_nullable' => 0,
          'size' => '20'
          },
      );
__PACKAGE__->set_primary_key('version');

package # Hide from PAUSE
  DBIx::Class::Version::TableCompat;
use base 'DBIx::Class';
__PACKAGE__->load_components(qw/ Core/);
__PACKAGE__->table('SchemaVersions');

__PACKAGE__->add_columns
    ( 'Version' => {
        'data_type' => 'VARCHAR',
        },
      'Installed' => {
          'data_type' => 'VARCHAR',
          },
      );
__PACKAGE__->set_primary_key('Version');

package # Hide from PAUSE
  DBIx::Class::Version;
use base 'DBIx::Class::Schema';
use strict;
use warnings;

__PACKAGE__->register_class('Table', 'DBIx::Class::Version::Table');

package # Hide from PAUSE
  DBIx::Class::VersionCompat;
use base 'DBIx::Class::Schema';
use strict;
use warnings;

__PACKAGE__->register_class('TableCompat', 'DBIx::Class::Version::TableCompat');


# ---------------------------------------------------------------------------

=head1 NAME

DBIx::Class::Schema::Versioned - DBIx::Class::Schema plugin for Schema upgrades

=head1 SYNOPSIS

  package MyApp::Schema;
  use base qw/DBIx::Class::Schema/;

  our $VERSION = 0.001;

  # load MyApp::Schema::CD, MyApp::Schema::Book, MyApp::Schema::DVD
  __PACKAGE__->load_classes(qw/CD Book DVD/);

  __PACKAGE__->load_components(qw/Schema::Versioned/);
  __PACKAGE__->upgrade_directory('/path/to/upgrades/');


=head1 DESCRIPTION

This module provides methods to apply DDL changes to your database using SQL
diff files. Normally these diff files would be created using
L<DBIx::Class::Schema/create_ddl_dir>.

A table called I<dbix_class_schema_versions> is created and maintained by the
module. This is used to determine which version your database is currently at.
Similarly the $VERSION in your DBIC schema class is used to determine the
current DBIC schema version.

The upgrade is initiated manually by calling C<upgrade> on your schema object,
this will attempt to upgrade the database from its current version to the current
schema version using a diff from your I<upgrade_directory>. If a suitable diff is
not found then no upgrade is possible.

NB: At the moment, only SQLite and MySQL are supported. This is due to
spotty behaviour in the SQL::Translator producers, please help us by
enhancing them. Ask on the mailing list or IRC channel for details (community details
in L<DBIx::Class>).

=head1 GETTING STARTED

Firstly you need to setup your schema class as per the L</SYNOPSIS>, make sure
you have specified an upgrade_directory and an initial $VERSION.

Then you'll need two scripts, one to create DDL files and diffs and another to perform
upgrades. Your creation script might look like a bit like this:

  use strict;
  use Pod::Usage;
  use Getopt::Long;
  use MyApp::Schema;

  my ( $preversion, $help ); 
  GetOptions(
    'p|preversion:s'  => \$preversion,
  ) or die pod2usage;

  my $schema = MyApp::Schema->connect(
    $dsn,
    $user,
    $password,
  );
  my $sql_dir = './sql';
  my $version = $schema->schema_version();
  $schema->create_ddl_dir( 'MySQL', $version, $sql_dir, $preversion );

Then your upgrade script might look like so:

  use strict;
  use MyApp::Schema;

  my $schema = MyApp::Schema->connect(
    $dsn,
    $user,
    $password,
  );

  if (!$schema->get_db_version()) {
    # schema is unversioned
    $schema->deploy();
  } else {
    $schema->upgrade();
  }

The script above assumes that if the database is unversioned then it is empty
and we can safely deploy the DDL to it. However things are not always so simple.

if you want to initialise a pre-existing database where the DDL is not the same
as the DDL for your current schema version then you will need a diff which 
converts the database's DDL to the current DDL. The best way to do this is
to get a dump of the database schema (without data) and save that in your
SQL directory as version 0.000 (the filename must be as with
L<DBIx::Class::Schema/ddl_filename>) then create a diff using your create DDL 
script given above from version 0.000 to the current version. Then hand check
and if necessary edit the resulting diff to ensure that it will apply. Once you have 
done all that you can do this:

  if (!$schema->get_db_version()) {
    # schema is unversioned
    $schema->install("0.000");
  }

  # this will now apply the 0.000 to current version diff
  $schema->upgrade();

In the case of an unversioned database the above code will create the
dbix_class_schema_versions table and write version 0.000 to it, then 
upgrade will then apply the diff we talked about creating in the previous paragraph
and then you're good to go.

=cut

package DBIx::Class::Schema::Versioned;

use strict;
use warnings;
use base 'DBIx::Class';

use Carp::Clan qw/^DBIx::Class/;
use POSIX 'strftime';

__PACKAGE__->mk_classdata('_filedata');
__PACKAGE__->mk_classdata('upgrade_directory');
__PACKAGE__->mk_classdata('backup_directory');
__PACKAGE__->mk_classdata('do_backup');
__PACKAGE__->mk_classdata('do_diff_on_init');


=head1 METHODS

=head2 upgrade_directory

Use this to set the directory your upgrade files are stored in.

=head2 backup_directory

Use this to set the directory you want your backups stored in (note that backups
are disabled by default).

=cut

=head2 install

=over 4

=item Arguments: $db_version

=back

Call this to initialise a previously unversioned database. The table 'dbix_class_schema_versions' will be created which will be used to store the database version.

Takes one argument which should be the version that the database is currently at. Defaults to the return value of L</schema_version>.

See L</getting_started> for more details.

=cut

sub install
{
  my ($self, $new_version) = @_;

  # must be called on a fresh database
  if ($self->get_db_version()) {
    carp 'Install not possible as versions table already exists in database';
  }

  # default to current version if none passed
  $new_version ||= $self->schema_version();

  if ($new_version) {
    # create versions table and version row
    $self->{vschema}->deploy;
    $self->_set_db_version({ version => $new_version });
  }
}

=head2 deploy

Same as L<DBIx::Class::Schema/deploy> but also calls C<install>.

=cut

sub deploy {
  my $self = shift;
  $self->next::method(@_);
  $self->install();
}

=head2 create_upgrade_path

=over 4

=item Arguments: { upgrade_file => $file }

=back

Virtual method that should be overriden to create an upgrade file. 
This is useful in the case of upgrading across multiple versions 
to concatenate several files to create one upgrade file.

You'll probably want the db_version retrieved via $self->get_db_version
and the schema_version which is retrieved via $self->schema_version 

=cut

sub create_upgrade_path {
	## override this method
}

=head2 upgrade

Call this to attempt to upgrade your database from the version it is at to the version
this DBIC schema is at. If they are the same it does nothing.

It requires an SQL diff file to exist in you I<upgrade_directory>, normally you will
have created this using L<DBIx::Class::Schema/create_ddl_dir>.

If successful the dbix_class_schema_versions table is updated with the current
DBIC schema version.

=cut

sub upgrade
{
  my ($self) = @_;
  my $db_version = $self->get_db_version();

  # db unversioned
  unless ($db_version) {
    carp 'Upgrade not possible as database is unversioned. Please call install first.';
    return;
  }

  # db and schema at same version. do nothing
  if ($db_version eq $self->schema_version) {
    carp "Upgrade not necessary\n";
    return;
  }

  # strangely the first time this is called can
  # differ to subsequent times. so we call it 
  # here to be sure.
  # XXX - just fix it
  $self->storage->sqlt_type;

  my $upgrade_file = $self->ddl_filename(
                                         $self->storage->sqlt_type,
                                         $self->schema_version,
                                         $self->upgrade_directory,
                                         $db_version,
                                        );

  $self->create_upgrade_path({ upgrade_file => $upgrade_file });

  unless (-f $upgrade_file) {
    carp "Upgrade not possible, no upgrade file found ($upgrade_file), please create one\n";
    return;
  }

  carp "\nDB version ($db_version) is lower than the schema version (".$self->schema_version."). Attempting upgrade.\n";

  # backup if necessary then apply upgrade
  $self->_filedata($self->_read_sql_file($upgrade_file));
  $self->backup() if($self->do_backup);
  $self->txn_do(sub { $self->do_upgrade() });

  # set row in dbix_class_schema_versions table
  $self->_set_db_version;
}

=head2 do_upgrade

This is an overwritable method used to run your upgrade. The freeform method
allows you to run your upgrade any way you please, you can call C<run_upgrade>
any number of times to run the actual SQL commands, and in between you can
sandwich your data upgrading. For example, first run all the B<CREATE>
commands, then migrate your data from old to new tables/formats, then 
issue the DROP commands when you are finished. Will run the whole file as it is by default.

=cut

sub do_upgrade
{
  my ($self) = @_;

  # just run all the commands (including inserts) in order                                                        
  $self->run_upgrade(qr/.*?/);
}

=head2 run_upgrade

 $self->run_upgrade(qr/create/i);

Runs a set of SQL statements matching a passed in regular expression. The
idea is that this method can be called any number of times from your
C<do_upgrade> method, running whichever commands you specify via the
regex in the parameter. Probably won't work unless called from the overridable
do_upgrade method.

=cut

sub run_upgrade
{
    my ($self, $stm) = @_;

    return unless ($self->_filedata);
    my @statements = grep { $_ =~ $stm } @{$self->_filedata};
    $self->_filedata([ grep { $_ !~ /$stm/i } @{$self->_filedata} ]);

    for (@statements)
    {      
        $self->storage->debugobj->query_start($_) if $self->storage->debug;
        $self->apply_statement($_);
        $self->storage->debugobj->query_end($_) if $self->storage->debug;
    }

    return 1;
}

=head2 apply_statement

Takes an SQL statement and runs it. Override this if you want to handle errors
differently.

=cut

sub apply_statement {
    my ($self, $statement) = @_;

    $self->storage->dbh->do($_) or carp "SQL was:\n $_";
}

=head2 get_db_version

Returns the version that your database is currently at. This is determined by the values in the
dbix_class_schema_versions table that C<upgrade> and C<install> write to.

=cut

sub get_db_version
{
    my ($self, $rs) = @_;

    my $vtable = $self->{vschema}->resultset('Table');
    my $version = 0;
    eval {
      my $stamp = $vtable->get_column('installed')->max;
      $version = $vtable->search({ installed => $stamp })->first->version;
    };
    return $version;
}

=head2 schema_version

Returns the current schema class' $VERSION

=cut

=head2 backup

This is an overwritable method which is called just before the upgrade, to
allow you to make a backup of the database. Per default this method attempts
to call C<< $self->storage->backup >>, to run the standard backup on each
database type. 

This method should return the name of the backup file, if appropriate..

This method is disabled by default. Set $schema->do_backup(1) to enable it.

=cut

sub backup
{
    my ($self) = @_;
    ## Make each ::DBI::Foo do this
    $self->storage->backup($self->backup_directory());
}

=head2 connection

Overloaded method. This checks the DBIC schema version against the DB version and
warns if they are not the same or if the DB is unversioned. It also provides
compatibility between the old versions table (SchemaVersions) and the new one
(dbix_class_schema_versions).

To avoid the checks on connect, set the env var DBIC_NO_VERSION_CHECK or alternatively you can set the ignore_version attr in the forth argument like so:

  my $schema = MyApp::Schema->connect(
    $dsn,
    $user,
    $password,
    { ignore_version => 1 },
  );

=cut

sub connection {
  my $self = shift;
  $self->next::method(@_);
  $self->_on_connect($_[3]);
  return $self;
}

sub _on_connect
{
  my ($self, $args) = @_;

  $args = {} unless $args;
  $self->{vschema} = DBIx::Class::Version->connect(@{$self->storage->connect_info()});
  my $vtable = $self->{vschema}->resultset('Table');

  # check for legacy versions table and move to new if exists
  my $vschema_compat = DBIx::Class::VersionCompat->connect(@{$self->storage->connect_info()});
  unless ($self->_source_exists($vtable)) {
    my $vtable_compat = $vschema_compat->resultset('TableCompat');
    if ($self->_source_exists($vtable_compat)) {
      $self->{vschema}->deploy;
      map { $vtable->create({ installed => $_->Installed, version => $_->Version }) } $vtable_compat->all;
      $self->storage->dbh->do("DROP TABLE " . $vtable_compat->result_source->from);
    }
  }

  # useful when connecting from scripts etc
  return if ($args->{ignore_version} || ($ENV{DBIC_NO_VERSION_CHECK} && !exists $args->{ignore_version}));
  my $pversion = $self->get_db_version();

  if($pversion eq $self->schema_version)
    {
#         carp "This version is already installed\n";
        return 1;
    }

  if(!$pversion)
    {
        carp "Your DB is currently unversioned. Please call upgrade on your schema to sync the DB.\n";
        return 1;
    }

  carp "Versions out of sync. This is " . $self->schema_version . 
    ", your database contains version $pversion, please call upgrade on your Schema.\n";
}

# is this just a waste of time? if not then merge with DBI.pm
sub _create_db_to_schema_diff {
  my $self = shift;

  my %driver_to_db_map = (
                          'mysql' => 'MySQL'
                         );

  my $db = $driver_to_db_map{$self->storage->dbh->{Driver}->{Name}};
  unless ($db) {
    print "Sorry, this is an unsupported DB\n";
    return;
  }

  $self->throw_exception($self->storage->_sqlt_version_error)
    if (not $self->storage->_sqlt_version_ok);

  my $db_tr = SQL::Translator->new({
                                    add_drop_table => 1,
                                    parser => 'DBI',
                                    parser_args => { dbh => $self->storage->dbh }
                                   });

  $db_tr->producer($db);
  my $dbic_tr = SQL::Translator->new;
  $dbic_tr->parser('SQL::Translator::Parser::DBIx::Class');
  $dbic_tr->data($self);
  $dbic_tr->producer($db);

  $db_tr->schema->name('db_schema');
  $dbic_tr->schema->name('dbic_schema');

  # is this really necessary?
  foreach my $tr ($db_tr, $dbic_tr) {
    my $data = $tr->data;
    $tr->parser->($tr, $$data);
  }

  my $diff = SQL::Translator::Diff::schema_diff($db_tr->schema, $db, 
                                                $dbic_tr->schema, $db,
                                                { ignore_constraint_names => 1, ignore_index_names => 1, caseopt => 1 });

  my $filename = $self->ddl_filename(
                                         $db,
                                         $self->schema_version,
                                         $self->upgrade_directory,
                                         'PRE',
                                    );
  my $file;
  if(!open($file, ">$filename"))
    {
      $self->throw_exception("Can't open $filename for writing ($!)");
      next;
    }
  print $file $diff;
  close($file);

  carp "WARNING: There may be differences between your DB and your DBIC schema. Please review and if necessary run the SQL in $filename to sync your DB.\n";
}


sub _set_db_version {
  my $self = shift;
  my ($params) = @_;
  $params ||= {};

  my $version = $params->{version} ? $params->{version} : $self->schema_version;
  my $vtable = $self->{vschema}->resultset('Table');
  $vtable->create({ version => $version,
                      installed => strftime("%Y-%m-%d %H:%M:%S", gmtime())
                      });

}

sub _read_sql_file {
  my $self = shift;
  my $file = shift || return;

  my $fh;
  open $fh, "<$file" or carp("Can't open upgrade file, $file ($!)");
  my @data = split(/\n/, join('', <$fh>));
  @data = grep(!/^--/, @data);
  @data = split(/;/, join('', @data));
  close($fh);
  @data = grep { $_ && $_ !~ /^-- / } @data;
  @data = grep { $_ !~ /^(BEGIN|BEGIN TRANSACTION|COMMIT)/m } @data;
  return \@data;
}

sub _source_exists
{
    my ($self, $rs) = @_;

    my $c = eval {
        $rs->search({ 1, 0 })->count;
    };
    return 0 if $@ || !defined $c;

    return 1;
}

1;


=head1 AUTHORS

Jess Robinson <castaway@desert-island.me.uk>
Luke Saunders <luke@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.
