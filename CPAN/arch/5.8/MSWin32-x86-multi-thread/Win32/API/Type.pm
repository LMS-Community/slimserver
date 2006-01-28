package Win32::API::Type;

# See the bottom of this file for the POD documentation.  Search for the
# string '=head'.

#######################################################################
#
# Win32::API::Type - Perl Win32 API type definitions
# 
# Version: 0.40 
# Date: 07 Mar 2003
# Author: Aldo Calpini <dada@perl.it>
# $Id$
#######################################################################

$VERSION = "0.40";

use Carp;

require Exporter;       # to export the constants to the main:: space
require DynaLoader;     # to dynuhlode the module.
@ISA = qw( Exporter DynaLoader );

use vars qw( %Known %PackSize %Modifier %Pointer );

sub DEBUG { 
    if ($Win32::API::DEBUG) { 
        printf @_ if @_ or return 1; 
    } else {
        return 0;
    }
}

%Known      = ();
%PackSize   = ();
%Modifier   = ();
%Pointer    = ();

INIT { 
    my $section = 'nothing';
    foreach (<DATA>) {
        next if /^\s*#/ or /^\s*$/;
        chomp;
        if( /\[(.+)\]/) {
            $section = $1;
            next;
        }
        if($section eq 'TYPE') {
            my($name, $packing) = split(/\s+/);
            # DEBUG "(PM)Type::INIT: Known('$name') => '$packing'\n";
            $Known{$name} = $packing;
        } elsif($section eq 'PACKSIZE') {
            my($packing, $size) = split(/\s+/);
            # DEBUG "(PM)Type::INIT: PackSize('$packing') => '$size'\n";
            $PackSize{$packing} = $size;
        } elsif($section eq 'MODIFIER') {
            my($modifier, $mapto) = split(/\s+/, $_, 2);
            my %maps = ();
            foreach my $item (split(/\s+/, $mapto)) {
                my($k, $v) = split(/=/, $item);
                $maps{$k} = $v;
            }           
            # DEBUG "(PM)Type::INIT: Modifier('$modifier') => '%maps'\n";
            $Modifier{$modifier} = { %maps };
        } elsif($section eq 'POINTER') {
            my($pointer, $pointto) = split(/\s+/);
            # DEBUG "(PM)Type::INIT: Pointer('$pointer') => '$pointto'\n";
            $Pointer{$pointer} = $pointto;
        }
    }
}

sub new {
    my $class = shift;
    my($type) = @_; 
    my $packing = packing($type);
    my $size = sizeof($type);
    my $self = {
        type => $type,
        packing => $packing,
        size => $size,
    };
    return bless $self;
}

sub typedef {
    my $class = shift;
    my($name, $type) = @_;  
    my $packing = packing($type, $name);
    DEBUG "(PM)Type::typedef: packing='$packing'\n";
    my $size = sizeof($type);
    $Known{$name} = $packing;
    return 1;
}


sub is_known {
    my $self = shift;
    my $type = shift;
    $type = $self unless defined $type;
    if(ref($type) =~ /Win32::API::Type/) {
        return 1;
    } else {
        return defined packing($type);
    }
}

sub sizeof {
    my $self = shift;
    my $type = shift;
    $type = $self unless defined $type;
    if(ref($type) =~ /Win32::API::Type/) {
        return $self->{size};
    } else {
        my $packing = packing($type);
        if($packing =~ /(\w)\*(\d+)/) {
            return $PackSize{ $1 } * $2;
        } else {
            return $PackSize{ $packing };
        }
    }   
}

