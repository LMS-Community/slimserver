#======================================================================
package DBD::SQLite::VirtualTable::FileContent;
#======================================================================
use strict;
use warnings;
use base 'DBD::SQLite::VirtualTable';

my %option_ok = map {($_ => 1)} qw/source content_col path_col
                                   expose root get_content/;

my %defaults = (
  content_col => "content",
  path_col    => "path",
  expose      => "*",
  get_content => "DBD::SQLite::VirtualTable::FileContent::get_content",
);


#----------------------------------------------------------------------
# object instanciation
#----------------------------------------------------------------------

sub NEW {
  my $class = shift;

  my $self  = $class->_PREPARE_SELF(@_);

  local $" = ", "; # for array interpolation in strings

  # initial parameter check
  !@{$self->{columns}}
    or die "${class}->NEW(): illegal options: @{$self->{columns}}";
  $self->{options}{source}
    or die "${class}->NEW(): missing (source=...)";
  my @bad_options = grep {!$option_ok{$_}} keys %{$self->{options}};
  !@bad_options
    or die "${class}->NEW(): bad options: @bad_options";

  # defaults ... tempted to use //= but we still want to support perl 5.8 :-(
  foreach my $k (keys %defaults) {
    defined $self->{options}{$k}
      or $self->{options}{$k} = $defaults{$k};
  }

  # get list of columns from the source table
  my $src_table  = $self->{options}{source};
  my $sql        = "PRAGMA table_info($src_table)";
  my $dbh        = ${$self->{dbh_ref}}; # can't use method ->dbh, not blessed yet
  my $src_info   = $dbh->selectall_arrayref($sql, {Slice => [1, 2]});
  @$src_info
    or die "${class}->NEW(source=$src_table): no such table in database";

  # associate each source colname with its type info or " " (should eval true)
  my %src_col = map  { ($_->[0] => $_->[1] || " ") } @$src_info;


  # check / complete the exposed columns
  my @exposed_cols;
  if ($self->{options}{expose} eq '*') {
    @exposed_cols = map {$_->[0]} @$src_info;
  }
  else {
    @exposed_cols = split /\s*,\s*/, $self->{options}{expose};
    my @bad_cols  = grep { !$src_col{$_} } @exposed_cols;
    die "table $src_table has no column named @bad_cols" if @bad_cols;
  }
  for (@exposed_cols) {
    die "$class: $self->{options}{content_col} cannot be both the "
      . "content_col and an exposed col" if $_ eq $self->{options}{content_col};
  }

  # build the list of columns for this table
  $self->{columns} = [ "$self->{options}{content_col} TEXT",
                       map {"$_ $src_col{$_}"} @exposed_cols ];

  # acquire a coderef to the get_content() implementation, which
  # was given as a symbolic reference in %options
  no strict 'refs';
  $self->{get_content} = \ &{$self->{options}{get_content}};

  bless $self, $class;
}

sub _build_headers {
  my $self = shift;

  my $cols = $self->sqlite_table_info;

  # headers : names of columns, without type information
  $self->{headers} = [ map {$_->{name}} @$cols ];
}


#----------------------------------------------------------------------
# method for initiating a search
#----------------------------------------------------------------------

sub BEST_INDEX {
  my ($self, $constraints, $order_by) = @_;

  $self->_build_headers if !$self->{headers};

  my @conditions;
  my $ix = 0;
  foreach my $constraint (grep {$_->{usable}} @$constraints) {
    my $col     = $constraint->{col};

    # if this is the content column, skip because we can't filter on it
    next if $col == 0;

    # for other columns, build a fragment for SQL WHERE on the underlying table
    my $colname = $col == -1 ? "rowid" : $self->{headers}[$col];
    push @conditions, "$colname $constraint->{op} ?";
    $constraint->{argvIndex} = $ix++;
    $constraint->{omit}      = 1;     # SQLite doesn't need to re-check the op
  }

  # TODO : exploit $order_by to add ordering clauses within idxStr

  my $outputs = {
    idxNum           => 1,
    idxStr           => join(" AND ", @conditions),
    orderByConsumed  => 0,
    estimatedCost    => 1.0,
    estimatedRows    => undef,
   };

  return $outputs;
}


#----------------------------------------------------------------------
# method for preventing updates
#----------------------------------------------------------------------

