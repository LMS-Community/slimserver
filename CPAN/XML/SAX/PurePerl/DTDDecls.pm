# $Id: DTDDecls.pm 1097 2004-07-16 12:55:19Z dean $

package XML::SAX::PurePerl;

use strict;
use XML::SAX::PurePerl::Productions qw($NameChar $SingleChar);

sub elementdecl {
    my ($self, $reader) = @_;
    
    if ($reader->match_string('<!ELEMENT')) {
        $self->skip_whitespace($reader) ||
            $self->parser_error("No whitespace after ELEMENT declaration", $reader);
        
        my $name = $self->Name($reader);
        
        $self->skip_whitespace($reader) ||
            $self->parser_error("No whitespace after ELEMENT's name", $reader);
            
        $self->contentspec($reader, $name);
        
        $self->skip_whitespace($reader);
        
        $reader->match('>') ||
            $self->parser_error("Closing angle bracket not found on ELEMENT declaration", $reader);
        
        return 1;
    }
    
    return 0;
}

sub contentspec {
    my ($self, $reader, $name) = @_;
    
    my $model;
    if ($reader->match_string('EMPTY')) {
        $model = 'EMPTY';
    }
    elsif ($reader->match_string('ANY')) {
        $model = 'ANY';
    }
    else {
        $model = $self->Mixed_or_children($reader);
    }

    if ($model) {
        # call SAX callback now.
        $self->element_decl({Name => $name, Model => $model});
        return 1;
    }
    
    $self->parser_error("contentspec not found in ELEMENT declaration", $reader);
}

sub Mixed_or_children {
    my ($self, $reader) = @_;

    my $model;
    if ($reader->match('(')) {
        $model = '(';
        
        $self->skip_whitespace($reader);
        
        if ($reader->match_string('#PCDATA')) {
            return $self->Mixed($reader);
        }

        # not matched - must be Children
        $reader->buffer('(');
        return $self->children($reader);
    }

    return;
}

# Mixed ::= ( '(' S* PCDATA ( S* '|' S* QName )* S* ')' '*' )
#               | ( '(' S* PCDATA S* ')' )
sub Mixed {
    my ($self, $reader) = @_;

    # Mixed_or_children already matched '(' S* '#PCDATA'

    my $model = '(#PCDATA';
            
    $self->skip_whitespace($reader);

    my %seen;
    
    while ($reader->match('|')) {
        $self->skip_whitespace($reader);

        my $name = $self->Name($reader) || 
            $self->parser_error("No 'Name' after Mixed content '|'", $reader);

        if ($seen{$name}) {
            $self->parser_error("Element '$name' has already appeared in this group", $reader);
        }
        $seen{$name}++;

        $model .= "|$name";
        
        $self->skip_whitespace($reader);
    }

    $reader->match(')') || $self->parser_error("no closing bracket on mixed content", $reader);

    $model .= ")";

    if ($reader->match('*')) {
        $model .= "*";
    }
    
    return $model;
}

# [[47]] Children ::= ChoiceOrSeq Cardinality?
# [[48]] Cp ::= ( QName | ChoiceOrSeq ) Cardinality?
#       ChoiceOrSeq ::= '(' S* Cp ( Choice | Seq )? S* ')'
# [[49]] Choice ::= ( S* '|' S* Cp )+
# [[50]] Seq    ::= ( S* ',' S* Cp )+
#        // Children ::= (Choice | Seq) Cardinality?
#        // Cp ::= ( QName | Choice | Seq) Cardinality?
#        // Choice ::= '(' S* Cp ( S* '|' S* Cp )+ S* ')'
#        // Seq    ::= '(' S* Cp ( S* ',' S* Cp )* S* ')'
# [[51]] Mixed ::= ( '(' S* PCDATA ( S* '|' S* QName )* S* ')' MixedCardinality )
#                | ( '(' S* PCDATA S* ')' )
#        Cardinality ::= '?' | '+' | '*'
#        MixedCardinality ::= '*'
sub children {
    my ($self, $reader) = @_;
    
    return $self->ChoiceOrSeq($reader) . $self->Cardinality($reader);    
}

