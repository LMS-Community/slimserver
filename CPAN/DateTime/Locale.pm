package DateTime::Locale;

use 5.008004;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '1.45';

use DateTime::Locale::Data;
use DateTime::Locale::FromData;
use DateTime::Locale::Util qw( parse_locale_code );
use Params::ValidationCompiler 0.13 qw( validation_for );
use Specio::Library::String;

my %Class;
my %DataForCode;
my %NameToCode;
my %NativeNameToCode;
my %UserDefinedAlias;

my %LoadCache;

sub register {
    my $class = shift;

    %LoadCache = ();

    if ( ref $_[0] ) {
        $class->_register(%$_) foreach @_;
    }
    else {
        $class->_register(@_);
    }
}

sub _register {
    shift;
    my %p = @_;

    my $id = $p{id};

    die q{'\@' or '=' are not allowed in locale ids}
        if $id =~ /[\@=]/;

    die
        "You cannot replace an existing locale ('$id') unless you also specify the 'replace' parameter as true\n"
        if !delete $p{replace} && exists $DataForCode{$id};

    $p{native_language} = $p{en_language}
        unless exists $p{native_language};

    my @en_pieces;
    my @native_pieces;
    foreach my $p (qw( language script territory variant )) {
        push @en_pieces,     $p{"en_$p"}     if exists $p{"en_$p"};
        push @native_pieces, $p{"native_$p"} if exists $p{"native_$p"};
    }

    $p{en_complete_name}     = join q{ }, @en_pieces;
    $p{native_complete_name} = join q{ }, @native_pieces;

    $id =~ s/_/-/g;

    $DataForCode{$id} = \%p;

    $NameToCode{ $p{en_complete_name} }           = $id;
    $NativeNameToCode{ $p{native_complete_name} } = $id;

    $Class{$id} = $p{class} if defined exists $p{class};
}

sub register_from_data {
    shift;

    %LoadCache = ();

    my %p = ref $_[0] ? %{ $_[0] } : @_;

    my $code = $p{code};

    die q{'\@' or '=' are not allowed in locale codes}
        if $code =~ /[\@=]/;

    $code =~ s/_/-/g;

    DateTime::Locale::Data::add_locale( $code, \%p );
    return $LoadCache{$code} = DateTime::Locale::FromData->new( \%p );
}

