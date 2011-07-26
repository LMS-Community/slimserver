package Media::Scan::Image;

use strict;
use base qw(Media::Scan::Result);

# Implementation is in xs/Image.xs and xs/Result.xs

sub as_hash {
    my $self = shift;
    
    return {
        %{ $self->SUPER::as_hash() },
        codec  => $self->codec,
        width  => $self->width,
        height => $self->height,
    };
}

1;