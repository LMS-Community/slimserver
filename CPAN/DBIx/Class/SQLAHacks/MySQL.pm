package # Hide from PAUSE
  DBIx::Class::SQLAHacks::MySQL;

use base qw( DBIx::Class::SQLAHacks );
use Carp::Clan qw/^DBIx::Class|^SQL::Abstract/;

#
# MySQL does not understand the standard INSERT INTO $table DEFAULT VALUES
# Adjust SQL here instead
#
sub insert {
  my $self = shift;

  my $table = $_[0];
  $table = $self->_quote($table);

  if (! $_[1] or (ref $_[1] eq 'HASH' and !keys %{$_[1]} ) ) {
    return "INSERT INTO ${table} () VALUES ()"
  }

  return $self->SUPER::insert (@_);
}

1;