sub add_aliases {
    shift;

    %LoadCache = ();

    my $aliases = ref $_[0] ? $_[0] : {@_};

    for my $alias ( keys %{$aliases} ) {
        my $code = $aliases->{$alias};

        die q{Can't alias an id to itself}
            if $alias eq $code;

        # check for overwrite?

        my %seen = ( $alias => 1, $code => 1 );
        my $copy = $code;
        while ( $copy = $UserDefinedAlias{$copy} ) {
            die
                "Creating an alias from $alias to $code would create a loop.\n"
                if $seen{$copy};

            $seen{$copy} = 1;
        }

        $UserDefinedAlias{$alias} = $code;
    }
}

sub remove_alias {
    shift;

    %LoadCache = ();

    my $alias = shift;

    return delete $UserDefinedAlias{$alias};
}

# deprecated
sub ids {
    shift->codes;
}

## no critic (Variables::ProhibitPackageVars)
sub codes {
    wantarray
        ? keys %DateTime::Locale::Data::Codes
        : [ keys %DateTime::Locale::Data::Codes ];
}

sub names {
    wantarray
        ? keys %DateTime::Locale::Data::Names
        : [ keys %DateTime::Locale::Data::Names ];
}

sub native_names {
    wantarray
        ? keys %DateTime::Locale::Data::NativeNames
        : [ keys %DateTime::Locale::Data::NativeNames ];
}

# These are hard-coded for backwards comaptibility with the DateTime::Language
# code.
my %DateTimeLanguageAliases = (

    #    'Afar'      => 'aa',
    'Amharic'   => 'am-ET',
    'Austrian'  => 'de-AT',
    'Brazilian' => 'pt-BR',
    'Czech'     => 'cs-CZ',
    'Danish'    => 'da-DK',
    'Dutch'     => 'nl-NL',
    'English'   => 'en-US',
    'French'    => 'fr-FR',

    #      'Gedeo'             => undef, # XXX
    'German'    => 'de-DE',
    'Italian'   => 'it-IT',
    'Norwegian' => 'no-NO',
    'Oromo'     => 'om-ET',    # Maybe om-KE or plain om ?
    'Portugese' => 'pt-PT',

    #    'Sidama'            => 'sid',
    'Somali'  => 'so-SO',
    'Spanish' => 'es-ES',
    'Swedish' => 'sv-SE',

    #    'Tigre'             => 'tig',
    'TigrinyaEthiopian' => 'ti-ET',
    'TigrinyaEritrean'  => 'ti-ER',
);

my %POSIXAliases = (
    C     => 'en-US',
    POSIX => 'en-US',
);

{
    my $validator = validation_for(
        name             => '_check_load_params',
        name_is_optional => 1,
        params           => [
            { type => t('NonEmptyStr') },
        ],
    );

    sub load {
        my $class = shift;
        my ($code) = $validator->(@_);

        # We used to use underscores in codes instead of dashes. We want to
        # support both indefinitely.
        $code =~ tr/_/-/;

        # Strip off charset for LC_* codes : en_GB.UTF-8 etc
        $code =~ s/\..*$//;

        return $LoadCache{$code} if exists $LoadCache{$code};

        while ( exists $UserDefinedAlias{$code} ) {
            $code = $UserDefinedAlias{$code};
        }

        $code = $DateTimeLanguageAliases{$code}
            if exists $DateTimeLanguageAliases{$code};
        $code = $POSIXAliases{$code} if exists $POSIXAliases{$code};
        $code = $DateTime::Locale::Data::ISO639Aliases{$code}
            if exists $DateTime::Locale::Data::ISO639Aliases{$code};

        if ( exists $DateTime::Locale::Data::Codes{$code} ) {
            return $class->_locale_object_for($code);
        }

        if ( exists $DateTime::Locale::Data::Names{$code} ) {
            return $class->_locale_object_for(
                $DateTime::Locale::Data::Names{$code} );
        }

        if ( exists $DateTime::Locale::Data::NativeNames{$code} ) {
            return $class->_locale_object_for(
                $DateTime::Locale::Data::NativeNames{$code} );
        }

        if ( my $locale = $class->_registered_locale_for($code) ) {
            return $locale;
        }

        if ( my $guessed = $class->_guess_code($code) ) {
            return $class->_locale_object_for($guessed);
        }

        die "Invalid locale code or name: $code\n";
    }
}

sub _guess_code {
    shift;
    my $code = shift;

    my %codes = parse_locale_code($code);

    my @guesses;

    if ( $codes{script} ) {
        my $guess = join q{-}, $codes{language}, $codes{script};

        push @guesses, $guess;

        $guess .= q{-} . $codes{territory} if defined $codes{territory};

        # version with script comes first
        unshift @guesses, $guess;
    }

    if ( $codes{variant} ) {
        push @guesses, join q{-}, $codes{language}, $codes{territory},
            $codes{variant};
    }

    if ( $codes{territory} ) {
        push @guesses, join q{-}, $codes{language}, $codes{territory};
    }

    push @guesses, $codes{language};

    for my $code (@guesses) {
        return $code
            if exists $DateTime::Locale::Data::Codes{$code}
            || exists $DateTime::Locale::Data::Names{$code};
    }
}

sub _locale_object_for {
    shift;
    my $code = shift;

    my $data = DateTime::Locale::Data::locale_data($code)
        or return;

    # We want to make a copy of the data just in case ...
    return $LoadCache{$code} = DateTime::Locale::FromData->new( \%{$data} );
}

sub _registered_locale_for {
    my $class = shift;
    my $code  = shift;

    # Custom locale registered by user
    if ( $Class{$code} ) {
        return $LoadCache{$code}
            = $class->_load_class_from_code( $code, $Class{$code} );
    }

    if ( $DataForCode{$code} ) {
        return $LoadCache{$code} = $class->_load_class_from_code($code);
    }

    if ( $NameToCode{$code} ) {
        return $LoadCache{$code}
            = $class->_load_class_from_code( $NameToCode{$code} );
    }

    if ( $NativeNameToCode{$code} ) {
        return $LoadCache{$code}
            = $class->_load_class_from_code( $NativeNameToCode{$code} );
    }
}

sub _load_class_from_code {
    my $class      = shift;
    my $code       = shift;
    my $real_class = shift;

    # We want the first alias for which there is data, even if it has
    # no corresponding .pm file.  There may be multiple levels of
    # alias to go through.
    my $data_code = $code;
    while ( exists $UserDefinedAlias{$data_code}
        && !exists $DataForCode{$data_code} ) {

        $data_code = $UserDefinedAlias{$data_code};
    }

    ( my $underscore_code = $data_code ) =~ s/-/_/g;
    $real_class ||= "DateTime::Locale::$underscore_code";

    unless ( $real_class->can('new') ) {
        ## no critic (BuiltinFunctions::ProhibitStringyEval, ErrorHandling::RequireCheckingReturnValueOfEval)
        eval "require $real_class";
        die $@ if $@;
        ## use critic
    }

    my $locale = $real_class->new(
        %{ $DataForCode{$data_code} },
        code => $code,
    );

    if ( $locale->can('cldr_version') ) {
        my $object_version = $locale->cldr_version;

        if ( $object_version ne $DateTime::Locale::Data::CLDRVersion ) {
            warn
                "Loaded $real_class, which is from an older version ($object_version)"
                . ' of the CLDR database than this installation of'
                . " DateTime::Locale ($DateTime::Locale::Data::CLDRVersion).\n";
        }
    }

    return $locale;
}
## use critic

1;

# ABSTRACT: Localization support for DateTime.pm

__END__

=pod

=encoding UTF-8

=head1 NAME

DateTime::Locale - Localization support for DateTime.pm

=head1 VERSION

version 1.45

=head1 SYNOPSIS

  use DateTime::Locale;

  my $loc = DateTime::Locale->load('en-GB');

  print $loc->native_name, "\n", $loc->datetime_format_long, "\n";

  # but mostly just things like ...

  my $dt = DateTime->now( locale => 'fr' );
  print "Aujourd'hui le mois est " . $dt->month_name, "\n";

=head1 DESCRIPTION

DateTime::Locale is primarily a factory for the various locale subclasses. It
also provides some functions for getting information on all the available
locales.

If you want to know what methods are available for locale objects, then please
read the L<DateTime::Locale::FromData> documentation.

=head1 USAGE

This module provides the following class methods:

=head2 DateTime::Locale->load( $locale_code | $locale_name )

Returns the locale object for the specified locale code or name - see the
L<DateTime::Locale::Catalog> documentation for the list of available codes and
names. The name provided may be either the English or native name.

If the requested locale is not found, a fallback search takes place to find a
suitable replacement.

The fallback search order is:

  {language}-{script}-{territory}
  {language}-{script}
  {language}-{territory}-{variant}
  {language}-{territory}
  {language}

Eg. For the locale code C<es-XX-UNKNOWN> the fallback search would be:

  es-XX-UNKNOWN   # Fails - no such locale
  es-XX           # Fails - no such locale
  es              # Found - the es locale is returned as the
                  # closest match to the requested id

Eg. For the locale code C<es-Latn-XX> the fallback search would be:

  es-Latn-XX      # Fails - no such locale
  es-Latn         # Fails - no such locale
  es-XX           # Fails - no such locale
  es              # Found - the es locale is returned as the
                  # closest match to the requested id

If no suitable replacement is found, then an exception is thrown.

The loaded locale is cached, so that B<locale objects may be singletons>.
Calling C<< DateTime::Locale->register_from_data >>, C<<
DateTime::Locale->add_aliases >>, or C<< DateTime::Locale->remove_alias >>
clears the cache.

=head2 DateTime::Locale->codes

  my @codes = DateTime::Locale->codes;
  my $codes = DateTime::Locale->codes;

Returns an unsorted list of the available locale codes, or an array reference
if called in a scalar context. This list does not include aliases.

=head2 DateTime::Locale->names

  my @names = DateTime::Locale->names;
  my $names = DateTime::Locale->names;

Returns an unsorted list of the available locale names in English, or an array
reference if called in a scalar context.

=head2 DateTime::Locale->native_names

  my @names = DateTime::Locale->native_names;
  my $names = DateTime::Locale->native_names;

Returns an unsorted list of the available locale names in their native
language, or an array reference if called in a scalar context. All native names
use UTF-8 as appropriate.

=head2 DateTime::Locale->register_from_data( $locale_data )

This method allows you to register a custom locale. The data for the locale is
specified as a hash (or hashref) where the keys match the method names given in
L<DateTime::Locale::FromData>.

If you just want to make some small changes on top of an existing locale you
can get that locale's data by calling C<< $locale->locale_data >>.

Here is an example of making a custom locale based off of C<en-US>:

  my $locale = DateTime::Locale->load('en-US');
  my %data   = $locale->locale_data;
  $data{code}               = 'en-US-CUSTOM';
  $data{time_format_medium} = 'HH:mm:ss';

  DateTime::Locale->register_from_data(%data);

  # Prints 18:24:38
  say DateTime->now( locale => 'en-US-CUSTOM' )->strftime('%X');

  # Prints 6:24:38 PM
  say DateTime->now( locale => 'en-US' )->strftime('%X');

The keys that should be present in the hash are the same as the accessor
methods provided by L<DateTime::Locale::FromData>, except for the following:

=over 4

=item The C<*_code> methods

While you should provide a C<code> key, the other methods like C<language_code>
and C<script_code> are determined by parsing the code.

=item All C<id> returning methods

These are aliases for the corresponding C<*code> methods.

=item C<prefers_24_hour_time>

This is determined by looking at the short time format to see how it formats
hours,

=item C<date_format_default> and C<time_format_default>

These are the corresponding medium formats.

=item C<datetime_format> and C<datetime_format_default>

This is the same as the medium format.

=item C<date_formats> and C<time_formats>

These are calculated as needed.

=item C<available_formats>

This should be provided as a hashref where the keys are things like C<Gy> or
C<MMMEd> and the values are an actual format like C<"y G"> or C<"E, MMM d">.

=item C<locale_data>

This is everything you pass in.

=back

=head1 LOADING LOCALES IN A PRE-FORKING SYSTEM

If you are running an application that does pre-forking (for example with
Starman), then you should try to load all the locales that you'll need in the
parent process. Locales are loaded on-demand, so loading them once in each
child will waste memory that could otherwise be shared.

=head1 CLDR DATA BUGS

Please be aware that all locale data has been generated from the CLDR (Common
Locale Data Repository) project locales data). The data is incomplete, and may
contain errors in some locales.

