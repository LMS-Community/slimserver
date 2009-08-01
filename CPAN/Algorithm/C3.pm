
package Algorithm::C3;

use strict;
use warnings;

use Carp 'confess';

our $VERSION = '0.07';

sub merge {
    my ($root, $parent_fetcher, $cache) = @_;

    $cache ||= {};

    my @STACK; # stack for simulating recursion

    my $pfetcher_is_coderef = ref($parent_fetcher) eq 'CODE';

    unless ($pfetcher_is_coderef or $root->can($parent_fetcher)) {
        confess "Could not find method $parent_fetcher in $root";
    }

    my $current_root = $root;
    my $current_parents = [ $root->$parent_fetcher ];
    my $recurse_mergeout = [];
    my $i = 0;
    my %seen = ( $root => 1 );

    my ($new_root, $mergeout, %tails);
    while(1) {
        if($i < @$current_parents) {
            $new_root = $current_parents->[$i++];

            if($seen{$new_root}) {
                my @isastack;
                my $reached;
                for(my $i = 0; $i < $#STACK; $i += 4) {
                    if($reached || ($reached = ($STACK[$i] eq $new_root))) {
                        push(@isastack, $STACK[$i]);
                    }
                }
                my $isastack = join(q{ -> }, @isastack, $current_root, $new_root);
                die "Infinite loop detected in parents of '$root': $isastack";
            }
            $seen{$new_root} = 1;

            unless ($pfetcher_is_coderef or $new_root->can($parent_fetcher)) {
                confess "Could not find method $parent_fetcher in $new_root";
            }

            push(@STACK, $current_root, $current_parents, $recurse_mergeout, $i);

            $current_root = $new_root;
            $current_parents = $cache->{pfetch}->{$current_root} ||= [ $current_root->$parent_fetcher ];
            $recurse_mergeout = [];
            $i = 0;
            next;
        }

        $seen{$current_root} = 0;

        $mergeout = $cache->{merge}->{$current_root} ||= do {

            # This do-block is the code formerly known as the function
            # that was a perl-port of the python code at
            # http://www.python.org/2.3/mro.html :)

            # Initial set (make sure everything is copied - it will be modded)
            my @seqs = map { [@$_] } @$recurse_mergeout;
            push(@seqs, [@$current_parents]) if @$current_parents;

            # Construct the tail-checking hash (actually, it's cheaper and still
            #   correct to re-use it throughout this function)
            foreach my $seq (@seqs) {
                $tails{$seq->[$_]}++ for (1..$#$seq);
            }

            my @res = ( $current_root );
            while (1) {
                my $cand;
                my $winner;
                foreach (@seqs) {
                    next if !@$_;
                    if(!$winner) {              # looking for a winner
                        $cand = $_->[0];        # seq head is candidate
                        next if $tails{$cand};  # he loses if in %tails
                        
                        # Handy warn to give a output like the ones on
                        # http://www.python.org/download/releases/2.3/mro/
                        #warn " = " . join(' + ', @res) . "  + merge([" . join('] [',  map { join(', ', @$_) } grep { @$_ } @seqs) . "])\n";
                        push @res => $winner = $cand;
                        shift @$_;                # strip off our winner
                        $tails{$_->[0]}-- if @$_; # keep %tails sane
                    }
                    elsif($_->[0] eq $winner) {
                        shift @$_;                # strip off our winner
                        $tails{$_->[0]}-- if @$_; # keep %tails sane
                    }
                }
                
                # Handy warn to give a output like the ones on
                # http://www.python.org/download/releases/2.3/mro/
                #warn " = " . join(' + ', @res) . "\n" if !$cand; 
                
                last if !$cand;
                die q{Inconsistent hierarchy found while merging '}
                    . $current_root . qq{':\n\t}
                    . qq{current merge results [\n\t\t}
                    . (join ",\n\t\t" => @res)
                    . qq{\n\t]\n\t} . qq{merging failed on '$cand'\n}
                  if !$winner;
            }
            \@res;
        };

        return @$mergeout if !@STACK;

        $i = pop(@STACK);
        $recurse_mergeout = pop(@STACK);
        $current_parents = pop(@STACK);
        $current_root = pop(@STACK);

        push(@$recurse_mergeout, $mergeout);
    }
}

1;

__END__

=pod

=head1 NAME

Algorithm::C3 - A module for merging hierarchies using the C3 algorithm

=head1 SYNOPSIS

  use Algorithm::C3;
  
  # merging a classic diamond 
  # inheritence graph like this:
  #
  #    <A>
  #   /   \
  # <B>   <C>
  #   \   /
  #    <D>  

  my @merged = Algorithm::C3::merge(
      'D', 
      sub {
          # extract the ISA array 
          # from the package
          no strict 'refs';
          @{$_[0] . '::ISA'};
      }
  );
  
  print join ", " => @merged; # prints D, B, C, A

=head1 DESCRIPTION

This module implements the C3 algorithm. I have broken this out 
into it's own module because I found myself copying and pasting 
it way too often for various needs. Most of the uses I have for 
C3 revolve around class building and metamodels, but it could 
also be used for things like dependency resolution as well since 
it tends to do such a nice job of preserving local precendence 
orderings. 

Below is a brief explanation of C3 taken from the L<Class::C3> 
module. For more detailed information, see the L<SEE ALSO> section 
and the links there.

=head2 What is C3?

C3 is the name of an algorithm which aims to provide a sane method 
resolution order under multiple inheritence. It was first introduced 
in the langauge Dylan (see links in the L<SEE ALSO> section), and 
then later adopted as the prefered MRO (Method Resolution Order) 
for the new-style classes in Python 2.3. Most recently it has been 
adopted as the 'canonical' MRO for Perl 6 classes, and the default 
MRO for Parrot objects as well.

=head2 How does C3 work.

C3 works by always preserving local precendence ordering. This 
essentially means that no class will appear before any of it's 
subclasses. Take the classic diamond inheritence pattern for 
instance:

     <A>
    /   \
  <B>   <C>
    \   /
     <D>

The standard Perl 5 MRO would be (D, B, A, C). The result being that 
B<A> appears before B<C>, even though B<C> is the subclass of B<A>. 
The C3 MRO algorithm however, produces the following MRO (D, B, C, A), 
which does not have this same issue.

This example is fairly trival, for more complex examples and a deeper 
explaination, see the links in the L<SEE ALSO> section.

=head1 FUNCTION

=over 4

=item B<merge ($root, $func_to_fetch_parent, $cache)>

This takes a C<$root> node, which can be anything really it
is up to you. Then it takes a C<$func_to_fetch_parent> which 
can be either a CODE reference (see L<SYNOPSIS> above for an 
example), or a string containing a method name to be called 
on all the items being linearized. An example of how this 
might look is below:

  {
      package A;
      
      sub supers {
          no strict 'refs';
          @{$_[0] . '::ISA'};
      }    
      
      package C;
      our @ISA = ('A');
      package B;
      our @ISA = ('A');    
      package D;       
      our @ISA = ('B', 'C');         
  }
  
  print join ", " => Algorithm::C3::merge('D', 'supers');

The purpose of C<$func_to_fetch_parent> is to provide a way 
for C<merge> to extract the parents of C<$root>. This is 
needed for C3 to be able to do it's work.

The C<$cache> parameter is an entirely optional performance
measure, and should not change behavior.

If supplied, it should be a hashref that merge can use as a
private cache between runs to speed things up.  Generally
speaking, if you will be calling merge many times on related
things, and the parent fetching function will return constant
results given the same arguments during all of these calls,
you can and should reuse the same shared cache hash for all
of the calls.  Example:

  sub do_some_merging {
      my %merge_cache;
      my @foo_mro = Algorithm::C3::Merge('Foo', \&get_supers, \%merge_cache);
      my @bar_mro = Algorithm::C3::Merge('Bar', \&get_supers, \%merge_cache);
      my @baz_mro = Algorithm::C3::Merge('Baz', \&get_supers, \%merge_cache);
      my @quux_mro = Algorithm::C3::Merge('Quux', \&get_supers, \%merge_cache);
      # ...
  }

=back

=head1 CODE COVERAGE

I use B<Devel::Cover> to test the code coverage of my tests, below 
is the B<Devel::Cover> report on this module's test suite.

 ------------------------ ------ ------ ------ ------ ------ ------ ------
 File                       stmt   bran   cond    sub    pod   time  total
 ------------------------ ------ ------ ------ ------ ------ ------ ------
 Algorithm/C3.pm           100.0  100.0  100.0  100.0  100.0  100.0  100.0
 ------------------------ ------ ------ ------ ------ ------ ------ ------
 Total                     100.0  100.0  100.0  100.0  100.0  100.0  100.0
 ------------------------ ------ ------ ------ ------ ------ ------ ------

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

=head1 AUTHORS

Stevan Little, E<lt>stevan@iinteractive.comE<gt>

Brandon L. Black, E<lt>blblack@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2006 by Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
