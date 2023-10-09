package Net::IDN::UTS46;

require 5.008005;	# Unicode BiDi classes

use strict;
use utf8;
use warnings;

use Carp;

our $VERSION = "1.001";
$VERSION = eval $VERSION;

our @ISA = ('Exporter');
our @EXPORT = ();
our @EXPORT_OK = ('uts46_to_ascii', 'uts46_to_unicode');
our %EXPORT_TAGS = ( 'all' => \@EXPORT_OK );

use Unicode::Normalize ();

use Net::IDN::Punycode 1.1 (':all');
use Net::IDN::Encode 2.100 (':_var');
use Net::IDN::UTS46::_Mapping 5.002 ('/^(Is|Map).*/');	# UTS #46 is only defined from Unicode 5.2.0

sub uts46_to_unicode {
  my ($label, %param) = @_;
  croak "Transitional processing is not defined for ToUnicode" if $param{'TransitionalProcessing'};

  splice @_, 1, 0, undef;
  goto &_process;
}

sub uts46_to_ascii {
  my ($label, %param) = @_;

  splice @_, 1, 0, sub {
    local $_ = shift;
    if(m/\P{ASCII}/) {
      eval { $_ = $IDNA_PREFIX . encode_punycode($_) };
      croak "$@ [A3]" if $@;
    }
    return $_;
  };
  goto &_process;
}

*to_unicode	= \&uts46_to_unicode;
*to_ascii	= \&uts46_to_ascii;

sub _process {
  my ($label, $to_ascii, %param) = @_;
  no warnings 'utf8';
  croak "The following parameter is invalid: $_"
    foreach(grep { !m/^(?:TransitionalProcessing|UseSTD3ASCIIRules|AllowUnassigned)$/ } keys %param);

  $param{'TransitionalProcessing'} = 0	unless exists $param{'TransitionalProcessing'};
  $param{'UseSTD3ASCIIRules'} = 1	unless exists $param{'UseSTD3ASCIIRules'};
  $param{'AllowUnassigned'} = 0		unless exists $param{'AllowUnassigned'};

# 1. Map
#   - disallowed
#
  if($param{'AllowUnassigned'}) {
    $label =~ m/^(\P{IsDisallowed}}|\P{Assigned})*$/ and croak sprintf('disallowed character U+%04X', ord($1));
  } else {
    $label =~ m/(\p{IsDisallowed})/ and croak sprintf('disallowed character U+%04X', ord($1));
    $label =~ m/(\P{Assigned})/ and croak sprintf('unassigned character U+%04X (in this version of perl)', ord($1));
  }

  if($param{'UseSTD3ASCIIRules'}) {
    $label =~ m/(\p{IsDisallowedSTD3Valid})/ and croak sprintf('disallowed_STD3_valid character U+%04X', ord($1));
    $label =~ m/(\p{IsDisallowedSTD3Mapped})/ and croak sprintf('disallowed_STD3_mapped character U+%04X', ord($1));
  };

#   - ignored
#
  $label = MapIgnored($label);
  ## $label = MapDisallowedSTD3Ignored($label)	if(!$param{'UseSTD3ASCIIRules'});

#   - mapped
#
  $label = MapMapped($label);
  $label = MapDisallowedSTD3Mapped($label) 	if(!$param{'UseSTD3ASCIIRules'});

#  - deviation
  $label = MapDeviation($label)			if($param{'TransitionalProcessing'});

# 2. Normalize
#
  $label = Unicode::Normalize::NFC($label);

