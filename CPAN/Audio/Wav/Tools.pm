package Audio::Wav::Tools;

use strict;

use vars qw( $VERSION );
$VERSION = '0.02';

sub new {
    my $class = shift;
    my %options = @_;
    my $self =	{
		'errorHandler'	=> undef,
		};

    foreach my $key ( qw( .01compatible oldcooledithack debug ) ) {
	$self -> {$key} = exists( $options{$key} ) && $options{$key} ? 1 : 0;
    }
    bless $self, $class;
    return $self;
}

sub is_debug {
    my $self = shift;
    return $self -> {'debug'};
}

sub is_01compatible {
    my $self = shift;
    return $self -> {'.01compatible'};
}

sub is_oldcooledithack {
    my $self = shift;
    return $self -> {'oldcooledithack'};
}

sub set_error_handler {
    my $self = shift;
    my $handler = shift;
    unless ( ref( $handler ) eq 'CODE' ) {
	die "set_error_handler is expecting a reference to a sub routine";
    }
    $self -> {'errorHandler'} = $handler;
}

sub is_big_endian {
    my $self = shift;
    return $self -> {'is_big_endian'} if exists( $self -> {'is_big_endian'} );
    my $VALUE = 1801677134;
    my $nativeLong  = pack( "L", $VALUE );   # 'kciN' (big) or 'Nick' (little)
    my $bigLong     = pack( "N", $VALUE );   # should return 'kciN'
    $self -> {'is_big_endian'} = $nativeLong eq $bigLong ? 1 : 0;
    return $self -> {'is_big_endian'};
}

sub get_info_fields {
    return (
	    'IARL'	=> 'archivallocation',
	    'IART'	=> 'artist',
	    'ICMS'	=> 'commissioned',
	    'ICMT'	=> 'comments',
	    'ICOP'	=> 'copyright',
	    'ICRD'	=> 'creationdate',
	    'IENG'	=> 'engineers',
	    'IGNR'	=> 'genre',
	    'IKEY'	=> 'keywords',
	    'IMED'	=> 'medium',
	    'INAM'	=> 'name',
	    'IPRD'	=> 'product',
	    'ISBJ'	=> 'subject',
	    'ISFT'	=> 'software',
	    'ISRC'	=> 'supplier',
	    'ISRF'	=> 'source',
	    'ITCH'	=> 'digitizer',
	  );
}

sub get_rev_info_fields {
    my $self = shift;
    return %{ $self -> {'rev_info_fields'} } if exists( $self -> {'rev_info_fields'} );
    my %info_fields = $self -> get_info_fields();
    my %rev_info;
    foreach my $key ( keys %info_fields ) {
	$rev_info{ $info_fields{$key} } = $key;
    }
    $self -> {'rev_info_fields'} = \%rev_info;
    return %rev_info;
}


sub get_sampler_fields {
# dwManufacturer dwProduct dwSamplePeriod dwMIDIUnityNote dwMIDIPitchFraction dwSMPTEFormat dwSMPTEOffset cSampleLoops cbSamplerData
# <sample-loop(s)> <sampler-specific-data> ) <sample-loop> struct dwIdentifier; dwType; dwStart; dwEnd; dwFraction; dwPlayCount;
    return (
	    'fields'	=> [ qw( manufacturer product sample_period midi_unity_note midi_pitch_fraction smpte_format smpte_offset sample_loops sample_data ) ],
	    'loop'	=> [ qw( id type start end fraction play_count ) ],
	    'extra'	=> [],
#	    'extra'	=> [ map 'unknown' . $_, 1 .. 3  ],
	   );
}

sub get_sampler_defaults {
    return (
	    'midi_pitch_fraction'	=> 0,
	    'smpte_format'		=> 0,
	    'smpte_offset'		=> 0,
	    'product'			=> 0,
	    'sample_period'		=> 0, # 22675,
	    'manufacturer'		=> 0,
	    'sample_data'		=> 0,
	    'midi_unity_note'		=> 65
	   );
}

sub get_sampler_loop_defaults {
    return (
	    'fraction'			=> 0,
	    'type'			=> 0
	   );
}


sub error {
    my $self = shift;
    my $filename = shift;
    my $msg = shift;
    my $type = shift;
    my $handler = $self -> {'errorHandler'};
    if ( $handler ) {
	my %hash = (
		    'filename'	=> $filename,
		    'message'	=> $msg ? $msg : '',
		   );
	$hash{'warning'} = 1 if ($type && $type eq 'warn');
	&$handler( %hash );
    } else {
	my $txt = $filename ? "$filename: $msg\n" : "$msg\n";
	if ( $type && $type eq 'warn' ) {
	    warn $txt;
	} else {
	    die $txt;
	}
    }
    return undef;
}

sub get_wav_pack {
    my $self = shift;
    return {
	    'order'	=> [ qw( format channels sample_rate bytes_sec block_align bits_sample ) ],
	    'types'	=> {
			    'format'      => 'v',
			    'channels'    => 'v',
			    'sample_rate' => 'V',
			    'bytes_sec'   => 'V',
			    'block_align' => 'v',
			    'bits_sample' => 'v',
			   },
    };
}

1;