sub ChoiceOrSeq {
    my ($self, $reader) = @_;
    
    $reader->match('(') || $self->parser_error("choice/seq contains no opening bracket", $reader);
    
    my $model = '(';
    
    $self->skip_whitespace($reader);

    $model .= $self->Cp($reader);

    if (my $choice = $self->Choice($reader)) {
        $model .= $choice;
    }
    else {
        $model .= $self->Seq($reader);
    }

    $self->skip_whitespace($reader);

    $reader->match(')') || $self->parser_error("choice/seq contains no closing bracket", $reader);

    $model .= ')';
    
    return $model;
}

sub Cardinality {
    my ($self, $reader) = @_;
    # cardinality is always optional
    if ($reader->match('?')) {
        return '?';
    }
    if ($reader->match('+')) {
        return '+';
    }
    if ($reader->match('*')) {
        return '*';
    }
    return '';
}

sub Cp {
    my ($self, $reader) = @_;

    my $model;
    if (my $name = $self->Name($reader)) {
        return $name . $self->Cardinality($reader);
    }
    return $self->ChoiceOrSeq($reader) . $self->Cardinality($reader);
}

sub Choice {
    my ($self, $reader) = @_;
    
    my $model = '';
    $self->skip_whitespace($reader);
    while ($reader->match('|')) {
        $self->skip_whitespace($reader);
        $model .= '|';
        $model .= $self->Cp($reader);
        $self->skip_whitespace($reader);
    }

    return $model;
}

sub Seq {
    my ($self, $reader) = @_;
    
    my $model = '';
    $self->skip_whitespace($reader);
    while ($reader->match(',')) {
        $self->skip_whitespace($reader);
        $model .= ',';
        $model .= $self->Cp($reader);
        $self->skip_whitespace($reader);
    }

    return $model;
}

sub AttlistDecl {
    my ($self, $reader) = @_;
    
    if ($reader->match_string('<!ATTLIST')) {
        # It's an attlist
        
        $self->skip_whitespace($reader) || 
            $self->parser_error("No whitespace after ATTLIST declaration", $reader);
        my $name = $self->Name($reader);

        $self->AttDefList($reader, $name);

        $self->skip_whitespace($reader);
        $reader->match('>') ||
            $self->parser_error("Closing angle bracket not found on ATTLIST declaration", $reader);
        return 1;
    }
    
    return 0;
}

sub AttDefList {
    my ($self, $reader, $name) = @_;

    1 while $self->AttDef($reader, $name);
}

sub AttDef {
    my ($self, $reader, $el_name) = @_;

    $self->skip_whitespace($reader) || return 0;
    my $att_name = $self->Name($reader) || return 0;
    $self->skip_whitespace($reader) || 
        $self->parser_error("No whitespace after Name in attribute definition", $reader);
    my $att_type = $self->AttType($reader);

    $self->skip_whitespace($reader) ||
        $self->parser_error("No whitespace after AttType in attribute definition", $reader);
    my ($default, $value) = $self->DefaultDecl($reader);
    
    # fire SAX event here!
    $self->attribute_decl({
            eName => $el_name, 
            aName => $att_name, 
            Type => $att_type, 
            ValueDefault => $default, 
            Value => $value,
            });
    return 1;
}

sub AttType {
    my ($self, $reader) = @_;

    return $self->StringType($reader) ||
            $self->TokenizedType($reader) ||
            $self->EnumeratedType($reader) ||
            $self->parser_error("Can't match AttType", $reader);
}

sub StringType {
    my ($self, $reader) = @_;
    if ($reader->match_string('CDATA')) {
        return 'CDATA';
    }
    return;
}

