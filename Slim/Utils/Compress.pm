package Slim::Utils::Compress;

# gzip routines

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
		-WindowBits => Compress::Raw::Zlib::WANT_GZIP(),
	} );
	
	if ( ($x->deflate( $opts->{in}, $opts->{out} )) == Compress::Raw::Zlib::Z_OK() ) {
		if ( ($x->flush( $opts->{out} )) == Compress::Raw::Zlib::Z_OK() ) {
			# add gzip header
			substr ${$opts->{out}}, 0, 0, _getGzipHeader();
			
			$x->deflateReset();
			return 1;
		}
	}
	
	# Failed, reset objects
	undef $gzip;
	
	return;
}

# A minimal RFC-1952 gzip header
sub _getGzipHeader {	
 	return pack 'CCCCVCC', 0x1F, 0x8B, 0x8, 0, time(), 0, 0x3;
}

1;
