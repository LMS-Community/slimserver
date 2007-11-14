# $Id: PurePerl.pm 1097 2004-07-16 12:55:19Z dean $

package XML::SAX::PurePerl;

use strict;
use vars qw/$VERSION/;

$VERSION = '0.90';

use XML::SAX::PurePerl::Productions qw($Any $CharMinusDash $SingleChar);
use XML::SAX::PurePerl::Reader;
use XML::SAX::PurePerl::EncodingDetect ();
use XML::SAX::Exception;
use XML::SAX::PurePerl::DocType ();
use XML::SAX::PurePerl::DTDDecls ();
use XML::SAX::PurePerl::XMLDecl ();
use XML::SAX::DocumentLocator ();
use XML::SAX::Base ();
use XML::SAX qw(Namespaces);
use XML::NamespaceSupport ();
use IO::File;

if ($] < 5.006) {
    require XML::SAX::PurePerl::NoUnicodeExt;
}
else {
    require XML::SAX::PurePerl::UnicodeExt;
}

use vars qw(@ISA);
@ISA = ('XML::SAX::Base');

my %int_ents = (
        amp => '&',
        lt => '<',
        gt => '>',
        quot => '"',
        apos => "'",
        );

my $xmlns_ns = "http://www.w3.org/2000/xmlns/";
my $xml_ns = "http://www.w3.org/XML/1998/namespace";

use Carp;
sub _parse_characterstream {
    my $self = shift;
    my ($fh) = @_;
    confess("CharacterStream is not yet correctly implemented");
    my $reader = XML::SAX::PurePerl::Reader::Stream->new($fh);
    return $self->_parse($reader);
}

sub _parse_bytestream {
    my $self = shift;
    my ($fh) = @_;
    my $reader = XML::SAX::PurePerl::Reader::Stream->new($fh);
    return $self->_parse($reader);
}

sub _parse_string {
    my $self = shift;
    my ($str) = @_;
    my $reader = XML::SAX::PurePerl::Reader::String->new($str);
    return $self->_parse($reader);
}

sub _parse_systemid {
    my $self = shift;
    my ($uri) = @_;
    my $reader = XML::SAX::PurePerl::Reader::URI->new($uri);
    return $self->_parse($reader);
}

sub _parse {
    my ($self, $reader) = @_;
    
    $reader->public_id($self->{ParseOptions}{Source}{PublicId});
    $reader->system_id($self->{ParseOptions}{Source}{SystemId});
    $reader->next;

    $self->{NSHelper} = XML::NamespaceSupport->new({xmlns => 1});

    $self->set_document_locator(
        XML::SAX::DocumentLocator->new(
            sub { $reader->public_id },
            sub { $reader->system_id },
            sub { $reader->line },
            sub { $reader->column },
        ),
    );
    
    $self->start_document({});

    if (defined $self->{ParseOptions}{Source}{Encoding}) {
        $reader->set_encoding($self->{ParseOptions}{Source}{Encoding});
    }
    else {
        $self->encoding_detect($reader);
    }
    
    # parse a document
    $self->document($reader);
    
    return $self->end_document({});
}

sub parser_error {
    my $self = shift;
    my ($error, $reader) = @_;
    
# warn("parser error: $error from ", $reader->line, " : ", $reader->column, "\n");
    my $exception = XML::SAX::Exception::Parse->new(
                Message => $error,
                ColumnNumber => $reader->column,
                LineNumber => $reader->line,
                PublicId => $reader->public_id,
                SystemId => $reader->system_id,
            );

    $self->fatal_error($exception);
    $exception->throw;
}

sub document {
    my ($self, $reader) = @_;
    
    # document ::= prolog element Misc*
    
    $self->prolog($reader);
    $self->element($reader) ||
        $self->parser_error("Document requires an element", $reader);
    
    while(!$reader->eof) {
        $self->Misc($reader) || 
                $self->parser_error("Only Comments, PIs and whitespace allowed at end of document", $reader);
    }
}

