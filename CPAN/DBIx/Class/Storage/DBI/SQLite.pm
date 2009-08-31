package DBIx::Class::Storage::DBI::SQLite;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;
use mro 'c3';

use POSIX 'strftime';
use File::Copy;
use File::Spec;

sub _dbh_last_insert_id {
  my ($self, $dbh, $source, $col) = @_;
  $dbh->func('last_insert_rowid');
}

sub backup
{
  my ($self, $dir) = @_;
  $dir ||= './';

  ## Where is the db file?
  my $dsn = $self->_dbi_connect_info()->[0];

  my $dbname = $1 if($dsn =~ /dbname=([^;]+)/);
  if(!$dbname)
  {
    $dbname = $1 if($dsn =~ /^dbi:SQLite:(.+)$/i);
  }
  $self->throw_exception("Cannot determine name of SQLite db file") 
    if(!$dbname || !-f $dbname);

#  print "Found database: $dbname\n";
#  my $dbfile = file($dbname);
  my ($vol, $dbdir, $file) = File::Spec->splitpath($dbname);
#  my $file = $dbfile->basename();
  $file = strftime("%Y-%m-%d-%H_%M_%S", localtime()) . $file; 
  $file = "B$file" while(-f $file);

  mkdir($dir) unless -f $dir;
  my $backupfile = File::Spec->catfile($dir, $file);

  my $res = copy($dbname, $backupfile);
  $self->throw_exception("Backup failed! ($!)") if(!$res);

  return $backupfile;
}

sub datetime_parser_type { return "DateTime::Format::SQLite"; } 

1;

=head1 NAME

DBIx::Class::Storage::DBI::SQLite - Automatic primary key class for SQLite

=head1 SYNOPSIS

  # In your table classes
  __PACKAGE__->load_components(qw/PK::Auto Core/);
  __PACKAGE__->set_primary_key('id');

=head1 DESCRIPTION

This class implements autoincrements for SQLite.

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