sub packing {
    # DEBUG "(PM)Type::packing: called by ". join("::", (caller(1))[0,3]). "\n";  
    my $self = shift;
    my $is_pointer = 0;
    if(ref($self) =~ /Win32::API::Type/) {
        # DEBUG "(PM)Type::packing: got an object\n"; 
        return $self->{packing};
    }
    my $type = ($self eq 'Win32::API::Type') ? shift : $self;
    my $name = shift;
    
    # DEBUG "(PM)Type::packing: got '$type', '$name'\n";  
    my($modifier, $size, $packing);
    if(exists $Pointer{$type}) {        
        # DEBUG "(PM)Type::packing: got '$type', is really '$Pointer{$type}'\n";
        $type = $Pointer{$type};
        $is_pointer = 1;
    } elsif($type =~ /(\w+)\s+(\w+)/) {
        $modifier = $1;
        $type = $2;
        # DEBUG "(PM)packing: got modifier '$modifier', type '$type'\n";
    }
    
    $type =~ s/\*$//;
    
    if(exists $Known{$type}) {
        if(defined $name and $name =~ s/\[(.*)\]$//) {
            $size = $1;
            $packing = $Known{$type}[0]."*".$size;  
            # DEBUG "(PM)Type::packing: composite packing: '$packing' '$size'\n";
        } else {
            $packing = $Known{$type};
            if($is_pointer and $packing eq 'c') {
               $packing = "p";
            }
            # DEBUG "(PM)Type::packing: simple packing: '$packing'\n";
        }
        if(defined $modifier and exists $Modifier{$modifier}->{$type}) {
            # DEBUG "(PM)Type::packing: applying modifier '$modifier' -> '$Modifier{$modifier}->{$type}'\n";
            $packing = $Modifier{$modifier}->{$type};
        }
        return $packing;
    } else {
        # DEBUG "(PM)Type::packing: NOT FOUND\n";
        return undef;
    }
}   


sub is_pointer {
    my $self = shift;
    my $type = shift;
    $type = $self unless defined $type;
    if(ref($type) =~ /Win32::API::Type/) {
        return 1;
    } else {    
        if($type =~ /\*$/) {
            return 1;
        } else {
            return exists $Pointer{$type};
        }
    }
}

sub Pack {
    my $type = $_[0];
    
    if(packing($type) eq 'c' and is_pointer($type)) {
        $_[1] = pack("Z*", $_[1]);
        return $_[1];
    }
    $_[1] = pack( packing($type), $_[1]);   
    return $_[1];
}

sub Unpack {
    my $type = $_[0];
    if(packing($type) eq 'c' and is_pointer($type)) {       
        DEBUG "(PM)Type::Unpack: got packing 'c', is a pointer, unpacking 'Z*' '$_[1]'\n";
        $_[1] = unpack("Z*", $_[1]);
        DEBUG "(PM)Type::Unpack: returning '$_[1]'\n";
        return $_[1];
    }
    DEBUG "(PM)Type::Unpack: unpacking '".packing($type)."' '$_[1]'\n"; 
    $_[1] = unpack( packing($type), $_[1]);
    DEBUG "(PM)Type::Unpack: returning '$_[1]'\n";  
    return $_[1];
}

1;

#######################################################################
# DOCUMENTATION
#

=head1 NAME

Win32::API::Type - C type support package for Win32::API

=head1 SYNOPSIS

  use Win32::API;
  
  Win32::API::Type->typedef( 'my_number', 'LONG' );


=head1 ABSTRACT

This module is a support package for Win32::API that implements
C types for the import with prototype functionality.

See L<Win32::API> for more info about its usage.

=head1 DESCRIPTION

This module is automatically imported by Win32::API, so you don't 
need to 'use' it explicitly. These are the methods of this package:

=over 4

=item C<typedef NAME, TYPE>

This method defines a new type named C<NAME>. This actually just 
creates an alias for the already-defined type C<TYPE>, which you
can use as a parameter in a Win32::API call.

=item C<sizeof TYPE>

This returns the size, in bytes, of C<TYPE>. Acts just like
the C function of the same name. 

=item C<is_known TYPE>

Returns true if C<TYPE> is known by Win32::API::Type, false
otherwise.

=back

=head2 SUPPORTED TYPES

This module should recognize all the types defined in the
Win32 Platform SDK header files. 
Please see the source for this module, in the C<__DATA__> section,
for the full list.

=head1 AUTHOR

