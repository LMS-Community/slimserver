########################################################################
# Writer.pm - write an XML document.
# Copyright (c) 1999 by Megginson Technologies.
# Copyright (c) 2004, 2005 by Joseph Walton <joe@kafsemo.org>.
# No warranty.  Commercial and non-commercial use freely permitted.
#
# $Id: /mirror/slim/trunk/server/CPAN/XML/Writer.pm 12555 2006-05-04T20:40:11.700353Z dsully  $
########################################################################

package XML::Writer;

require 5.004;

use strict;
use vars qw($VERSION);
use Carp;
use IO::Handle;
$VERSION = "0.600";



########################################################################
# Constructor.
########################################################################

#
# Public constructor.
#
# This actually does most of the work of the module: it defines closures
# for all of the real processing, and selects the appropriate closures
# to use based on the value of the UNSAFE parameter.  The actual methods
# are just stubs.
#
sub new {
  my ($class, %params) = (@_);

                                # If the user wants namespaces,
                                # intercept the request here; it will
                                # come back to this constructor
                                # from within XML::Writer::Namespaces::new()
  if ($params{NAMESPACES}) {
    delete $params{NAMESPACES};
    return new XML::Writer::Namespaces(%params);
  }

                                # Set up $self and basic parameters
  my $self;
  my $output;
  my $unsafe = $params{UNSAFE};
  my $newlines = $params{NEWLINES};
  my $dataMode = $params{DATA_MODE};
  my $dataIndent = $params{DATA_INDENT} || 0;

                                # If the NEWLINES parameter is specified,
                                # set the $nl variable appropriately
  my $nl = '';
  if ($newlines) {
    $nl = "\n";
  }

  my $outputEncoding = $params{ENCODING};
  my ($checkUnencodedRepertoire, $escapeEncoding);
  if (lc($outputEncoding) eq 'us-ascii') {
    $checkUnencodedRepertoire = \&_croakUnlessASCII;
    $escapeEncoding = \&_escapeASCII;
  } else {
    my $doNothing = sub {};
    $checkUnencodedRepertoire = $doNothing;
    $escapeEncoding = $doNothing;
  }

                                # Parse variables
  my @elementStack = ();
  my $elementLevel = 0;
  my %seen = ();

  my $hasData = 0;
  my @hasDataStack = ();
  my $hasElement = 0;
  my @hasElementStack = ();
  my $hasHeading = 0; # Does this document have anything before the first element?

  #
  # Private method to show attributes.
  #
  my $showAttributes = sub {
    my $atts = $_[0];
    my $i = 1;
    while ($atts->[$i]) {
      my $aname = $atts->[$i++];
      my $value = _escapeLiteral($atts->[$i++]);
      $value =~ s/\x0a/\&#10\;/g;
      &{$escapeEncoding}($value);
      $output->print(" $aname=\"$value\"");
    }
  };

                                # Method implementations: the SAFE_
                                # versions perform error checking
                                # and then call the regular ones.
  my $end = sub {
    $output->print("\n");
  };

  my $SAFE_end = sub {
    if (!$seen{ELEMENT}) {
      croak("Document cannot end without a document element");
    } elsif ($elementLevel > 0) {
      croak("Document ended with unmatched start tag(s): @elementStack");
    } else {
      @elementStack = ();
      $elementLevel = 0;
      %seen = ();
      &{$end};
    }
  };

  my $xmlDecl = sub {
    my ($encoding, $standalone) = (@_);
    if ($standalone && $standalone ne 'no') {
      $standalone = 'yes';
    }

    # Only include an encoding if one has been explicitly supplied,
    #  either here or on construction. Allow the empty string
    #  to suppress it.
    if (!defined($encoding)) {
      $encoding = $outputEncoding;
    }
    $output->print("<?xml version=\"1.0\"");
    if ($encoding) {
      $output->print(" encoding=\"$encoding\"");
    }
    if ($standalone) {
      $output->print(" standalone=\"$standalone\"");
    }
    $output->print("?>\n");
    $hasHeading = 1;
  };

  my $SAFE_xmlDecl = sub {
    if ($seen{ANYTHING}) {
      croak("The XML declaration is not the first thing in the document");
    } else {
      $seen{ANYTHING} = 1;
      $seen{XMLDECL} = 1;
      &{$xmlDecl};
    }
  };

  my $pi = sub {
    my ($target, $data) = (@_);
    if ($data) {
      $output->print("<?$target $data?>");
    } else {
      $output->print("<?$target?>");
    }
    if ($elementLevel == 0) {
      $output->print("\n");
      $hasHeading = 1;
    }
  };

  my $SAFE_pi = sub {
    my ($name, $data) = (@_);
    $seen{ANYTHING} = 1;
    if (($name =~ /^xml/i) && ($name !~ /^xml-stylesheet$/i)) {
      carp("Processing instruction target begins with 'xml'");
    } 

    if ($name =~ /\?\>/ || (defined($data) && $data =~ /\?\>/)) {
      croak("Processing instruction may not contain '?>'");
    } elsif ($name =~ /\s/) {
      croak("Processing instruction name may not contain whitespace");
    } else {
      &{$pi};
    }
  };

  my $comment = sub {
    my $data = $_[0];
    if ($dataMode && $elementLevel) {
      $output->print("\n");
      $output->print(" " x ($elementLevel * $dataIndent));
    }
    $output->print("<!-- $data -->");
    if ($dataMode && $elementLevel) {
      $hasElement = 1;
    } elsif ($elementLevel == 0) {
      $output->print("\n");
      $hasHeading = 1;
    }
  };

  my $SAFE_comment = sub {
    my $data = $_[0];
    if ($data =~ /--/) {
      carp("Interoperability problem: \"--\" in comment text");
    }

    if ($data =~ /-->/) {
      croak("Comment may not contain '-->'");
    } else {
      &{$checkUnencodedRepertoire}($data);
      $seen{ANYTHING} = 1;
      &{$comment};
    }
  };

  my $doctype = sub {
    my ($name, $publicId, $systemId) = (@_);
    $output->print("<!DOCTYPE $name");
    if ($publicId) {
      unless ($systemId) {
        croak("A DOCTYPE declaration with a public ID must also have a system ID");
      }
      $output->print(" PUBLIC \"$publicId\" \"$systemId\"");
    } elsif ($systemId) {
      $output->print(" SYSTEM \"$systemId\"");
    }
    $output->print(">\n");
    $hasHeading = 1;
  };

  my $SAFE_doctype = sub {
    my $name = $_[0];
    if ($seen{DOCTYPE}) {
      croak("Attempt to insert second DOCTYPE declaration");
    } elsif ($seen{ELEMENT}) {
      croak("The DOCTYPE declaration must come before the first start tag");
    } else {
      $seen{ANYTHING} = 1;
      $seen{DOCTYPE} = $name;
      &{$doctype};
    }
  };

  my $startTag = sub {
    my $name = $_[0];
    if ($dataMode && ($hasHeading || $elementLevel)) {
      $output->print("\n");
      $output->print(" " x ($elementLevel * $dataIndent));
    }
    $elementLevel++;
    push @elementStack, $name;
    $output->print("<$name");
    &{$showAttributes}(\@_);
    $output->print("$nl>");
    if ($dataMode) {
      $hasElement = 1;
      push @hasDataStack, $hasData;
      $hasData = 0;
      push @hasElementStack, $hasElement;
      $hasElement = 0;
    }
  };

  my $SAFE_startTag = sub {
    my $name = $_[0];

    &{$checkUnencodedRepertoire}($name);
    _checkAttributes(\@_);

    if ($seen{ELEMENT} && $elementLevel == 0) {
      croak("Attempt to insert start tag after close of document element");
    } elsif ($elementLevel == 0 && $seen{DOCTYPE} && $name ne $seen{DOCTYPE}) {
      croak("Document element is \"$name\", but DOCTYPE is \""
            . $seen{DOCTYPE}
            . "\"");
    } elsif ($dataMode && $hasData) {
      croak("Mixed content not allowed in data mode: element $name");
    } else {
      $seen{ANYTHING} = 1;
      $seen{ELEMENT} = 1;
      &{$startTag};
    }
  };

  my $emptyTag = sub {
    my $name = $_[0];
    if ($dataMode && ($hasHeading || $elementLevel)) {
      $output->print("\n");
      $output->print(" " x ($elementLevel * $dataIndent));
    }
    $output->print("<$name");
    &{$showAttributes}(\@_);
    $output->print("$nl />");
    if ($dataMode) {
      $hasElement = 1;
    }
  };

  my $SAFE_emptyTag = sub {
    my $name = $_[0];

    &{$checkUnencodedRepertoire}($name);
    _checkAttributes(\@_);

    if ($seen{ELEMENT} && $elementLevel == 0) {
      croak("Attempt to insert empty tag after close of document element");
    } elsif ($elementLevel == 0 && $seen{DOCTYPE} && $name ne $seen{DOCTYPE}) {
      croak("Document element is \"$name\", but DOCTYPE is \""
            . $seen{DOCTYPE}
            . "\"");
    } elsif ($dataMode && $hasData) {
      croak("Mixed content not allowed in data mode: element $name");
    } else {
      $seen{ANYTHING} = 1;
      $seen{ELEMENT} = 1;
      &{$emptyTag};
    }
  };

  my $endTag = sub {
    my $name = $_[0];
    my $currentName = pop @elementStack;
    $name = $currentName unless $name;
    $elementLevel--;
    if ($dataMode && $hasElement) {
      $output->print("\n");
      $output->print(" " x ($elementLevel * $dataIndent));
    }
    $output->print("</$name$nl>");
    if ($dataMode) {
      $hasData = pop @hasDataStack;
      $hasElement = pop @hasElementStack;
    }
  };

  my $SAFE_endTag = sub {
    my $name = $_[0];
    my $oldName = $elementStack[$#elementStack];
    if ($elementLevel <= 0) {
      croak("End tag \"$name\" does not close any open element");
    } elsif ($name && ($name ne $oldName)) {
      croak("Attempt to end element \"$oldName\" with \"$name\" tag");
    } else {
      &{$endTag};
    }
  };

  my $characters = sub {
    my $data = $_[0];
    if ($data =~ /[\&\<\>]/) {
      $data =~ s/\&/\&amp\;/g;
      $data =~ s/\</\&lt\;/g;
      $data =~ s/\>/\&gt\;/g;
    }
    &{$escapeEncoding}($data);
    $output->print($data);
    $hasData = 1;
  };

  my $SAFE_characters = sub {
    if ($elementLevel < 1) {
      croak("Attempt to insert characters outside of document element");
    } elsif ($dataMode && $hasElement) {
      croak("Mixed content not allowed in data mode: characters");
    } else {
      _croakUnlessDefinedCharacters($_[0]);
      &{$characters};
    }
  };

  my $raw = sub {
    $output->print($_[0]);
    # Don't set $hasData or any other information: we know nothing
    # about what was just written.
    #
  };

  my $SAFE_raw = sub {
    croak('raw() is only available when UNSAFE is set');
  };

  my $cdata = sub {
      my $data = $_[0];
      $data    =~ s/\]\]>/\]\]\]\]><!\[CDATA\[>/g;
      $output->print("<![CDATA[$data]]>");
      $hasData = 1;
  };

  my $SAFE_cdata = sub {
    if ($elementLevel < 1) {
      croak("Attempt to insert characters outside of document element");
    } elsif ($dataMode && $hasElement) {
      croak("Mixed content not allowed in data mode: characters");
    } else {
      _croakUnlessDefinedCharacters($_[0]);
      &{$checkUnencodedRepertoire}($_[0]);
      &{$cdata};
    }
  };

                                # Assign the correct closures based on
                                # the UNSAFE parameter
  if ($unsafe) {
    $self = {'END' => $end,
             'XMLDECL' => $xmlDecl,
             'PI' => $pi,
             'COMMENT' => $comment,
             'DOCTYPE' => $doctype,
             'STARTTAG' => $startTag,
             'EMPTYTAG' => $emptyTag,
             'ENDTAG' => $endTag,
             'CHARACTERS' => $characters,
             'RAW' => $raw,
             'CDATA' => $cdata
            };
  } else {
    $self = {'END' => $SAFE_end,
             'XMLDECL' => $SAFE_xmlDecl,
             'PI' => $SAFE_pi,
             'COMMENT' => $SAFE_comment,
             'DOCTYPE' => $SAFE_doctype,
             'STARTTAG' => $SAFE_startTag,
             'EMPTYTAG' => $SAFE_emptyTag,
             'ENDTAG' => $SAFE_endTag,
             'CHARACTERS' => $SAFE_characters,
             'RAW' => $SAFE_raw,               # This will intentionally fail
             'CDATA' => $SAFE_cdata
            };
  }

                                # Query methods
  $self->{'IN_ELEMENT'} = sub {
    my ($ancestor) = (@_);
    return $elementStack[$#elementStack] eq $ancestor;
  };

  $self->{'WITHIN_ELEMENT'} = sub {
    my ($ancestor) = (@_);
    my $el;
    foreach $el (@elementStack) {
      return 1 if $el eq $ancestor;
    }
    return 0;
  };

  $self->{'CURRENT_ELEMENT'} = sub {
    return $elementStack[$#elementStack];
  };

  $self->{'ANCESTOR'} = sub {
    my ($n) = (@_);
    if ($n < scalar(@elementStack)) {
      return $elementStack[$#elementStack-$n];
    } else {
      return undef;
    }
  };

                                # Set and get the output destination.
  $self->{'GETOUTPUT'} = sub {
    return $output;
  };

  $self->{'SETOUTPUT'} = sub {
    my $newOutput = $_[0];

    if (ref($newOutput) eq 'SCALAR') {
      $output = new XML::Writer::_String($newOutput);
    } else {
                                # If there is no OUTPUT parameter,
                                # use standard output
      $output = $newOutput || \*STDOUT;
      if ($outputEncoding) {
        if (lc($outputEncoding) eq 'utf-8') {
          binmode($output, ':encoding(utf-8)');
        } elsif (lc($outputEncoding) eq 'us-ascii') {
          binmode($output, ':encoding(us-ascii)');
        } else {
          die 'The only supported encodings are utf-8 and us-ascii';
        }
      }
    }
  };

  $self->{'SETDATAMODE'} = sub {
    $dataMode = $_[0];
  };

  $self->{'GETDATAMODE'} = sub {
    return $dataMode;
  };

  $self->{'SETDATAINDENT'} = sub {
    $dataIndent = $_[0];
  };

  $self->{'GETDATAINDENT'} = sub {
    return $dataIndent;
  };

                                # Set the output.
  &{$self->{'SETOUTPUT'}}($params{'OUTPUT'});

                                # Return the blessed object.
  return bless $self, $class;
}



########################################################################
# Public methods
########################################################################

#
# Finish writing the document.
#
sub end {
  my $self = shift;
  &{$self->{END}};
}

#
# Write an XML declaration.
#
sub xmlDecl {
  my $self = shift;
  &{$self->{XMLDECL}};
}

#
# Write a processing instruction.
#
sub pi {
  my $self = shift;
  &{$self->{PI}};
}

#
# Write a comment.
#
sub comment {
  my $self = shift;
  &{$self->{COMMENT}};
}

#
# Write a DOCTYPE declaration.
#
sub doctype {
  my $self = shift;
  &{$self->{DOCTYPE}};
}

#
# Write a start tag.
#
sub startTag {
  my $self = shift;
  &{$self->{STARTTAG}};
}

#
# Write an empty tag.
#
sub emptyTag {
  my $self = shift;
  &{$self->{EMPTYTAG}};
}

#
# Write an end tag.
#
sub endTag {
  my $self = shift;
  &{$self->{ENDTAG}};
}

#
# Write a simple data element.
#
sub dataElement {
  my ($self, $name, $data, %atts) = (@_);
  $self->startTag($name, %atts);
  $self->characters($data);
  $self->endTag($name);
}

#
# Write a simple CDATA element.
#
sub cdataElement {
    my ($self, $name, $data, %atts) = (@_);
    $self->startTag($name, %atts);
    $self->cdata($data);
    $self->endTag($name);
}

#
# Write character data.
#
sub characters {
  my $self = shift;
  &{$self->{CHARACTERS}};
}

#
# Write raw, unquoted, completely unchecked character data.
#
sub raw {
  my $self = shift;
  &{$self->{RAW}};
}

#
# Write CDATA.
#
sub cdata {
    my $self = shift;
    &{$self->{CDATA}};
}

#
# Query the current element.
#
sub in_element {
  my $self = shift;
  return &{$self->{IN_ELEMENT}};
}

#
# Query the ancestors.
#
sub within_element {
  my $self = shift;
  return &{$self->{WITHIN_ELEMENT}};
}

#
# Get the name of the current element.
#
sub current_element {
  my $self = shift;
  return &{$self->{CURRENT_ELEMENT}};
}

#
# Get the name of the numbered ancestor (zero-based).
#
sub ancestor {
  my $self = shift;
  return &{$self->{ANCESTOR}};
}

#
# Get the current output destination.
#
sub getOutput {
  my $self = shift;
  return &{$self->{GETOUTPUT}};
}


#
# Set the current output destination.
#
sub setOutput {
  my $self = shift;
  return &{$self->{SETOUTPUT}};
}

#
# Set the current data mode (true or false).
#
sub setDataMode {
  my $self = shift;
  return &{$self->{SETDATAMODE}};
}


#
# Get the current data mode (true or false).
#
sub getDataMode {
  my $self = shift;
  return &{$self->{GETDATAMODE}};
}


#
# Set the current data indent step.
#
sub setDataIndent {
  my $self = shift;
  return &{$self->{SETDATAINDENT}};
}


#
# Get the current data indent step.
#
sub getDataIndent {
  my $self = shift;
  return &{$self->{GETDATAINDENT}};
}


#
# Empty stub.
#
sub addPrefix {
}


#
# Empty stub.
#
sub removePrefix {
}



########################################################################
# Private functions.
########################################################################

#
# Private: check for duplicate attributes and bad characters.
# Note - this starts at $_[1], because $_[0] is assumed to be an
# element name.
#
sub _checkAttributes {
  my %anames;
  my $i = 1;
  while ($_[0]->[$i]) {
    my $name = $_[0]->[$i];
    $i += 1;
    if ($anames{$name}) {
      croak("Two attributes named \"$name\"");
    } else {
      $anames{$name} = 1;
    }
    _croakUnlessDefinedCharacters($_[0]->[$i]);
    $i += 1;
  }
}

#
# Private: escape an attribute value literal.
#
sub _escapeLiteral {
  my $data = $_[0];
  if ($data =~ /[\&\<\>\"]/) {
    $data =~ s/\&/\&amp\;/g;
    $data =~ s/\</\&lt\;/g;
    $data =~ s/\>/\&gt\;/g;
    $data =~ s/\"/\&quot\;/g;
  }
  return $data;
}

sub _escapeASCII($) {
  $_[0] =~ s/([^\x00-\x7F])/sprintf('&#x%X;', ord($1))/ge;
}

sub _croakUnlessASCII($) {
  if ($_[0] =~ /[^\x00-\x7F]/) {
    croak('Non-ASCII characters are not permitted in this part of a US-ASCII document');
  }
}

# Enforce XML 1.0, section 2.2's definition of "Char" (only reject low ASCII,
#  so as not to require Unicode support from perl)
sub _croakUnlessDefinedCharacters($) {
  if ($_[0] =~ /([\x00-\x08\x0B-\x0C\x0E-\x1F])/) {
    croak(sprintf('Code point \u%04X is not a valid character in XML', ord($1)));
  }
}


########################################################################
# XML::Writer::Namespaces - subclass for Namespace processing.
########################################################################

package XML::Writer::Namespaces;
use strict;
use vars qw(@ISA);
use Carp;

@ISA = qw(XML::Writer);

#
# Constructor
#
sub new {
  my ($class, %params) = (@_);

  my $unsafe = $params{UNSAFE};

                                # Snarf the prefix map, if any, and
                                # note the default prefix.
  my %prefixMap = ();
  if ($params{PREFIX_MAP}) {
    %prefixMap = (%{$params{PREFIX_MAP}});
    delete $params{PREFIX_MAP};
  }
  $prefixMap{'http://www.w3.org/XML/1998/namespace'} = 'xml';

                                # Generate the reverse map for URIs
  my $uriMap = {};
  my $key;
  foreach $key (keys(%prefixMap)) {
    $uriMap->{$prefixMap{$key}} = $key;
  }

  my $defaultPrefix = $uriMap->{''};
  delete $prefixMap{$defaultPrefix} if ($defaultPrefix);

                                # Create an instance of the parent.
  my $self = new XML::Writer(%params);

                                # Snarf the parent's methods that we're
                                # going to override.
  my $OLD_startTag = $self->{STARTTAG};
  my $OLD_emptyTag = $self->{EMPTYTAG};
  my $OLD_endTag = $self->{ENDTAG};

                                # State variables
  my @stack;
  my $prefixCounter = 1;
  my $nsDecls = {'http://www.w3.org/XML/1998/namespace' => 'xml'};
  my $nsDefaultDecl = undef;
  my $nsCopyFlag = 0;
  my @forcedNSDecls = ();

  if ($params{FORCED_NS_DECLS}) {
    @forcedNSDecls = @{$params{FORCED_NS_DECLS}};
    delete $params{FORCED_NS_DECLS};
  }

  #
  # Push the current declaration state.
  #
  my $pushState = sub {
    push @stack, [$nsDecls, $nsDefaultDecl, $nsCopyFlag, $uriMap];
    $nsCopyFlag = 0;
  };


  #
  # Pop the current declaration state.
  #
  my $popState = sub {
    ($nsDecls, $nsDefaultDecl, $nsCopyFlag, $uriMap) = @{pop @stack};
  };

  #
  # Generate a new prefix.
  #
  my $genPrefix = sub {
    my $uri = $_[0];
    my $prefixCounter = 1;
    my $prefix = $prefixMap{$uri};
    my %clashMap = %{$uriMap};
    while( my ($u, $p) = each(%prefixMap)) {
      $clashMap{$p} = $u;
    }

    while (!defined($prefix) || ($clashMap{$prefix} && $clashMap{$prefix} ne $uri)) {
      $prefix = "__NS$prefixCounter";
      $prefixCounter++;
    }

    return $prefix;
  };

  #
  # Perform namespace processing on a single name.
  #
  my $processName = sub {
    my ($nameref, $atts, $attFlag) = (@_);
    my ($uri, $local) = @{$$nameref};
    my $prefix = $nsDecls->{$uri};

                                # Is this an element name that matches
                                # the default NS?
    if (!$attFlag && $defaultPrefix && ($uri eq $defaultPrefix)) {
      unless ($nsDefaultDecl && ($nsDefaultDecl eq $uri)) {
        push @{$atts}, 'xmlns';
        push @{$atts}, $uri;
        $nsDefaultDecl = $uri;
      }
      $$nameref = $local;

      if (defined($uriMap->{''})) {
        delete ($nsDecls->{$uriMap->{''}});
      }

      $nsDecls->{$uri} = '';
      unless ($nsCopyFlag) {
        $uriMap = {%{$uriMap}};
        $nsDecls = {%{$nsDecls}};
        $nsCopyFlag = 1;
      }
      $uriMap->{''} = $uri;
      
                                # Is there a straight-forward prefix?
    } elsif ($prefix) {
      $$nameref = "$prefix:$local";
    } else {
      $prefix = &{$genPrefix}($uri);
      unless ($nsCopyFlag) {
        $uriMap = {%{$uriMap}};
        $nsDecls = {%{$nsDecls}};
        $nsCopyFlag = 1;
      }
      $uriMap->{$prefix} = $uri;
      $nsDecls->{$uri} = $prefix;
      push @{$atts}, "xmlns:$prefix";
      push @{$atts}, $uri;
      $$nameref = "$prefix:$local";
    }
  };


  #
  # Perform namespace processing on element and attribute names.
  #
  my $nsProcess = sub {
    if (ref($_[0]->[0]) eq 'ARRAY') {
      &{$processName}(\$_[0]->[0], $_[0], 0);
    }
    my $i = 1;
    while ($_[0]->[$i]) {
      if (ref($_[0]->[$i]) eq 'ARRAY') {
        &{$processName}(\$_[0]->[$i], $_[0], 1);
      }
      $i += 2;
    }

    # We do this if any declarations are forced, due either to
    #  constructor arguments or to a call during processing.
    if (@forcedNSDecls) {
      foreach (@forcedNSDecls) {
        my @dummy = ($_, 'dummy');
        my $d2 = \@dummy;
        if ($defaultPrefix && ($_ eq $defaultPrefix)) {
          &{$processName}(\$d2, $_[0], 0);
        } else {
          &{$processName}(\$d2, $_[0], 1);
        }
      }
      @forcedNSDecls = ();
    }
  };


  # Indicate that a namespace should be declared by the next open element
  $self->{FORCENSDECL} = sub {
    push @forcedNSDecls, $_[0];
  };


  #
  # Start tag, with NS processing
  #
  $self->{STARTTAG} = sub {
    my $name = $_[0];
    unless ($unsafe) {
      _checkNSNames(\@_);
    }
    &{$pushState}();
    &{$nsProcess}(\@_);
    &{$OLD_startTag};
  };


  #
  # Empty tag, with NS processing
  #
  $self->{EMPTYTAG} = sub {
    unless ($unsafe) {
      _checkNSNames(\@_);
    }
    &{$pushState}();
    &{$nsProcess}(\@_);
    &{$OLD_emptyTag};
    &{$popState}();
  };


  #
  # End tag, with NS processing
  #
  $self->{ENDTAG} = sub {
    my $name = $_[0];
    if (ref($_[0]) eq 'ARRAY') {
      my $pfx = $nsDecls->{$_[0]->[0]};
      if ($pfx) {
        $_[0] = $pfx . ':' . $_[0]->[1];
      } else {
        $_[0] = $_[0]->[1];
      }
    } else {
      $_[0] = $_[0];
    }
#    &{$nsProcess}(\@_);
    &{$OLD_endTag};
    &{$popState}();
  };


  #
  # Processing instruction, but only if not UNSAFE.
  #
  unless ($unsafe) {
    my $OLD_pi = $self->{PI};
    $self->{PI} = sub {
      my $target = $_[0];
      if (index($target, ':') >= 0) {
        croak "PI target '$target' contains a colon.";
      }
      &{$OLD_pi};
    }
  };


  #
  # Add a prefix to the prefix map.
  #
  $self->{ADDPREFIX} = sub {
    my ($uri, $prefix) = (@_);
    if ($prefix) {
      $prefixMap{$uri} = $prefix;
    } else {
      if (defined($defaultPrefix)) {
        delete($prefixMap{$defaultPrefix});
      }
      $defaultPrefix = $uri;
    }
  };


  #
  # Remove a prefix from the prefix map.
  #
  $self->{REMOVEPREFIX} = sub {
    my ($uri) = (@_);
    if ($defaultPrefix && ($defaultPrefix eq $uri)) {
      $defaultPrefix = undef;
    }
    delete $prefixMap{$uri};
  };


  #
  # Bless and return the object.
  #
  return bless $self, $class;
}


#
# Add a preferred prefix for a namespace URI.
#
sub addPrefix {
  my $self = shift;
  return &{$self->{ADDPREFIX}};
}


#
# Remove a preferred prefix for a namespace URI.
#
sub removePrefix {
  my $self = shift;
  return &{$self->{REMOVEPREFIX}};
}


#
# Check names.
#
sub _checkNSNames {
  my $names = $_[0];
  my $i = 1;
  my $name = $names->[0];

                                # Check the element name.
  if (ref($name) eq 'ARRAY') {
    if (index($name->[1], ':') >= 0) {
      croak("Local part of element name '" .
            $name->[1] .
            "' contains a colon.");
    }
  } elsif (index($name, ':') >= 0) {
    croak("Element name '$name' contains a colon.");
  }

                                # Check the attribute names.
  while ($names->[$i]) {
    my $name = $names->[$i];
    if (ref($name) eq 'ARRAY') {
      my $local = $name->[1];
      if (index($local, ':') >= 0) {
        croak "Local part of attribute name '$local' contains a colon.";
      }
    } else {
      if ($name =~ /^xmlns/) {
        croak "Attribute name '$name' begins with 'xmlns'";
      } elsif (index($name, ':') >= 0) {
        croak "Attribute name '$name' contains ':'";
      }
    }
    $i += 2;
  }
}

sub forceNSDecl
{
  my $self = shift;
  return &{$self->{FORCENSDECL}};
}


package XML::Writer::_String;

# Internal class, behaving sufficiently like an IO::Handle,
#  that stores written output in a string
#
# Heavily inspired by Simon Oliver's XML::Writer::String

sub new
{
  my $class = shift;
  my $scalar_ref = shift;
  return bless($scalar_ref, $class);
}

sub print
{
  ${(shift)} .= join('', @_);
  return 1;
}

1;
__END__

########################################################################
# POD Documentation
########################################################################

=head1 NAME

XML::Writer - Perl extension for writing XML documents.

=head1 SYNOPSIS

  use XML::Writer;
  use IO::File;

  my $output = new IO::File(">output.xml");

  my $writer = new XML::Writer(OUTPUT => $output);
  $writer->startTag("greeting", 
                    "class" => "simple");
  $writer->characters("Hello, world!");
  $writer->endTag("greeting");
  $writer->end();
  $output->close();


=head1 DESCRIPTION

XML::Writer is a helper module for Perl programs that write an XML
document.  The module handles all escaping for attribute values and
character data and constructs different types of markup, such as tags,
comments, and processing instructions.

By default, the module performs several well-formedness checks to
catch errors during output.  This behaviour can be extremely useful
during development and debugging, but it can be turned off for
production-grade code.

The module can operate either in regular mode in or Namespace
processing mode.  In Namespace mode, the module will generate
Namespace Declarations itself, and will perform additional checks on
the output.

Additional support is available for a simplified data mode with no
mixed content: newlines are automatically inserted around elements and
elements can optionally be indented based as their nesting level.


=head1 METHODS

=head2 Writing XML

=over 4

=item new([$params])

Create a new XML::Writer object:

  my $writer = new XML::Writer(OUTPUT => $output, NEWLINES => 1);

Arguments are an anonymous hash array of parameters:

=over 4

=item OUTPUT

An object blessed into IO::Handle or one of its subclasses (such as
IO::File), or a reference to a string; if this parameter is not present,
the module will write to standard output. If a string reference is passed,
it will capture the generated XML (as a string; to get bytes use the
C<Encode> module).

=item NAMESPACES

A true (1) or false (0, undef) value; if this parameter is present and
its value is true, then the module will accept two-member array
reference in the place of element and attribute names, as in the
following example:

  my $rdfns = "http://www.w3.org/1999/02/22-rdf-syntax-ns#";
  my $writer = new XML::Writer(NAMESPACES => 1);
  $writer->startTag([$rdfns, "Description"]);

The first member of the array is a namespace URI, and the second part
is the local part of a qualified name.  The module will automatically
generate appropriate namespace declarations and will replace the URI
part with a prefix.

=item PREFIX_MAP

A hash reference; if this parameter is present and the module is
performing namespace processing (see the NAMESPACES parameter), then
the module will use this hash to look up preferred prefixes for
namespace URIs:


  my $rdfns = "http://www.w3.org/1999/02/22-rdf-syntax-ns#";
  my $writer = new XML::Writer(NAMESPACES => 1,
                               PREFIX_MAP => {$rdfns => 'rdf'});

The keys in the hash table are namespace URIs, and the values are the
associated prefixes.  If there is not a preferred prefix for the
namespace URI in this hash, then the module will automatically
generate prefixes of the form "__NS1", "__NS2", etc.

To set the default namespace, use '' for the prefix.

=item FORCED_NS_DECLS

An array reference; if this parameter is present, the document element
will contain declarations for all the given namespace URIs.
Declaring namespaces in advance is particularly useful when a large
number of elements from a namespace are siblings, but don't share a direct
ancestor from the same namespace.

=item NEWLINES

A true or false value; if this parameter is present and its value is
true, then the module will insert an extra newline before the closing
delimiter of start, end, and empty tags to guarantee that the document
does not end up as a single, long line.  If the paramter is not
present, the module will not insert the newlines.

=item UNSAFE

A true or false value; if this parameter is present and its value is
true, then the module will skip most well-formedness error checking.
If the parameter is not present, the module will perform the
well-formedness error checking by default.  Turn off error checking at
your own risk!

=item DATA_MODE

A true or false value; if this parameter is present and its value is
true, then the module will enter a special data mode, inserting
newlines automatically around elements and (unless UNSAFE is also
specified) reporting an error if any element has both characters and
elements as content.

=item DATA_INDENT

A numeric value; if this parameter is present, it represents the
indent step for elements in data mode (it will be ignored when not in
data mode).

=item ENCODING

A character encoding; currently this must be one of 'utf-8' or 'us-ascii'.
If present, it will be used for the underlying character encoding and as the
default in the XML declaration.

=back

=item end()

Finish creating an XML document.  This method will check that the
document has exactly one document element, and that all start tags are
closed:

  $writer->end();

=item xmlDecl([$encoding, $standalone])

Add an XML declaration to the beginning of an XML document.  The
version will always be "1.0".  If you provide a non-null encoding or
standalone argument, its value will appear in the declaration (any
non-null value for standalone except 'no' will automatically be
converted to 'yes'). If not given here, the encoding will be taken from the
ENCODING argument. Pass the empty string to suppress this behaviour.

  $writer->xmlDecl("UTF-8");

=item doctype($name, [$publicId, $systemId])

Add a DOCTYPE declaration to an XML document.  The declaration must
appear before the beginning of the root element.  If you provide a
publicId, you must provide a systemId as well, but you may provide
just a system ID by passing 'undef' for the publicId.

  $writer->doctype("html");

=item comment($text)

Add a comment to an XML document.  If the comment appears outside the
document element (either before the first start tag or after the last
end tag), the module will add a carriage return after it to improve
readability. In data mode, comments will be treated as empty tags:

  $writer->comment("This is a comment");

=item pi($target [, $data])

Add a processing instruction to an XML document:

  $writer->pi('xml-stylesheet', 'href="style.css" type="text/css"');

If the processing instruction appears outside the document element
(either before the first start tag or after the last end tag), the
module will add a carriage return after it to improve readability.

The $target argument must be a single XML name.  If you provide the
$data argument, the module will insert its contents following the
$target argument, separated by a single space.

=item startTag($name [, $aname1 => $value1, ...])

Add a start tag to an XML document.  Any arguments after the element
name are assumed to be name/value pairs for attributes: the module
will escape all '&', '<', '>', and '"' characters in the attribute
values using the predefined XML entities:

  $writer->startTag('doc', 'version' => '1.0',
                           'status' => 'draft',
                           'topic' => 'AT&T');

All start tags must eventually have matching end tags.

=item emptyTag($name [, $aname1 => $value1, ...])

Add an empty tag to an XML document.  Any arguments after the element
name are assumed to be name/value pairs for attributes (see startTag()
for details):

  $writer->emptyTag('img', 'src' => 'portrait.jpg',
                           'alt' => 'Portrait of Emma.');

=item endTag([$name])

Add an end tag to an XML document.  The end tag must match the closest
open start tag, and there must be a matching and properly-nested end
tag for every start tag:

  $writer->endTag('doc');

If the $name argument is omitted, then the module will automatically
supply the name of the currently open element:

  $writer->startTag('p');
  $writer->endTag();

=item dataElement($name, $data [, $aname1 => $value1, ...])

Print an entire element containing only character data.  This is
equivalent to

  $writer->startTag($name [, $aname1 => $value1, ...]);
  $writer->characters($data);
  $writer->endTag($name);

=item characters($data)

Add character data to an XML document.  All '<', '>', and '&'
characters in the $data argument will automatically be escaped using
the predefined XML entities:

  $writer->characters("Here is the formula: ");
  $writer->characters("a < 100 && a > 5");

You may invoke this method only within the document element
(i.e. after the first start tag and before the last end tag).

In data mode, you must not use this method to add whitespace between
elements.

=item raw($data)

Print data completely unquoted and unchecked to the XML document.  For
example C<raw('<')> will print a literal < character.  This
necessarily bypasses all well-formedness checking, and is therefore
only available in unsafe mode.

This can sometimes be useful for printing entities which are defined
for your XML format but the module doesn't know about, for example
&nbsp; for XHTML.

=item cdata($data)

As C<characters()> but writes the data quoted in a CDATA section, that
is, between <![CDATA[ and ]]>.  If the data to be written itself
contains ]]>, it will be written as several consecutive CDATA
sections.

=item cdataElement($name, $data [, $aname1 => $value1, ...])

As C<dataElement()> but the element content is written as one or more
CDATA sections (see C<cdata()>).

=item setOutput($output)

Set the current output destination, as in the OUTPUT parameter for the
constructor.

=item getOutput()

Return the current output destination, as in the OUTPUT parameter for
the constructor.

=item setDataMode($mode)

Enable or disable data mode, as in the DATA_MODE parameter for the
constructor.

=item getDataMode()

Return the current data mode, as in the DATA_MODE parameter for the
constructor.

=item setDataIndent($step)

Set the indent step for data mode, as in the DATA_INDENT parameter for
the constructor.

=item getDataIndent()

Return the indent step for data mode, as in the DATA_INDENT parameter
for the constructor.


=back

=head2 Querying XML

=over 4

=item in_element($name)

Return a true value if the most recent open element matches $name:

  if ($writer->in_element('dl')) {
    $writer->startTag('dt');
  } else {
    $writer->startTag('li');
  }

=item within_element($name)

Return a true value if any open element matches $name:

  if ($writer->within_element('body')) {
    $writer->startTag('h1');
  } else {
    $writer->startTag('title');
  }

=item current_element()

Return the name of the currently open element:

  my $name = $writer->current_element();

This is the equivalent of

  my $name = $writer->ancestor(0);

=item ancestor($n)

Return the name of the nth ancestor, where $n=0 for the current open
element.

=back


=head2 Additional Namespace Support

As of 0.510, these methods may be used while writing a document.

=over 4

=item addPrefix($uri, $prefix)

Add a preferred mapping between a Namespace URI and a prefix.  See
also the PREFIX_MAP constructor parameter.

To set the default namespace, omit the $prefix parameter or set it to
''.

=item removePrefix($uri)

Remove a preferred mapping between a Namespace URI and a prefix.

=item forceNSDecl($uri)

Indicate that a namespace declaration for this URI should be included
with the next element to be started.

=back


=head1 ERROR REPORTING

With the default settings, the XML::Writer module can detect several
basic XML well-formedness errors:

=over 4

=item *

Lack of a (top-level) document element, or multiple document elements.

=item *

Unclosed start tags.

=item *

Misplaced delimiters in the contents of processing instructions or
comments.

=item *

Misplaced or duplicate XML declaration(s).

=item *

Misplaced or duplicate DOCTYPE declaration(s).

=item *

Mismatch between the document type name in the DOCTYPE declaration and
the name of the document element.

=item *

Mismatched start and end tags.

=item *

Attempts to insert character data outside the document element.

=item *

Duplicate attributes with the same name.

=back

During Namespace processing, the module can detect the following
additional errors:

=over 4

=item *

Attempts to use PI targets or element or attribute names containing a
colon.

=item *

Attempts to use attributes with names beginning "xmlns".

=back

To ensure full error detection, a program must also invoke the end
method when it has finished writing a document:

  $writer->startTag('greeting');
  $writer->characters("Hello, world!");
  $writer->endTag('greeting');
  $writer->end();

This error reporting can catch many hidden bugs in Perl programs that
create XML documents; however, if necessary, it can be turned off by
providing an UNSAFE parameter:

  my $writer = new XML::Writer(OUTPUT => $output, UNSAFE => 1);


=head1 AUTHOR

David Megginson E<lt>david@megginson.comE<gt>


=head1 COPYRIGHT

Copyright 1999, 2000 David Megginson E<lt>david@megginson.comE<gt>

Copyright 2004, 2005 Joseph Walton E<lt>joe@kafsemo.orgE<gt>


=head1 SEE ALSO

XML::Parser

=cut
