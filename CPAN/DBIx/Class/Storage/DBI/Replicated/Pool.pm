package DBIx::Class::Storage::DBI::Replicated::Pool;

use Moose;
use MooseX::AttributeHelpers;
use DBIx::Class::Storage::DBI::Replicated::Replicant;
use List::Util 'sum';
use Scalar::Util 'reftype';
use DBI ();
use Carp::Clan qw/^DBIx::Class/;
use MooseX::Types::Moose qw/Num Int ClassName HashRef/;

use namespace::clean -except => 'meta';

=head1 NAME

DBIx::Class::Storage::DBI::Replicated::Pool - Manage a pool of replicants

=head1 SYNOPSIS

This class is used internally by L<DBIx::Class::Storage::DBI::Replicated>.  You
shouldn't need to create instances of this class.

=head1 DESCRIPTION

In a replicated storage type, there is at least one replicant to handle the
read only traffic.  The Pool class manages this replicant, or list of 
replicants, and gives some methods for querying information about their status.

=head1 ATTRIBUTES

This class defines the following attributes.

=head2 maximum_lag ($num)

This is a number which defines the maximum allowed lag returned by the
L<DBIx::Class::Storage::DBI/lag_behind_master> method.  The default is 0.  In
general, this should return a larger number when the replicant is lagging
behind its master, however the implementation of this is database specific, so
don't count on this number having a fixed meaning.  For example, MySQL will
return a number of seconds that the replicating database is lagging.

=cut

has 'maximum_lag' => (
  is=>'rw',
  isa=>Num,
  required=>1,
  lazy=>1,
  default=>0,
);

=head2 last_validated

This is an integer representing a time since the last time the replicants were
validated. It's nothing fancy, just an integer provided via the perl L<time|perlfunc/time>
builtin.

=cut

has 'last_validated' => (
  is=>'rw',
  isa=>Int,
  reader=>'last_validated',
  writer=>'_last_validated',
  lazy=>1,
  default=>0,
);

=head2 replicant_type ($classname)

Base class used to instantiate replicants that are in the pool.  Unless you
need to subclass L<DBIx::Class::Storage::DBI::Replicated::Replicant> you should
just leave this alone.

=cut

has 'replicant_type' => (
  is=>'ro',
  isa=>ClassName,
  required=>1,
  default=>'DBIx::Class::Storage::DBI',
  handles=>{
    'create_replicant' => 'new',
  },  
);

=head2 replicants

A hashref of replicant, with the key being the dsn and the value returning the
actual replicant storage.  For example if the $dsn element is something like:

  "dbi:SQLite:dbname=dbfile"

You could access the specific replicant via:

  $schema->storage->replicants->{'dbname=dbfile'}

This attributes also supports the following helper methods:

=over 4

=item set_replicant($key=>$storage)

Pushes a replicant onto the HashRef under $key

=item get_replicant($key)

Retrieves the named replicant

=item has_replicants

Returns true if the Pool defines replicants.

=item num_replicants

The number of replicants in the pool

=item delete_replicant ($key)

removes the replicant under $key from the pool

=back

=cut

has 'replicants' => (
  is=>'rw',
  metaclass => 'Collection::Hash',
  isa=>HashRef['Object'],
  default=>sub {{}},
  provides  => {
    'set' => 'set_replicant',
    'get' => 'get_replicant',
    'empty' => 'has_replicants',
    'count' => 'num_replicants',
    'delete' => 'delete_replicant',
    'values' => 'all_replicant_storages',
  },
);

has next_unknown_replicant_id => (
  is => 'rw',
  metaclass => 'Counter',
  isa => Int,
  default => 1,
  provides => {
    inc => 'inc_unknown_replicant_id'
  },
);

=head1 METHODS

This class defines the following methods.

=head2 connect_replicants ($schema, Array[$connect_info])

Given an array of $dsn or connect_info structures suitable for connected to a
database, create an L<DBIx::Class::Storage::DBI::Replicated::Replicant> object
and store it in the L</replicants> attribute.

=cut

sub connect_replicants {
  my $self = shift @_;
  my $schema = shift @_;

  my @newly_created = ();
  foreach my $connect_info (@_) {
    $connect_info = [ $connect_info ]
      if reftype $connect_info ne 'ARRAY';

    my $connect_coderef =
      (reftype($connect_info->[0])||'') eq 'CODE' ? $connect_info->[0]
        : (reftype($connect_info->[0])||'') eq 'HASH' &&
          $connect_info->[0]->{dbh_maker};

    my $dsn;
    my $replicant = do {
# yes this is evil, but it only usually happens once (for coderefs)
# this will fail if the coderef does not actually DBI::connect
      no warnings 'redefine';
      my $connect = \&DBI::connect;
      local *DBI::connect = sub {
        $dsn = $_[1];
        goto $connect;
      };
      $self->connect_replicant($schema, $connect_info);
    };

    my $key;

    if (!$dsn) {
      if (!$connect_coderef) {
        $dsn = $connect_info->[0];
        $dsn = $dsn->{dsn} if (reftype($dsn)||'') eq 'HASH';
      }
      else {
        # all attempts to get the DSN failed
        $key = "UNKNOWN_" . $self->next_unknown_replicant_id;
        $self->inc_unknown_replicant_id;
      }
    }
    if ($dsn) {
      $replicant->dsn($dsn);
      ($key) = ($dsn =~ m/^dbi\:.+\:(.+)$/i);
    }

    $replicant->id($key);
    $self->set_replicant($key => $replicant);  

    push @newly_created, $replicant;
  }

  return @newly_created;
}

