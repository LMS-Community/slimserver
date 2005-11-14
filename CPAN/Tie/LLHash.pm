package Tie::LLHash;
use strict;
use vars qw($VERSION);
use Carp;


$VERSION = '1.003';

sub TIEHASH {
   my $pkg = shift;

   my $self = bless {}, $pkg;
   %$self = ( %$self, %{shift()} ) if ref $_[0];
   $self->CLEAR;

   # Initialize the hash if more arguments are given
   while (@_) {
      $self->last( splice(@_, 0, 2) );
   }
   
   return $self;
}

# Standard access methods:

sub FETCH {
   my $self = shift;
   my $key = shift;

   return undef unless $self->EXISTS($key);
   return $self->{'nodes'}{$key}{'value'};
}

sub STORE {
   my $self = shift;
   my $name = shift;
   my $value = shift;

   if (exists $self->{'nodes'}{$name}) {
     return $self->{'nodes'}{$name}{'value'} = $value;
   }

   croak ("No such key '$name', use first() or insert() to add keys") unless $self->{lazy};
   return $self->last($name, $value);
}


sub FIRSTKEY {
   my $self = shift;
   return $self->{'current'} = $self->{'first'};
}

sub NEXTKEY {
   my $self = shift;
   return $self->{'current'} = (defined $self->{'current'}
				? $self->{'nodes'}{ $self->{'current'} }{'next'}
				: $self->{'first'});
}

sub EXISTS {
   my $self = shift;
   my $name = shift;
   return exists $self->{'nodes'}{$name};
}

sub DELETE {
  my $self = shift;
  my $key = shift;
  #my $debug = 0;
  
  return unless $self->EXISTS($key);
  my $node = $self->{'nodes'}{$key};

  if ($self->{'first'} eq $self->{'last'}) {
    $self->{'first'} = undef;
    $self->{'current'} = undef;
    $self->{'last'} = undef;
    
  } elsif ($self->{'first'} eq $key) {
    $self->{'first'} = $node->{'next'};
    $self->{'nodes'}{ $self->{'first'} }{'prev'} = undef;
    $self->{'current'} = undef;
    
  } elsif ($self->{'last'} eq $key) {
    $self->{'current'} = $self->{'last'} = $node->{'prev'};
    $self->{'nodes'}{ $self->{'last'} }{'next'} = undef;
    
  } else {
    my $key_one   = $node->{'prev'};
    my $key_three = $node->{'next'};
    $self->{'nodes'}{$key_one  }{'next'} = $key_three;
    $self->{'nodes'}{$key_three}{'prev'} = $key_one;
    $self->{'current'} = $key_one;
  }
   
  return +(delete $self->{'nodes'}{$key})->{value};
}

sub CLEAR {
   my $self = shift;
   
   $self->{'first'} = undef;
   $self->{'last'} = undef;
   $self->{'current'} = undef;
   $self->{'nodes'} = {};
}

# Special access methods 
# Use (tied %hash)->method to get at them

sub insert {
   my $self = shift;
   my $two_key = shift;
   my $two_value = shift;
   my $one_key = shift;
   
   # insert(key,val) and insert(key,val,undef)  ==  first(key,val)
   return $self->first($two_key, $two_value) unless defined $one_key;

   croak ("No such key '$one_key'") unless $self->EXISTS($one_key);
   croak ("'$two_key' already exists") if $self->EXISTS($two_key);

   my $three_key = $self->{'nodes'}{$one_key}{'next'};

   $self->{'nodes'}{$one_key}{'next'} = $two_key;

   $self->{'nodes'}{$two_key}{'prev'} = $one_key;
   $self->{'nodes'}{$two_key}{'next'} = $three_key;
   $self->{'nodes'}{$two_key}{'value'} = $two_value;
   
   if (defined $three_key) {
      $self->{'nodes'}{$three_key}{'prev'} = $two_key;
   }

   # If we're adding to the end of the hash, adjust the {last} pointer:
   if ($one_key eq $self->{'last'}) {
      $self->{'last'} = $two_key;
   }

   return $two_value;
}

sub first {
   my $self = shift;
   
   if (@_) { # Set it
      my $newkey = shift;
      my $newvalue = shift;

      croak ("'$newkey' already exists") if $self->EXISTS($newkey);
      
      # Create the new node
      $self->{'nodes'}{$newkey} =
      {
         'next'  => undef,
         'value' => $newvalue,
         'prev'  => undef,
      };
      
      # Put it in its relative place
      if (defined $self->{'first'}) {
         $self->{'nodes'}{$newkey}{'next'} = $self->{'first'};
         $self->{'nodes'}{ $self->{'first'} }{'prev'} = $newkey;
      }
      
      # Finally, make this node the first node
      $self->{'first'} = $newkey;

      # If this is an empty hash, make it the last node too
      $self->{'last'} = $newkey unless (defined $self->{'last'});
   }
   return $self->{'first'};
}

sub last {
   my $self = shift;
   
   if (@_) { # Set it
      my $newkey = shift;
      my $newvalue = shift;

      croak ("'$newkey' already exists") if $self->EXISTS($newkey);
   
      # Create the new node
      $self->{'nodes'}{$newkey} =
      {
         'next'  => undef,
         'value' => $newvalue,
         'prev'  => undef,
      };

      # Put it in its relative place
      if (defined $self->{'last'}) {
         $self->{'nodes'}{$newkey}{'prev'} = $self->{'last'};
         $self->{'nodes'}{ $self->{'last'} }{'next'} = $newkey;
      }

      # Finally, make this node the last node
      $self->{'last'} = $newkey;

      # If this is an empty hash, make it the first node too
      $self->{'first'} = $newkey unless (defined $self->{'first'});
   }
   return $self->{'last'};
}

