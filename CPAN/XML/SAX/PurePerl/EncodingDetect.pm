# $Id: EncodingDetect.pm 1097 2004-07-16 12:55:19Z dean $

package XML::SAX::PurePerl; # NB, not ::EncodingDetect!

use strict;

sub encoding_detect {
    my ($parser, $reader) = @_;
    
    my $error = "Invalid byte sequence at start of file";
    
    # BO == Byte Order mark
    if ($reader->match_nocheck("\x00")) {
        # maybe BO-UCS4-be, BO-UCS4-3412, UCS4-be, UCS4-2143, UCS4-3412, UTF-16BE
        if ($reader->match_nocheck("\x00")) {
            # maybe BO-UCS4-be, BO-UCS4-2143, UCS4-be, UCS4-2143
            if ($reader->match_nocheck("\xFE")) {
                if ($reader->match_nonext("\xFF")) {
                    # BO-UCS4-be
                    $reader->set_encoding("UCS-4BE");
                    $reader->next;
                    return;
                }
            }
            elsif ($reader->match_nocheck("\xFF")) {
                if ($reader->match_nonext("\xFE")) {
                    # BO-UCS-4-2143
                    $reader->set_encoding("UCS-4-2143");
                    $reader->next;
                    return;
                }
            }
            elsif ($reader->match_nocheck("\x00")) {
                if ($reader->match_nonext("\x3C")) {
                    # UCS4-be
                    $reader->set_encoding("UCS-4BE");
                    $reader->next;
                    $reader->buffer('<');
                    return;
                }
            }
            elsif ($reader->match_nocheck("\x3C")) {
                if ($reader->match_nonext("\x00")) {
                    # UCS-4-2143
                    $reader->set_encoding("UCS-4-2143");
                    $reader->next;
                    $reader->buffer('<');
                    return;
                }
            }
        }
        elsif ($reader->match_nocheck("\x3C")) {
            # maybe UCS4-3412, UTF-16BE
            if ($reader->match_nocheck("\x00")) {
                if ($reader->match_nonext("\x00")) {
                    # UCS4-3412
                    $reader->set_encoding("UCS-4-3412");
                    $reader->next;
                    # these are parsable chars
                    $reader->buffer("<");
                    return;
                }
                elsif ($reader->match_nonext("\x3F")) {
                    # UTF-16BE
                    $reader->set_encoding("UTF-16BE");
                    # these are parsable chars
                    $reader->buffer("<?");
                    return;
                }
            }
        }
        
        $parser->parser_error($error, $reader);
    }
    elsif ($reader->match_nocheck("\xFF")) {
        # maybe BO-UCS-4LE, UTF-16LE
        if ($reader->match_nocheck("\xFE")) {
            if ($reader->match_nocheck("\x00")) {
                if ($reader->match_nonext("\x00")) {
                    $reader->set_encoding("UCS-4LE");
                    $reader->next;
                    return;
                }
            }
            else {
                my $byte1 = $reader->current;
                $reader->next;
                my $char = chr unpack("v", $byte1 . $reader->current);
                $reader->set_encoding("UTF-16LE");
                $reader->next;
                $reader->buffer($char);
                return;
            }
        }
        
        $parser->parser_error($error, $reader);
    }
    elsif ($reader->match_nocheck("\xFE")) {
        # maybe BO-UCS-4-3412, UTF-16BE
        if ($reader->match_nocheck("\xFF")) {
            if ($reader->match_nocheck("\x00")) {
                if ($reader->match_nonext("\x00")) {
                    $reader->set_encoding("UCS-4-3412");
                    $reader->next;
                    return;
                }
                elsif ($reader->match_nonext("\x3C")) {
                    $reader->set_encoding("UTF-16BE");
                    $reader->next;
                    $reader->buffer("<");
                    return;
                }
            }
        }
        $parser->parser_error($error, $reader);
    }
    elsif ($reader->match_nocheck("\xEF")) {
        if ($reader->match_nocheck("\xBB")) {
            if ($reader->match_nonext("\xBF")) {
                # OK, UTF-8
                $reader->set_encoding("UTF-8");
                $reader->next;
                return;
            }
        }
        $parser->parser_error($error, $reader);
    }
    elsif ($reader->match_nocheck("\x3C")) {
        if ($reader->match_nocheck("\x00")) {
            if ($reader->match_nocheck("\x00")) {
                if ($reader->match_nonext("\x00")) {
                    $reader->set_encoding("UCS-4LE");
                    $reader->next;
                    $reader->buffer("<");
                    return;
                }
            }
            elsif ($reader->match_nocheck("\x3F")) {
                if ($reader->match_nonext("\x00")) {
                    $reader->set_encoding("UTF-16LE");
                    $reader->next;
                    $reader->buffer("<?");
                    return;
                }
            }
        }
        elsif ($reader->match_nocheck("\x3F")) {
            if ($reader->match_nocheck("\x78")) {
                if ($reader->match_nocheck("\x6D")) {
                    # some 7 or 8 bit charset with ASCII chars in right place
                    $reader->buffer("<?xm");
                    return;
                }
                else {
                    $reader->buffer('<?x');
                    return;
                }
            }
            else {
                $reader->buffer('<?');
                return;
            }
        }
        else {
            # assume we have "<tag", and assume UTF-8/ASCII
            $reader->buffer("<");
            return;
        }
    }
    elsif ($reader->match_nocheck("\x4C") && 
            $reader->match_nocheck("\x6F") &&
            $reader->match_nocheck("\xA7") &&
            $reader->match_nonext("\x94"))
    {
        $reader->set_encoding("EBCDIC");
        $reader->next;
        return;
    }
    
    # lets just try parsing it...
    return;
    
    # $parser->parser_error($error, $reader);
}

1;

