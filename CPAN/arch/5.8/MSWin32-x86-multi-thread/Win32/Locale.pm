
package Win32::Locale;
# Time-stamp: "2004-01-11 18:56:06 AST"
use strict;
use vars qw($VERSION %MSLocale2LangTag);
$VERSION = '0.04';
%MSLocale2LangTag = (

  0x0436 => 'af'   ,  # <AFK> <Afrikaans> <Afrikaans>
  0x041c => 'sq'   ,  # <SQI> <Albanian> <Albanian>

  0x0401 => 'ar-sa',  # <ARA> <Arabic> <Arabic (Saudi Arabia)>
  0x0801 => 'ar-iq',  # <ARI> <Arabic> <Arabic (Iraq)>
  0x0C01 => 'ar-eg',  # <ARE> <Arabic> <Arabic (Egypt)>
  0x1001 => 'ar-ly',  # <ARL> <Arabic> <Arabic (Libya)>
  0x1401 => 'ar-dz',  # <ARG> <Arabic> <Arabic (Algeria)>
  0x1801 => 'ar-ma',  # <ARM> <Arabic> <Arabic (Morocco)>
  0x1C01 => 'ar-tn',  # <ART> <Arabic> <Arabic (Tunisia)>
  0x2001 => 'ar-om',  # <ARO> <Arabic> <Arabic (Oman)>
  0x2401 => 'ar-ye',  # <ARY> <Arabic> <Arabic (Yemen)>
  0x2801 => 'ar-sy',  # <ARS> <Arabic> <Arabic (Syria)>
  0x2C01 => 'ar-jo',  # <ARJ> <Arabic> <Arabic (Jordan)>
  0x3001 => 'ar-lb',  # <ARB> <Arabic> <Arabic (Lebanon)>
  0x3401 => 'ar-kw',  # <ARK> <Arabic> <Arabic (Kuwait)>
  0x3801 => 'ar-ae',  # <ARU> <Arabic> <Arabic (U.A.E.)>
  0x3C01 => 'ar-bh',  # <ARH> <Arabic> <Arabic (Bahrain)>
  0x4001 => 'ar-qa',  # <ARQ> <Arabic> <Arabic (Qatar)>

  0x042b => 'hy'   ,  # <HYE> <Armenian> <Armenian>
  0x044d => 'as'   ,  # <ASM> <Assamese> <Assamese>
  0x042c => 'az-latn',  # <AZE> <Azeri> <Azeri (Latin)>
  0x082c => 'az-cyrl',  # <AZC> <Azeri> <Azeri (Cyrillic)>
  0x042D => 'eu'   ,  # <EUQ> <Basque> <Basque>
  0x0423 => 'be'   ,  # <BEL> <Belarussian> <Belarussian>
  0x0445 => 'bn'   ,  # <BEN> <Bengali> <Bengali>
  0x0402 => 'bg'   ,  # <BGR> <Bulgarian> <Bulgarian>
  0x0403 => 'ca'   ,  # <CAT> <Catalan> <Catalan>

  # Chinese is zh, not cn!
  0x0404 => 'zh-tw',  # <CHT> <Chinese> <Chinese (Taiwan)>
  0x0804 => 'zh-cn',  # <CHS> <Chinese> <Chinese (PRC)>
  0x0C04 => 'zh-hk',  # <ZHH> <Chinese> <Chinese (Hong Kong)>
  0x1004 => 'zh-sg',  # <ZHI> <Chinese> <Chinese (Singapore)>
  0x1404 => 'zh-mo',  # <ZHM> <Chinese> <Chinese (Macau SAR)>

  0x041a => 'hr'   ,  # <HRV> <Croatian> <Croatian>
  0x0405 => 'cs'   ,  # <CSY> <Czech> <Czech>
  0x0406 => 'da'   ,  # <DAN> <Danish> <Danish>
  0x0413 => 'nl-nl',  # <NLD> <Dutch> <Dutch (Netherlands)>
  0x0813 => 'nl-be',  # <NLB> <Dutch> <Dutch (Belgium)>
  
  0x0409 => 'en-us',  # <ENU> <English> <English (United States)>
  0x0809 => 'en-gb',  # <ENG> <English> <English (United Kingdom)>
  0x0c09 => 'en-au',  # <ENA> <English> <English (Australia)>
  0x1009 => 'en-ca',  # <ENC> <English> <English (Canada)>
  0x1409 => 'en-nz',  # <ENZ> <English> <English (New Zealand)>
  0x1809 => 'en-ie',  # <ENI> <English> <English (Ireland)>
  0x1c09 => 'en-za',  # <ENS> <English> <English (South Africa)>
  0x2009 => 'en-jm',  # <ENJ> <English> <English (Jamaica)>
  0x2409 => 'en-jm',  # <ENB> <English> <English (Caribbean)>  # a hack
  0x2809 => 'en-bz',  # <ENL> <English> <English (Belize)>
  0x2c09 => 'en-tt',  # <ENT> <English> <English (Trinidad)>
  0x3009 => 'en-zw',  # <ENW> <English> <English (Zimbabwe)>
  0x3409 => 'en-ph',  # <ENP> <English> <English (Philippines)>
  
  0x0425 => 'et'   ,  # <ETI> <Estonian> <Estonian>
  0x0438 => 'fo'   ,  # <FOS> <Faeroese> <Faeroese>
  0x0429 => 'pa'   ,  # <FAR> <Farsi> <Farsi>   # =Persian
  0x040b => 'fi'   ,  # <FIN> <Finnish> <Finnish>
  
  0x040c => 'fr-fr',  # <FRA> <French> <French (France)>
  0x080c => 'fr-be',  # <FRB> <French> <French (Belgium)>
  0x0c0c => 'fr-ca',  # <FRC> <French> <French (Canada)>
  0x100c => 'fr-ch',  # <FRS> <French> <French (Switzerland)>
  0x140c => 'fr-lu',  # <FRL> <French> <French (Luxembourg)>
  0x180c => 'fr-mc',  # <FRM> <French> <French (Monaco)>
  
  0x0437 => 'ka'   ,  # <KAT> <Georgian> <Georgian>
  
  0x0407 => 'de-de',  # <DEU> <German> <German (Germany)>
  0x0807 => 'de-ch',  # <DES> <German> <German (Switzerland)>
  0x0c07 => 'de-at',  # <DEA> <German> <German (Austria)>
  0x1007 => 'de-lu',  # <DEL> <German> <German (Luxembourg)>
  0x1407 => 'de-li',  # <DEC> <German> <German (Liechtenstein)>
  
  0x0408 => 'el'   ,  # <ELL> <Greek> <Greek>
  0x0447 => 'gu'   ,  # <GUJ> <Gujarati> <Gujarati>
  0x040D => 'he'   ,  # <HEB> <Hebrew> <Hebrew>  # formerly 'iw'
  0x0439 => 'hi'   ,  # <HIN> <Hindi> <Hindi>
  0x040e => 'hu'   ,  # <HUN> <Hungarian> <Hungarian>
  0x040F => 'is'   ,  # <ISL> <Icelandic> <Icelandic>
  0x0421 => 'id'   ,  # <IND> <Indonesian> <Indonesian>  # formerly 'in'
  0x0410 => 'it-it',  # <ITA> <Italian> <Italian (Italy)>
  0x0810 => 'it-ch',  # <ITS> <Italian> <Italian (Switzerland)>
  0x0411 => 'ja'   ,  # <JPN> <Japanese> <Japanese>  # not "jp"!
  0x044b => 'kn'   ,  # <KAN> <Kannada> <Kannada>
  0x0860 => 'ks'   ,  # <KAI> <Kashmiri> <Kashmiri (India)>
  0x043f => 'kk'   ,  # <KAZ> <Kazakh> <Kazakh>
  0x0457 => 'kok'  ,  # <KOK> <Konkani> <Konkani>    3-letters!
  0x0412 => 'ko'   ,  # <KOR> <Korean> <Korean>
  0x0812 => 'ko'   ,  # <KOJ> <Korean> <Korean (Johab)>  ?
  0x0426 => 'lv'   ,  # <LVI> <Latvian> <Latvian>  # = lettish
  0x0427 => 'lt'   ,  # <LTH> <Lithuanian> <Lithuanian>
  0x0827 => 'lt'   ,  # <LTH> <Lithuanian> <Lithuanian (Classic)>  ?
  0x042f => 'mk'   ,  # <MKD> <FYOR Macedonian> <FYOR Macedonian>
  0x043e => 'ms'   ,  # <MSL> <Malay> <Malaysian>
  0x083e => 'ms-bn',  # <MSB> <Malay> <Malay Brunei Darussalam>
  0x044c => 'ml'   ,  # <MAL> <Malayalam> <Malayalam>
  0x044e => 'mr'   ,  # <MAR> <Marathi> <Marathi>
  0x0461 => 'ne-np',  # <NEP> <Nepali> <Nepali (Nepal)>
  0x0861 => 'ne-in',  # <NEI> <Nepali> <Nepali (India)>
  0x0414 => 'nb'   ,  # <NOR> <Norwegian> <Norwegian (Bokmal)>   #was no-bok
  0x0814 => 'nn'   ,  # <NON> <Norwegian> <Norwegian (Nynorsk)>  #was no-nyn
                        # note that this leaves nothing using "no" ("Norwegian")
  0x0448 => 'or'   ,  # <ORI> <Oriya> <Oriya>
  0x0415 => 'pl'   ,  # <PLK> <Polish> <Polish>
  0x0416 => 'pt-br',  # <PTB> <Portuguese> <Portuguese (Brazil)>
  0x0816 => 'pt-pt',  # <PTG> <Portuguese> <Portuguese (Portugal)>
  0x0446 => 'pa'   ,  # <PAN> <Punjabi> <Punjabi>
  0x0417 => 'rm'   ,  # <RMS> <Rhaeto-Romanic> <Rhaeto-Romanic>
  0x0418 => 'ro'   ,  # <ROM> <Romanian> <Romanian>
  0x0818 => 'ro-md',  # <ROV> <Romanian> <Romanian (Moldova)>
  0x0419 => 'ru'   ,  # <RUS> <Russian> <Russian>
  0x0819 => 'ru-md',  # <RUM> <Russian> <Russian (Moldova)>
  0x043b => 'se'   ,  # <SZI> <Sami> <Sami (Lappish)>  assuming == "Northern Sami"
  0x044f => 'sa'   ,  # <SAN> <Sanskrit> <Sanskrit>
  0x0c1a => 'sr-cyrl', # <SRB> <Serbian> <Serbian (Cyrillic)>
  0x081a => 'sr-latn', # <SRL> <Serbian> <Serbian (Latin)>
  0x0459 => 'sd'   ,  # <SND> <Sindhi> <Sindhi>
  0x041b => 'sk'   ,  # <SKY> <Slovak> <Slovak>
  0x0424 => 'sl'   ,  # <SLV> <Slovenian> <Slovenian>
  0x042e => 'wen'  ,  # <SBN> <Sorbian> <Sorbian>  # !!! 3 letters
  
  0x040a => 'es-es',  # <ESP> <Spanish> <Spanish (Spain - Traditional Sort)>
  0x080a => 'es-mx',  # <ESM> <Spanish> <Spanish (Mexico)>
  0x0c0a => 'es-es',  # <ESN> <Spanish> <Spanish (Spain - Modern Sort)>
  0x100a => 'es-gt',  # <ESG> <Spanish> <Spanish (Guatemala)>
  0x140a => 'es-cr',  # <ESC> <Spanish> <Spanish (Costa Rica)>
  0x180a => 'es-pa',  # <ESA> <Spanish> <Spanish (Panama)>
  0x1c0a => 'es-do',  # <ESD> <Spanish> <Spanish (Dominican Republic)>
  0x200a => 'es-ve',  # <ESV> <Spanish> <Spanish (Venezuela)>
  0x240a => 'es-co',  # <ESO> <Spanish> <Spanish (Colombia)>
  0x280a => 'es-pe',  # <ESR> <Spanish> <Spanish (Peru)>
  0x2c0a => 'es-ar',  # <ESS> <Spanish> <Spanish (Argentina)>
  0x300a => 'es-ec',  # <ESF> <Spanish> <Spanish (Ecuador)>
  0x340a => 'es-cl',  # <ESL> <Spanish> <Spanish (Chile)>
  0x380a => 'es-uy',  # <ESY> <Spanish> <Spanish (Uruguay)>
  0x3c0a => 'es-py',  # <ESZ> <Spanish> <Spanish (Paraguay)>
  0x400a => 'es-bo',  # <ESB> <Spanish> <Spanish (Bolivia)>
  0x440a => 'es-sv',  # <ESE> <Spanish> <Spanish (El Salvador)>
  0x480a => 'es-hn',  # <ESH> <Spanish> <Spanish (Honduras)>
  0x4c0a => 'es-ni',  # <ESI> <Spanish> <Spanish (Nicaragua)>
  0x500a => 'es-pr',  # <ESU> <Spanish> <Spanish (Puerto Rico)>
  
  0x0430 => 'st'   ,  # <SXT> <Sutu> <Sutu>  == soto, sesotho
  0x0441 => 'sw-ke',  # <SWK> <Swahili> <Swahili (Kenya)>
  0x041D => 'sv'   ,  # <SVE> <Swedish> <Swedish>
  0x081d => 'sv-fi',  # <SVF> <Swedish> <Swedish (Finland)>
  0x0449 => 'ta'   ,  # <TAM> <Tamil> <Tamil>
  0x0444 => 'tt'   ,  # <TAT> <Tatar> <Tatar (Tatarstan)>
  0x044a => 'te'   ,  # <TEL> <Telugu> <Telugu>
  0x041E => 'th'   ,  # <THA> <Thai> <Thai>
  0x0431 => 'ts'   ,  # <TSG> <Tsonga> <Tsonga>    (not Tonga!)
  0x0432 => 'tn'   ,  # <TNA> <Tswana> <Tswana>    == Setswana
  0x041f => 'tr'   ,  # <TRK> <Turkish> <Turkish>
  0x0422 => 'uk'   ,  # <UKR> <Ukrainian> <Ukrainian>
  0x0420 => 'ur-pk',  # <URD> <Urdu> <Urdu (Pakistan)>
  0x0820 => 'ur-in',  # <URI> <Urdu> <Urdu (India)>
  0x0443 => 'uz-latn',  # <UZB> <Uzbek> <Uzbek (Latin)>
  0x0843 => 'uz-cyrl',  # <UZC> <Uzbek> <Uzbek (Cyrillic)>
  0x0433 => 'ven'  ,  # <VEN> <Venda> <Venda>
  0x042a => 'vi'   ,  # <VIT> <Vietnamese> <Vietnamese>
  0x0434 => 'xh'   ,  # <XHS> <Xhosa> <Xhosa>
  0x043d => 'yi'   ,  # <JII> <Yiddish> <Yiddish>  # formetly ji
  0x0435 => 'zu'   ,  # <ZUL> <Zulu> <Zulu>
);
#-----------------------------------------------------------------------------

