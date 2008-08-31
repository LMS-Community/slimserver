
package Class::C3;

use strict;
use warnings;

our $VERSION = '0.19';

our $C3_IN_CORE;
our $C3_XS;

BEGIN {
    if($] > 5.009_004) {
        $C3_IN_CORE = 1;
        require mro;
    }
    else {
        eval "require Class::C3::XS";
        my $error = $@;
        if(!$error) {
            $C3_XS = 1;
        }
        else {
            die $error if $error !~ /\blocate\b/;
            require Algorithm::C3;
            require Class::C3::next;
        }
    }
}

# this is our global stash of both 
# MRO's and method dispatch tables
# the structure basically looks like
# this:
#
#   $MRO{$class} = {
#      MRO => [ <class precendence list> ],
#      methods => {
#          orig => <original location of method>,
#          code => \&<ref to original method>
#      },
#      has_overload_fallback => (1 | 0)
#   }
#
our %MRO;

# use these for debugging ...
sub _dump_MRO_table { %MRO }
our $TURN_OFF_C3 = 0;

# state tracking for initialize()/uninitialize()
our $_initialized = 0;

sub import {
    my $class = caller();
    # skip if the caller is main::
    # since that is clearly not relevant
    return if $class eq 'main';

    return if $TURN_OFF_C3;
    mro::set_mro($class, 'c3') if $C3_IN_CORE;

    # make a note to calculate $class 
    # during INIT phase
    $MRO{$class} = undef unless exists $MRO{$class};
}

## initializers

sub initialize {
    %next::METHOD_CACHE = ();
    # why bother if we don't have anything ...
    return unless keys %MRO;
    if($C3_IN_CORE) {
        mro::set_mro($_, 'c3') for keys %MRO;
    }
    else {
        if($_initialized) {
            uninitialize();
            $MRO{$_} = undef foreach keys %MRO;
        }
        _calculate_method_dispatch_tables();
        _apply_method_dispatch_tables();
        $_initialized = 1;
    }
}

sub uninitialize {
    # why bother if we don't have anything ...
    %next::METHOD_CACHE = ();
    return unless keys %MRO;    
    if($C3_IN_CORE) {
        mro::set_mro($_, 'dfs') for keys %MRO;
    }
    else {
        _remove_method_dispatch_tables();    
        $_initialized = 0;
    }
}

sub reinitialize { goto &initialize }

## functions for applying C3 to classes

sub _calculate_method_dispatch_tables {
    return if $C3_IN_CORE;
    my %merge_cache;
    foreach my $class (keys %MRO) {
        _calculate_method_dispatch_table($class, \%merge_cache);
    }
}

