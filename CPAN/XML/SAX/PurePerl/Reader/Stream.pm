# $Id: Stream.pm 1097 2004-07-16 12:55:19Z dean $

package XML::SAX::PurePerl::Reader::Stream;

use strict;
use vars qw(@ISA);

use XML::SAX::PurePerl::Reader qw(
    EOF
    BUFFER
    INTERNAL_BUFFER
    LINE
    COLUMN
    CURRENT
    ENCODING
);
use XML::SAX::Exception;

@ISA = ('XML::SAX::PurePerl::Reader');

use constant FH => 11;
use constant BUFFER_SIZE => 12;

sub new {
    my $class = shift;
    my $ioref = shift;
    XML::SAX::PurePerl::Reader::set_raw_stream($ioref);
    my @parts;
    @parts[FH, LINE, COLUMN, BUFFER, EOF, INTERNAL_BUFFER, BUFFER_SIZE] =
        ($ioref, 1,   0,      '',     0,   '',              1);
    return bless \@parts, $class;
}

sub next {
    my $self = shift;
    
    # check for chars in buffer first.
    if (length($self->[BUFFER])) {
        return $self->[CURRENT] = substr($self->[BUFFER], 0, 1, ''); # last param truncates buffer
    }
    

    if (length($self->[INTERNAL_BUFFER])) {
BUFFERED_READ:
        $self->[CURRENT] = substr($self->[INTERNAL_BUFFER], 0, 1, '');
        if ($self->[CURRENT] eq "\x0A") {
            $self->[LINE]++;
            $self->[COLUMN] = 1;
        }
        else { $self->[COLUMN]++ }
        return;
    }
    
    my $bytesread = read($self->[FH], $self->[INTERNAL_BUFFER], $self->[BUFFER_SIZE]);
    if ($bytesread) {
        goto BUFFERED_READ;
    }
    elsif (defined($bytesread)) {
        $self->[EOF]++;
        return $self->[CURRENT] = undef;
    }
    throw XML::SAX::Exception::Parse(
        Message => "Error reading from filehandle: $!",
    );
}

sub set_encoding {
    my $self = shift;
    my ($encoding) = @_;
    # warn("set encoding to: $encoding\n");
    XML::SAX::PurePerl::Reader::switch_encoding_stream($self->[FH], $encoding);
    $self->[BUFFER_SIZE] = 1024;
    $self->[ENCODING] = $encoding;
}

sub bytepos {
    my $self = shift;
    tell($self->[FH]);
}

1;

