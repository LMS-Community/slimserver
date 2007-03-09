=head1 NAME

Compress::LZF - extremely light-weight Lempel-Ziv-Free compression

=head1 SYNOPSIS

   # import compress/decompress functions
   use Compress::LZF;
   # the same as above
   use Compress::LZF ':compress';

   $compressed = compress $uncompressed_data;
   $original_data = decompress $compressed;

   # import sfreeze, sfreeze_cref and sfreeze_c
   use Compress::LZF ':freeze';

   $serialized = sfreeze_c [4,5,6];
   $original_data = sthaw $serialized;

=head1 DESCRIPTION

LZF is an extremely fast (not that much slower than a pure memcpy)
compression algorithm. It is ideal for applications where you want to save
I<some> space but not at the cost of speed. It is ideal for repetitive
data as well. The module is self-contained and very small (no large
library to be pulled in). It is also free, so there should be no problems
incoporating this module into commercial programs.

I have no idea wether any patents in any countries apply to this
algorithm, but at the moment it is believed that it is free from any
patents.

=head1 FUNCTIONS

=head2 $compressed = compress $uncompressed

Try to compress the given string as quickly and as much as possible. In
the worst case, the string can enlarge by 1 byte, but that should be the
absolute exception. You can expect a 45% compression ratio on large,
binary strings.

=head2 $decompressed = decompress $compressed

Uncompress the string (compressed by C<compress>) and return the original
data. Decompression errors can result in either broken data (there is no
checksum kept) or a runtime error.

=head2 $serialized = sfreeze $value (simplified freeze)

Often there is the need to serialize data into a string. This function does that, by using the Storable
module. It does the following transforms:

  undef (the perl undefined value)
     => a special cookie (undef'ness is being preserved)
  IV, NV, PV (i.e. a _plain_ perl scalar):
     => stays as is when it contains normal text/numbers
     => gets serialized into a string
  RV, undef, other funny objects (magical ones for example):
     => data structure is freeze'd into a string.

That is, it tries to leave "normal", human-readable data untouched but
still serializes complex data structures into strings. The idea is to keep
readability as high as possible, and in cases readability can't be helped
anyways, it tries to compress the string.

The C<sfreeze> functions will enlarge the original data one byte at most
and will only load the Storable method when neccessary.

=head2 $serialized = sfreeze_c $value (sfreeze and compress)

Similar to C<sfreeze>, but always tries to C<c>ompress the resulting
string. This still leaves most small objects (most numbers) untouched.

=head2 $serialized = sfreeze_cr $value (sfreeze and compress references)

Similar to C<sfreeze>, but tries to C<c>ompress the resulting string
unless it's a "simple" string. References for example are not "simple" and
as such are being compressed.

=head2 $original_data = sthaw $serialized

Recreate the original object from it's serialized representation. This
function automatically detects all the different sfreeze formats.

=head2 Compress::LZF::set_serializer $package, $freeze, $thaw

Set the serialize module and functions to use. The default is "Storable",
"Storable::net_mstore" and "Storable::mretrieve", which should be fine for
most purposes.

=head1 SEE ALSO

Other Compress::* modules, especially Compress::LZV1 (an older, less
speedy module that guarentees only 1 byte overhead worst case) and
Compress::Zlib.

http://liblzf.plan9.de/

=head1 AUTHOR

This perl extension and the underlying liblzf were written by Marc Lehmann
<schmorp@schmorp.de> (See also http://liblzf.plan9.de/).

=head1 BUGS

=cut

package Compress::LZF;

require Exporter;
require DynaLoader;

$VERSION = '1.71';
@ISA = qw/Exporter DynaLoader/;
%EXPORT_TAGS = (
      freeze   => [qw(sfreeze sfreeze_cr sfreeze_c sthaw)],
      compress => [qw(compress decompress)],
);

Exporter::export_tags('compress');
Exporter::export_ok_tags('freeze');

bootstrap Compress::LZF $VERSION;

1;





