package # hide from PAUSE
  DBIx::Class::Storage::DBI::Replicated::Types;

# DBIx::Class::Storage::DBI::Replicated::Types - Types used internally by
# L<DBIx::Class::Storage::DBI::Replicated>

use MooseX::Types
  -declare => [qw/BalancerClassNamePart Weight DBICSchema DBICStorageDBI/];
use MooseX::Types::Moose qw/ClassName Str Num/;

class_type 'DBIx::Class::Storage::DBI';
class_type 'DBIx::Class::Schema';

subtype DBICSchema, as 'DBIx::Class::Schema';
subtype DBICStorageDBI, as 'DBIx::Class::Storage::DBI';

subtype BalancerClassNamePart,
  as ClassName;

coerce BalancerClassNamePart,
  from Str,
  via {
    my $type = $_;
    if($type=~m/^::/) {
      $type = 'DBIx::Class::Storage::DBI::Replicated::Balancer'.$type;
    }
    Class::MOP::load_class($type);
    $type;
  };

subtype Weight,
  as Num,
  where { $_ >= 0 },
  message { 'weight must be a decimal greater than 0' };

# AUTHOR
#
#  John Napiorkowski <john.napiorkowski@takkle.com>
#
# LICENSE
#
#  You may distribute this code under the same terms as Perl itself.

1;