sub prolog {
    my ($self, $reader) = @_;
    
    $self->XMLDecl($reader);
    
    # consume all misc bits
    1 while($self->Misc($reader));
    
    if ($self->doctypedecl($reader)) {
        while (!$reader->eof) {
            $self->Misc($reader) || last;
        }
    }
}

sub element {
    my ($self, $reader) = @_;
    
    if ($reader->match_char('<')) {
        my $name = $self->Name($reader) ||
                $self->parser_error("Invalid element name", $reader);

        my %attribs;
        
        while( my ($k, $v) = $self->Attribute($reader) ) {
            $attribs{$k} = $v;
        }
        
        $self->skip_whitespace($reader);
        
        my $content;
        unless ($reader->match_sequence('/', '>')) {
            $reader->match_char('>') ||
                $self->parser_error("No close element tag", $reader);
            
            # only push onto _el_stack if not an empty element
            push @{$self->{_el_stack}}, $name;
            $content++;
        }
        
        # Namespace processing
        $self->{NSHelper}->push_context;
        my @new_ns;
#        my %attrs = @attribs;
#        while (my ($k,$v) = each %attrs) {
        if ($self->get_feature(Namespaces)) {
            while ( my ($k, $v) = each %attribs ) {
                if ($k =~ m/^xmlns(:(.*))?$/) {
                    my $prefix = $2 || '';
                    $self->{NSHelper}->declare_prefix($prefix, $v);
                    my $ns = 
                        {
                            Prefix       => $prefix,
                            NamespaceURI => $v,
                        };
                    push @new_ns, $ns;
                    $self->SUPER::start_prefix_mapping($ns);
                }
            }
        }

        # Create element object and fire event
        my %attrib_hash;
        while (my ($name, $value) = each %attribs ) {
            # TODO normalise value here
            my ($ns, $prefix, $lname);
            if ($self->get_feature(Namespaces)) {
                ($ns, $prefix, $lname) = $self->{NSHelper}->process_attribute_name($name);
            }
            $ns ||= ''; $prefix ||= ''; $lname ||= '';
            $attrib_hash{"{$ns}$lname"} = {
                Name => $name,
                LocalName => $lname,
                Prefix => $prefix,
                NamespaceURI => $ns,
                Value => $value,
            };
        }
        
        %attribs = (); # lose the memory since we recurse deep
        
        my ($ns, $prefix, $lname);
        if ($self->get_feature(Namespaces)) {
            ($ns, $prefix, $lname) = $self->{NSHelper}->process_element_name($name);
        }
        $ns ||= ''; $prefix ||= ''; $lname ||= '';

        my $el = 
        {
            Name => $name,
            LocalName => $lname,
            Prefix => $prefix,
            NamespaceURI => $ns,
            Attributes => \%attrib_hash,
        };
        $self->start_element($el);
        
        # warn("($name\n");
        
        if ($content) {
            $self->content($reader);
            
            $reader->match_sequence('<', '/') || $self->parser_error("No close tag marker", $reader);
            my $end_name = $self->Name($reader);
            $end_name eq $name || $self->parser_error("End tag mismatch ($end_name != $name)", $reader);
            $self->skip_whitespace($reader);
            $reader->match_char('>') || $self->parser_error("No close '>' on end tag", $reader);
        }
        
        my %end_el = %$el;
        delete $end_el{Attributes};
        $self->end_element(\%end_el);

        for my $ns (@new_ns) {
            $self->end_prefix_mapping($ns);
        }
        $self->{NSHelper}->pop_context;
        
        return 1;
    }
    
    return 0;
}

sub content {
    my ($self, $reader) = @_;
    
    $self->CharData($reader);
    
    while (1) {
        if ($reader->match_sequence('<', '/')) {
            $reader->buffer('</');
            return 1;
        }
        elsif ( $self->Reference($reader) ||
                $self->CDSect($reader) || 
                $self->PI($reader) || 
                $self->Comment($reader) ||
                $self->element($reader) 
               )
        {
            $self->CharData($reader);
            next;
        }
        else {
            last;
        }
    }
    
    return 1;
}

