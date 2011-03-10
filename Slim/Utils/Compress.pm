package Slim::Utils::Compress;

# gzip routines

use strict;

# The minimal RFC-1952 gzip header
use constant GZIP_HEADER => pack 'CCCCVCC', 0x1F, 0x8B, 0x8, 0, 0, 0, 0x3;

my $gzip;

BEGIN {
	my $hasZlib;
	
	sub hasZlib {
		return $hasZlib if defined $hasZlib;
		
		$hasZlib = 0;
		eval { 
			require Compress::Raw::Zlib;
			$hasZlib = 1;
		};
	}
}

sub gzip {
	my $opts = shift;
	
	my $x = $gzip ||= Compress::Raw::Zlib::Deflate->new( {
		-AppendOutput => 1,
		-CRC32        => 1,
		-WindowBits   => -Compress::Raw::Zlib::MAX_WBITS(),
	} );
	
	if ( ($x->deflate( $opts->{in}, $opts->{out} )) == Compress::Raw::Zlib::Z_OK() ) {
		if ( ($x->flush( $opts->{out}, Compress::Raw::Zlib::Z_FINISH() )) == Compress::Raw::Zlib::Z_OK() ) {
			# add gzip header
			substr ${$opts->{out}}, 0, 0, GZIP_HEADER;
			
			# add gzip trailer of crc32 + uncompressed size
			${$opts->{out}} .= pack 'VV', $x->crc32(), length( ${$opts->{in}} );
			
			$x->deflateReset();
			return 1;
		}
	}
	
	# Failed, reset objects
	undef $gzip;
	
	return;
}

1;
