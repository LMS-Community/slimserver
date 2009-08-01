package Class::Member::Dynamic;

use strict;
our $VERSION='1.6';

use Carp 'confess';

sub import {
  my $pack=shift;
  ($pack)=caller;
  my $dummy;

  my $getset=sub : lvalue {
    my $I=shift;
    my $what=shift;
    my $rc=\$dummy;

    if( UNIVERSAL::isa( $I, 'HASH' ) ) {
      $what=$pack.'::'.$what;
      if( $#_>=0 ) {
	$I->{$what}=shift;
      }
      $rc=\$I->{$what};
    } elsif( UNIVERSAL::isa( $I, 'GLOB' ) ) {
      $what=$pack.'::'.$what;
      if( $#_>=0 ) {
	${*$I}{$what}=shift;
      }
      $rc=\${*$I}{$what};
    } else {
      confess "$pack\::$what must be called as instance method\n";
    }
    $$rc;
  };

  foreach my $name (@_) {
    if( $name=~/^-(.*)/ ) {	# reserved name, aka option
      if( $1 eq 'CLASS_MEMBERS' ) {
	local $_;
	no strict 'refs';
	*{$pack.'::CLASS_MEMBERS'}=[grep {!/^-/} @_];
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

Class::Member::Dynamic - A module to make the module developement easier

=head1 SYNOPSIS

 package MyModule;
 use Class::Member::Dynamic qw/member_A member_B/;

=head1 DESCRIPTION

See L<Class::Member>.

=head1 AUTHOR

Torsten Foertsch E<lt>Torsten.Foertsch@gmx.netE<gt>

=head1 COPYRIGHT

Copyright 2003-2008 Torsten Foertsch.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
