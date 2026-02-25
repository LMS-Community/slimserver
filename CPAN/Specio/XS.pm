package Specio::XS;

use strict;
use warnings;

our $VERSION = '0.53';

use Clone qw( clone );

use Exporter qw( import );

## no critic (Modules::ProhibitAutomaticExportation)
our @EXPORT = qw(  _clone );

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _clone {
    return clone(shift);
}

1;
