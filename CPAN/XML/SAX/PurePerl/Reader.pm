# $Id: Reader.pm 1097 2004-07-16 12:55:19Z dean $

package XML::SAX::PurePerl::Reader;

use strict;
use XML::SAX::PurePerl::Reader::URI;
use XML::SAX::PurePerl::Productions qw( $SingleChar $Letter $NameChar );
use Exporter ();

use vars qw(@ISA @EXPORT_OK);
@ISA = qw(Exporter);
@EXPORT_OK = qw(
    EOF
    BUFFER
    INTERNAL_BUFFER
    LINE
    COLUMN
    CURRENT
    ENCODING
);

use constant EOF => 0;
use constant BUFFER => 1;
use constant INTERNAL_BUFFER => 2;
use constant LINE => 3;
use constant COLUMN => 4;
use constant MATCHED => 5;
use constant CURRENT => 6;
use constant CONSUMED => 7;
use constant ENCODING => 8;
use constant SYSTEM_ID => 9;
use constant PUBLIC_ID => 10;

require XML::SAX::PurePerl::Reader::Stream;
require XML::SAX::PurePerl::Reader::String;

if ($] >= 5.007002) {
    require XML::SAX::PurePerl::Reader::UnicodeExt;
}
else {
    require XML::SAX::PurePerl::Reader::NoUnicodeExt;
}

sub new {
    my $class = shift;
    my $thing = shift;
    
    # try to figure if this $thing is a handle of some sort
    if (ref($thing) && UNIVERSAL::isa($thing, 'IO::Handle')) {
        return XML::SAX::PurePerl::Reader::Stream->new($thing)->init;
    }
    my $ioref;
    if (tied($thing)) {
        my $class = ref($thing);
        no strict 'refs';
        $ioref = $thing if defined &{"${class}::TIEHANDLE"};
    }
    else {
        eval {
            $ioref = *{$thing}{IO};
        };
        undef $@;
    }
    if ($ioref) {
        return XML::SAX::PurePerl::Reader::Stream->new($thing)->init;
    }
    
    if ($thing =~ /</) {
        # assume it's a string
        return XML::SAX::PurePerl::Reader::String->new($thing)->init;
    }
    
    # assume it is a uri
    return XML::SAX::PurePerl::Reader::URI->new($thing)->init;
}

sub init {
    my $self = shift;
    $self->[LINE] = 1;
    $self->[COLUMN] = 1;
    $self->nextchar;
    return $self;
}

sub match {
    my $self = shift;
    if ($self->match_nocheck(@_)) {
        if ($self->[MATCHED] =~ $SingleChar) {
            return 1;
        }
        throw XML::SAX::Exception::Parse (
            Message => "Not a valid XML character: '&#x".
                        sprintf("%X", ord($self->[MATCHED])).
                        ";'"
        );
    }
    return 0;
}

sub match_char {
    my $self = shift;
    
    if (defined($self->[CURRENT]) && $self->[CURRENT] eq $_[0]) {
        $self->[MATCHED] = $_[0];
        $self->nextchar;
        return 1;
    }
    $self->[MATCHED] = '';
    return 0;
}

sub match_re {
    my $self = shift;
    
    if ($self->[CURRENT] =~ $_[0]) {
        $self->[MATCHED] = $self->[CURRENT];
        $self->nextchar;
        return 1;
    }
    $self->[MATCHED] = '';
    return 0;
}

sub match_not {
    my $self = shift;
    
    my $current = $self->[CURRENT];
    return 0 unless defined $current;
    
    for my $m (@_) {
        if ($current eq $m) {
            $self->[MATCHED] = '';
            return 0;
        }
    }
    $self->[MATCHED] = $current;
    $self->nextchar;
    return 1;
}

my %hist;
END {
    foreach my $k (sort { $hist{$a} <=> $hist{$b} } keys %hist ) {
        my $x = $k;
        $k =~ s/^(.{80})(.{3}).*/$1\.\.\./s;
        # warn("$k called $hist{$x} times\n");
    }
}