sub TokenizedType {
    my ($self, $reader) = @_;
    if ($reader->match_string('IDREFS')) {
        return 'IDREFS';
    }
    if ($reader->match_string('IDREF')) {
        return 'IDREF';
    }
    if ($reader->match_string('ID')) {
        return 'ID';
    }
    if ($reader->match_string('ENTITIES')) {
        return 'ENTITIES';
    }
    if ($reader->match_string('ENTITY')) {
        return 'ENTITY';
    }
    if ($reader->match_string('NMTOKENS')) {
        return 'NMTOKENS';
    }
    if ($reader->match_string('NMTOKEN')) {
        return 'NMTOKEN';
    }
    return;
}

sub EnumeratedType {
    my ($self, $reader) = @_;
    return $self->NotationType($reader) || $self->Enumeration($reader);
}

sub NotationType {
    my ($self, $reader) = @_;
    if ($reader->match_string('NOTATION')) {
        $self->skip_whitespace($reader) ||
            $self->parser_error("No whitespace after NOTATION", $reader);
        $reader->match('(') ||
            $self->parser_error("No opening bracket in notation section", $reader);
        $self->skip_whitespace($reader);
        my $model = 'NOTATION (';
        my $name = $self->Name($reader) ||
            $self->parser_error("No name in notation section", $reader);
        $model .= $name;
        $self->skip_whitespace($reader);
        while ($reader->match('|')) {
            $model .= '|';
            $self->skip_whitespace($reader);
            my $name = $self->Name($reader) ||
                $self->parser_error("No name in notation section", $reader);
            $model .= $name;
            $self->skip_whitespace($reader);
        }
        $reader->match(')') || 
            $self->parser_error("No closing bracket in notation section", $reader);
        $model .= ')';

        return $model;
    }
    return;
}

sub Enumeration {
    my ($self, $reader) = @_;
    if ($reader->match('(')) {
        $self->skip_whitespace($reader);
        my $model = '(';
        my $nmtoken = $self->Nmtoken($reader) ||
            $self->parser_error("No Nmtoken in enumerated declaration", $reader);
        $model .= $nmtoken;
        $self->skip_whitespace($reader);
        while ($reader->match('|')) {
            $model .= '|';
            $self->skip_whitespace($reader);
            my $nmtoken = $self->Nmtoken($reader) ||
                $self->parser_error("No Nmtoken in enumerated declaration", $reader);
            $model .= $nmtoken;
            $self->skip_whitespace($reader);
        }
        $reader->match(')') ||
            $self->parser_error("No closing bracket in enumerated declaration", $reader);
        $model .= ')';

        return $model;
    }
    return;
}

sub Nmtoken {
    my ($self, $reader) = @_;
    $reader->consume($NameChar);
    return $reader->consumed;
}

sub DefaultDecl {
    my ($self, $reader) = @_;
    if ($reader->match_string('#REQUIRED')) {
        return '#REQUIRED';
    }
    if ($reader->match_string('#IMPLIED')) {
        return '#IMPLIED';
    }
    my $model = '';
    if ($reader->match_string('#FIXED')) {
        $self->skip_whitespace($reader) || $self->parser_error(
                "no whitespace after FIXED specifier", $reader);
        my $value = $self->AttValue($reader);
        return "#FIXED", $value;
    }
    my $value = $self->AttValue($reader);
    return undef, $value;
}

sub EntityDecl {
    my ($self, $reader) = @_;
    
    if ($reader->match_string('<!ENTITY')) {
        $self->skip_whitespace($reader) || $self->parser_error(
            "No whitespace after ENTITY declaration", $reader);
        
        $self->PEDecl($reader) || $self->GEDecl($reader);
        
        $self->skip_whitespace($reader);
        $reader->match('>') || $self->parser_error("No closing '>' in entity definition", $reader);
        
        return 1;
    }
    return 0;
}

