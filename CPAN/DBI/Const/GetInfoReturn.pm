# $Id: GetInfoReturn.pm 8696 2007-01-24 23:12:38Z timbo $
#
# Copyright (c) 2002  Tim Bunce  Ireland
#
# Constant data describing return values from the DBI getinfo function.
#
# You may distribute under the terms of either the GNU General Public
# License or the Artistic License, as specified in the Perl README file.

package DBI::Const::GetInfoReturn;

use strict;

use Exporter ();

use vars qw(@ISA @EXPORT @EXPORT_OK %GetInfoReturnTypes %GetInfoReturnValues);

@ISA = qw(Exporter);
@EXPORT = qw(%GetInfoReturnTypes %GetInfoReturnValues);

my
$VERSION = sprintf("2.%06d", q$Revision: 8696 $ =~ /(\d+)/o);


=head1 NAME

DBI::Const::GetInfoReturn - Data and functions for describing GetInfo results

=head1 SYNOPSIS

The interface to this module is undocumented and liable to change.

=head1 DESCRIPTION

Data and functions for describing GetInfo results

=cut

use DBI::Const::GetInfoType;

use DBI::Const::GetInfo::ANSI ();
use DBI::Const::GetInfo::ODBC ();

%GetInfoReturnTypes =
(
  %DBI::Const::GetInfo::ANSI::ReturnTypes
, %DBI::Const::GetInfo::ODBC::ReturnTypes
);

%GetInfoReturnValues = ();
{
  my $A = \%DBI::Const::GetInfo::ANSI::ReturnValues;
  my $O = \%DBI::Const::GetInfo::ODBC::ReturnValues;
  while ( my ($k, $v) = each %$A ) {
    my %h = ( exists $O->{$k} ) ? ( %$v, %{$O->{$k}} ) : %$v;
    $GetInfoReturnValues{$k} = \%h;
  }
  while ( my ($k, $v) = each %$O ) {
    next if exists $A->{$k};
    my %h = %$v;
    $GetInfoReturnValues{$k} = \%h;
  }
}

# -----------------------------------------------------------------------------

sub Format {
  my $InfoType = shift;
  my $Value    = shift;

  return '' unless defined $Value;

  my $ReturnType = $GetInfoReturnTypes{$InfoType};

  return sprintf '0x%08X', $Value if $ReturnType eq 'SQLUINTEGER bitmask';
  return sprintf '0x%08X', $Value if $ReturnType eq 'SQLINTEGER bitmask';
# return '"' . $Value . '"'       if $ReturnType eq 'SQLCHAR';
  return $Value;
}


sub Explain {
  my $InfoType = shift;
  my $Value    = shift;

  return '' unless defined $Value;
  return '' unless exists $GetInfoReturnValues{$InfoType};

  $Value = int $Value;
  my $ReturnType = $GetInfoReturnTypes{$InfoType};
  my %h = reverse %{$GetInfoReturnValues{$InfoType}};

  if ( $ReturnType eq 'SQLUINTEGER bitmask'|| $ReturnType eq 'SQLINTEGER bitmask') {
    my @a = ();
    for my $k ( sort { $a <=> $b } keys %h ) {
      push @a, $h{$k} if $Value & $k;
    }
    return wantarray ? @a : join(' ', @a );
  }
  else {
    return $h{$Value} ||'?';
  }
}

1;
