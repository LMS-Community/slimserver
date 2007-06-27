#  Copyright (c) 1998-2001 by Mike Blazer.  All rights reserved.

package Win32::DriveInfo;

use Win32::API;
use Cwd;
use strict 'vars';
use vars qw/$VERSION
  $GetVolumeInformation $GetDriveType $GetLogicalDrives
  $GetVersionEx $GetDiskFreeSpace $GetDiskFreeSpaceEx/;

use constant DWORD_NULL => pack("L",0);
$VERSION = '0.06';

#==================
sub GetVersionEx () {
#==================
# on Win95 if returning $dwBuildNumber(low word of original)
# is greater than 1000, the system is running OSR 2 or a later release.
   $GetVersionEx ||= new Win32::API("kernel32", "GetVersionEx", ['P'], 'N') or return;

   my ($dwOSVersionInfoSize, $dwMajorVersion, $dwMinorVersion,
       $dwBuildNumber,       $dwPlatformId,   $szCSDVersion) =
       (148, 0, 0, 0, 0, "\0"x128);

   my $OSVERSIONINFO = pack "LLLLLa128",
      ($dwOSVersionInfoSize, $dwMajorVersion, $dwMinorVersion,
       $dwBuildNumber,       $dwPlatformId,   $szCSDVersion);

   return undef if $GetVersionEx->Call($OSVERSIONINFO) == 0;
   ($dwOSVersionInfoSize, $dwMajorVersion, $dwMinorVersion,
    $dwBuildNumber,       $dwPlatformId,   $szCSDVersion) =
   unpack "LLLLLa128", $OSVERSIONINFO;

   $szCSDVersion =~ s/\0.*$//;
   $szCSDVersion =~ s/^\s*(.*?)\s*$/$1/;
   $dwBuildNumber = $dwBuildNumber & 0xffff if Win32::IsWin95();

   ($dwMajorVersion, $dwMinorVersion, $dwBuildNumber,
    $dwPlatformId, $szCSDVersion);
}

#==================
sub GetDiskFreeSpace ($) {
#==================
   my $drive = shift;
   return undef unless $drive =~ s/^([a-z])(:(\\)?)?$/$1:\\/i;

   $GetDiskFreeSpace ||=
     new Win32::API("kernel32", "GetDiskFreeSpace", ['P','P','P','P','P'], 'N') or return;

   my ($lpRootPathName, $lpSectorsPerCluster, $lpBytesPerSector,
       $lpNumberOfFreeClusters, $lpTotalNumberOfClusters) =
       ($drive, DWORD_NULL, DWORD_NULL, DWORD_NULL, DWORD_NULL);

   return undef if $GetDiskFreeSpace->Call(
     $lpRootPathName, $lpSectorsPerCluster, $lpBytesPerSector,
     $lpNumberOfFreeClusters, $lpTotalNumberOfClusters
   ) == 0;

   ($lpSectorsPerCluster, $lpBytesPerSector,
    $lpNumberOfFreeClusters, $lpTotalNumberOfClusters) =
   (unpack ("L",$lpSectorsPerCluster),
    unpack ("L",$lpBytesPerSector),
    unpack ("L",$lpNumberOfFreeClusters),
    unpack ("L",$lpTotalNumberOfClusters));

   ($lpSectorsPerCluster, $lpBytesPerSector,
    $lpNumberOfFreeClusters, $lpTotalNumberOfClusters);
}

#==================
sub GetDiskFreeSpaceEx ($) {
#==================
   my $drive = shift;
   return undef unless $drive =~ s/^([a-z])(:(\\)?)?$/$1:\\/i ||
                       $drive =~ s/^(\\\\\w+\\\w+\$?)(\\)?$/$1\\/;

   $GetDiskFreeSpaceEx ||=
       new Win32::API("kernel32", "GetDiskFreeSpaceEx", ['P','P','P','P'], 'N') or return;

   my ($lpDirectoryName, $lpFreeBytesAvailableToCaller,
       $lpTotalNumberOfBytes, $lpTotalNumberOfFreeBytes) =
      ($drive, "\0"x8, "\0"x8, "\0"x8);

   return undef if $GetDiskFreeSpaceEx->Call(
     $lpDirectoryName, $lpFreeBytesAvailableToCaller,
     $lpTotalNumberOfBytes, $lpTotalNumberOfFreeBytes
   ) == 0;

   ($lpFreeBytesAvailableToCaller,
    $lpTotalNumberOfBytes,
    $lpTotalNumberOfFreeBytes) =
   (unpack_LARGE_INTEGER ($lpFreeBytesAvailableToCaller),
    unpack_LARGE_INTEGER ($lpTotalNumberOfBytes),
    unpack_LARGE_INTEGER ($lpTotalNumberOfFreeBytes));

   ($lpFreeBytesAvailableToCaller, $lpTotalNumberOfBytes,
    $lpTotalNumberOfFreeBytes);
}