sub _SQLITE_UPDATE {
  my ($self, $old_rowid, $new_rowid, @values) = @_;

  die "attempt to update a readonly virtual table";
}


#----------------------------------------------------------------------
# file slurping function (not a method!)
#----------------------------------------------------------------------

sub get_content {
  my ($path, $root) = @_;

  $path = "$root/$path" if $root;

  my $content = "";
  if (open my $fh, "<", $path) {
    local $/;          # slurp the whole file into a scalar
    $content = <$fh>;
    close $fh;
  }
  else {
    warn "can't open $path";
  }

  return $content;
}



#======================================================================
package DBD::SQLite::VirtualTable::FileContent::Cursor;
#======================================================================
use strict;
use warnings;
use base "DBD::SQLite::VirtualTable::Cursor";


sub FILTER {
  my ($self, $idxNum, $idxStr, @values) = @_;

  my $vtable = $self->{vtable};

  # build SQL
  local $" = ", ";
  my @cols = @{$vtable->{headers}};
  $cols[0] = 'rowid';                 # replace the content column by the rowid
  push @cols, $vtable->{options}{path_col}; # path col in last position
  my $sql  = "SELECT @cols FROM $vtable->{options}{source}";
  $sql .= " WHERE $idxStr" if $idxStr;

  # request on the index table
  my $dbh = $vtable->dbh;
  $self->{sth} = $dbh->prepare($sql)
    or die DBI->errstr;
  $self->{sth}->execute(@values);
  $self->{row} = $self->{sth}->fetchrow_arrayref;

  return;
}


sub EOF {
  my ($self) = @_;

  return !$self->{row};
}

sub NEXT {
  my ($self) = @_;

  $self->{row} = $self->{sth}->fetchrow_arrayref;
}

sub COLUMN {
  my ($self, $idxCol) = @_;

  return $idxCol == 0 ? $self->file_content : $self->{row}[$idxCol];
}

sub ROWID {
  my ($self) = @_;

  return $self->{row}[0];
}

sub file_content {
  my ($self) = @_;

  my $root = $self->{vtable}{options}{root};
  my $path = $self->{row}[-1];
  my $get_content_func = $self->{vtable}{get_content};

  return $get_content_func->($path, $root);
}


1;

__END__


=head1 NAME

DBD::SQLite::VirtualTable::FileContent -- virtual table for viewing file contents


=head1 SYNOPSIS

Within Perl :

  $dbh->sqlite_create_module(fcontent => "DBD::SQLite::VirtualTable::FileContent");

Then, within SQL :

  CREATE VIRTUAL TABLE tbl USING fcontent(
     source      = src_table,
     content_col = content,
     path_col    = path,
     expose      = "path, col1, col2, col3", -- or "*"
     root        = "/foo/bar"
     get_content = Foo::Bar::read_from_file
    );

  SELECT col1, path, content FROM tbl WHERE ...;

=head1 DESCRIPTION

A "FileContent" virtual table is bound to some underlying I<source
table>, which has a column containing paths to files.  The virtual
table behaves like a database view on the source table, with an added
column which exposes the content from those files.

This is especially useful as an "external content" to some
fulltext table (see L<DBD::SQLite::Fulltext_search>) : the index
table stores some metadata about files, and then the fulltext engine
can index both the metadata and the file contents.

=head1 PARAMETERS

Parameters for creating a C<FileContent> virtual table are
specified within the C<CREATE VIRTUAL TABLE> statement, just
like regular column declarations, but with an '=' sign.
Authorized parameters are :

=over

=item C<source>

The name of the I<source table>.
This parameter is mandatory. All other parameters are optional.

=item C<content_col>

The name of the virtual column exposing file contents.
The default is C<content>.

=item C<path_col>

The name of the column in C<source> that contains paths to files.
The default is C<path>.

=item C<expose>

A comma-separated list (within double quotes) of source column names
to be exposed by the virtual table. The default is C<"*">, which means
all source columns.

=item C<root>

An optional root directory that will be prepended to the I<path> column
when opening files.

=item C<get_content>

Fully qualified name of a Perl function for reading file contents.
The default implementation just slurps the entire file into a string;
but this hook can point to more sophisticated implementations, like for
example a function that would remove html tags. The hooked function is
called like this :

  $file_content = $get_content->($path, $root);

=back

=head1 AUTHOR

Laurent Dami E<lt>dami@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright Laurent Dami, 2014.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
