package Media::Scan::Progress;

use strict;

# Implementation is in xs/Progress.xs

sub as_hash {
    my $self = shift;
    
    return {
        phase    => $self->phase,
        cur_item => $self->cur_item,
        total    => $self->total,
        done     => $self->done,
        eta      => $self->eta,
        rate     => $self->rate,
    };
}

1;