#==========================
sub unpack_LARGE_INTEGER ($) {
  my ($b, $a) = unpack "LL", shift;
  $a*2**32+$b;
}

#==================
sub DriveType ($) {
#==================
   my $drive = shift;
   return undef unless $drive =~ s/^([a-z])(:(\\)?)?$/$1:\\/i ||
                       $drive =~ s/^(\\\\\w+\\\w+\$?)(\\)?$/$1\\/;

   $GetDriveType ||= new Win32::API("kernel32", "GetDriveType", ['P'], 'N') or return;

   my ($lpDirectoryName) = $drive;

   my $type = $GetDriveType->Call( $lpDirectoryName );
}

#==================
sub DriveSpace ($) {
#==================
  my $drive = shift;
  return undef unless $drive =~ s/^([a-z])(:(\\)?)?$/$1:\\/i ||
                      $drive =~ s/^(\\\\\w+\\\w+\$?)(\\)?$/$1\\/;

  my ($MajorVersion, $MinorVersion, $BuildNumber, $PlatformId, $BuildStr) = GetVersionEx();
  my ($FreeBytesAvailableToCaller, $TotalNumberOfBytes, $TotalNumberOfFreeBytes);

  my ($SectorsPerCluster, $BytesPerSector,
      $NumberOfFreeClusters, $TotalNumberOfClusters) = GetDiskFreeSpace($drive);

#  return undef if ! defined $BytesPerSector;

  if (Win32::IsWinNT()  || $MajorVersion > 4 ||
      $MinorVersion > 0 || $BuildNumber  > 1000) {
     ($FreeBytesAvailableToCaller,
      $TotalNumberOfBytes,
      $TotalNumberOfFreeBytes) = GetDiskFreeSpaceEx($drive);

  } elsif (defined $BytesPerSector) {
     ($FreeBytesAvailableToCaller,
      $TotalNumberOfBytes,
      $TotalNumberOfFreeBytes) = (
      $SectorsPerCluster * $BytesPerSector * $NumberOfFreeClusters,
      $SectorsPerCluster * $BytesPerSector * $TotalNumberOfClusters,
      $SectorsPerCluster * $BytesPerSector * $NumberOfFreeClusters );
  }

  ($SectorsPerCluster, $BytesPerSector,
   $NumberOfFreeClusters, $TotalNumberOfClusters,
   $FreeBytesAvailableToCaller, $TotalNumberOfBytes,
   $TotalNumberOfFreeBytes);
}

#===========================
sub DrivesInUse () {
#===========================
   my (@dr, $i);
   $GetLogicalDrives ||= new Win32::API("kernel32", "GetLogicalDrives", [], 'N') or return;

   my $bitmask = $GetLogicalDrives->Call;
   for $i(0..25) {
     push (@dr, chr(ord("A")+$i)) if $bitmask & 2**$i;
   }
   @dr;
}

#===========================
sub FreeDriveLetters () {
#===========================
   my (@dr, $i);
   $GetLogicalDrives ||= new Win32::API("kernel32", "GetLogicalDrives", [], 'N') or return;

   my $bitmask = $GetLogicalDrives->Call;
   for $i(0..25) {
     push (@dr, (A..Z)[$i]) unless $bitmask & 2**$i;
   }
   @dr;
}

#==================
sub IsReady ($) {
#==================
   my $drive = shift;
   return undef unless $drive =~ s/^([a-z])(:(\\)?)?$/$1:\\/i ||
                       $drive =~ s/^(\\\\\w+\\\w+\$?)(\\)?$/$1\\/;
   my $dir = cwd;
   my $rc  = chdir $drive;
   chdir $dir;
   $rc;
}

