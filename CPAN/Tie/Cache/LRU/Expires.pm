package Tie::Cache::LRU::Expires;

use strict;
use Tie::Cache::LRU 0.21;

use vars qw($VERSION);

$VERSION="0.54";

sub TIEHASH {
  my $class = shift;
  my $self  = {
     LRU     => undef,
     LRUOBJ  => undef,
     ENTRIES => 100,
     EXPIRES => 3600,
     @_,
  };

  tie  %{$self->{LRU}}, 'Tie::Cache::LRU', $self->{ENTRIES};
  $self->{LRUOBJ}=tied %{$self->{LRU}};

return bless $self, $class;
}

sub FETCH {
  my $self =shift;
  my $key  =shift;

  my $value=$self->{LRUOBJ}->FETCH($key);

  if (defined $value) {
    my $curtime=time();
    if ($curtime <= $value->{BORDER}) {
      return $value->{VALUE};
    }
    else {
      return undef;
    }
  }
  else {
    return undef;
  }
}

sub STORE {
  my $self  = shift;
  my $key   = shift;
  my $val   = shift;

  my $value={
    VALUE   => $val,
    BORDER  => time()+$self->{EXPIRES}
  };

  $self->{LRUOBJ}->STORE($key,$value);
return $val;
}

sub DELETE {
  my $self = shift;
  my $key  = shift;

  $self->{LRUOBJ}->DELETE($key);
return undef;
}

sub FIRSTKEY {
  return undef;
}

sub NEXTKEY {
  return undef;
}

sub DESTROY {
}

sub CLEAR {
    my ($self) = @_;
    $self->{LRUOBJ}->CLEAR();
}

sub EXISTS {
  my $self = shift;
  my $key  = shift;
  if ($self->{LRUOBJ}->EXISTS($key)) {
    my $curtime=time();
    my $value=$self->{LRUOBJ}->FETCH($key);
    if ($curtime <= $value->{BORDER}) {
      return 1;
    }
    else {
      return 0;
    }
  }
  else {
    return 0;
  }
}

sub lru_size {
  my $self = shift;
  my $lru  = $self->{LRUOBJ};
  return $lru->curr_size();
}

=pod

=head1 NAME

Tie::Cache::LRU::Expires - Extends Tie::Cache::LRU with expiring

=head1 SYNOPSIS

	use Tie::Cache::LRU::Expires;

	tie %cache, 'Tie::Cache::LRU::Expires', EXPIRES => 10, ENTRIES => 1000;
        $cache_obj = tied %cache;

        for(1..1000) {
           $cache{$_}="test $_";
        }
        sleep 4;
        for(1000..1500) {
           $cache{$_}="test $_";
        }

        print $cache_obj->lru_size(),"\n";		# access to the
							# number of entries
							# used in the LRU
							# cache.

        sleep 4;
	for(1..10) { print $cache{$_},"\n"; }
	for(1100..1110) { print $cache{$_},"\n"; }
        sleep 4;
	for(1..10) { print $cache{$_},"\n"; }    	# expired (undefs).
	for(1100..1110) { print $cache{$_},"\n"; }
        sleep 4;
	for(1100..1110) { print $cache{$_},"\n"; }	# now also expired.

	# Clearing the cache

	%cache=();



=head1 DESCRIPTION

This is an expiring LRU cache, using Tie::Cache::LRU. Each entry
in this cache expires after 'EXPIRES' seconds (default 3600). The
cache is in RAM (see Tie::Cache::LRU). ENTRIES provides the maximum
number of entries in the Tie::Cache::LRU cache.

It works by checking if a cached entry hasn't expired. If it has,
undef is returned, otherwise it's value. If the entry wasn't cached,
undef is also returned (of course). Expired entries will eventually
drop of the LRU; or, if referenced will (as can be expected, otherwise
they wouldn't be referenced) be refreshed.

NB! If entries keep being referenced and are expired, but never refreshed,
they will never leave the LRU!

=head1 SEE ALSO

L<Tie::Cache::LRU>.

=head1 USAGE

See SYNOPSIS. Too simple to explain.

=head1 AUTHOR

Hans Oesterholt-Dijkema <oesterhol@cpan.org>

=cut

1;
