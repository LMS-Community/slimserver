package DBIx::Migration;

use strict;
use base qw/Class::Accessor::Fast/;
use DBI;
use File::Slurp;
use File::Spec;

our $VERSION = '0.05';

__PACKAGE__->mk_accessors(qw/debug dbh dir dsn password username/);

=head1 NAME

DBIx::Migration - Seamless DB schema up- and downgrades

=head1 SYNOPSIS

    # migrate.pl
    my $m = DBIx::Migration->new(
        {
            dsn => 'dbi:SQLite:/Users/sri/myapp/db/sqlite/myapp.db',
            dir => '/Users/sri/myapp/db/sqlite'
        }
    );

    my $version = $m->version;   # Get current version from database
    $m->migrate(2);              # Migrate database to version 2

    # /Users/sri/myapp/db/sqlite/schema_1_up.sql
    CREATE TABLE foo (
        id INTEGER PRIMARY KEY,
        bar TEXT
    );

    # /Users/sri/myapp/db/sqlite/schema_1_down.sql
    DROP TABLE foo;

    # /Users/sri/myapp/db/sqlite/schema_2_up.sql
    CREATE TABLE bar (
        id INTEGER PRIMARY KEY,
        baz TEXT
    );

    # /Users/sri/myapp/db/sqlite/schema_2_down.sql
    DROP TABLE bar;

=head1 DESCRIPTION

Seamless DB schema up- and downgrades.

=head1 METHODS

=over 4

=item $self->debug($debug)

Enable/Disable debug messages.

=item $self->dir($dir)

Get/Set directory.

=item $self->dsn($dsn)

Get/Set dsn.

=item $self->migrate($version)

Migrate database to version.

=cut

sub migrate {
    my ( $self, $wanted ) = @_;
    $self->_connect;
    $wanted = $self->_newest unless defined $wanted;
    my $version = $self->_version;
    if ( defined $version && ( $wanted eq $version ) ) {
        print "Database is already at version $wanted\n" if $self->debug;
        return 1;
    }

    unless ( defined $version ) {
        $self->_create_migration_table;
        $version = 0;
    }

    # Up- or downgrade
    my @need;
    my $type = 'down';
    if ( $wanted > $version ) {
        $type = 'up';
        $version += 1;
        @need = $version .. $wanted;
    }
    else {
        $wanted += 1;
        @need = reverse( $wanted .. $version );
    }
    my $files = $self->_files( $type, \@need );
    if ( defined $files ) {
        for my $file (@$files) {
            my $name = $file->{name};
            my $ver  = $file->{version};
            print qq/Processing "$name"\n/ if $self->debug;
            next unless $file;
            my $text = read_file($name);
            $text =~ s/\s*--.*$//g;
            for my $sql ( split /;/, $text ) {
                next unless $sql =~ /\w/;
                print "$sql\n" if $self->debug;
                $self->{_dbh}->do($sql);
                if ( $self->{_dbh}->err ) {
                    die "Database error: " . $self->{_dbh}->errstr;
                }
            }
            $ver -= 1 if ( ( $ver > 0 ) && ( $type eq 'down' ) );
            $self->_update_migration_table($ver);
        }
    }
    else {
        my $newver = $self->_version;
        print "Database is at version $newver, couldn't migrate to $wanted\n"
          if ( $self->debug && ( $wanted != $newver ) );
        return 0;
    }
    $self->_disconnect;
    return 1;
}

=item $self->password

Get/Set database password.

=item $self->username($username)

Get/Set database username.

=item $self->version

Get migration version from database.

=cut

sub version {
    my $self = shift;
    $self->_connect;
    my $version = $self->_version;
    $self->_disconnect;
    return $version;
}

sub _connect {
    my $self = shift;
    if ( $self->dbh ) {
        $self->{_dbh} = $self->dbh;
    }
    else {
        $self->{_dbh} = DBI->connect(
            $self->dsn,
            $self->username,
            $self->password,
            {
                RaiseError => 0,
                PrintError => 0,
                AutoCommit => 1
            }
          )
          or die qq/Couldn't connect to database, "$!"/;
    }
}

sub _create_migration_table {
    my $self = shift;
    $self->{_dbh}->do(<<"EOF");
CREATE TABLE dbix_migration (
    name CHAR(64) PRIMARY KEY,
    value CHAR(64)
);
EOF
    $self->{_dbh}->do(<<"EOF");
    INSERT INTO dbix_migration ( name, value ) VALUES ( 'version', '0' );
EOF
}

sub _disconnect {
    my $self = shift;
    $self->{_dbh}->disconnect unless $self->dbh;
}

sub _files {
    my ( $self, $type, $need ) = @_;
    my @files;
    for my $i (@$need) {
        opendir(DIR, $self->dir) or die $!;
        while (my $file = readdir(DIR)) {
            next unless $file =~ /_${i}_$type\.sql$/;
            $file = File::Spec->catdir($self->dir, $file);
            push @files, { name => $file, version => $i };
        }
        closedir(DIR);
    }
    return undef unless @$need == @files;
    return @files ? \@files : undef;
}

sub _newest {
    my $self   = shift;
    my $newest = 0;

    opendir(DIR, $self->dir) or die $!;
    while (my $file = readdir(DIR)) {
        next unless $file =~ /_up\.sql$/;
        $file =~ /\D*(\d+)_up.sql$/;
        $newest = $1 if $1 > $newest;
    }
    closedir(DIR);

    return $newest;
}

sub _update_migration_table {
    my ( $self, $version ) = @_;
    $self->{_dbh}->do(<<"EOF");
UPDATE dbix_migration SET value = '$version' WHERE name = 'version';
EOF
}

sub _version {
    my $self    = shift;
    my $version = undef;
    eval {
        my $sth = $self->{_dbh}->prepare(<<"EOF");
SELECT value FROM dbix_migration WHERE name = ?;
EOF
        $sth->execute('version');
        for my $val ( $sth->fetchrow_arrayref ) {
            $version = $val->[0];
        }
    };
    return $version;
}

=back

=head1 AUTHOR

Sebastian Riedel, C<sri@oook.de>

=head1 COPYRIGHT

This program is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