sub CDSect {
    my ($self, $reader) = @_;
    
    if ($reader->match_sequence('<', '!', '[', 'C', 'D', 'A', 'T', 'A', '[')) {
        $self->start_cdata({});
        my $chars = '';
        while (1) {
            if ($reader->eof) {
                $self->parser_error("EOF looking for CDATA section end", $reader);
            }
            $reader->consume_not(']');
            $chars .= $reader->consumed;
            if ($reader->match_char(']')) {
                if ($reader->match_sequence(']', '>')) {
                    # end of CDATA section
                    
                    $self->characters({Data => $chars});
                    last;
                }
                $chars .= ']';
            }
        }
        $self->end_cdata({});
        return 1;
    }
    
    return 0;
}

sub CharData {
    my ($self, $reader) = @_;
    
    my $chars = '';
    while (1) {
        $reader->consume_not('<', '&', ']');
        $chars .= $reader->consumed;
        if ($reader->match_char(']')) {
            if ($reader->match_sequence(']', '>')) {
                $self->parser_error("String ']]>' not allowed in character data", $reader);
            }
            else {
                $chars .= ']';
            }
            next;
        }
        last;
    }
    
    $self->characters({ Data => $chars }) if length($chars);
}

sub Misc {
    my ($self, $reader) = @_;
    if ($self->Comment($reader)) {
        return 1;
    }
    elsif ($self->PI($reader)) {
        return 1;
    }
    elsif ($self->skip_whitespace($reader)) {
        return 1;
    }
    
    return 0;
}

sub Reference {
    my ($self, $reader) = @_;
    
    if (!$reader->match_char('&')) {
        return 0;
    }
    
    if ($reader->match_char('#')) {
        # CharRef
        my $char;
        my $ref;
        if ($reader->match_char('x')) {
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
            $char = chr_ref($ref);
        }
        $reader->match_char(';') ||
                $self->parser_error("No semi-colon found after character reference", $reader);
        if ($char !~ $SingleChar) { # match a single character
            $self->parser_error("Character reference &#$ref; refers to an illegal XML character ($char)", $reader);
        }
        $self->characters({ Data => $char });
        return 1;
    }
    else {
        # EntityRef
        my $name = $self->Name($reader);
        $reader->match_char(';') ||
                $self->parser_error("No semi-colon found after entity name", $reader);
        
        # expand it
        if ($self->_is_entity($name)) {
            
            if ($self->_is_external($name)) {
                my $value = $self->_get_entity($name);
                my $ent_reader = XML::SAX::PurePerl::Reader::URI->new($value);
                $self->encoding_detect($ent_reader);
                $self->extParsedEnt($ent_reader);
            }
            else {
                my $value = $self->_stringify_entity($name);
                my $ent_reader = XML::SAX::PurePerl::Reader::String->new($value);
                $self->content($ent_reader);
            }
            return 1;
        }
        elsif (_is_internal($name)) {
            $self->characters({ Data => $int_ents{$name} });
            return 1;
        }
        else {
            $self->parser_error("Undeclared entity", $reader);
        }
    }
}

sub AttReference {
    # a reference in an attribute value.
    my ($self, $reader) = @_;
    
    if ($reader->match_char('#')) {
        # CharRef
        my $char;
        my $ref;
        if ($reader->match_char('x')) {
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
            $char = chr_ref($ref);
        }
        $reader->match_char(';') ||
                $self->parser_error("No semi-colon found after character reference", $reader);
        if ($char !~ $SingleChar) { # match a single character
            $self->parser_error("Character reference '&#$ref;' refers to an illegal XML character ($char)", $reader);
        }
        return $char;
    }
    else {
        # EntityRef
        my $name = $self->Name($reader);
        $reader->match_char(';') ||
                $self->parser_error("No semi-colon found after entity name", $reader);
        
        # expand it
        if ($self->_is_entity($name)) {
            if ($self->_is_external($name)) {
                $self->parser_error("No external entity references allowed in attribute values", $reader);
            }
            else {
                my $value = $self->_stringify_entity($name);
                return $value;
            }
        }
        elsif (_is_internal($name)) {
            return $int_ents{$name};
        }
        else {
            $self->parser_error("Undeclared entity '$name'", $reader);
        }
    }
        
}