#==================
sub VolumeInfo ($) {
#==================
   my $drive = shift;
   return undef unless $drive =~ s/^([a-z])(:(\\)?)?$/$1:\\/i;

   $GetVolumeInformation ||=
    new Win32::API("kernel32", "GetVolumeInformation", ['P','P','N','P','P','P','P','N'], 'N') or return;

   my ($lpRootPathName, $lpVolumeNameBuffer, $nVolumeNameSize,
       $lpVolumeSerialNumber, $lpMaximumComponentLength, $lpFileSystemFlags,
       $lpFileSystemNameBuffer, $nFileSystemNameSize) =
       ($drive, "\0"x256, 256, DWORD_NULL, DWORD_NULL, DWORD_NULL, "\0"x256, 256);

   return undef if $GetVolumeInformation->Call(
     $lpRootPathName, $lpVolumeNameBuffer, $nVolumeNameSize,
     $lpVolumeSerialNumber, $lpMaximumComponentLength, $lpFileSystemFlags,
     $lpFileSystemNameBuffer, $nFileSystemNameSize
   ) == 0;

   ($lpVolumeSerialNumber, $lpMaximumComponentLength, $lpFileSystemFlags) =
   (unpack ("L",$lpVolumeSerialNumber),
    unpack ("L",$lpMaximumComponentLength),
    unpack ("L",$lpFileSystemFlags));

   $lpVolumeNameBuffer     =~ s/\0.*$//;
   $lpFileSystemNameBuffer =~ s/\0.*$//;

   if ($lpVolumeSerialNumber) {
     $lpVolumeSerialNumber = uc sprintf "%08x", $lpVolumeSerialNumber;
     $lpVolumeSerialNumber =~ s/(....)(....)/$1:$2/;
   } else {
     $lpVolumeSerialNumber = "";
   }

   my @attr;
   if ($lpFileSystemFlags & FS_CASE_IS_PRESERVED      () ) { push @attr, 1 }
   if ($lpFileSystemFlags & FS_CASE_SENSITIVE         () ) { push @attr, 2 }
   if ($lpFileSystemFlags & FS_UNICODE_STORED_ON_DISK () ) { push @attr, 3 }
   if ($lpFileSystemFlags & FS_PERSISTENT_ACLS        () ) { push @attr, 4 }
   if ($lpFileSystemFlags & FS_VOL_IS_COMPRESSED      () ) { push @attr, 5 }
   if ($lpFileSystemFlags & FS_FILE_COMPRESSION       () ) { push @attr, 6 }


   ($lpVolumeNameBuffer, $lpVolumeSerialNumber,
    $lpMaximumComponentLength, $lpFileSystemNameBuffer, @attr);
}

sub FS_CASE_IS_PRESERVED      { 0x00000002 }
sub FS_CASE_SENSITIVE         { 0x00000001 }
sub FS_UNICODE_STORED_ON_DISK { 0x00000004 }
sub FS_PERSISTENT_ACLS        { 0x00000008 }
sub FS_VOL_IS_COMPRESSED      { 0x00008000 }
sub FS_FILE_COMPRESSION       { 0x00000010 }


1;

__END__

=head1 NAME

Win32::DriveInfo - drives on Win32 systems

=head1 SYNOPSIS

    use Win32::DriveInfo;

    ($SectorsPerCluster,
     $BytesPerSector,
     $NumberOfFreeClusters,
     $TotalNumberOfClusters,
     $FreeBytesAvailableToCaller,
     $TotalNumberOfBytes,
     $TotalNumberOfFreeBytes) = Win32::DriveInfo::DriveSpace('f');

     $TotalNumberOfFreeBytes = (Win32::DriveInfo::DriveSpace('c:'))[6];

     $TotalNumberOfBytes = (Win32::DriveInfo::DriveSpace("\\\\serv\\share"))[5];

     @drives = Win32::DriveInfo::DrivesInUse();

     @freelet = Win32::DriveInfo::FreeDriveLetters();

     $type = Win32::DriveInfo::DriveType('a');

     ($VolumeName,
      $VolumeSerialNumber,
      $MaximumComponentLength,
      $FileSystemName, @attr) = Win32::DriveInfo::VolumeInfo('g');

     ($MajorVersion, $MinorVersion, $BuildNumber,
      $PlatformId, $BuildStr) = Win32::DriveInfo::GetVersionEx();

     # check is your CD-ROM loaded
     $CDROM = ( grep { Win32::DriveInfo::DriveType($_) == 5 }
	Win32::DriveInfo::DrivesInUse() )[0];
     $CD_inside = Win32::DriveInfo::IsReady($CDROM);

