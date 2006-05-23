
package Algorithm::C3;

use strict;
use warnings;

use Carp 'confess';

our $VERSION = '0.01';

# this function is a perl-port of the 
# python code on this page:
#   http://www.python.org/2.3/mro.html
sub _merge {                
    my (@seqs) = @_;
    my $class_being_merged = $seqs[0]->[0];
    my @res; 
    while (1) {
        # remove all empty seqences
        my @nonemptyseqs = (map { (@{$_} ? $_ : ()) } @seqs);
        # return the list if we have no more no-empty sequences
        return @res if not @nonemptyseqs; 
        my $reject;
        my $cand; # a canidate ..
        foreach my $seq (@nonemptyseqs) {
            $cand = $seq->[0]; # get the head of the list
            my $nothead;            
            foreach my $sub_seq (@nonemptyseqs) {
                # XXX - this is instead of the python "in"
                my %in_tail = (map { $_ => 1 } @{$sub_seq}[ 1 .. $#{$sub_seq} ]);
                # NOTE:
                # jump out as soon as we find one matching
                # there is no reason not too. However, if 
                # we find one, then just remove the '&& last'
                ++$nothead && last if exists $in_tail{$cand};      
            }
            last unless $nothead; # leave the loop with our canidate ...
            $reject = $cand;
            $cand = undef;        # otherwise, reject it ...
        }
        die "Inconsistent hierarchy found while merging '$class_being_merged':\n\t" .
            "current merge results [\n\t\t" . (join ",\n\t\t" => @res) . "\n\t]\n\t" .
            "merging failed on '$reject'\n" if not $cand;
        push @res => $cand;
        # now loop through our non-empties and pop 
        # off the head if it matches our canidate
        foreach my $seq (@nonemptyseqs) {
            shift @{$seq} if $seq->[0] eq $cand;
        }
    }
}

sub merge {
    my ($root, $_parent_fetcher) = @_;
    my $parent_fetcher = $_parent_fetcher;
    unless (ref($parent_fetcher) && ref($parent_fetcher) eq 'CODE') {
        $parent_fetcher = $root->can($_parent_fetcher) || confess "Could not find method $_parent_fetcher in $root";
    } 
    return _merge(
        [ $root ],
        (map { [ merge($_, $_parent_fetcher) ] } $root->$parent_fetcher()),
        [ $parent_fetcher->($root) ],
    );
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

=item B<merge ($root, $func_to_fetch_parent)>

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

=back

=head1 CODE COVERAGE

I use B<Devel::Cover> to test the code coverage of my tests, below 
is the B<Devel::Cover> report on this module's test suite.

 ------------------------ ------ ------ ------ ------ ------ ------ ------
 File                       stmt   bran   cond    sub    pod   time  total
 ------------------------ ------ ------ ------ ------ ------ ------ ------
 Algorithm/C3.pm           100.0  100.0   55.6  100.0  100.0  100.0   94.4
 ------------------------ ------ ------ ------ ------ ------ ------ ------
 Total                     100.0  100.0   55.6  100.0  100.0  100.0   94.4
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

=head1 AUTHOR

Stevan Little, E<lt>stevan@iinteractive.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2006 by Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