sub extParsedEnt {
    my ($self, $reader) = @_;
    
    $self->TextDecl($reader);
    $self->content($reader);
}

sub _is_internal {
    my $e = shift;
    return 1 if $e eq 'amp' || $e eq 'lt' || $e eq 'gt' || $e eq 'quot' || $e eq 'apos';
    return 0;
}

sub _is_external {
    my ($self, $name) = @_;
# TODO: Fix this to use $reader to store the entities perhaps.
    if ($self->{ParseOptions}{external_entities}{$name}) {
        return 1;
    }
    return ;
}

sub _is_entity {
    my ($self, $name) = @_;
# TODO: ditto above
    if (exists $self->{ParseOptions}{entities}{$name}) {
        return 1;
    }
    return 0;
}

sub _stringify_entity {
    my ($self, $name) = @_;
# TODO: ditto above
    if (exists $self->{ParseOptions}{expanded_entity}{$name}) {
        return $self->{ParseOptions}{expanded_entity}{$name};
    }
    # expand
    my $reader = XML::SAX::PurePerl::Reader::URI->new($self->{ParseOptions}{entities}{$name});
    $reader->consume(qr/./);
    return $self->{ParseOptions}{expanded_entity}{$name} = $reader->consumed;
}

sub _get_entity {
    my ($self, $name) = @_;
# TODO: ditto above
    return $self->{ParseOptions}{entities}{$name};
}

sub skip_whitespace {
    my ($self, $reader) = @_;
    
    my $found = 0;
    while (1) {
        if ($reader->match_char("\x20") ||
            $reader->match_char("\x0A") ||
            $reader->match_char("\x0D") ||
            $reader->match_char("\x09"))
        {
            $found++;
        }
        else {
            last;
        }
    }
    return $found;
}

sub Attribute {
    my ($self, $reader) = @_;
    
    $self->skip_whitespace($reader) || return;
    if ($reader->match_sequence('/', '>')) {
        $reader->buffer("/>");
        return;
    }
    if ($reader->match_char(">")) {
        $reader->buffer(">");
        return;
    }
    if (my $name = $self->Name($reader)) {
        $self->skip_whitespace($reader);
        $reader->match_char('=') ||
                $self->parser_error("No '=' in Attribute", $reader);
        $self->skip_whitespace($reader);
        my $value = $self->AttValue($reader);

        if (!$self->cdata_attrib($name)) {
            $value =~ s/^\x20*//; # discard leading spaces
            $value =~ s/\x20*$//; # discard trailing spaces
            $value =~ s/ {1,}/ /g; # all >1 space to single space
        }
        
        return $name, $value;
    }
    
    return;
}

sub cdata_attrib {
    # TODO implement this!
    return 0;
}

sub AttValue {
    my ($self, $reader) = @_;
    
    my $quote = '"';
    if (!$reader->match_char($quote)) {
        $quote = "'";
        $reader->match_char($quote) ||
                $self->parser_error("Not a quote character", $reader);
    }
    
    my $value = '';
    
    while (1) {
        if ($reader->consume_not('<', '&', $quote)) {
            my $to_append = $reader->consumed;
            $to_append =~ s/[\x09\x0A\x0D]/\x20/g; # Attrib value normalize
            $value .= $to_append;
        }
        elsif ($reader->match_char('&')) {
            $value .= $self->AttReference($reader);
        }
        elsif ($reader->match_char($quote)) {
            # end of attrib
            last;
        }
        else {
            $self->parser_error("Invalid character in attribute value", $reader);
        }
    }

    return $value;
}