=head2 connect_replicant ($schema, $connect_info)

Given a schema object and a hashref of $connect_info, connect the replicant
and return it.

=cut

sub connect_replicant {
  my ($self, $schema, $connect_info) = @_;
  my $replicant = $self->create_replicant($schema);
  $replicant->connect_info($connect_info);

## It is undesirable for catalyst to connect at ->conect_replicants time, as
## connections should only happen on the first request that uses the database.
## So we try to set the driver without connecting, however this doesn't always
## work, as a driver may need to connect to determine the DB version, and this
## may fail.
##
## Why this is necessary at all, is that we need to have the final storage
## class to apply the Replicant role.

  $self->_safely($replicant, '->_determine_driver', sub {
    $replicant->_determine_driver
  });

  DBIx::Class::Storage::DBI::Replicated::Replicant->meta->apply($replicant);  
  return $replicant;
}

=head2 _safely_ensure_connected ($replicant)

The standard ensure_connected method with throw an exception should it fail to
connect.  For the master database this is desirable, but since replicants are
allowed to fail, this behavior is not desirable.  This method wraps the call
to ensure_connected in an eval in order to catch any generated errors.  That
way a slave can go completely offline (ie, the box itself can die) without
bringing down your entire pool of databases.

=cut

sub _safely_ensure_connected {
  my ($self, $replicant, @args) = @_;

  return $self->_safely($replicant, '->ensure_connected', sub {
    $replicant->ensure_connected(@args)
  });
}

=head2 _safely ($replicant, $name, $code)

Execute C<$code> for operation C<$name> catching any exceptions and printing an
error message to the C<<$replicant->debugobj>>.

Returns 1 on success and undef on failure.

=cut

sub _safely {
  my ($self, $replicant, $name, $code) = @_;

  eval {
    $code->()
  }; 
  if ($@) {
    $replicant
      ->debugobj
      ->print(
        sprintf( "Exception trying to $name for replicant %s, error is %s",
          $replicant->_dbi_connect_info->[0], $@)
        );
  	return;
  }
  return 1;
}

=head2 connected_replicants

Returns true if there are connected replicants.  Actually is overloaded to
return the number of replicants.  So you can do stuff like:

  if( my $num_connected = $storage->has_connected_replicants ) {
    print "I have $num_connected connected replicants";
  } else {
    print "Sorry, no replicants.";
  }

This method will actually test that each replicant in the L</replicants> hashref
is actually connected, try not to hit this 10 times a second.

=cut

sub connected_replicants {
  my $self = shift @_;
  return sum( map {
    $_->connected ? 1:0
  } $self->all_replicants );
}

=head2 active_replicants

This is an array of replicants that are considered to be active in the pool.
This does not check to see if they are connected, but if they are not, DBIC
should automatically reconnect them for us when we hit them with a query.

=cut

sub active_replicants {
  my $self = shift @_;
  return ( grep {$_} map {
    $_->active ? $_:0
  } $self->all_replicants );
}

=head2 all_replicants

Just a simple array of all the replicant storages.  No particular order to the
array is given, nor should any meaning be derived.

=cut

sub all_replicants {
  my $self = shift @_;
  return values %{$self->replicants};
}

=head2 validate_replicants

This does a check to see if 1) each replicate is connected (or reconnectable),
2) that is ->is_replicating, and 3) that it is not exceeding the lag amount
defined by L</maximum_lag>.  Replicants that fail any of these tests are set to
inactive, and thus removed from the replication pool.

This tests L<all_replicants>, since a replicant that has been previous marked
as inactive can be reactived should it start to pass the validation tests again.

See L<DBIx::Class::Storage::DBI> for more about checking if a replicating
connection is not following a master or is lagging.

Calling this method will generate queries on the replicant databases so it is
not recommended that you run them very often.

This method requires that your underlying storage engine supports some sort of
native replication mechanism.  Currently only MySQL native replication is
supported.  Your patches to make other replication types work are welcomed.

=cut

sub validate_replicants {
  my $self = shift @_;
  foreach my $replicant($self->all_replicants) {
    if($self->_safely_ensure_connected($replicant)) {
      my $is_replicating = $replicant->is_replicating;
      unless(defined $is_replicating) {
        $replicant->debugobj->print("Storage Driver ".ref($self)." Does not support the 'is_replicating' method.  Assuming you are manually managing.\n");
        next;
      } else {
        if($is_replicating) {
          my $lag_behind_master = $replicant->lag_behind_master;
          unless(defined $lag_behind_master) {
            $replicant->debugobj->print("Storage Driver ".ref($self)." Does not support the 'lag_behind_master' method.  Assuming you are manually managing.\n");
            next;
          } else {
            if($lag_behind_master <= $self->maximum_lag) {
              $replicant->active(1);
            } else {
              $replicant->active(0);  
            }
          }    
        } else {
          $replicant->active(0);
        }
      }
    } else {
      $replicant->active(0);
    }
  }
  ## Mark that we completed this validation.  
  $self->_last_validated(time);  
}

=head1 AUTHOR

John Napiorkowski <john.napiorkowski@takkle.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