sub match_nonext {
    my $self = shift;
    
    my $current = $self->[CURRENT];
    return 0 unless defined $current;
    
    foreach my $m (@_) {
        # $hist{$m}++;
        if (my $ref = ref($m)) {
            if ($ref eq 'Regexp' && $current =~ $m) {
                $self->[MATCHED] = $current;
                return 1;
            }
        }
        elsif ($current eq $m) {
            $self->[MATCHED] = $current;
            return 1;
        }
    }
    $self->[MATCHED] = '';
    return 0;    
}

sub match_nocheck {
    my $self = shift;
    
    if ($self->match_nonext(@_)) {
        $self->nextchar;

        return 1;
    }
    return 0;
}

sub matched {
    my $self = shift;
    return $self->[MATCHED];
}

my $unpack_type = ($] >= 5.007002) ? 'U*' : 'C*';

sub match_string {
    my $self = shift;
    my ($str) = @_;
    my $matched = '';
#    for my $char (map { chr } unpack($unpack_type, $str)) {
    for my $char (split //, $str) {
        if ($self->match_char($char)) {
            $matched .= $self->[MATCHED];
        }
        else {
            $self->buffer($matched);
            return 0;
        }
    }
    return 1;
}

# avoids split
sub match_sequence {
    my $self = shift;
    my $matched = '';
    for my $char (@_) {
        if ($self->match_char($char)) {
            $matched .= $self->[MATCHED];
        }
        else {
            $self->buffer($matched);
            return 0;
        }
    }
    return 1;
}

sub consume_name {
    my $self = shift;
    
    my $current = $self->[CURRENT];
    return unless defined $current; # perhaps die here instead?
    
    my $name;
    if ($current eq '_') {
        $name = '_';
    }
    elsif ($current eq ':') {
        $name = ':';
    }
    else {
        $self->consume($Letter) ||
                throw XML::SAX::Exception::Parse ( 
                    Message => "Name contains invalid start character: '&#x".
                                sprintf("%X", ord($self->[CURRENT])).
                                ";'", reader => $self );
        $name = $self->[CONSUMED];
    }
    
    $self->consume($NameChar);
    $name .= $self->[CONSUMED];
    return $name;
}

sub consume {
    my $self = shift;
    
    my $consumed = '';
    
    while(!$self->eof && $self->match_re(@_)) {
        $consumed .= $self->[MATCHED];
    }
    return length($self->[CONSUMED] = $consumed);
}



sub consume_not {
    my $self = shift;
    
    my $consumed = '';
    
    while(!$self->[EOF] && $self->match_not(@_)) {
        $consumed .= $self->[MATCHED];
    }
    return length($self->[CONSUMED] = $consumed);
}

sub consumed {
    my $self = shift;
    return $self->[CONSUMED];
}

sub current {
    my $self = shift;
    return $self->[CURRENT];
}

sub buffer {
    my $self = shift;
    # warn("buffering: '$_[0]' + '$self->[CURRENT]' + '$self->[BUFFER]'\n");
    local $^W;
    my $current = $self->[CURRENT];
    if ($] >= 5.006 && $] < 5.007) {
        $current = pack("C0A*", $current);
    }
    $self->[BUFFER] = $_[0] . $current . $self->[BUFFER];
    $self->[COLUMN] -= length($_[0]);
    $self->nextchar;
}

sub public_id {
    my ($self, $value) = @_;
    if (defined $value) {
        return $self->[PUBLIC_ID] = $value;
    }
    return $self->[PUBLIC_ID];
}

sub system_id {
    my ($self, $value) = @_;
    if (defined $value) {
        return $self->[SYSTEM_ID] = $value;
    }
    return $self->[SYSTEM_ID];
}

sub line {
    shift->[LINE];
}

sub column {
    shift->[COLUMN];
}

sub get_encoding {
    my $self = shift;
    return $self->[ENCODING];
}

sub eof {
    return shift->[EOF];
}

1;

__END__

=head1 NAME

XML::Parser::PurePerl::Reader - Abstract Reader factory class

=cut