=head1 ABSTRACT

With this module you can get total/free space on Win32 drives,
volume names, architecture, filesystem type, drive attributes,
list of all available drives and free drive-letters. Additional
function to determine Windows version info.

The intention was to have a part of Dave Roth's Win32::AdminMisc
functionality on Win95/98.

The current version of Win32::DriveInfo is available at:

  http://base.dux.ru/guest/fno/perl/

=head1 DESCRIPTION

=over 4

Module provides few functions:

=item DriveSpace ( drive )

C<($SectorsPerCluster, $BytesPerSector, $NumberOfFreeClusters,>
C<$TotalNumberOfClusters, $FreeBytesAvailableToCaller,>
C<$TotalNumberOfBytes, $TotalNumberOfFreeBytes) =>
B<Win32::DriveInfo::DriveSpace>( drive );

   drive - drive-letter in either 'c' or 'c:' or 'c:\\' form or UNC path
           in either "\\\\server\\share" or "\\\\server\\share\\" form.
   $SectorsPerCluster          - number of sectors per cluster.
   $BytesPerSector             - number of bytes per sector.
   $NumberOfFreeClusters       - total number of free clusters on the disk.
   $TotalNumberOfClusters      - total number of clusters on the disk.
   $FreeBytesAvailableToCaller - total number of free bytes on the disk that
                                 are available to the user associated with the
                                 calling thread, b.
   $TotalNumberOfBytes         - total number of bytes on the disk, b.
   $TotalNumberOfFreeBytes     - total number of free bytes on the disk, b.

B<Note:> in case that UNC path was given first 4 values are C<undef>.

B<Win 95 note:> Win32 API C<GetDiskFreeSpaceEx()> function that is realized
by internal (not intended for users) C<GetDiskFreeSpaceEx()> subroutine
is available on Windows 95 OSR2 (OEM Service Release 2) only. This means build
numbers (C<$BuildNumber>
in C<GetVersionEx ( )> function, described here later) greater then 1000.

On lower Win95 builds
C<$FreeBytesAvailableToCaller, $TotalNumberOfBytes, $TotalNumberOfFreeBytes> are
realized through the internal C<GetDiskFreeSpace()> function that is claimed less
trustworthy in Win32 SDK documentation.

That's why on lower Win 95 builds this function will return 7 C<undef>'s
for UNC drives.

To say in short: B<don't use C<DriveSpace ( )> for UNC paths on early Win 95!>
Where possible use

  net use * \\server\share

and then usual '\w:' syntax.

=item DrivesInUse ( )

Returns sorted array of all drive-letters in use.

=item FreeDriveLetters ( )

Returns sorted array of all drive-letters that are available for allocation.

=item DriveType ( drive )

Returns integer value:

   0     - the drive type cannot be determined.
   1     - the root directory does not exist.
   2     - the drive can be removed from the drive (removable).
   3     - the disk cannot be removed from the drive (fixed).
   4     - the drive is a remote (network) drive.
   5     - the drive is a CD-ROM drive.
   6     - the drive is a RAM disk.

   drive - drive-letter in either 'c' or 'c:' or 'c:\\' form or UNC path
           in either "\\\\server\\share" or "\\\\server\\share\\" form.

In case of UNC path 4 will be returned that means that
networked drive is available (1 - if not available).

=item IsReady ( drive )

Returns TRUE if root of the C<drive> is accessible, otherwise FALSE.
This one isn't really something cool - the function just tries to
chdir to the C<drive>'s root. This takes time and produces unpleasant
sound in case the removable drive is not loaded. If somebody knows
some better way to determine is there something inside your CD-ROM
or FDD - please let me know (in fact CD-ROMs, RAM drives and network
drives return their status fast,
may be some other devices make problem, dunno).

   drive - drive-letter in either 'c' or 'c:' or 'c:\\' form or UNC path
           in either "\\\\server\\share" or "\\\\server\\share\\" form.


