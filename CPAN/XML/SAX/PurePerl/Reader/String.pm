# $Id: String.pm 1097 2004-07-16 12:55:19Z dean $

package XML::SAX::PurePerl::Reader::String;

use strict;
use vars qw(@ISA);

use XML::SAX::PurePerl::Reader qw(
    CURRENT
    LINE
    COLUMN
    INTERNAL_BUFFER
    BUFFER
    ENCODING
    EOF
);

@ISA = ('XML::SAX::PurePerl::Reader');

use constant DISCARDED => 11;

sub new {
    my $class = shift;
    my $string = shift;
    my @parts;
    @parts[BUFFER, EOF, LINE, COLUMN, INTERNAL_BUFFER, DISCARDED] =
            ('',   0,   1,    0,      $string,         '');
    return bless \@parts, $class;
}

sub next {
    my $self = shift;
    
    $self->[DISCARDED] .= $self->[CURRENT] if defined $self->[CURRENT];
    
    # check for chars in buffer first.
    if (length($self->[BUFFER])) {
        return $self->[CURRENT] = substr($self->[BUFFER], 0, 1, ''); # last param truncates buffer
    }
    
    $self->[CURRENT] = substr($self->[INTERNAL_BUFFER], 0, 1, '');
    
    if ($self->[CURRENT] eq "\x0A") {
        $self->[LINE]++;
        $self->[COLUMN] = 1;
    } else { $self->[COLUMN]++ }

    $self->[EOF]++ unless length($self->[INTERNAL_BUFFER]);
    return;
}

sub set_encoding {
    my $self = shift;
    my ($encoding) = @_;

    XML::SAX::PurePerl::Reader::switch_encoding_string($self->[INTERNAL_BUFFER], $encoding, "utf-8");
    $self->[ENCODING] = $encoding;
}

sub bytepos {
    my $self = shift;
    length($self->[DISCARDED]);
}

1;
