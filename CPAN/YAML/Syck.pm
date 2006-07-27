package YAML::Syck;
use strict;
use vars qw( @ISA @EXPORT $VERSION $ImplicitTyping $UseCode $LoadCode $DumpCode $SortKeys $DeparseObject );
use 5.00307;
use Exporter;

BEGIN {
    $VERSION = '0.64';
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

    *Load = \&YAML::Syck::LoadYAML;
    *Dump = \&YAML::Syck::DumpYAML;

    eval {
        require B::Deparse;
        $DeparseObject = B::Deparse->new;
    }
}


sub DumpFile {
    my $file = shift;
    local *FH;
    open FH, "> $file" or die "Cannot write to $file: $!";
    print FH Dump($_[0]);
}
sub LoadFile {
    my $file = shift;
    local *FH;
    open FH, "< $file" or die "Cannot read from $file: $!";
    Load(do { local $/; <FH> })
}

1;
