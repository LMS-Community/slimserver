package YAML::XS;
use 5.008003;
use strict;
$YAML::XS::VERSION = '0.35';
use base 'Exporter';

@YAML::XS::EXPORT = qw(Load Dump);
@YAML::XS::EXPORT_OK = qw(LoadFile DumpFile);
%YAML::XS::EXPORT_TAGS = (
    all => [qw(Dump Load LoadFile DumpFile)],
);
# $YAML::XS::UseCode = 0;
# $YAML::XS::DumpCode = 0;
# $YAML::XS::LoadCode = 0;

$YAML::XS::QuoteNumericStrings = 1;

use YAML::XS::LibYAML qw(Load Dump);

sub DumpFile {
    my $OUT;
    my $filename = shift;
    if (ref $filename eq 'GLOB') {
        $OUT = $filename;
    }
    else {
        my $mode = '>';
        if ($filename =~ /^\s*(>{1,2})\s*(.*)$/) {
            ($mode, $filename) = ($1, $2);
        }
        open $OUT, $mode, $filename
          or die "Can't open '$filename' for output:\n$!";
    }
    local $/ = "\n"; # reset special to "sane"
    print $OUT YAML::XS::LibYAML::Dump(@_);
}

sub LoadFile {
    my $IN;
    my $filename = shift;
    if (ref $filename eq 'GLOB') {
        $IN = $filename;
    }
    else {
        open $IN, $filename
          or die "Can't open '$filename' for input:\n$!";
    }
    return YAML::XS::LibYAML::Load(do { local $/; <$IN> });
}

# XXX Figure out how to lazily load this module. 
# So far I've tried using the C function:
#      load_module(PERL_LOADMOD_NOIMPORT, newSVpv("B::Deparse", 0), NULL);
# But it didn't seem to work.
use B::Deparse;

# XXX The following code should be moved from Perl to C.
$YAML::XS::coderef2text = sub {
    my $coderef = shift;
    my $deparse = B::Deparse->new();
    my $text;
    eval {
        local $^W = 0;
        $text = $deparse->coderef2text($coderef);
    };
    if ($@) {
        warn "YAML::XS failed to dump code ref:\n$@";
        return;
    }
    $text =~ s[BEGIN \{\$\{\^WARNING_BITS\} = "UUUUUUUUUUUU\\001"\}]
              [use warnings;]g;

    return $text;
};

$YAML::XS::glob2hash = sub {
    my $hash = {};
    for my $type (qw(PACKAGE NAME SCALAR ARRAY HASH CODE IO)) {
        my $value = *{$_[0]}{$type};
        $value = $$value if $type eq 'SCALAR';
        if (defined $value) {
            if ($type eq 'IO') {
                my @stats = qw(device inode mode links uid gid rdev size
                               atime mtime ctime blksize blocks);
                undef $value;
                $value->{stat} = {};
                map {$value->{stat}{shift @stats} = $_} stat(*{$_[0]});
                $value->{fileno} = fileno(*{$_[0]});
                {
                    local $^W;
                    $value->{tell} = tell(*{$_[0]});
                }
            }
            $hash->{$type} = $value;
        }
    }
    return $hash;
};

use constant _QR_MAP => {
    '' => sub { qr{$_[0]} },
    x => sub { qr{$_[0]}x },
    i => sub { qr{$_[0]}i },
    s => sub { qr{$_[0]}s },
    m => sub { qr{$_[0]}m },
    ix => sub { qr{$_[0]}ix },
    sx => sub { qr{$_[0]}sx },
    mx => sub { qr{$_[0]}mx },
    si => sub { qr{$_[0]}si },
    mi => sub { qr{$_[0]}mi },
    ms => sub { qr{$_[0]}sm },
    six => sub { qr{$_[0]}six },
    mix => sub { qr{$_[0]}mix },
    msx => sub { qr{$_[0]}msx },
    msi => sub { qr{$_[0]}msi },
    msix => sub { qr{$_[0]}msix },
};

sub __qr_loader {
    if ($_[0] =~ /\A  \(\?  ([ixsm]*)  (?:-  (?:[ixsm]*))?  : (.*) \)  \z/x) {
        my $sub = _QR_MAP->{$1} || _QR_MAP->{''};
        &$sub($2);
    }
    else {
        qr/$_[0]/;
    }
}

1;

=encoding utf8

=head1 NAME

YAML::XS - Perl YAML Serialization using XS and libyaml

=head1 SYNOPSIS

    use YAML::XS;

    my $yaml = Dump [ 1..4 ];
    my $array = Load $yaml;

=head1 DESCRIPTION

Kirill Siminov's C<libyaml> is arguably the best YAML implementation.
The C library is written precisely to the YAML 1.1 specification. It was
originally bound to Python and was later bound to Ruby.

This module is a Perl XS binding to libyaml which offers Perl the best YAML
support to date.

This module exports the functions C<Dump>, C<Load>, C<DumpFile> and
C<LoadFile>. These functions are intended to work exactly like C<YAML.pm>'s
corresponding functions.

=head1 CONFIGURATION

=over 4

=item C<$YAML::XS::UseCode>

=item C<$YAML::XS::DumpCode>

=item C<$YAML::XS::LoadCode>

If enabled supports deparsing and evaling of code blocks.

=item C<$YAML::XS::QuoteNumericStrings>

When true (the default) strings that look like numbers but have not been
numified will be quoted when dumping.

This ensures leading that things like leading zeros and other formatting
are preserved.

=back

=head1 USING YAML::XS WITH UNICODE

Handling unicode properly in Perl can be a pain. YAML::XS only deals
with streams of utf8 octets. Just remember this:

    $perl = Load($utf8_octets);
    $utf8_octets = Dump($perl);

There are many, many places where things can go wrong with unicode.
If you are having problems, use Devel::Peek on all the possible
data points.

=head1 SEE ALSO

 * YAML.pm
 * YAML::Syck
 * YAML::Tiny

=head1 AUTHOR

Ingy döt Net <ingy@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2007, 2008, 2010, 2011. Ingy döt Net.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut
