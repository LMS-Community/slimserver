package Slim::Utils::Compress;

# deflate/gzip routines

my $deflate;
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

sub deflate {
	my $opts = shift;
	
	my $type = $opts->{type};
	my $x;
	
	if ( $type eq 'deflate' ) {
		$x = $deflate ||= Compress::Raw::Zlib::Deflate->new( {
			-WindowBits => -Compress::Raw::Zlib::MAX_WBITS(),
		} );
	}
	elsif ( $type eq 'gzip' ) {
		$x = $gzip ||= Compress::Raw::Zlib::Deflate->new( {
			-WindowBits => Compress::Raw::Zlib::WANT_GZIP(),
		} );
	}
	
	if ( ($x->deflate( $opts->{in}, $opts->{out} )) == Compress::Raw::Zlib::Z_OK() ) {
		if ( ($x->flush( $opts->{out} )) == Compress::Raw::Zlib::Z_OK() ) {
			if ( $type eq 'gzip' ) { # add gzip header
				substr ${$opts->{out}}, 0, 0, _getGzipHeader();
			}
			return 1;
		}
	}
	
	# Failed, reset objects
	undef $deflate;
	undef $gzip;
	
	return;
}

# A minimal RFC-1952 gzip header
sub _getGzipHeader {	
 	return pack 'CCCCVCC', 0x1F, 0x8B, 0x8, 0, time(), 0, 0x3;
}

1;