sub get_ms_locale {
  my $locale;
  return unless defined do {
    # see if there's a W32 registry on this machine, and if so, look in it
    local $SIG{"__DIE__"} = "";
    eval '
      use Win32::TieRegistry ();
      my $i18n = Win32::TieRegistry->new(
         "HKEY_CURRENT_USER/Control Panel/International",
         { Delimiter => "/" }
      );
      #print "no key!" unless $i18n;
      $locale = $i18n->GetValue("Locale") if $i18n;
      undef $i18n;
    ';
    #print "<$@>\n" if $@;
    $locale;
  };
  return unless $locale =~ m/^[0-9a-fA-F]+$/s;
  return hex($locale);
}

sub get_language {
  my $lang = $MSLocale2LangTag{ $_[0] || get_ms_locale() || '' };
  return unless $lang;
  return $lang;
}

sub get_locale {
  # I guess this is right.
  my $lang = get_language(@_);
  return unless $lang and $lang =~ m/^[a-z]{2}(?:-[a-z]{2})?$/s;
  
  # should we try to turn "fi" into "fi_FI"?
  
  $lang =~ tr/-/_/;
  return $lang;
}
#-----------------------------------------------------------------------------

# If we're just executed...
unless(caller) {
  my $locale = get_ms_locale();
  if($locale) {
    printf "Locale 0x%08x (%s => %s) => Lang %s\n",
      $locale, $locale,
      get_locale($locale)   || '?',
      get_language($locale) || '?',
  } else {
    print "Can't get ms-locale\n";
  }
}