sub key_before {
   return $_[0]->{'nodes'}{$_[1]}{'prev'};
}

sub key_after {
   return $_[0]->{'nodes'}{$_[1]}{'next'};
}

sub current_key {
   return $_[0]->{'current'};
}

sub current_value {
   my $self = shift;
   return $self->FETCH($self->{'current'});
}

sub next  { my $s=shift; $s->NEXTKEY($_) }
sub prev  {
   my $self = shift;
   return $self->{'current'} = $self->{'nodes'}{ $self->{'current'} }{'prev'};
}
sub reset { my $s=shift; $s->FIRSTKEY($_) }

1;
__END__

=head1 NAME

Tie::LLHash.pm - ordered hashes

=head1 DESCRIPTION

This class implements an ordered hash-like object.  It's a cross between a
Perl hash and a linked list.  Use it whenever you want the speed and
structure of a Perl hash, but the orderedness of a list.

Don't use it if you want to be able to address your hash entries by number, 
like you can in a real list ($list[5]).

See also Tie::IxHash by Gurusamy Sarathy.  It's similar (it also does
ordered hashes), but it has a different internal data structure and a
different flavor of usage.  IxHash stores its data internally as both
a hash and an array in parallel.  LLHash stores its data as a
bidirectional linked list, making both inserts and deletes very fast.
IxHash therefore makes your hash behave more like a list than LLHash
does.  This module keeps more of the hash flavor.

=head1 SYNOPSIS

 use Tie::LLHash;
 
 # A new empty ordered hash:
 tie (%hash, "Tie::LLHash");
 # A new ordered hash with stuff in it:
 tie (%hash2, "Tie::LLHash", key1=>$val1, key2=>$val2);
 # Allow easy insertions at the end of the hash:
 tie (%hash2, "Tie::LLHash", {lazy=>1}, key1=>$val1, key2=>$val2);
 
 # Add some entries:
 (tied %hash)->first('the' => 'hash');
 (tied %hash)->insert('here' => 'now', 'the'); 
 (tied %hash)->first('All' => 'the');
 (tied %hash)->insert('are' => 'right', 'the');
 (tied %hash)->insert('things' => 'in', 'All');
 (tied %hash)->last('by' => 'gum');

 $value = $hash{'things'}; # Look up a value
 $hash{'here'} = 'NOW';    # Set the value of an EXISTING RECORD!
 
 
 $key = (tied %hash)->key_before('in');  # Returns the previous key
 $key = (tied %hash)->key_after('in');   # Returns the next key
 
 # Luxury routines:
 $key = (tied %hash)->current_key;
 $val = (tied %hash)->current_value;
 (tied %hash)->next;
 (tied %hash)->prev;
 (tied %hash)->reset;

 # If lazy-mode is set, new keys will be added at the end.
 $hash{newkey} = 'newval';
 $hash{newkey2} = 'newval2';

=head1 METHODS

=over 4

=item * insert(key, value, previous_key)

This inserts a new key-value pair into the hash right after the C<previous_key> key.
If C<previous_key> is undefined (or not supplied), this is exactly equivalent to
C<first(key, value)>.  If C<previous_key> is defined, then it must be a string which
is already a key in the hash - otherwise we'll croak().

=item * first(key, value)  (or)  first()

Gets or sets the first key in the hash.  Without arguments, simply returns a string
which is the first key in the database.  With arguments, it inserts a new key-value
pair at the beginning of the hash.

=item * last(key, value)  (or)  last()

Gets or sets the last key in the hash.  Without arguments, simply returns a string
which is the last key in the database.  With arguments, it inserts a new key-value
pair at the end of the hash.

=item * key_before(key)

Returns the name of the key immediately before the given key.  If no keys are
before the given key, returns C<undef>.

=item * key_after(key)

Returns the name of the key immediately after the given key.  If no keys are
after the given key, returns C<undef>.

=item * current_key()

When iterating through the hash, this returns the key at the current position
in the hash.

=item * current_value()

When iterating through the hash, this returns the value at the current position
in the hash.

=item * next()

Increments the current position in the hash forward one item.  Returns the
new current key, or C<undef> if there are no more entries.

=item * prev()

Increments the current position in the hash backward one item.  Returns the
new current key, or C<undef> if there are no more entries.

=item * reset()

Resets the current position to be the start of the order.  Returns the new
current key, or C<undef> if there are no keys.

=back 
 
=head1 ITERATION TECHNIQUES

Here is a smattering of ways you can iterate over the hash.  I include it here
simply because iteration is probably important to people who need ordered data.

 while (($key, $val) = each %hash) {
    print ("$key: $val\n");
 }
 
 foreach $key (keys %hash) {
    print ("$key: $hash{$key}\n");
 }
 
 my $obj = tied %hash;  # For the following examples

 $key = $obj->reset;
 while (exists $hash{$key}) {
    print ("$key: $hash{$key}\n");
    $key = $obj->next;
 }

 $obj->reset;
 while (exists $hash{$obj->current_key}) {
    $key = $obj->current_key;
    print ("$key: $hash{$key}\n");
    $obj->next;
 }

=head1 WARNINGS

=over 4

=item * Unless you're using lazy-mode, don't add new elements to the hash by
simple assignment, a la <$hash{$new_key} = $value>, because LLHash won't
know where in the order to put the new element.


=head1 TO DO

I could speed up the keys() routine in a scalar context if I knew how to
sense when NEXTKEY is being called on behalf of keys().  Not sure whether
this is possible.

I may also want to add a method for... um, I forgot.  Something.

=head1 AUTHOR

Ken Williams <ken@forum.swarthmore.edu>

Copyright (c) 1998 Swarthmore College. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

#  LocalWords:  undef
