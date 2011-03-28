package Media::Scan::Video;

use strict;
use base qw(Media::Scan::Result);

# Implementation is in xs/Video.xs and xs/Result.xs

sub hash {
    my $self = shift;
    
    return {
        %{ $self->SUPER::hash() },
        codec  => $self->codec,
        width  => $self->width,
        height => $self->height,
        fps    => $self->fps,
    };
}

1;