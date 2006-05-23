package # hide from PAUSE 
    DBIx::Class::Storage;

use strict;
use warnings;

sub new { die "Virtual method!" }
sub debug { die "Virtual method!" }
sub debugcb { die "Virtual method!" }
sub debugfh { die "Virtual method!" }
sub disconnect { die "Virtual method!" }
sub connected { die "Virtual method!" }
sub ensure_connected { die "Virtual method!" }
sub sql_maker { die "Virtual method!" }
sub txn_begin { die "Virtual method!" }
sub txn_commit { die "Virtual method!" }
sub txn_rollback { die "Virtual method!" }
sub insert { die "Virtual method!" }
sub update { die "Virtual method!" }
sub delete { die "Virtual method!" }
sub select { die "Virtual method!" }
sub select_single { die "Virtual method!" }
sub columns_info_for { die "Virtual method!" }


package DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION;

use overload '"' => sub {
  'DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION'
};

sub new {
  my $class = shift;
  return bless {}, $class;
}

1;
