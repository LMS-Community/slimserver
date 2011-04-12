package Media::Scan::Error;

use strict;

# Implementation is in xs/Error.xs

sub as_hash {
    my $self = shift;
    
    return {
        error_code   => $self->error_code,
        averror      => $self->averror,
        path         => $self->path,
        error_string => $self->error_string,
    };
}

1;