package Tie::Cache::LRU::LinkedList;

use strict;
use vars qw($VERSION);
$VERSION = '0.01';

use Carp::Assert;

use base qw(Tie::Cache::LRU::Virtual);

use constant SUCCESS => 1;
use constant FAILURE => 0;

# Node members.
use enum qw(KEY VALUE PREV NEXT);


=pod

=head1 NAME

Tie::Cache::LRU::LinkedList - Tie::Cache::LRU implemented using a linked list

=head1 SYNOPSIS

  use Tie::Cache::LRU::LinkedList;

  tie %cache, 'Tie::Cache::LRU', 500;

  ...the rest is as Tie::Cache::LRU...

=head1 DESCRIPTION

This is an implementation of Tie::Cache::LRU using a linked list
structure.  Theoretically, this is an efficient algorithm, however it
may be lose out in smaller cache sizes (where small <= ??) due to its
relatively high constant.

=cut

sub TIEHASH {
    my($class, $max_size) = @_;
    my $self = bless {}, $class;

    $max_size = $class->DEFAULT_MAX_SIZE unless defined $max_size;

    $self->_init;
    $self->max_size($max_size);

    return $self;
}


sub FETCH {
    my($self, $key) = @_;

    return unless $self->EXISTS($key);

    my $node = $self->{index}{$key};
    $self->_promote($node);
    return $node->[VALUE];
}


sub STORE {
    my($self, $key, $value) = @_;

    if( $self->EXISTS($key) ) {
        my $node = $self->{index}{$key};
        $node->[VALUE] = $value;
        $self->_promote($node);
    }
    else {
        my $node = [];
        @{$node}[KEY, VALUE] = ($key, $value);

        ### Might it be smarter to just attach the new node to the list
        ### and call _promote()?
        # Make ourselves the freshest.
        if(defined $self->{freshest} ) {
            $self->{freshest}->[NEXT] = $node;
            $node->[PREV] = $self->{freshest};
        }
        else {
            assert($self->{size} == 0);
        }
        $self->{freshest} = $node;
        
        # If we're the first node, we are stinky, too.
        unless( defined $self->{stinkiest} ) {
            assert($self->{size} == 0);
            $self->{stinkiest} = $node;
        }
        $self->{size}++;
        $self->{index}{$key} = $node;
        $self->_cull;
    }
    return SUCCESS;
}


sub EXISTS {
    my($self, $key) = @_;

    return exists $self->{index}{$key};
}


sub CLEAR {
    my($self) = @_;
    $self->_init;
}


sub DELETE {
    my($self, $key) = @_;

    return unless $self->EXISTS($key);

    my $node = $self->{index}{$key};
    $self->{freshest}  = $node->[PREV] if $self->{freshest}  == $node;
    $self->{stinkiest} = $node->[NEXT] if $self->{stinkiest} == $node;
    $self->_yank($node);
    delete $self->{index}{$key};
    
    $self->{size}--;
    
    return $node->[VALUE];
}


# keys() should return most to least recent.
sub FIRSTKEY {
    my($self) = shift;
    my $first_node = $self->{freshest};
    assert($self->{size} == 0 xor defined $first_node);
    return $first_node->[KEY];
}

sub NEXTKEY  {
    my($self, $last_key) = @_;
    my $last_node = $self->{index}{$last_key};
    assert(defined $last_node) if DEBUG;

    # NEXTKEY uses PREV, yes.  We're going from newest to oldest.
    return defined $last_node->[PREV] ? $last_node->[PREV][KEY]
                              : undef;
}


sub DESTROY  {
    my($self) = shift;

    # The chain must be broken.
    $self->_init;
    
    return SUCCESS;
}


sub max_size {
    my($self) = shift;

    if(@_) {
        my ($new_max_size) = shift;
        assert(defined $new_max_size && $new_max_size !~ /\D/);
        $self->{max_size} = $new_max_size;

        # Immediately purge the cache if necessary.
        $self->_cull if $self->{size} > $new_max_size;

        return SUCCESS;
    }
    else {
        return $self->{max_size};
    }
}


sub curr_size {
    my($self) = shift;

    # We brook no arguments.
    assert(!@_);

    return $self->{size};
}


sub _init {
    my($self) = shift;

    # The cache is a chain.  We must break up its structure so Perl
    # can GC it.
    while( my($key, $node) = each %{$self->{index}} ) {
        $node->[NEXT] = undef;
        $node->[PREV] = undef;
    }

    $self->{freshest}  = undef;
    $self->{stinkiest} = undef;
    $self->{index} = {};
    $self->{size} = 0;
    
    return SUCCESS;
}


sub _yank {
    my($self, $node) = @_;
    
    my $prev_node = $node->[PREV];
    my $next_node = $node->[NEXT];
    $prev_node->[NEXT] = $next_node if defined $prev_node;
    $next_node->[PREV] = $prev_node if defined $next_node;

    $node->[NEXT] = undef;
    $node->[PREV] = undef;

    return SUCCESS;
}


sub _promote {
    my($self, $node) = @_;

    # _promote can take a node or a key.  Get the node from the key.
    $node = $self->{index}{$node} unless ref $node;
    return unless defined $node;

    # Don't bother if there's only one node, or if this node is
    # already the freshest.
    return if $self->{size} == 1 or $self->{freshest} == $node;

    # On the off chance that we're about to promote the stinkiest node,
    # make sure the stinkiest pointer is updated.
    if( $self->{stinkiest} == $node ) {
        assert(not defined $node->[PREV]);
        $self->{stinkiest} = $node->[NEXT];
    }

    # Pull the $node out of its position.
    $self->_yank($node);

    # Place the $node at the head.
    my $old_head  = $self->{freshest};
    $old_head->[NEXT]  = $node;
    $node->[PREV]      = $old_head;
    $node->[NEXT]      = undef;

    $self->{freshest} = $node;

    return SUCCESS;
}


sub _cull {
    my($self) = @_;
    
    my $max_size = $self->max_size;

    for( ;$self->{size} > $max_size; $self->{size}-- ) {
        my $rotten = $self->{stinkiest};
        assert(!defined $rotten->[PREV]);
        my $new_stink = $rotten->[NEXT];
        
        $rotten->[NEXT]    = undef;
        
        # Gotta watch out for autoviv.
        $new_stink->[PREV] = undef if defined $new_stink;
        
        $self->{stinkiest} = $new_stink;
        if( $self->{freshest} eq $rotten ) {
            assert( $self->{size} == 1 ) if DEBUG;
            $self->{freshest}  = $new_stink;
        }

        delete $self->{index}{$rotten->[KEY]};
    }
    
    return SUCCESS;
}


=pod

=head1 AUTHOR

Michael G Schwern <schwern@pobox.com>

=head1 SEE ALSO

L<Tie::Cache::LRU>, L<Tie::Cache::LRU::LinkedList>,
L<Tie::Cache::LRU::Virtual>, L<Tie::Cache>

=cut

1;

