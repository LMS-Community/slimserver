package Win32::AbsPath;
require Exporter;
@ISA = (Exporter);
@EXPORT = qw();   #&new);
@EXPORT_OK = qw(RelativeToAbsolute Relative2Absolute canonpath FixPath FixPaths FullPath FullPaths);
use Cwd;
$VERSION = '1.0';

sub Relative2Absolute {
 local $_;
 foreach $_ (@_) {
#print "DO: $_\n";
  my $root;
  s#\\#/#g;
  if (m#^(\w:)(/.*)$#) {
    $root = $1;
    $_ = $2;
  } elsif (m#^(//[^/]+/[^/]+)(.*)#) {
    $root = $1;
    $_ = $2;
  } elsif (m#^(/.*)#) {
   $root = getcwd();
   $root =~ s#^(\w:|//[^/]+/[^/]+).*#$1#;
  } elsif (m#^(\w:)(.*)$#) {
    $root = $1;
    $_ = $2;
    my $oldcwd = getcwd();
    chdir($root) or return;
    $_ = substr( getcwd(), 2).'/'.$_;
    chdir($oldcwd) or return;
  } else {
    $_ = getcwd().'/'.$_;
    ($root,$_) = m#^(\w:|//[^/]+/[^/]+)(.*)$#;
  }
  s#//+#/#g;
  s#(/\.)+(?=/|$)##g;
  s#/\.\.(\.+)(?=/|$)#'/..'x(length($1)+1)#ge;
  while(s{/[^/]+/\.\.(/|$)}{/}){};
  s#(/\.\.)*/?$##;
  s#^(/\.\.)+##;
  $_=$root.$_;
  s#^(\w:)$#$1\\#;
  s#/#\\#g;
 }
 @_
}
*FixPaths = \&Relative2Absolute;
*FullPaths=\&Relative2Absolute;
*rel2abs = \&Relative2Absolute;

*canonpath=\&RelativeToAbsolute;
*Fix=\&RelativeToAbsolute;
*FixPath=\&RelativeToAbsolute;
*FullPath=\&RelativeToAbsolute;
*reltoabs = \&RelativeToAbsolute;
sub RelativeToAbsolute ($) {
 my $str = shift;
 Relative2Absolute $str;
 $str;
}

1;

=head1 NAME

Win32::AbsPath - convert relative to absolute paths

Version 1.0

=head1 SYNOPSIS

 use Win32::AbsPath;
 $path = Win32::AbsPath::Fix '../some\dir\file.doc'
 system("winword $path");

 use Win32::AbsPath qw(Relative2Absolute);
 @paths = qw(
  ..\dir\file.txt
  ./other.doc
  c:\boot.ini
 );
 Relative2Absolute @paths;

=head1 DESCRIPTION

Convert relative paths to absolute. Understands UNC paths.

The functions understands many different types of paths

    dir\file.txt
    ..\dir\file.txt
    c:\dir\file.txt
    c:\dir\..\file.txt
    \dir\file.txt
    \\server\share\dir\..\file.txt
    c:dir\file.txt

and of course you may pepper these with whatever mixtures of \.\ and
\..\ you like. You may use both forward and backward slashes, the result
will be in backward slashes.

! The ussage of paths of type c:file.txt is slightly deprecated. It IS
supported, but may lead to a change of current directory. The function
first chdir()s top the current directory on the drive mentioned in the
path and then back to cwd() in time it was called. If any of those
chdir()s fails, the result of the function will be undef.

This is likely to happen if one of the drives is a floppy or CD, or
if one of the drives was a network drive and was disconnected.

=head1 Functions

=over 2

=item Relative2Absolute

 Relative2Absolute @list;

Converts all paths in @list to absolute paths C<in-place>.
That is the function changes the list you pass in.

=item RelativeToAbsolute

 $abspath = RelativeToAbsolute $relpath;

Converts the relative path to absolute. Returns the absolute path, but
doesn't change the parameter. It takes exactly one parameter!

 print join(' ',RelativeToAbsolute '_file.txt','_other.txt');
    prints
 c:\_file.txt _other.txt
    instead of
 c:\_file.txt c:\_other.txt

=item Win32::AbsPath::Fix $path

The same as RelativeToAbsolute.

=back

=head2 AUTHOR

<Jenda@Krynicky.cz> and Mike <blazer@mail.nevalink.ru>

=cut
