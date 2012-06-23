package Slim::Utils::Compress;

# gzip routines

use strict;

# The minimal RFC-1952 gzip header
use constant GZIP_HEADER => pack 'CCCCVCC', 0x1F, 0x8B, 0x8, 0, 0, 0, 0x3;

my $gzip;
my $gunzip;

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

sub gunzip {
	my $opts = shift;
	
	my $x = $gunzip ||= Compress::Raw::Zlib::Inflate->new( {
		-WindowBits => -Compress::Raw::Zlib::MAX_WBITS(),
	} );
	
	_removeGzipHeader( $opts->{in} );
	
	if ( ($x->inflate( $opts->{in}, $opts->{out} )) == Compress::Raw::Zlib::Z_OK() ) {
		$x->inflateReset();
		return 1;
	}
	
	# Failed, reset objects
	undef $gunzip;
	
	return;
}

# From Compress::Zlib, to avoid having to include all
# of new Compress::Zlib and IO::* compress modules
sub _removeGzipHeader($)
{
    my $string = shift ;

    return Compress::Raw::Zlib::Z_DATA_ERROR() 
        if length($$string) < IO::Compress::Gzip::Constants::GZIP_MIN_HEADER_SIZE();

    my ($magic1, $magic2, $method, $flags, $time, $xflags, $oscode) = 
        unpack ('CCCCVCC', $$string);

    return Compress::Raw::Zlib::Z_DATA_ERROR()
        unless $magic1 == IO::Compress::Gzip::Constants::GZIP_ID1() and $magic2 == IO::Compress::Gzip::Constants::GZIP_ID2() and
           $method == Compress::Raw::Zlib::Z_DEFLATED() and !($flags & IO::Compress::Gzip::Constants::GZIP_FLG_RESERVED()) ;
    substr($$string, 0, IO::Compress::Gzip::Constants::GZIP_MIN_HEADER_SIZE()) = '' ;

    # skip extra field
    if ($flags & IO::Compress::Gzip::Constants::GZIP_FLG_FEXTRA())
    {
        return Compress::Raw::Zlib::Z_DATA_ERROR()
            if length($$string) < IO::Compress::Gzip::Constants::GZIP_FEXTRA_HEADER_SIZE();

        my ($extra_len) = unpack ('v', $$string);
        $extra_len += IO::Compress::Gzip::Constants::GZIP_FEXTRA_HEADER_SIZE();
        return Compress::Raw::Zlib::Z_DATA_ERROR()
            if length($$string) < $extra_len ;

        substr($$string, 0, $extra_len) = '';
    }

    # skip orig name
    if ($flags & IO::Compress::Gzip::Constants::GZIP_FLG_FNAME())
    {
        my $name_end = index ($$string, IO::Compress::Gzip::Constants::GZIP_NULL_BYTE());
        return Compress::Raw::Zlib::Z_DATA_ERROR()
           if $name_end == -1 ;
        substr($$string, 0, $name_end + 1) =  '';
    }

    # skip comment
    if ($flags & IO::Compress::Gzip::Constants::GZIP_FLG_FCOMMENT())
    {
        my $comment_end = index ($$string, IO::Compress::Gzip::Constants::GZIP_NULL_BYTE());
        return Compress::Raw::Zlib::Z_DATA_ERROR()
            if $comment_end == -1 ;
        substr($$string, 0, $comment_end + 1) = '';
    }

    # skip header crc
    if ($flags & IO::Compress::Gzip::Constants::GZIP_FLG_FHCRC())
    {
        return Compress::Raw::Zlib::Z_DATA_ERROR()
            if length ($$string) < IO::Compress::Gzip::Constants::GZIP_FHCRC_SIZE();
        substr($$string, 0, IO::Compress::Gzip::Constants::GZIP_FHCRC_SIZE()) = '';
    }
    
    return Compress::Raw::Zlib::Z_OK();
}		

1;