Aldo Calpini ( I<dada@perl.it> ).

=cut


__DATA__

[TYPE]
ATOM					s
BOOL					L
BOOLEAN					c
BYTE					C
CHAR					c
COLORREF				L
DWORD                   L
DWORD32                 L
DWORD64                 Q
FLOAT                   f
HACCEL                  L
HANDLE                  L
HBITMAP                 L
HBRUSH                  L
HCOLORSPACE             L
HCONV                   L
HCONVLIST               L
HCURSOR                 L
HDC                     L
HDDEDATA                L
HDESK                   L
HDROP                   L
HDWP                    L
HENHMETAFILE            L
HFILE                   L
HFONT                   L
HGDIOBJ                 L
HGLOBAL                 L
HHOOK                   L
HICON                   L
HIMC                    L
HINSTANCE               L
HKEY                    L
HKL                     L
HLOCAL                  L
HMENU                   L
HMETAFILE               L
HMODULE                 L
HPALETTE                L
HPEN                    L
HRGN                    L
HRSRC                   L
HSZ                     L
HWINSTA                 L
HWND                    L
INT                     i
INT32                   i
INT64                   q
LANGID                  s
LCID                    L
LCSCSTYPE               L
LCSGAMUTMATCH           L
LCTYPE                  L
LONG                    l
LONG32                  l
LONG64                  q
LONGLONG                q
LPARAM                  L
LRESULT                 L
REGSAM                  L
SC_HANDLE               L
SC_LOCK                 L
SERVICE_STATUS_HANDLE   L
SHORT                   s
SIZE_T                  L
SSIZE_T                 L
TBYTE                   c
TCHAR                   C
UCHAR                   C
UINT                    I
UINT_PTR                L
UINT32                  I
UINT64                  Q
ULONG                   L
ULONG32                 L
ULONG64                 Q
ULONGLONG               Q
USHORT                  S
WCHAR                   S
WORD                    S
WPARAM                  L
VOID                    c

int                     i
long                    l
float                   f
double                  d
char                    c

#CRITICAL_SECTION   24 -- a structure
#LUID                   ?   8 -- a structure
#VOID   0
#CONST  4
#FILE_SEGMENT_ELEMENT   8 -- a structure

[PACKSIZE]
c   1
C   1
d   8
f   4
i   4
I   4
l   4
L   4
q   8
Q   8
s   2
S   2
p   4

[MODIFIER]
unsigned    int=I long=L short=S char=C

[POINTER]
INT_PTR                 INT
LPBOOL                  BOOL
LPBYTE                  BYTE
LPCOLORREF              COLORREF
LPCSTR                  CHAR
#LPCTSTR                    CHAR or WCHAR
LPCTSTR                 CHAR
LPCVOID                 any
LPCWSTR                 WCHAR
LPDWORD                 DWORD
LPHANDLE                HANDLE
LPINT                   INT
LPLONG                  LONG
LPSTR                   CHAR
#LPTSTR                 CHAR or WCHAR
LPTSTR                  CHAR
LPVOID                  VOID
LPWORD                  WORD
LPWSTR                  WCHAR

PBOOL                   BOOL
PBOOLEAN                BOOL
PBYTE                   BYTE
PCHAR                   CHAR
PCSTR                   CSTR
PCWCH                   CWCH
PCWSTR                  CWSTR
PDWORD                  DWORD
PFLOAT                  FLOAT
PHANDLE                 HANDLE
PHKEY                   HKEY
PINT                    INT
PLCID                   LCID
PLONG                   LONG
PSHORT                  SHORT
PSTR                    CHAR
#PTBYTE                 TBYTE --
#PTCHAR                 TCHAR --
#PTSTR                  CHAR or WCHAR
PTSTR                   CHAR
PUCHAR                  UCHAR
PUINT                   UINT
PULONG                  ULONG
PUSHORT                 USHORT
PVOID                   VOID
PWCHAR                  WCHAR
PWORD                   WORD
PWSTR                   WCHAR
