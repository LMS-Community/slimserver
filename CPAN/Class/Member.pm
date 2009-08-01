package Class::Member;

use 5.008_000;
use strict;
our $VERSION='1.6';

use Carp 'confess';

sub import {
  my $pack=shift;
  ($pack)=caller;

  my $getset_hash=sub : lvalue {
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

  my $getset_glob=sub : lvalue {
    my $I=shift;
    my $what=shift;
    unless( UNIVERSAL::isa( $I, 'GLOB' ) ) {
      confess "$pack\::$what must be called as instance method\n";
    }
    $what=$pack.'::'.$what;
    if( $#_>=0 ) {
      ${*$I}{$what}=shift;
    }
    ${*$I}{$what};
  };

  my $getset=sub : lvalue {
    my $I=shift;
    my $name=shift;

    if( UNIVERSAL::isa( $I, 'HASH' ) ) {
      no strict 'refs';
      no warnings 'redefine';
      *{$pack.'::'.$name}=sub:lvalue {
	my $I=shift;
	&{$getset_hash}( $I, $name, @_ );
      };
    } elsif( UNIVERSAL::isa( $I, 'GLOB' ) ) {
      no strict 'refs';
      no warnings 'redefine';
      *{$pack.'::'.$name}=sub:lvalue {
	my $I=shift;
	&{$getset_glob}( $I, $name, @_ );
      };
    } else {
      confess "$pack\::$name must be called as instance method\n";
    }
    $I->$name(@_);
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

1;				# make require fail

__END__

=head1 NAME

Class::Member - A set of modules to make the module developement easier

=head1 SYNOPSIS

 package MyModule;
 use Class::Member::HASH qw/member_A member_B -CLASS_MEMBERS
                            -NEW=new -INIT=init/;
 
 or
 
 package MyModule;
 use Class::Member::GLOB qw/member_A member_B -CLASS_MEMBERS
                            -NEW=new -INIT=init/;
 
 or
 
 package MyModule;
 use Class::Member qw/member_A member_B -CLASS_MEMBERS/;
 
 or
 
 package MyModule;
 use Class::Member::Dynamic qw/member_A member_B -CLASS_MEMBERS/;

=head1 DESCRIPTION

Perl class instances are mostly blessed HASHes or GLOBs and store member
variables either as C<$self-E<gt>{membername}> or
C<${*$self}{membername}> respectively.

This is very error prone when you start to develope derived classes based
on such modules. The developer of the derived class must watch the
member variables of the base class to avoid name conflicts.

To avoid that C<Class::Member::XXX> stores member variables in its own
namespace prepending the package name to the variable name, e.g.

 package My::New::Module;

 use Class::Member::HASH qw/member_A memberB/;

will store C<member_A> as C<$self-E<gt>{'My::New::Module::member_A'}>.

To make access to these members easier it exports access functions into
the callers namespace. To access C<member_A> you simply call.

 $self->member_A;		# read access
 $self->member_A($new_value);	# write access
 $self->member_A=$new_value;	# write access (used as lvalue)

C<Class::Member::HASH> and C<Class::Member::GLOB> are used if your objects
are HASH or GLOB references. But sometimes you do not know whether your
instances are GLOBs or HASHes (Consider developement of derived classes where
the base class is likely to be changed.). In this case use C<Class::Member>
and the methods are defined at compile time to handle each type of objects,
GLOBs and HASHes. But the first access to a method redefines it according
to the actual object type. Thus, the first access will last slightly longer
but all subsequent calls are executed at the same speed as
C<Class::Member::GLOB> or C<Class::Member::HASH>.

C<Class::Member::Dynamic> is used if your objects can be GLOBs and HASHes at
the same time. The actual type is determined at each access and the
appropriate action is taken.

In addition to member names there are a few options that can be given:
C<-CLASS_MEMBERS>. It lets the C<import()> function create an array named
C<@CLASS_MEMBERS> in the caller's namespace that contains the names of all
methods it defines. Thus, you can create a contructor that expects named
parameters where each name corresponds to a class member:

 use Class::Member qw/member_A member_B -CLASS_MEMBERS/;
 our @CLASS_MEMBERS;
 
 sub new {
   my $parent=shift;
   my $class=ref($parent) || $parent;
   my $I=bless {}=>$class;
   my %o=@_;
 
   if( ref($parent) ) {		# inherit first
     foreach my $m (@CLASS_MEMBERS) {
       $I->$m=$parent->$m;
     }
   }
 
   # then override with named parameters
   foreach my $m (@CLASS_MEMBERS) {
     $I->$m=$o{$m} if( exists $o{$m} );
   }
 
   $I->init;
 
   return $I;
 }

Further, if you use one of C<Class::Member::HASH> or C<Class::Member::GLOB> a
constructor method can be created automatically. Just add C<-NEW> or
C<-NEW=name> to the C<use()> call. The first form creates a C<new()> method
that is implemented as shown except of the C<$I-E<gt>init> call. The 2nd form
can be used if your constructor must not be named C<new>.

What happens if one C<Class::Member> based class inherits the constructor
from another C<Class::Member> based class? In this case the inherited
contructor works for the C<@CLASS_MEMBERS> of the base class as well as the
derived class. For example:

 package Base;
 use Class::Member::HASH qw/-NEW -CLASS_MEMBERS el1 el2/;

 package Inherited;
 use Class::Member::HASH qw/-CLASS_MEMBERS el3/;
 use base qw/Base/;

Now C<Inherited->new> calls the constructor of the base class but one can
pass C<el1>, C<el2> as well as C<el3> parameters.

The C<$I-E<gt>init> call is added by specifying the C<-INIT> or C<-INIT=name>
option. If given a new function C<&{I N I T}> is created in the caller's
namespace to hold the name of the C<init()> method. Yes, the symbol name does
contain spaces to make it harder to change by chance. You don't normally have
to care about it. Again, the C<-INIT=name> form is used if your C<init()>
method is not named C<init>.

The C<init()> method itself is provided by you.

More detailed here is how the initializer is called:

 my $init=$self->can('I N I T');
 if( $init ) {
   $init=$init->();
   $self->$init;
 }

That means the constructor looks if the class itself or one of the base
classes provides a C<I N I T> method (the name includes spaces between each
pair of characters). If so it calls that method to fetch the initializer name.
The last step calls the initializer itself.

=head1 AUTHOR

Torsten Foertsch E<lt>Torsten.Foertsch@gmx.netE<gt>

=head1 SEE ALSO

L<Class::Member::HASH>, L<Class::Member::GLOB>, L<Class::Member::Dynamic>

=head1 COPYRIGHT

Copyright 2003-2008 Torsten Foertsch.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
