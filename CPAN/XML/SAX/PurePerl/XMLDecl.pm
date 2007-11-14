# $Id: XMLDecl.pm 1097 2004-07-16 12:55:19Z dean $

package XML::SAX::PurePerl;

use strict;
use XML::SAX::PurePerl::Productions qw($S $VersionNum $EncNameStart $EncNameEnd);

sub XMLDecl {
    my ($self, $reader) = @_;
    
    if ($reader->match_string("<?xml") && $reader->match($S)) {
        $self->skip_whitespace($reader);
        
        # get version attribute
        $self->VersionInfo($reader) || 
            $self->parser_error("XML Declaration lacks required version attribute", $reader);
        
        if (!$self->skip_whitespace($reader)) {
            $reader->match_string('?>') || $self->parser_error("Syntax error", $reader);
            return;
        }
        
        if ($self->EncodingDecl($reader)) {
            if (!$self->skip_whitespace($reader)) {
                $reader->match_string('?>') || $self->parser_error("Syntax error", $reader);
                return;
            }
        }
        
        $self->SDDecl($reader);
        
        $self->skip_whitespace($reader);
        
        $reader->match_string('?>') || $self->parser_error("Syntax error in XML declaration", $reader);
        # TODO: Call SAX event (xml_decl?)
        # actually, sax has no xml_decl event.
    }
    else {
        # no xml decl
        if (!$reader->get_encoding) {
            $reader->set_encoding("UTF-8");
        }
    }
}

sub VersionInfo {
    my ($self, $reader) = @_;
    
    $reader->match_string('version')
        || return 0;
    $self->skip_whitespace($reader);
    $reader->match('=') || 
        $self->parser_error("Invalid token", $reader);
    $self->skip_whitespace($reader);
    
    # set right quote char
    my $quote = $self->quote($reader);
    
    # get version value
    $reader->consume($VersionNum) || 
        $self->parser_error("Version number contains invalid characters", $reader);
    
    my $vernum = $reader->consumed;
    if ($vernum ne "1.0") {
        $self->parser_error("Only XML version 1.0 supported. Saw: '$vernum'", $reader);
    }

    $reader->match($quote) || 
        $self->parser_error("Invalid token while looking for quote character", $reader);
    
    return 1;
}

sub SDDecl {
    my ($self, $reader) = @_;
    
    $reader->match_string("standalone") || return 0;
    
    $self->skip_whitespace($reader);
    $reader->match('=') || $self->parser_error(
        "No '=' by standalone declaration", $reader);
    $self->skip_whitespace($reader);
    
    my $quote = $self->quote($reader);
    
    if ($reader->match_string('yes')) {
        $self->{standalone} = 1;
    }
    elsif ($reader->match_string('no')) {
        $self->{standalone} = 0;
    }
    else {
        $self->parser_error("standalone declaration must be 'yes' or 'no'", $reader);
    }
    
    $reader->match($quote) ||
        $self->parser_error("Invalid token in XML declaration", $reader);
    
    return 1;
}

sub EncodingDecl {
    my ($self, $reader) = @_;
    
    $reader->match_string('encoding') || return 0;
    
    $self->skip_whitespace($reader);
    $reader->match('=') || $self->parser_error(
        "No '=' by encoding declaration", $reader);
    $self->skip_whitespace($reader);
    
    my $quote = $self->quote($reader);
    
    my $encoding = '';
    $reader->match($EncNameStart) ||
        $self->parser_error("Invalid encoding name", $reader);
    $encoding .= $reader->matched;
    $reader->consume($EncNameEnd);
    $encoding .= $reader->consumed;
    $reader->set_encoding($encoding);
    
    $reader->match($quote) ||
        $self->parser_error("Invalid token in XML declaration", $reader);
    
    return 1;
}

sub TextDecl {
    my ($self, $reader) = @_;
    
    $reader->match_string('<?xml')
        || return;
    $self->skip_whitespace($reader) || $self->parser_error("No whitespace after text declaration", $reader);
    
    if ($self->VersionInfo($reader)) {
        $self->skip_whitespace($reader) ||
                $self->parser_error("Lack of whitespace after version attribute in text declaration", $reader);
    }
    
    $self->EncodingDecl($reader) ||
        $self->parser_error("Encoding declaration missing from external entity text declaration", $reader);
    
    $self->skip_whitespace($reader);
    
    $reader->match_string('?>') || $self->parser_error("Syntax error", $reader);
    
    return 1;
}

1;
