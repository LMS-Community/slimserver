use strict; use warnings;

package YAML::XS;
our $VERSION = '0.65';

use base 'Exporter';

@YAML::XS::EXPORT = qw(Load Dump);
@YAML::XS::EXPORT_OK = qw(LoadFile DumpFile);
%YAML::XS::EXPORT_TAGS = (
    all => [qw(Dump Load LoadFile DumpFile)],
);
our ($UseCode, $DumpCode, $LoadCode);
# $YAML::XS::UseCode = 0;
# $YAML::XS::DumpCode = 0;
# $YAML::XS::LoadCode = 0;

$YAML::XS::QuoteNumericStrings = 1;

use YAML::XS::LibYAML qw(Load Dump);
use Scalar::Util qw/ openhandle /;

sub DumpFile {
    my $OUT;
    my $filename = shift;
    if (openhandle $filename) {
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
    if (openhandle $filename) {
        $IN = $filename;
    }
    else {
        open $IN, $filename
          or die "Can't open '$filename' for input:\n$!";
    }
    return YAML::XS::LibYAML::Load(do { local $/; local $_ = <$IN> });
}


# XXX The following code should be moved from Perl to C.
$YAML::XS::coderef2text = sub {
    my $coderef = shift;
    require B::Deparse;
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
