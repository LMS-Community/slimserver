# $Id: NoUnicodeExt.pm 1097 2004-07-16 12:55:19Z dean $

package XML::SAX::PurePerl::Reader;
use strict;

use XML::SAX::PurePerl::Reader qw(
    CURRENT
    ENCODING
);

sub set_raw_stream {
    # no-op
}

sub switch_encoding_stream {
    my ($fh, $encoding) = @_;
    throw XML::SAX::Exception::Parse (
        Message => "Only ASCII encoding allowed without perl 5.7.2 or higher. You tried: $encoding",
    ) if $encoding !~ /(ASCII|UTF\-?8)/i;
}

sub switch_encoding_string {
    my (undef, $encoding) = @_;
    throw XML::SAX::Exception::Parse (
        Message => "Only ASCII encoding allowed without perl 5.7.2 or higher. You tried: $encoding",
    ) if $encoding !~ /(ASCII|UTF\-?8)/i;
}

sub nextchar {
    my $self = shift;
    $self->next;
    
    return unless defined $self->[CURRENT];

    if ($self->[CURRENT] eq "\x0D") {
        $self->next;
        return unless defined($self->[CURRENT]);
        if ($self->[CURRENT] ne "\x0A") {
            $self->buffer("\x0A");
        }
    }
    
    return unless $self->[ENCODING];
    my $n = ord($self->[CURRENT]);
    # warn(sprintf("ch: 0x%x ($self->[CURRENT])\n", $n));
    if (($] < 5.007002) && ($n > 0x7F)) {
        # utf8 surrogate
        my $current = $self->[CURRENT];
        if    ($n >= 0xFC) {
            # read 5 chars
            $self->next; $current .= $self->[CURRENT];
            $self->next; $current .= $self->[CURRENT];
            $self->next; $current .= $self->[CURRENT];
            $self->next; $current .= $self->[CURRENT];
            $self->next; $current .= $self->[CURRENT];
        }
        elsif ($n >= 0xF8) {
            # read 4 chars
            $self->next; $current .= $self->[CURRENT];
            $self->next; $current .= $self->[CURRENT];
            $self->next; $current .= $self->[CURRENT];
            $self->next; $current .= $self->[CURRENT];
        }
        elsif ($n >= 0xF0) {
            # read 3 chars
            $self->next; $current .= $self->[CURRENT];
            $self->next; $current .= $self->[CURRENT];
            $self->next; $current .= $self->[CURRENT];
        }
        elsif ($n >= 0xE0) {
            # read 2 chars
            $self->next; $current .= $self->[CURRENT];
            $self->next; $current .= $self->[CURRENT];
        }
        elsif ($n >= 0xC0) {
            # read 1 char
            $self->next; $current .= $self->[CURRENT];
        }
        else {
            throw XML::SAX::Exception::Parse(
                Message => sprintf("Invalid character 0x%x", $n),
                ColumnNumber => $self->column,
                LineNumber => $self->line,
                PublicId => $self->public_id,
                SystemId => $self->system_id,
            );
        }
        if ($] >= 5.006001) {
            $self->[CURRENT] = pack("U0A*", $current);
        }
        else {
            $self->[CURRENT] = $current;
        }
        # warn("read extra. current now: $current\n");
    }
}

1;