When reporting errors in data, please check the primary data sources first,
then where necessary report errors directly to the primary source via the CLDR
bug report system. See L<http://unicode.org/cldr/filing_bug_reports.html> for
details.

Once these errors have been confirmed, please forward the error report and
corrections to the DateTime mailing list, datetime@perl.org.

=head1 AUTHOR EMERITUS

Richard Evans wrote the first version of DateTime::Locale, including the tools
to extract the CLDR data.

=head1 SEE ALSO

datetime@perl.org mailing list

=head1 SUPPORT

Bugs may be submitted at L<https://github.com/houseabsolute/DateTime-Locale/issues>.

There is a mailing list available for users of this distribution,
L<mailto:datetime@perl.org>.

=head1 SOURCE

The source code repository for DateTime-Locale can be found at L<https://github.com/houseabsolute/DateTime-Locale>.

=head1 DONATIONS

If you'd like to thank me for the work I've done on this module, please
consider making a "donation" to me via PayPal. I spend a lot of free time
creating free software, and would appreciate any support you'd care to offer.

Please note that B<I am not suggesting that you must do this> in order for me
to continue working on this particular software. I will continue to do so,
inasmuch as I have in the past, for as long as it interests me.

Similarly, a donation made in this way will probably not make me work on this
software much more, unless I get so many donations that I can consider working
on free software full time (let's all have a chuckle at that together).

To donate, log into PayPal and send money to autarch@urth.org, or use the
button at L<https://houseabsolute.com/foss-donations/>.

=head1 AUTHOR

Dave Rolsky <autarch@urth.org>

=head1 CONTRIBUTORS

=for stopwords Alexander Pankoff Jacques Deguest James Raspass Karen Etheridge Mohammad S Anwar Ryley Breiddal Sergey Leschenko yasu47b

=over 4

=item *

Alexander Pankoff <ccntrq@screenri.de>

=item *

Jacques Deguest <jack@deguest.jp>

=item *

James Raspass <jraspass@gmail.com>

=item *

Karen Etheridge <ether@cpan.org>

=item *

Mohammad S Anwar <mohammad.anwar@yahoo.com>

=item *

Ryley Breiddal <rbreiddal@presinet.com>

=item *

Sergey Leschenko <Sergey.Leschenko@portaone.com>

=item *

yasu47b <nakayamayasuhiro1986@gmail.com>

=back

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2003 - 2025 by Dave Rolsky.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

The full text of the license can be found in the
F<LICENSE> file included with this distribution.

=cut
