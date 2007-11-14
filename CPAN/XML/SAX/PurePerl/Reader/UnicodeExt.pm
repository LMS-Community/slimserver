# $Id: UnicodeExt.pm 1097 2004-07-16 12:55:19Z dean $

package XML::SAX::PurePerl::Reader;
use strict;

use XML::SAX::PurePerl::Reader qw(CURRENT);
use Encode;

sub set_raw_stream {
    my ($fh) = @_;
    binmode($fh, ":bytes");
}

sub switch_encoding_stream {
    my ($fh, $encoding) = @_;
    binmode($fh, ":encoding($encoding)");
}

sub switch_encoding_string {
    Encode::from_to($_[0], $_[1], "utf-8");
}

sub nextchar {
    my $self = shift;
    $self->next;

    return unless defined($self->[CURRENT]);

    if ($self->[CURRENT] eq "\x0D") {
        $self->next;
        return unless defined($self->[CURRENT]);
        if ($self->[CURRENT] ne "\x0A") {
            $self->buffer("\x0A");
        }
    }
}


1;