#-----------------------------------------------------------------------------
1;

__END__

=head1 NAME

Win32::Locale - get the current MSWin locale or language

=head1 SYNOPSIS

  use Win32::Locale;
  my $language = Win32::Locale::get_language();
  if($language eq 'en-us') {
    print "Wasaaap homeslice!\n";
  } else {
    print "You $language people ain't FROM around here, are ya?\n";
  }

=head1 DESCRIPTION

This library provides some simple functions allowing Perl under MSWin
to ask what the current locale/language setting is.  (Yes, MSWin
conflates locales and languages, it seems; and the way it's
conflated is even stranger after MSWin98.)

Note that you should be able to safely use this module under any
OS; the functions just won't be able to access any current
locale value.

=head1 FUNCTIONS

Note that these functions are not exported,
nor are they exportable:

=over

=item Win32::Locale::get_language()

Returns the (all-lowercase) RFC3066 language tag corresponding
to the currently currently selected MS locale.

Returns nothing if the MS locale value isn't accessible
(notably, if you're not running under MSWin!), or if it
corresponds to no known language tag.  Example: "en-us".

In list context, this may in the future be made to return
multiple values.

=item Win32::Locale::get_locale()

Returns the (all-lowercase) Unixish locale tag corresponding
to the currently currently selected MS locale.  Example: "en_us".

Returns nothing if the MS locale value isn't accessible
(notably, if you're not running under MSWin!), or if it
corresponds to no locale.

In list context, this may in the future be made to return
multiple values.

Note that this function is B<experimental>, and I greatly welcome
suggestions.

=item Win32::Locale::get_ms_locale()

Returns the MS locale ID code for the currently selected MSWindows
locale.  For example, returns the number 1033 for "US
English".  (You may know the number 1033 better as 0x00000409,
as these numbers are usually given in hex in MS documents).

Returns nothing if the value isn't accessible (notably, if you're
not running under MSWin!).