=item VolumeInfo ( drive )

C<($VolumeName, $VolumeSerialNumber, $MaximumComponentLength,>
C<$FileSystemName, @attr) => B<Win32::DriveInfo::VolumeInfo> ( drive );

   drive - drive-letter in either 'c' or 'c:' or 'c:\\' form.

   $VolumeName             - name of the specified volume.
   $VolumeSerialNumber     - volume serial number.
   $MaximumComponentLength -
        filename component supported by the specified file system.
        A filename component is that portion of a filename between backslashes.
        Indicate that long names are supported by the specified file system.
        For a FAT file system supporting long names, the function stores
        the value 255, rather than the previous 8.3 indicator. Long names can
        also be supported on systems that use the New Technology file system
        (NTFS).
   $FileSystemName         - name of the file system (such as FAT, FAT32, CDFS or NTFS).
   @attr                   - array of integers 1-6
     1 - file system preserves the case of filenames
     2 - file system supports case-sensitive filenames
     3 - file system supports Unicode in filenames as they appear on disk
     4 - file system preserves and enforces ACLs (access-control lists).
         For example, NTFS preserves and enforces ACLs, and FAT does not.
     5 - file system supports file-based compression
     6 - specified volume is a compressed volume; for ex., a DoubleSpace volume

=item GetVersionEx ( )

This function provides version of the OS in use.

C<($MajorVersion, $MinorVersion, $BuildNumber, $PlatformId, $BuildStr) =>
B<Win32::DriveInfo::GetVersionEx> ( );

   $MajorVersion - major version number of the operating system. For Windows NT
                   version 3.51, it's 3; for Windows NT version 4.0, it's 4.

   $MinorVersion - minor version number of the operating system. For Windows NT
                   version 3.51, it's 51; for Windows NT version 4.0, it's 0.
   $BuildNumber  - build number of the operating system.
   $PlatformId   - 0 for Win32s, 1 for Win95/98, 2 for Win NT
   $BuildStr     - Windows NT: Contains string, such as "Service Pack 3".
                   Indicates the latest Service Pack installed on the system.
                   If no Service Pack has been installed, the string is empty.
                   Windows 95: Contains a null-terminated string that provides
                   arbitrary additional information about the operating system.

=back

Nothing is exported by default. All functions return C<undef> on errors.

=head1 INSTALLATION

As this is just a plain module no special installation is needed. Just put
it into /Win32 subdir somewhere in your @INC.  The standard

 Makefile.PL
 make
 make test
 make install

installation procedure is provided. In addition

 make html

will produce the HTML-docs.

This module requires

Win32::API module by Aldo Calpini

=head1 CAVEATS

This module has been created and tested in a Win95 environment on GS port
of Perl 5.004_02. As it uses Win32::API module I expect it would work fine
with other ports like ActiveState if Win32::API (API.dll) is compiled for
this port.

=head1 CHANGES

 0.02 - Austin Durbin <adurbin@earthlink.net> tested module on Win NT
        and discovered small bug in UNC paths handling. Fixed.
        Thanks Austin!

 0.03 - fixed bug that returned incorrect values for volumes that are
        larger than 0x7fffffff bytes (2 GB). Approved on Win98 with FAT32.

 0.04 - added IsReady() function and MakeMaker compartible distribution.
        Empty SerialNumber fixed. Now it's empty string, previously it
	was evaluated to 0000:0000.
	Minor enhancements.

 0.05 - test.pl fixed, other minor fixes.
	The last 0.0x version before the major update (soon!)

 0.06 - test.pl fixed more ;-)

=head1 BUGS

C<DriveSpace ( )> returns incorrect $NumberOfFreeClusters,
$TotalNumberOfClusters values on the large ( >2M ) drives.
Dunno whether somebody use these values or not but I'll try to
fix this in the next release.

Please report if any bugs.

=head1 VERSION

This man page documents Win32::DriveInfo version 0.06

February 19, 2001

=head1 AUTHOR

Mike Blazer C<<>blazer@mail.nevalink.ruC<>>

=head1 COPYRIGHT

Copyright (C) 1998-2001 by Mike Blazer. All rights reserved.

=head1 LICENSE

This package is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
