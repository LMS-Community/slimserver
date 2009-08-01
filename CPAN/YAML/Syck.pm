package YAML::Syck;
# See documentation after the __END__ mark.

use strict;
use vars qw(
    @ISA @EXPORT $VERSION
    $Headless $SortKeys $SingleQuote
    $ImplicitBinary $ImplicitTyping $ImplicitUnicode 
    $UseCode $LoadCode $DumpCode
    $DeparseObject
);
use 5.00307;
use Exporter;

BEGIN {
    $VERSION = '1.05';
    @EXPORT  = qw( Dump Load DumpFile LoadFile );
    @ISA     = qw( Exporter );

    $SortKeys = 1;

    local $@;
    eval {
        require XSLoader;
        XSLoader::load(__PACKAGE__, $VERSION);
        1;
    } or do {
        require DynaLoader;
        push @ISA, 'DynaLoader';
        __PACKAGE__->bootstrap($VERSION);
    };

}

use constant QR_MAP => {
    ''   => sub { qr{$_[0]}     }, 
    x    => sub { qr{$_[0]}x    }, 
    i    => sub { qr{$_[0]}i    }, 
    s    => sub { qr{$_[0]}s    }, 
    m    => sub { qr{$_[0]}m    }, 
    ix   => sub { qr{$_[0]}ix   }, 
    sx   => sub { qr{$_[0]}sx   }, 
    mx   => sub { qr{$_[0]}mx   }, 
    si   => sub { qr{$_[0]}si   }, 
    mi   => sub { qr{$_[0]}mi   }, 
    ms   => sub { qr{$_[0]}sm   }, 
    six  => sub { qr{$_[0]}six  }, 
    mix  => sub { qr{$_[0]}mix  }, 
    msx  => sub { qr{$_[0]}msx  }, 
    msi  => sub { qr{$_[0]}msi  }, 
    msix => sub { qr{$_[0]}msix }, 
};

sub __qr_helper {
    if ($_[0] =~ /\A  \(\?  ([ixsm]*)  (?:-  (?:[ixsm]*))?  : (.*) \)  \z/x) {
        my $sub = QR_MAP()->{$1} || QR_MAP()->{''};
        &$sub($2);
    }
    else {
        qr/$_[0]/;
    }
}

sub Dump {
    $#_ ? join('', map { YAML::Syck::DumpYAML($_) } @_)
        : YAML::Syck::DumpYAML($_[0]);
}

sub Load {
    if (wantarray) {
        my ($rv) = YAML::Syck::LoadYAML($_[0]);
        @{$rv};
    }
    else {
        YAML::Syck::LoadYAML($_[0]);
    }
}

# NOTE. The code below (_is_openhandle) avoids to require/load
# Scalar::Util unless it is given a ref or glob
# as an argument. That is purposeful, so to avoid
# the need for this dependency unless strictly necessary.
# If that was not the case, Scalar::Util::openhandle could
# be used directly.

sub _is_openhandle {
    my $h = shift;
    if ( ref($h) || ref(\$h) eq 'GLOB' ) {
        require Scalar::Util;
        return Scalar::Util::openhandle($h);
    } else {
        return undef;
    }
}

sub DumpFile {
    my $file = shift;
    if ( _is_openhandle($file) ) {
        if ($#_) {
            print {$file} YAML::Syck::DumpYAML($_) for @_;
        }
        else {
            print {$file} YAML::Syck::DumpYAML($_[0]);
        }
    }
    else {
        local *FH;
        open FH, "> $file" or die "Cannot write to $file: $!";
        if ($#_) {
            print FH YAML::Syck::DumpYAML($_) for @_;
        }
        else {
            print FH YAML::Syck::DumpYAML($_[0]);
        }
        close FH;
    }
}

sub LoadFile {
    my $file = shift;
    if ( _is_openhandle($file) ) {
        Load(do { local $/; <$file> });
    }
    else {
        local *FH;
        open FH, "< $file" or die "Cannot read from $file: $!";
        Load(do { local $/; <FH> });
    }
}

1;

__END__
=pod

=head1 NAME 

YAML::Syck - Fast, lightweight YAML loader and dumper

=head1 VERSION

This document describes version 1.04 of YAML::Syck, released February 17, 2008.