=item Win32::Locale::get_language($msid)

Returns the (all-lowercase) RFC3066 language tag corresponding
to the given MS locale code, or nothing if none.

In list context, this may in the future be made to return
multiple values.

=item Win32::Locale::get_locale($msid)

Returns the (all-lowercase) Unixish locale tag corresponding
to the given MS locale code, or nothing if none.

In list context, this may in the future be made to return
multiple values.

=back

("Nothing", above, means "in scalar context, undef; in list
context, empty-list".)

=head1 AND MORE

This module provides an (unexported) public hash,
%Win32::Locale::MSLocale2LangTag, that maps
from the MS locale ID code to my idea of the single best corresponding
RFC3066 language tag.

The hash's contents are relatively certain for well-known
languages (US English is "en-us"), but are still experimental
in its finer details (like Konkani being "kok").

=head1 SEE ALSO

L<I18N::LangTags|I18N::LangTags>,
L<I18N::LangTags::List|I18N::LangTags::List>,
L<Locale::Maketext|Locale::Maketext>.

=head1 COPYRIGHT AND DISCLAIMER

Copyright (c) 2001,2003 Sean M. Burke.  All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

I am not affiliated with the Microsoft corporation, nor the ActiveState
corporation.

Product and company names mentioned in this document may be the
trademarks or service marks of their respective owners.  Trademarks 
and service marks might not be identified as such, although
this must not be construed as anyone's expression of validity
or invalidity of each trademark or service mark.

=head1 AUTHOR

Sean M. Burke C<sburke@cpan.org>

=cut

# No big whoop.