sub GEDecl {
    my ($self, $reader) = @_;

    my $name = $self->Name($reader) || $self->parser_error("No entity name given", $reader);
    $self->skip_whitespace($reader) || $self->parser_error("No whitespace after entity name", $reader);

    # TODO: ExternalID calls lexhandler method. Wrong place for it.
    my $value;
    if ($value = $self->ExternalID($reader)) {
        $value .= $self->NDataDecl($reader);
    }
    else {
        $value = $self->EntityValue($reader);
    }

    if ($self->{ParseOptions}{entities}{$name}) {
        warn("entity $name already exists\n");
    } else {
        $self->{ParseOptions}{entities}{$name} = 1;
        $self->{ParseOptions}{expanded_entity}{$name} = $value; # ???
    }
    # do callback?
    return 1;
}

sub PEDecl {
    my ($self, $reader) = @_;
    
    $reader->match('%') || return 0;
    $self->skip_whitespace($reader) || $self->parser_error("No whitespace after parameter entity marker", $reader);
    my $name = $self->Name($reader) || $self->parser_error("No parameter entity name given", $reader);
    $self->skip_whitespace($reader) || $self->parser_error("No whitespace after parameter entity name", $reader);
    my $value = $self->ExternalID($reader) ||
                $self->EntityValue($reader) ||
                $self->parser_error("PE is not a value or an external resource", $reader);
    # do callback?
    return 1;
}

my $quotre = qr/[^%&\"]/;
my $aposre = qr/[^%&\']/;

sub EntityValue {
    my ($self, $reader) = @_;
    
    my $quote = '"';
    my $re = $quotre;
    if (!$reader->match($quote)) {
        $quote = "'";
        $re = $aposre;
        $reader->match($quote) ||
                $self->parser_error("Not a quote character", $reader);
    }
    
    my $value = '';
    
    while (1) {
        if ($reader->consume($re)) {
            $value .= $reader->consumed;
        }
        elsif ($reader->match('&')) {
            # if it's a char ref, expand now:
            if ($reader->match('#')) {
                my $char;
                my $ref;
                if ($reader->match('x')) {
                    $reader->consume(qr/[0-9a-fA-F]/) ||
                        $self->parser_error("Hex character reference contains illegal characters", $reader);
                    $ref = $reader->consumed;
                    $char = chr_ref(hex($ref));
                    $ref = "x$ref";
                }
                else {
                    $reader->consume(qr/[0-9]/) ||
                        $self->parser_error("Decimal character reference contains illegal characters", $reader);
                    $ref = $reader->consumed;
                    $char = chr($ref);
                }
                $reader->match(';') ||
                    $self->parser_error("No semi-colon found after character reference", $reader);
                if ($char !~ $SingleChar) { # match a single character
                    $self->parser_error("Character reference '&#$ref;' refers to an illegal XML character ($char)", $reader);
                }
                $value .= $char;
            }
            else {
                # entity refs in entities get expanded later, so don't parse now.
                $value .= '&';
            }
        }
        elsif ($reader->match('%')) {
            $value .= $self->PEReference($reader);
        }
        elsif ($reader->match($quote)) {
            # end of attrib
            last;
        }
        else {
            $self->parser_error("Invalid character in attribute value", $reader);
        }
    }
    
    return $value;
}

sub NDataDecl {
    my ($self, $reader) = @_;
    $self->skip_whitespace($reader) || return '';
    $reader->match_string("NDATA") || return '';
    $self->skip_whitespace($reader) || $self->parser_error("No whitespace after NDATA declaration", $reader);
    my $name = $self->Name($reader) || $self->parser_error("NDATA declaration lacks a proper Name", $reader);
    return " NDATA $name";
}

sub NotationDecl {
    my ($self, $reader) = @_;
    
    if ($reader->match_string('<!NOTATION')) {
        $self->skip_whitespace($reader) ||
            $self->parser_error("No whitespace after NOTATION declaration", $reader);
        $reader->consume(qr/[^>]/); # FIXME
        $reader->match('>'); # FIXME
        $self->notation_decl({Name => "FIXME", SystemId => "FIXME", PublicId => "FIXME" });
        return 1;
    }
    return 0;
}

1;