sub Comment {
    my ($self, $reader) = @_;
    
    if ($reader->match_sequence('<', '!', '-', '-')) {
        my $comment_str = '';
        while (1) {
            if ($reader->match_char('-')) {
                if ($reader->match_char('-')) {
                    $reader->match_char('>') ||
                        $self->parser_error("Invalid string in comment field", $reader);
                    last;
                }
                $comment_str .= '-';
                $reader->consume($CharMinusDash) ||
                    $self->parser_error("Invalid string in comment field", $reader);
                $comment_str .= $reader->consumed;
            }
            elsif ($reader->consume($CharMinusDash)) {
                $comment_str .= $reader->consumed;
            }
            else {
                $self->parser_error("Invalid string in comment field", $reader);
            }
        }
        
        $self->comment({ Data => $comment_str });
        
        return 1;
    }
    return 0;
}

sub PI {
    my ($self, $reader) = @_;
    if ($reader->match_sequence('<', '?')) {
        my ($target, $data);
        $target = $self->Name($reader) ||
            $self->parser_error("PI has no target", $reader);
        if ($self->skip_whitespace($reader)) {
            while (1) {
                if ($reader->match_sequence('?', '>')) {
                    last;
                }
                elsif ($reader->match_re($Any)) {
                    $data .= $reader->matched;
                }
                else {
                    last;
                }
            }
        }
        else {
            $reader->match_sequence('?', '>') ||
                $self->parser_error("PI closing sequence not found", $reader);
        }
        $self->processing_instruction({ Target => $target, Data => $data });
        
        return 1;
    }
    return 0;
}

sub Name {
    my ($self, $reader) = @_;
    
    return $reader->consume_name();
}

sub quote {
    my ($self, $reader) = @_;
    my $quote = '"';
    
    if (!$reader->match_char($quote)) {
        $quote = "'";
        $reader->match_char($quote) ||
            $self->parser_error("Invalid quote token", $reader);
    }
    return $quote;
}

1;
__END__

=head1 NAME

XML::SAX::PurePerl - Pure Perl XML Parser with SAX2 interface

=head1 SYNOPSIS

  use XML::Handler::Foo;
  use XML::SAX::PurePerl;
  my $handler = XML::Handler::Foo->new();
  my $parser = XML::SAX::PurePerl->new(Handler => $handler);
  $parser->parse_uri("myfile.xml");

=head1 DESCRIPTION

This module implements an XML parser in pure perl. It is written around the
upcoming perl 5.8's unicode support and support for multiple document 
encodings (using the PerlIO layer), however it has been ported to work with
ASCII/UTF8 documents under lower perl versions.

The SAX2 API is described in detail at http://sourceforge.net/projects/perl-xml/, in
the CVS archive, under libxml-perl/docs. Hopefully those documents will be in a
better location soon.

Please refer to the SAX2 documentation for how to use this module - it is merely a
front end to SAX2, and implements nothing that is not in that spec (or at least tries
not to - please email me if you find errors in this implementation).

=head1 BUGS

XML::SAX::PurePerl is B<slow>. Very slow. I suggest you use something else
in fact. However it is great as a fallback parser for XML::SAX, where the
user might not be able to install an XS based parser or C library.

Currently lots, probably. At the moment the weakest area is parsing DOCTYPE declarations,
though the code is in place to start doing this. Also parsing parameter entity
references is causing me much confusion, since it's not exactly what I would call
trivial, or well documented in the XML grammar. XML documents with internal subsets
are likely to fail.

I am however trying to work towards full conformance using the Oasis test suite.

=head1 AUTHOR

Matt Sergeant, matt@sergeant.org. Copyright 2001.

Please report all bugs to the Perl-XML mailing list at perl-xml@listserv.activestate.com.

=head1 LICENSE

This is free software. You may use it or redistribute it under the same terms as
Perl 5.7.2 itself.

=cut

