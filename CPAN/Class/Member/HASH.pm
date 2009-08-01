package Class::Member::HASH;

use strict;
our $VERSION='1.6';

use Carp 'confess';

my $get_class_members;
$get_class_members=sub {
  my $pack=$_[0];
  no strict 'refs';
  my %cm;
  @cm{@{$pack.'::CLASS_MEMBERS'}}=();
  foreach my $p (@{$pack.'::ISA'}) {
    @cm{$get_class_members->($p)}=();
  }
  return keys %cm;
};

sub import {
  my $pack=shift;
  ($pack)=caller;

  my $getset=sub : lvalue {
    my $I=shift;
    my $what=shift;
    unless( UNIVERSAL::isa( $I, 'HASH' ) ) {
      confess "$pack\::$what must be called as instance method\n";
    }
    $what=$pack.'::'.$what;
    if( $#_>=0 ) {
      $I->{$what}=shift;
    }
    $I->{$what};
  };

  my $new=sub {
    my $parent=shift;
    my $class=ref($parent) || $parent;

    my $I=bless {}=>$class;
    my %o=@_;
    my @CLASS_MEMBERS=$get_class_members->($pack);

    if( ref($parent) ) {		# inherit first
      foreach my $m (@CLASS_MEMBERS) {
	$I->$m=$parent->$m;
      }
    }

    # then override with named parameters
    foreach my $m (@CLASS_MEMBERS) {
      $I->$m=$o{$m} if( exists $o{$m} );
    }

    my $init=$I->can('I N I T');
    if( $init ) {
      $init=$init->();
      $I->$init;
    }

    return $I;
  };

  foreach my $name (@_) {
    if( $name=~/^-(.*)/ ) {	# reserved name, aka option
      my $o=$1;
      if( $o eq 'CLASS_MEMBERS' ) {
	local $_;
	no strict 'refs';
	*{$pack.'::CLASS_MEMBERS'}=[grep {!/^-/} @_];
      } elsif( $o=~/^NEW=(.+)/ ) {
	no strict 'refs';
	*{$pack.'::'.$1}=$new;
      } elsif( $o eq 'NEW' ) {
	no strict 'refs';
	*{$pack.'::new'}=$new;
      } elsif( $o=~/^INIT=(.+)/ ) {
	no strict 'refs';
	my $init="$1";
	*{$pack.'::I N I T'}=sub(){$init};
      } elsif( $o eq 'INIT' ) {
	no strict 'refs';
	*{$pack.'::I N I T'}=sub(){"init"};
      }
    } else {
      no strict 'refs';
      *{$pack.'::'.$name}=sub:lvalue {
	my $I=shift;
	&{$getset}( $I, $name, @_ );
      };
    }
  }
}

1;

__END__

=head1 NAME

Class::Member::HASH - A module to make the module developement easier

=head1 SYNOPSIS

 package MyModule;
 use Class::Member::HASH qw/member_A member_B/;

=head1 DESCRIPTION

See L<Class::Member>.

=head1 AUTHOR

Torsten Foertsch E<lt>Torsten.Foertsch@gmx.netE<gt>

=head1 COPYRIGHT

Copyright 2003-8 Torsten Foertsch.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