=head1 SYNOPSIS

    use YAML::Syck;

    # Set this for interoperability with other YAML/Syck bindings:
    # e.g. Load('Yes') becomes 1 and Load('No') becomes ''.
    $YAML::Syck::ImplicitTyping = 1;

    $data = Load($yaml);
    $yaml = Dump($data);

    # $file can be an IO object, or a filename
    $data = LoadFile($file);
    DumpFile($file, $data);

    # A string with multiple YAML streams in it
    $yaml = Dump(@data);
    @data = Load($yaml);

=head1 DESCRIPTION

This module provides a Perl interface to the B<libsyck> data serialization
library.  It exports the C<Dump> and C<Load> functions for converting
Perl data structures to YAML strings, and the other way around.

B<NOTE>: If you are working with other language's YAML/Syck bindings
(such as Ruby), please set C<$YAML::Syck::ImplicitTyping> to C<1> before
calling the C<Load>/C<Dump> functions.  The default setting is for
preserving backward-compatibility with C<YAML.pm>.

=head1 FLAGS

=head2 $YAML::Syck::Headless

Defaults to false.  Setting this to a true value will make C<Dump> omit the
leading C<---\n> marker.

=head2 $YAML::Syck::SortKeys

Defaults to false.  Setting this to a true value will make C<Dump> sort
hash keys.

=head2 $YAML::Syck::SingleQuote

Defaults to false.  Setting this to a true value will make C<Dump> always emit
single quotes instead of bare strings.

=head2 $YAML::Syck::ImplicitTyping

Defaults to false.  Setting this to a true value will make C<Load> recognize
various implicit types in YAML, such as unquoted C<true>, C<false>, as well as
integers and floating-point numbers.  Otherwise, only C<~> is recognized to
be C<undef>.

=head2 $YAML::Syck::ImplicitUnicode

Defaults to false.  For Perl 5.8.0 or later, setting this to a true value will
make C<Load> set Unicode flag on for every string that contains valid UTF8
sequences, and make C<Dump> return a unicode string.

Regardless of this flag, Unicode strings are dumped verbatim without escaping;
byte strings with high-bit set will be dumped with backslash escaping.

However, because YAML does not distinguish between these two kinds of strings,
so this flag will affect loading of both variants of strings.

=head2 $YAML::Syck::ImplicitBinary

Defaults to false.  For Perl 5.8.0 or later, setting this to a true value will
make C<Dump> generate Base64-encoded C<!!binary> data for all non-Unicode
scalars containing high-bit bytes.

=head2 $YAML::Syck::UseCode / $YAML::Syck::LoadCode / $YAML::Syck::DumpCode

These flags control whether or not to try and eval/deparse perl source code;
each of them defaults to false.

Setting C<$YAML::Syck::UseCode> to a true value is equivalent to setting
both C<$YAML::Syck::LoadCode> and C<$YAML::Syck::DumpCode> to true.

=head1 BUGS

Dumping Glob/IO values does not work yet.

=head1 CAVEATS

This module implements the YAML 1.0 spec.  To deal with data in YAML 1.1, 
please use the C<YAML::XS> module instead.

The current implementation bundles libsyck source code; if your system has a
site-wide shared libsyck, it will I<not> be used.

Tag names such as C<!!perl/hash:Foo> is blessed into the package C<Foo>, but
the C<!hs/foo> and C<!!hs/Foo> tags are blessed into C<hs::Foo>.  Note that
this holds true even if the tag contains non-word characters; for example,
C<!haskell.org/Foo> is blessed into C<haskell.org::Foo>.  Please use
L<Class::Rebless> to cast it into other user-defined packages.

=head1 SEE ALSO

L<YAML>, L<JSON::Syck>

L<http://www.yaml.org/>

=head1 AUTHORS

Audrey Tang E<lt>cpan@audreyt.orgE<gt>

=head1 COPYRIGHT

Copyright 2005, 2006, 2007, 2008 by Audrey Tang E<lt>cpan@audreyt.orgE<gt>.

This software is released under the MIT license cited below.

The F<libsyck> code bundled with this library is released by
"why the lucky stiff", under a BSD-style license.  See the F<COPYING>
file for details.

=head2 The "MIT" License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

=cut