# 3. Break
#
  my @ll = split /\./, $label, -1;

  ## Note: leading dots must be ignored (IDNA test vectors)
  ##
  shift @ll while @ll and (length $ll[0] <= 0);

  ## IDNA test vectors: an empty label at the end (separating the root domain
  ##                    "", if present) must be preserved. It is not checked for
  ##			the minumum length criteria and the dot separting it is
  ##			not included in the maximum length of the domain.
  ##
  my $rooted = @ll && length($ll[$#ll]) < 1; pop @ll if $rooted;

# 4. Convert/Validate
#
  foreach my $l (@ll) {
    if($l =~ m/^(?:(?i)$IDNA_PREFIX)(\p{ASCII}+)$/o) {
      eval { $l = decode_punycode($1); };
      croak 'Invalid Punycode sequence [P4]' if $@;

      _validate_label($l, %param,
	'TransitionalProcessing' => 0,
	'AllowUnassigned' => 0,			## keep the Punycode version
      ) unless $@;
    } else {
      _validate_label($l,%param,'_AssumeNFC' => 1);
    }

    _validate_bidi($l,%param);
    _validate_contextj($l,%param);

    if(defined $to_ascii) {
      $l = $to_ascii->($l, %param);
    }

    ## IDNA test vectors: labels have to be checked for the minimum length of 1 (but not for the
    ##                    maximum length of 63) even in to_unicode.
    ##
    croak "empty label [A4_2]" if length($l) < 1;
    croak "label too long [A4_2]" if length($l) > 63 and defined $to_ascii;
  }

  my $domain = join('.', @ll);

  ## IDNA test vectors: domains have to be checked for the minimum length of 1 (but not for the
  ##                    maximum length of 253 excluding a final dot) even in to_unicode.
  ##
  croak "empty domain name [A4_1]" if length($domain) < 1;
  croak "domain name too long [A4_1]" if length($domain) > 253 and defined $to_ascii;

  $domain .= '.' if $rooted;

  return $domain;
}

sub _validate_label {
  my($l,%param) = @_;
  no warnings 'utf8';

  $l eq Unicode::Normalize::NFC($l)	or croak "not in Unicode Normalization Form NFC [V1]" unless $param{'_AssumeNFC'};

  $l =~ m/^..--/			and croak "contains U+002D HYPHEN-MINUS in both third and forth position [V2]";
  $l =~ m/^-/				and croak "begins with U+002D HYPHEN-MINUS [V3]";
  $l =~ m/-$/				and croak "ends with U+002D HYPHEN-MINUS [V3]";
  $l =~ m/\./				and croak "contains U+0023 FULL STOP [V4]";
  $l =~ m/^\p{IsMark}/			and croak "begins with General_Category=Mark [V5]";

  unless($param{'AllowUnassigned'}) {
    $l =~m/(\p{Unassigned})/		and croak sprintf "contains unassigned character U+%04X [V6]", ord $1;
  }

  if($param{'UseSTD3ASCIIRules'}) {
    $l =~m/(\p{IsDisallowedSTD3Valid})/	and croak sprintf "contains disallowed_STD3_valid character U+%04X [V6]", ord $1;
  }

  if($param{'TransitionalProcessing'}) {
    $l =~m/(\p{IsDeviation})/		and croak sprintf "contains deviation character U+%04X [V6]", ord $1;
  }

  $l =~ m/(\p{IsDisallowed})/		and croak sprintf "contains disallowed character U+%04X [V6]", ord $1;

  return 1;
}

sub _validate_bidi {
  my($l,%param) = @_;
  no warnings 'utf8';

  ## IDNA test vectors: _labels_ that don't contain RTL characters are skipped
  ##			(RFC 5893 mandates checks for _all_ labels if the 
  ##			_domain_ contains RTL characters in any label) 
  return 1 unless length($l); 
  return 1 unless $l =~ m/[\p{Bc:R}\p{Bc:AL}\p{Bc:AN}]/;


  ## IDNA test vectors: LTR labels may start with "neutral" characters of
  ##			BidiClass NSM or EN (RFC 5893 says LTR labels must
  ##			start with BidiClass L)
  ##
  if( $l =~ m/^[\p{Bc:NSM}\p{Bc:EN}]*\p{Bc:L}/ ) { # LTR (left-to-right)
    $l =~ m/[^\p{Bc:L}\p{Bc:EN}\p{Bc:ES}\p{Bc:CS}\p{Bc:ET}\p{Bc:BN}\p{Bc:ON}\p{Bc:NSM}]/ and croak 'contains characters with wrong bidi class for LTR [B5]';
    $l =~ m/[\p{Bc:L}\p{Bc:EN}][\p{Bc:NSM}\P{Assigned}]*$/ or croak 'ends with character of wrong bidi class for LTR [B6]';
    return 1;
  } 

  if( $l =~ m/^[\p{Bc:R}\p{Bc:AL}]/ ) { # RTL (right-to-left)
    $l =~ m/[^\p{Bc:R}\p{Bc:AL}\p{Bc:AN}\p{Bc:EN}\p{Bc:ES}\p{Bc:CS}\p{Bc:ET}\p{Bc:ON}\p{Bc:BN}\p{Bc:NSM}]/ and croak 'contains characters with wrong bidi class for RTL [B2]';
    $l =~ m/[\p{Bc:R}\p{Bc:AL}\p{Bc:EN}\p{Bc:AN}][\p{Bc:NSM}\P{Assigned}]*$/ or croak 'ends with character of wrong bidi class for RTL [B3]';
    $l =~ m/\p{Bc:EN}.*\p{Bc:AN}|\p{Bc:AN}.*\p{Bc:EN}/ and croak 'contains characters with both bidi class EN and AN [B4]';
    return 1;
  }

  croak 'starts with character of wrong bidi class [B1]';
}

# For perl versions < 5.11, we use a conrete list of characters; this is safe
# because the Unicode version supported by theses perl versions will not be
# updated. For newer perl versions, we use the Unicode property (which is
# supported from 5.11), so we will always be up-to-date with the Unicode
# version supported by our underlying perl.
#
my $_RE_Ccc_Virama	= $] >= 5.011 ? qr/\p{Ccc:Virama}/ : qr/[\x{094D}\x{09CD}\x{0A4D}\x{0ACD}\x{0B4D}\x{0BCD}\x{0C4D}\x{0CCD}\x{0D4D}\x{0DCA}\x{0E3A}\x{0F84}\x{1039}\x{103A}\x{1714}\x{1734}\x{17D2}\x{1A60}\x{1B44}\x{1BAA}\x{1BF2}\x{1BF3}\x{2D7F}\x{A806}\x{A8C4}\x{A953}\x{A9C0}\x{ABED}\x{00010A3F}\x{00011046}\x{000110B9}]/;
my $_RE_JoiningType_L	= $] >= 5.011 ? qr/\p{Joining_Type:L}/ : qr/(?!)/;
my $_RE_JoiningType_R	= $] >= 5.011 ? qr/\p{Joining_Type:R}/ : qr/[\x{0622}-\x{0625}\x{0627}\x{0629}\x{062F}-\x{0632}\x{0648}\x{0671}-\x{0673}\x{0675}-\x{0677}\x{0688}-\x{0699}\x{06C0}\x{06C3}-\x{06CB}\x{06CD}\x{06CF}\x{06D2}\x{06D3}\x{06D5}\x{06EE}\x{06EF}\x{0710}\x{0715}-\x{0719}\x{071E}\x{0728}\x{072A}\x{072C}\x{072F}\x{074D}\x{0759}-\x{075B}\x{076B}\x{076C}\x{0771}\x{0773}\x{0774}\x{0778}\x{0779}]/;
my $_RE_JoiningType_D	= $] >= 5.011 ? qr/\p{Joining_Type:D}/ : qr/[\x{0620}\x{0626}\x{0628}\x{062A}-\x{062E}\x{0633}-\x{063F}\x{0641}-\x{0647}\x{0649}\x{064A}\x{066E}\x{066F}\x{0678}-\x{0687}\x{069A}-\x{06BF}\x{06C1}\x{06C2}\x{06CC}\x{06CE}\x{06D0}\x{06D1}\x{06FA}-\x{06FC}\x{06FF}\x{0712}-\x{0714}\x{071A}-\x{071D}\x{071F}-\x{0727}\x{0729}\x{072B}\x{072D}\x{072E}\x{074E}-\x{0758}\x{075C}-\x{076A}\x{076D}-\x{0770}\x{0772}\x{0775}-\x{0777}\x{077A}-\x{077F}\x{07CA}-\x{07EA}]/;
my $_RE_JoiningType_T	= $] >= 5.011 ? qr/\p{Joining_Type:T}/ : qr/[\x{00AD}\x{0300}-\x{036F}\x{0483}-\x{0489}\x{0591}-\x{05BD}\x{05BF}\x{05C1}\x{05C2}\x{05C4}\x{05C5}\x{05C7}\x{0610}-\x{061A}\x{064B}-\x{065F}\x{0670}\x{06D6}-\x{06DC}\x{06DF}-\x{06E4}\x{06E7}\x{06E8}\x{06EA}-\x{06ED}\x{070F}\x{0711}\x{0730}-\x{074A}\x{07A6}-\x{07B0}\x{07EB}-\x{07F3}\x{0816}-\x{0819}\x{081B}-\x{0823}\x{0825}-\x{0827}\x{0829}-\x{082D}\x{0859}-\x{085B}\x{0900}-\x{0902}\x{093A}\x{093C}\x{0941}-\x{0948}\x{094D}\x{0951}-\x{0957}\x{0962}\x{0963}\x{0981}\x{09BC}\x{09C1}-\x{09C4}\x{09CD}\x{09E2}\x{09E3}\x{0A01}\x{0A02}\x{0A3C}\x{0A41}\x{0A42}\x{0A47}\x{0A48}\x{0A4B}-\x{0A4D}\x{0A51}\x{0A70}\x{0A71}\x{0A75}\x{0A81}\x{0A82}\x{0ABC}\x{0AC1}-\x{0AC5}\x{0AC7}\x{0AC8}\x{0ACD}\x{0AE2}\x{0AE3}\x{0B01}\x{0B3C}\x{0B3F}\x{0B41}-\x{0B44}\x{0B4D}\x{0B56}\x{0B62}\x{0B63}\x{0B82}\x{0BC0}\x{0BCD}\x{0C3E}-\x{0C40}\x{0C46}-\x{0C48}\x{0C4A}-\x{0C4D}\x{0C55}\x{0C56}\x{0C62}\x{0C63}\x{0CBC}\x{0CBF}\x{0CC6}\x{0CCC}\x{0CCD}\x{0CE2}\x{0CE3}\x{0D41}-\x{0D44}\x{0D4D}\x{0D62}\x{0D63}\x{0DCA}\x{0DD2}-\x{0DD4}\x{0DD6}\x{0E31}\x{0E34}-\x{0E3A}\x{0E47}-\x{0E4E}\x{0EB1}\x{0EB4}-\x{0EB9}\x{0EBB}\x{0EBC}\x{0EC8}-\x{0ECD}\x{0F18}\x{0F19}\x{0F35}\x{0F37}\x{0F39}\x{0F71}-\x{0F7E}\x{0F80}-\x{0F84}\x{0F86}\x{0F87}\x{0F8D}-\x{0F97}\x{0F99}-\x{0FBC}\x{0FC6}\x{102D}-\x{1030}\x{1032}-\x{1037}\x{1039}\x{103A}\x{103D}\x{103E}\x{1058}\x{1059}\x{105E}-\x{1060}\x{1071}-\x{1074}\x{1082}\x{1085}\x{1086}\x{108D}\x{109D}\x{135D}-\x{135F}\x{1712}-\x{1714}\x{1732}-\x{1734}\x{1752}\x{1753}\x{1772}\x{1773}\x{17B4}\x{17B5}\x{17B7}-\x{17BD}\x{17C6}\x{17C9}-\x{17D3}\x{17DD}\x{180B}-\x{180D}\x{18A9}\x{1920}-\x{1922}\x{1927}\x{1928}\x{1932}\x{1939}-\x{193B}\x{1A17}\x{1A18}\x{1A56}\x{1A58}-\x{1A5E}\x{1A60}\x{1A62}\x{1A65}-\x{1A6C}\x{1A73}-\x{1A7C}\x{1A7F}\x{1B00}-\x{1B03}\x{1B34}\x{1B36}-\x{1B3A}\x{1B3C}\x{1B42}\x{1B6B}-\x{1B73}\x{1B80}\x{1B81}\x{1BA2}-\x{1BA5}\x{1BA8}\x{1BA9}\x{1BE6}\x{1BE8}\x{1BE9}\x{1BED}\x{1BEF}-\x{1BF1}\x{1C2C}-\x{1C33}\x{1C36}\x{1C37}\x{1CD0}-\x{1CD2}\x{1CD4}-\x{1CE0}\x{1CE2}-\x{1CE8}\x{1CED}\x{1DC0}-\x{1DE6}\x{1DFC}-\x{1DFF}\x{200B}\x{200E}\x{200F}\x{202A}-\x{202E}\x{2060}-\x{2064}\x{206A}-\x{206F}\x{20D0}-\x{20F0}\x{2CEF}-\x{2CF1}\x{2D7F}\x{2DE0}-\x{2DFF}\x{302A}-\x{302F}\x{3099}\x{309A}\x{A66F}-\x{A672}\x{A67C}\x{A67D}\x{A6F0}\x{A6F1}\x{A802}\x{A806}\x{A80B}\x{A825}\x{A826}\x{A8C4}\x{A8E0}-\x{A8F1}\x{A926}-\x{A92D}\x{A947}-\x{A951}\x{A980}-\x{A982}\x{A9B3}\x{A9B6}-\x{A9B9}\x{A9BC}\x{AA29}-\x{AA2E}\x{AA31}\x{AA32}\x{AA35}\x{AA36}\x{AA43}\x{AA4C}\x{AAB0}\x{AAB2}-\x{AAB4}\x{AAB7}\x{AAB8}\x{AABE}\x{AABF}\x{AAC1}\x{ABE5}\x{ABE8}\x{ABED}\x{FB1E}\x{FE00}-\x{FE0F}\x{FE20}-\x{FE26}\x{FEFF}\x{FFF9}-\x{FFFB}\x{101FD}\x{10A01}-\x{10A03}\x{10A05}\x{10A06}\x{10A0C}-\x{10A0F}\x{10A38}-\x{10A3A}\x{10A3F}\x{11001}\x{11038}-\x{11046}\x{11080}\x{11081}\x{110B3}-\x{110B6}\x{110B9}\x{110BA}\x{110BD}\x{1D167}-\x{1D169}\x{1D173}-\x{1D182}\x{1D185}-\x{1D18B}\x{1D1AA}-\x{1D1AD}\x{1D242}-\x{1D244}\x{E0001}\x{E0020}-\x{E007F}\x{E0100}-\x{E01EF}]/;

sub _validate_contextj {
  my($l,%param) = @_;
  no warnings 'utf8';
  return 1 unless defined($l) && length($l);

# catch ContextJ characters without defined rule (as of Unicode 6.0.0, this cannot match)
#
  $l =~ m/([^\x{200C}\x{200D}\P{Join_Control}])/ and croak sprintf "contains CONTEXTJ character U+%04X without defined rule [C1]", ord($1);

# RFC 5892, Appendix A.1. ZERO WIDTH NON-JOINER
#    Code point:
#       U+200C
# 
#    Overview:
#       This may occur in a formally cursive script (such as Arabic) in a
#       context where it breaks a cursive connection as required for
#       orthographic rules, as in the Persian language, for example.  It
#       also may occur in Indic scripts in a consonant-conjunct context
#       (immediately following a virama), to control required display of
#       such conjuncts.
# 
# 
#    Lookup:
#       True
#
#    Rule Set:
#       False;
#       If Canonical_Combining_Class(Before(cp)) .eq.  Virama Then True;
#       If RegExpMatch((Joining_Type:{L,D})(Joining_Type:T)*\u200C
#          (Joining_Type:T)*(Joining_Type:{R,D})) Then True;

  $l =~ m/
	$_RE_Ccc_Virama
	\x{200C}
     |
	(?: $_RE_JoiningType_L | $_RE_JoiningType_D) $_RE_JoiningType_T*
	\x{200C}
	 $_RE_JoiningType_T*(?: $_RE_JoiningType_R | $_RE_JoiningType_D)
     |
	(\x{200C})
    /xo and defined($1) and croak sprintf "rule for CONTEXTJ character U+%04X not satisfied [C2]", ord($1);

# RFC 5892, Appendix A.2. ZERO WIDTH JOINER
#
#    Code point:
#       U+200D
# 
#    Overview:
#       This may occur in Indic scripts in a consonant-conjunct context
#       (immediately following a virama), to control required display of
#       such conjuncts.
# 
#    Lookup:
#       True

#    Rule Set:
#       False;
#       If Canonical_Combining_Class(Before(cp)) .eq.  Virama Then True;

  $l =~ m/
	$_RE_Ccc_Virama
	\x{200D}
     |
	(\x{200D})
    /xo and defined($1) and croak sprintf "rule for CONTEXTJ character U+%04X not satisfied [C2]", ord($1);
}

1;

__END__

=encoding utf8

=head1 NAME

Net::IDN::UTS46 - Unicode IDNA Compatibility Processing (S<UTS #46>)

=head1 SYNOPSIS

  use Net::IDN:: ':all';
  my $a = uts46_to_ascii("müller.example.org");
  my $b = Net::IDN::UTS46::to_unicode('EXAMPLE.XN--11B5BS3A9AJ6G');
  
  $domain =~ m/\P{Net::IDN::UTS46::IsDisallowed} and die 'oops';

=head1 DESCRIPTION

This module implements the Unicode Technical Standard #46 (Unicode IDNA
Compatibility Processing). UTS #46 is one variant of Internationalized Domain
Names (IDN), which aims to be compatible with domain names registered under
either IDNA2003 or IDNA2008.

You should use this module if you want an exact implementation of the UTS #46
specification.

However, if you just want to convert domain names and don't care which standard
is used internally, you should use L<Net::IDN::Encode> instead.

=head1 FUNCTIONS

By default, this module does not export any subroutines. You may use the
C<:all> tag to import everything. 

You can omit the C<'uts46_'> prefix when accessing the functions with a
full-qualified module name (e.g. you can access C<uts46_to_unicode> as
C<Net::IDN::UTS46::uts46_to_unicode> or C<Net::IDN::UTS46::to_unicode>. 

The following functions are available:

=over

=item uts46_to_ascii( $domain, %param )

Implements the "ToASCII" function from UTS #46, section 4.2. It converts a domain name to
ASCII and throws an exception on invalid input.

This function takes the following optional parameters (C<%param>):

=over

=item AllowUnassigned

(boolean) If set to a true value, unassigned code points in the label are
allowed. This is an extension over UTS #46.

The default is false.

=item UseSTD3ASCIIRules

(boolean) If set to a true value, checks the label for compliance with S<STD 3>
(S<RFC 1123>) syntax for host name parts.

The default is true.

=item TransitionalProcessing

(boolean) If set to true, the conversion will be compatible with IDNA2003. This
only affects four characters: C<'ß'> (U+00DF), 'ς' (U+03C2), ZWJ (U+200D) and
ZWNJ (U+200C). Usually, you will want to set this to false.

The default is false.

=back

=item uts46_to_unicode( $label, %param )

Implements the "ToUnicode" function from UTS #46, section 4.3. It converts a domain name to
Unicode and throws an exception on invalid input.

This function takes the following optional parameters (C<%param>):

=over

=item AllowUnassigned

  see above.

=item UseSTD3ASCIIRules

  see above.

=item TransitionalProcessing

(boolean) If given, this parameter must be false. The UTS #46 specification
does not define transitional processing for ToUnicode.

=back

=back

=head1 UNICODE CHARACTER PROPERTIES

This module also defines the character properties listed below.

Each character has exactly one of the following properties:

=over

=item C<\p{Net::IDN::UTS46::IsValid}>

The code point is valid, and not modified (i.e. a deviation character) in UTS #46.

=item C<\p{Net::IDN::UTS46::IsIgnored}>

The code point is removed (i.e. mapped to an empty string) in UTS #46.

=item C<\p{Net::IDN::UTS46::IsMapped}>

The code point is replaced by another string in UTS #46.

=item C<\p{Net::IDN::UTS46::IsDeviation}>

The code point is either mapped or valid, depending on whether the processing is transitional or not.

=item C<\p{Net::IDN::UTS46::IsDisallowed}>

The code point is not allowed in UTS #46.

=item C<\p{Net::IDN::UTS46::IsDisallowedSTD3Ignored}>

The code point is not allowed in UTS #46 if C<UseSTDASCIIRules> are used but would be ignored otherwise.

=item C<\p{Net::IDN::UTS46::IsDisallowedSTD3Mapped}>

The code point is not allowed in UTS #46 if C<UseSTDASCIIRules> are used but would be mapped otherwise.

=back

=head1 AUTHOR

Claus FE<auml>rber <CFAERBER@cpan.org>

=head1 LICENSE

Copyright 2011-2014 Claus FE<auml>rber.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Net::IDN::UTS46::Mapping>, L<Net::IDN::Encode>, S<UTS #46> (L<http://www.unicode.org/reports/tr46/>)