sub _calculate_method_dispatch_table {
    return if $C3_IN_CORE;
    my ($class, $merge_cache) = @_;
    no strict 'refs';
    my @MRO = calculateMRO($class, $merge_cache);
    $MRO{$class} = { MRO => \@MRO };
    my $has_overload_fallback;
    my %methods;
    # NOTE: 
    # we do @MRO[1 .. $#MRO] here because it
    # makes no sense to interogate the class
    # which you are calculating for. 
    foreach my $local (@MRO[1 .. $#MRO]) {
        # if overload has tagged this module to 
        # have use "fallback", then we want to
        # grab that value 
        $has_overload_fallback = ${"${local}::()"} 
            if !defined $has_overload_fallback && defined ${"${local}::()"};
        foreach my $method (grep { defined &{"${local}::$_"} } keys %{"${local}::"}) {
            # skip if already overriden in local class
            next unless !defined *{"${class}::$method"}{CODE};
            $methods{$method} = {
                orig => "${local}::$method",
                code => \&{"${local}::$method"}
            } unless exists $methods{$method};
        }
    }    
    # now stash them in our %MRO table
    $MRO{$class}->{methods} = \%methods; 
    $MRO{$class}->{has_overload_fallback} = $has_overload_fallback;        
}

sub _apply_method_dispatch_tables {
    return if $C3_IN_CORE;
    foreach my $class (keys %MRO) {
        _apply_method_dispatch_table($class);
    }     
}

sub _apply_method_dispatch_table {
    return if $C3_IN_CORE;
    my $class = shift;
    no strict 'refs';
    ${"${class}::()"} = $MRO{$class}->{has_overload_fallback}
        if !defined &{"${class}::()"}
           && defined $MRO{$class}->{has_overload_fallback};
    foreach my $method (keys %{$MRO{$class}->{methods}}) {
        if ( $method =~ /^\(/ ) {
            my $orig = $MRO{$class}->{methods}->{$method}->{orig};
            ${"${class}::$method"} = $$orig if defined $$orig;
        }
        *{"${class}::$method"} = $MRO{$class}->{methods}->{$method}->{code};
    }    
}

sub _remove_method_dispatch_tables {
    return if $C3_IN_CORE;
    foreach my $class (keys %MRO) {
        _remove_method_dispatch_table($class);
    }
}

sub _remove_method_dispatch_table {
    return if $C3_IN_CORE;
    my $class = shift;
    no strict 'refs';
    delete ${"${class}::"}{"()"} if $MRO{$class}->{has_overload_fallback};    
    foreach my $method (keys %{$MRO{$class}->{methods}}) {
        delete ${"${class}::"}{$method}
            if defined *{"${class}::${method}"}{CODE} && 
               (*{"${class}::${method}"}{CODE} eq $MRO{$class}->{methods}->{$method}->{code});       
    }
}

sub calculateMRO {
    my ($class, $merge_cache) = @_;

    return Algorithm::C3::merge($class, sub { 
        no strict 'refs'; 
        @{$_[0] . '::ISA'};
    }, $merge_cache);
}

# Method overrides to support 5.9.5+ or Class::C3::XS

sub _core_calculateMRO { @{mro::get_linear_isa($_[0], 'c3')} }

if($C3_IN_CORE) {
    no warnings 'redefine';
    *Class::C3::calculateMRO = \&_core_calculateMRO;
}
elsif($C3_XS) {
    no warnings 'redefine';
    *Class::C3::calculateMRO = \&Class::C3::XS::calculateMRO;
    *Class::C3::_calculate_method_dispatch_table
        = \&Class::C3::XS::_calculate_method_dispatch_table;
}

1;

__END__

=pod

=head1 NAME

Class::C3 - A pragma to use the C3 method resolution order algortihm

=head1 SYNOPSIS

    package A;
    use Class::C3;     
    sub hello { 'A::hello' }

    package B;
    use base 'A';
    use Class::C3;     

    package C;
    use base 'A';
    use Class::C3;     

    sub hello { 'C::hello' }

    package D;
    use base ('B', 'C');
    use Class::C3;    

    # Classic Diamond MI pattern
    #    <A>
    #   /   \
    # <B>   <C>
    #   \   /
    #    <D>

    package main;
    
    # initializez the C3 module 
    # (formerly called in INIT)
    Class::C3::initialize();  

    print join ', ' => Class::C3::calculateMRO('Diamond_D') # prints D, B, C, A

    print D->hello() # prints 'C::hello' instead of the standard p5 'A::hello'
    
    D->can('hello')->();          # can() also works correctly
    UNIVERSAL::can('D', 'hello'); # as does UNIVERSAL::can()

=head1 DESCRIPTION

This is pragma to change Perl 5's standard method resolution order from depth-first left-to-right 
(a.k.a - pre-order) to the more sophisticated C3 method resolution order. 

=head2 What is C3?

C3 is the name of an algorithm which aims to provide a sane method resolution order under multiple
inheritence. It was first introduced in the langauge Dylan (see links in the L<SEE ALSO> section),
and then later adopted as the prefered MRO (Method Resolution Order) for the new-style classes in 
Python 2.3. Most recently it has been adopted as the 'canonical' MRO for Perl 6 classes, and the 
default MRO for Parrot objects as well.

=head2 How does C3 work.

C3 works by always preserving local precendence ordering. This essentially means that no class will 
appear before any of it's subclasses. Take the classic diamond inheritence pattern for instance:

     <A>
    /   \
  <B>   <C>
    \   /
     <D>

The standard Perl 5 MRO would be (D, B, A, C). The result being that B<A> appears before B<C>, even 
though B<C> is the subclass of B<A>. The C3 MRO algorithm however, produces the following MRO 
(D, B, C, A), which does not have this same issue.

This example is fairly trival, for more complex examples and a deeper explaination, see the links in
the L<SEE ALSO> section.

=head2 How does this module work?

This module uses a technique similar to Perl 5's method caching. When C<Class::C3::initialize> is 
called, this module calculates the MRO of all the classes which called C<use Class::C3>. It then 
gathers information from the symbol tables of each of those classes, and builds a set of method 
aliases for the correct dispatch ordering. Once all these C3-based method tables are created, it 
then adds the method aliases into the local classes symbol table. 

The end result is actually classes with pre-cached method dispatch. However, this caching does not
do well if you start changing your C<@ISA> or messing with class symbol tables, so you should consider
your classes to be effectively closed. See the L<CAVEATS> section for more details.

=head1 OPTIONAL LOWERCASE PRAGMA

This release also includes an optional module B<c3> in the F<opt/> folder. I did not include this in 
the regular install since lowercase module names are considered I<"bad"> by some people. However I
think that code looks much nicer like this:

  package MyClass;
  use c3;
  
The the more clunky:

  package MyClass;
  use Class::C3;
  
But hey, it's your choice, thats why it is optional.

=head1 FUNCTIONS

=over 4

=item B<calculateMRO ($class)>

Given a C<$class> this will return an array of class names in the proper C3 method resolution order.

=item B<initialize>

This B<must be called> to initalize the C3 method dispatch tables, this module B<will not work> if 
you do not do this. It is advised to do this as soon as possible B<after> loading any classes which 
use C3. Here is a quick code example:
  
  package Foo;
  use Class::C3;
  # ... Foo methods here
  
  package Bar;
  use Class::C3;
  use base 'Foo';
  # ... Bar methods here
  
  package main;
  
  Class::C3::initialize(); # now it is safe to use Foo and Bar

This function used to be called automatically for you in the INIT phase of the perl compiler, but 
that lead to warnings if this module was required at runtime. After discussion with my user base 
(the L<DBIx::Class> folks), we decided that calling this in INIT was more of an annoyance than a 
convience. I apologize to anyone this causes problems for (although i would very suprised if I had 
any other users other than the L<DBIx::Class> folks). The simplest solution of course is to define 
your own INIT method which calls this function. 

NOTE: 

If C<initialize> detects that C<initialize> has already been executed, it will L</uninitialize> and
clear the MRO cache first.

=item B<uninitialize>

Calling this function results in the removal of all cached methods, and the restoration of the old Perl 5
style dispatch order (depth-first, left-to-right). 

=item B<reinitialize>

This is an alias for L</initialize> above.

=back

=head1 METHOD REDISPATCHING

It is always useful to be able to re-dispatch your method call to the "next most applicable method". This 
module provides a pseudo package along the lines of C<SUPER::> or C<NEXT::> which will re-dispatch the 
method along the C3 linearization. This is best show with an examples.

  # a classic diamond MI pattern ...
     <A>
    /   \
  <B>   <C>
    \   /
     <D>
  
  package A;
  use c3; 
  sub foo { 'A::foo' }       
 
  package B;
  use base 'A'; 
  use c3;     
  sub foo { 'B::foo => ' . (shift)->next::method() }       
 
  package B;
  use base 'A'; 
  use c3;    
  sub foo { 'C::foo => ' . (shift)->next::method() }   
 
  package D;
  use base ('B', 'C'); 
  use c3; 
  sub foo { 'D::foo => ' . (shift)->next::method() }   
  
  print D->foo; # prints out "D::foo => B::foo => C::foo => A::foo"

A few things to note. First, we do not require you to add on the method name to the C<next::method> 
call (this is unlike C<NEXT::> and C<SUPER::> which do require that). This helps to enforce the rule 
that you cannot dispatch to a method of a different name (this is how C<NEXT::> behaves as well). 

The next thing to keep in mind is that you will need to pass all arguments to C<next::method> it can 
not automatically use the current C<@_>. 

If C<next::method> cannot find a next method to re-dispatch the call to, it will throw an exception.
You can use C<next::can> to see if C<next::method> will succeed before you call it like so:

  $self->next::method(@_) if $self->next::can; 

Additionally, you can use C<maybe::next::method> as a shortcut to only call the next method if it exists. 
The previous example could be simply written as:

  $self->maybe::next::method(@_);

There are some caveats about using C<next::method>, see below for those.

=head1 CAVEATS

This module used to be labeled as I<experimental>, however it has now been pretty heavily tested by 
the good folks over at L<DBIx::Class> and I am confident this module is perfectly usable for 
whatever your needs might be. 

But there are still caveats, so here goes ...

=over 4

=item Use of C<SUPER::>.

The idea of C<SUPER::> under multiple inheritence is ambigious, and generally not recomended anyway.
However, it's use in conjuntion with this module is very much not recommended, and in fact very 
discouraged. The recommended approach is to instead use the supplied C<next::method> feature, see
more details on it's usage above.

=item Changing C<@ISA>.

It is the author's opinion that changing C<@ISA> at runtime is pure insanity anyway. However, people
do it, so I must caveat. Any changes to the C<@ISA> will not be reflected in the MRO calculated by this
module, and therefor probably won't even show up. If you do this, you will need to call C<reinitialize> 
in order to recalulate B<all> method dispatch tables. See the C<reinitialize> documentation and an example
in F<t/20_reinitialize.t> for more information.

=item Adding/deleting methods from class symbol tables.

This module calculates the MRO for each requested class by interogatting the symbol tables of said classes. 
So any symbol table manipulation which takes place after our INIT phase is run will not be reflected in 
the calculated MRO. Just as with changing the C<@ISA>, you will need to call C<reinitialize> for any 
changes you make to take effect.

=item Calling C<next::method> from methods defined outside the class

There is an edge case when using C<next::method> from within a subroutine which was created in a different 
module than the one it is called from. It sounds complicated, but it really isn't. Here is an example which 
will not work correctly:

  *Foo::foo = sub { (shift)->next::method(@_) };

The problem exists because the anonymous subroutine being assigned to the glob C<*Foo::foo> will show up 
in the call stack as being called C<__ANON__> and not C<foo> as you might expect. Since C<next::method> 
uses C<caller> to find the name of the method it was called in, it will fail in this case. 

But fear not, there is a simple solution. The module C<Sub::Name> will reach into the perl internals and 
assign a name to an anonymous subroutine for you. Simply do this:
    
  use Sub::Name 'subname';
  *Foo::foo = subname 'Foo::foo' => sub { (shift)->next::method(@_) };

and things will Just Work. Of course this is not always possible to do, but to be honest, I just can't 
manage to find a workaround for it, so until someone gives me a working patch this will be a known 
limitation of this module.

=back

=head1 COMPATIBILITY

If your software requires Perl 5.9.5 or higher, you do not need L<Class::C3>, you can simply C<use mro 'c3'>, and not worry about C<initialize()>, avoid some of the above caveats, and get the best possible performance.  See L<mro> for more details.

If your software is meant to work on earlier Perls, use L<Class::C3> as documented here.  L<Class::C3> will detect Perl 5.9.5+ and take advantage of the core support when available.

=head1 Class::C3::XS

This module will load L<Class::C3::XS> if it's installed and you are running on a Perl version older than 5.9.5.  Installing this is recommended when possible, as it results in significant performance improvements (but unlike the 5.9.5+ core support, it still has all of the same caveats as L<Class::C3>).

=head1 CODE COVERAGE

L<Devel::Cover> was reporting 94.4% overall test coverage earlier in this module's life.  Currently, the test suite does things that break under coverage testing, but it is fair to assume the coverage is still close to that value.

=head1 SEE ALSO

=head2 The original Dylan paper

=over 4

=item L<http://www.webcom.com/haahr/dylan/linearization-oopsla96.html>

=back

=head2 The prototype Perl 6 Object Model uses C3

=over 4

=item L<http://svn.openfoundry.org/pugs/perl5/Perl6-MetaModel/>

=back

=head2 Parrot now uses C3

=over 4

=item L<http://aspn.activestate.com/ASPN/Mail/Message/perl6-internals/2746631>

=item L<http://use.perl.org/~autrijus/journal/25768>

=back

=head2 Python 2.3 MRO related links

=over 4

=item L<http://www.python.org/2.3/mro.html>

=item L<http://www.python.org/2.2.2/descrintro.html#mro>

=back

=head2 C3 for TinyCLOS

=over 4

=item L<http://www.call-with-current-continuation.org/eggs/c3.html>

=back 

=head1 ACKNOWLEGEMENTS

=over 4

=item Thanks to Matt S. Trout for using this module in his module L<DBIx::Class> 
and finding many bugs and providing fixes.

=item Thanks to Justin Guenther for making C<next::method> more robust by handling 
calls inside C<eval> and anon-subs.

=item Thanks to Robert Norris for adding support for C<next::can> and 
C<maybe::next::method>.

=back

=head1 AUTHOR

Stevan Little, E<lt>stevan@iinteractive.comE<gt>

Brandon L. Black, E<lt>blblack@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2005, 2006 by Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
