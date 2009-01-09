package Audio::Wav::Read;

use strict;
use FileHandle;

use vars qw( $VERSION );
$VERSION = '0.02';

=head1 NAME

Audio::Wav::Read - Module for reading Microsoft WAV files.

=head1 SYNOPSIS

    use Audio::Wav;
    my $wav = new Audio::Wav;
    my $read = $wav -> read( 'filename.wav' );
    my $details = $read -> details();

=head1 DESCRIPTION

Reads Microsoft Wav files.

=head1 SEE ALSO

L<Audio::Wav>

L<Audio::Wav::Write>

=head1 NOTES

This module shouldn't be used directly, a blessed object can be returned from L<Audio::Wav>.

=head1 METHODS

=cut

sub new {
    my $class = shift;
    my $file = shift;
    my $tools = shift;
    $file =~ s#//#/#g;
    my $size = -s $file;
    my $handle = new FileHandle $file;

    my $self = {
		'real_size'	=> $size,
		'file'		=> $file,
		'handle'	=> $handle,
		'tools'		=> $tools,
	       };

    bless $self, $class;

    unless ( defined $handle ) {
	$self -> _error( "unable to open file ($!)" );
	return $self;
    }

    binmode $handle;

    $self -> {'data'} = $self -> _read_file();
    my $details = $self -> details();
    if ($details) {
		$self -> _init_read_sub();
		$self -> {'pos'} = $details -> {'data_start'};
		$self -> move_to();
	}
    return $self;
}


=head2 file_name

Returns the file name.

    my $file = $read -> file_name();

=cut

sub file_name {
    my $self = shift;
    return $self -> {'file'};
}

=head2 get_info

Returns information contained within the wav file.

    my $info = $read -> get_info();

Returns a reference to a hash containing;
(for example, a file marked up for use in Audio::Mix)

    {
	'keywords'	=> 'bpm:126 key:a',
	'name'		=> 'Mission Venice',
	'artist'	=> 'Nightmares on Wax'
    };

=cut

sub get_info {
    my $self = shift;
    return undef unless exists( $self -> {'data'} -> {'info'} );
    return $self -> {'data'} -> {'info'};
}

=head2 get_cues

Returns the cuepoints marked within the wav file.

    my $cues = $read -> get_cues();

Returns a reference to a hash containing;
(for example, a file marked up for use in Audio::Mix)
(position is byte offset)

    {
      1 => {
	     label => 'sig',
	     position => 764343,
	     note => 'first'
	   },
      2 => {
	     label => 'fade_in',
	     position => 1661774,
	     note => 'trig'
	   },
      3 => {
	     label => 'sig',
	     position => 18033735,
	     note => 'last'
	   },
      4 => {
	     label => 'fade_out',
	     position => 17145150,
	     note => 'trig'
	   },
      5 => {
	     label => 'end',
	     position => 18271676
	   }
    }

=cut

sub get_cues {
    my $self = shift;
    return undef unless exists( $self -> {'data'} -> {'cue'} );
    my $data = $self -> {'data'};
    my $cues = $data -> {'cue'};
    my $output = {};
    foreach my $id ( keys %$cues ) {
	my $pos = $cues -> {$id} -> {'position'};
	my $record = { 'position' => $pos };
	$record -> {'label'} = $data -> {'labl'} -> {$id} if ( exists $data -> {'labl'} -> {$id} );
	$record -> {'note'} = $data -> {'note'} -> {$id} if ( exists $data -> {'note'} -> {$id} );
	$output -> {$id} = $record;
    }
    return $output;
}

=head2 read_raw

Reads raw packed bytes from the current audio data position in the file.

    my $data = $self -> read_raw( $byte_length );

=cut

sub read_raw {
    my $self = shift;
    my $len = shift;
    my $data_finish = $self -> {'data'} -> {'data_finish'};
    if ( $self -> {'pos'} + $len > $data_finish ) {
	$len = $data_finish - $self -> {'pos'};
    }
    return $self -> _read_raw( $len );
}

sub _read_raw {
    my $self = shift;
    my $len = shift;
    my $data;
    return undef unless $len;
    $self -> {'pos'} += read( $self -> {'handle'}, $data, $len );
    return $data;
}

=head2 read

Returns the current audio data position sample across all channels.

    my @channels = $self -> read();

Returns an array of unpacked samples.
Each element is a channel i.e ( left, right ).
The numbers will be in the range;

    where $samp_max = ( 2 ** bits_per_sample ) / 2
    -$samp_max to +$samp_max

=cut

sub read {
    my $self = shift;
    my $val;
    my $block = $self -> {'data'} -> {'block_align'};
    return () if $self -> {'pos'} + $block > $self -> {'data'} -> {'data_finish'};
    $self -> {'pos'} += read( $self -> {'handle'}, $val, $block );
    return () unless defined( $val );
    return &{ $self -> {'read_sub'} }( $val );
}

sub _init_read_sub {
    my $self = shift;
    my $details = $self -> {'data'};
    my $channels = $details -> {'channels'};
    my $sub;
    if ($details->{'bits_sample'} && $details -> {'bits_sample'} <= 8 ) {
	my $offset = ( 2 ** $details -> {'bits_sample'} ) / 2;
	$sub = sub { return map $_ - $offset, unpack( 'C'.$channels, shift() ) };
    } else {
	if ( $self -> {'tools'} -> is_big_endian() ) {
	    $sub = sub { return unpack( 's'.$channels,				# 3. unpack native as signed short
				    pack( 'S'.$channels,			# 2. pack native unsigned short
					unpack( 'v'.$channels, shift() )	# 1. unpack little-endian unsigned short
				    )
				);
		   };
	} else {
	    $sub = sub { return unpack( 's'.$channels, shift() ) };
	}
    }
    $self -> {'read_sub'} = $sub;
}

=head2 position

Returns the current audio data position (as byte offset).

    my $byte_offset = $read -> position();

=cut

sub position {
    my $self = shift;
    return $self -> {'pos'} - $self -> {'data'} -> {'data_start'};
}

=head2 offset

Returns the current audio data offset (as bytes from the beginning of the file).

    my $byte_offset = $read -> offset();

=cut

sub offset {
    my $self = shift;
    return $self -> {'data'} -> {'data_start'};
}

=head2 move_to

Moves the current audio data position to byte offset.

    $read -> move_to( $byte_offset );

=cut

sub move_to {
    my $self = shift;
    my $pos = shift;
    $pos = $self -> {'data'} -> {'data_start'} unless defined( $pos );
    if ( seek $self -> {'handle'}, $pos, 0 ) {
	$self -> {'pos'} = $pos;
	return 1;
    } else {
	return $self -> _error( "can't move to position '$pos'" );
    }
}

=head2 move_to_sample

Moves the current audio data position to sample offset.

    $read -> move_to_sample( $sample_offset );

=cut

sub move_to_sample {
    my $self = shift;
    my $pos = shift;
    return $self -> move_to() unless defined( $pos );
    return $self -> move_to( $pos * $self -> {'data'} -> {'block_align'} );
}

=head2 length

Returns the number of bytes of audio data in the file.

    my $audio_bytes = $read -> length();

=cut

sub length {
    my $self = shift;
    return $self -> {'data'} -> {'data_length'};
}

=head2 length_samples

Returns the number of samples of audio data in the file.

    my $audio_samples = $read -> length_samples();

=cut

sub length_samples {
    my $self = shift;
    my $data = $self -> {'data'};
    return $data -> {'data_length'} / $data -> {'block_align'};
}

=head2 length_seconds

Returns the number of seconds of audio data in the file.

    my $audio_seconds = $read -> length_seconds();

=cut

sub length_seconds {
    my $self = shift;
    my $data = $self -> {'data'};
    my $length =  $data -> {'data_length'};
    my $rate = $data -> {'bytes_sec'};
    if ($length || $rate) {
 	   return $length / $rate;
 	} else {
 		return 0;
 	}
}

=head2 details

Returns a reference to a hash of lots of details about the file.
Too many to list here, try it with Data::Dumper.....

    use Data::Dumper;
    my $details = $read -> details();
    print Data::Dumper->Dump([ $details ]);

=cut

sub details {
    my $self = shift;
    return $self -> {'data'};
}

#########

sub _read_file {
    my $self = shift;
    my $handle = $self -> {'handle'};
    my %details;
    my $type = $self -> _read_raw( 4 );
    my $length = $self -> _read_long( );
    my $subtype = $self -> _read_raw( 4 );
    my $tools = $self -> {'tools'};
    my $old_cooledit = $tools -> is_oldcooledithack();
    my $debug = $tools -> is_debug();

    $details{'total_length'} = $length;
    
    # Bug 10386, some tagging programs do not correctly adjust the chunk length
    # when adding ID3 chunks, so always read to the end of the file looking for chunks.
    $length = $self->{'real_size'};

    unless ( $type eq 'RIFF' && $subtype eq 'WAVE' ) {
	return $self -> _error( "doesn't seem to be a wav file" );
    }

	my $walkover;  # for fixing cooledit 96 data-chunk bug

    while ( ! eof $handle && $self -> {'pos'} < $length ) {
		my $head;
		if ($walkover) {
			# rectify cooledit 96 data-chunk bug
			$head = $walkover . $self->_read_raw(3);
			$walkover=undef;
			print("debug: CoolEdit 96 data-chunk bug detected!\n") if $debug;
		} else {
			$head = $self -> _read_raw( 4 );
		}
		my $chunk_len = $self -> _read_long();

		printf("debug: head: '$head' at %6d (%6d bytes)\n",$self->{pos},$chunk_len) if $debug;

		if ( $head eq 'fmt ' ) {
		    my $format = $self -> _read_fmt( $chunk_len );
		    my $comp = delete( $format -> {'format'} );
		    unless ( $comp == 1 ) {
			return $self -> _error( "seems to be compressed, I can't handle anything other than uncompressed PCM" );
		    }
		    %details = ( %details, %$format );
		    next;
		} elsif ( $head eq 'cue ' ) {
		    $details{'cue'} = $self -> _read_cue( $chunk_len, \%details );
		    next;
		} elsif ( $head eq 'smpl' ) {
		    $details{'sampler'} = $self -> _read_sampler( $chunk_len );
		    next;
		} elsif ( $head eq 'LIST' ) {
		    my $list = $self -> _read_list( $chunk_len, \%details );
		    next;
		} elsif ( $head eq 'DISP' ) {
		    $details{'display'} = $self -> _read_disp( $chunk_len );
		    next;
		} elsif ( $head eq 'data' ) {
		    $details{'data_start'} = $self -> {'pos'};
		    $details{'data_length'} = $chunk_len;
		} elsif ( $head =~ /^id3[2 ]$/i ) { # Look for 'id3 ' or 'ID32'
			# Save ID3 tag offset for use by MP3 library if it wants to read the tags
			$details{'id3_offset'} = $self->{'pos'};
		} else {
		    $head =~ s/[^\w]+//g;
		  	$self -> _error( "ignored unknown block type: $head at $self->{pos} for $chunk_len", 'warn' );
#			djb - we should just skip over unknown chunks, rather than restarting the scan
#		    next if $chunk_len > 100;
		}

		seek $handle, $chunk_len, 1;
		$self -> {'pos'} += $chunk_len;

		# read padding
		if ($chunk_len % 2) {
			my $pad = $self->_read_raw(1);
			if ( ($pad =~ /\w/) && $old_cooledit && ($head eq 'data') ) {
				# Oh no, this file was written by cooledit 96...
				# This is not a pad byte but the first letter of the next head.
				$walkover = $pad;
			}
		}

		#unless ( $old_cooledit ) {
		#    $chunk_len += 1 if $chunk_len % 2; # padding
		#}
		#seek $handle, $chunk_len, 1;
		#$self -> {'pos'} += $chunk_len;


    }

    if ( exists $details{'data_start'} ) {
		$details{'length'} = $details{'data_length'} / $details{'bytes_sec'};
		$details{'data_finish'} = $details{'data_start'} + $details{'data_length'};
    } else {
		$details{'data_start'} = 0;
		$details{'data_length'} = 0;
		$details{'length'} = 0;
		$details{'data_finish'} = 0;
    }
    return \%details;
}


sub _read_list {
    my $self = shift;
    my $length = shift;
    my $details = shift;
    my $note = $self -> _read_raw( 4 );
    my $pos = 4;

    if ( $note eq 'adtl' ) {
	my %allowed = map { $_, 1 } qw( ltxt note labl );
	while ( $pos < $length ) {
	    my $head = $self -> _read_raw( 4 );
	    $pos += 4;
	    if ( $head eq 'ltxt' ) {
		my $record = $self -> _decode_block( [ 1 .. 6 ] );
		$pos += 24;
	    } else {
		my $bits = $self -> _read_long();
		$pos += $bits + 4;

		if ( $head eq 'labl' || $head eq 'note' ) {
		    my $id = $self -> _read_long();
		    my $text = $self -> _read_raw( $bits - 4 );
		    $text =~ s/\0+$//;
		    $details -> {$head} -> {$id} = $text;
		} else {
		    my $unknown = $self -> _read_raw ( $bits ); # skip unknown chunk
		}
		if ($bits % 2) { # eat padding
		    my $padding = $self -> _read_raw(1);
		    $pos++;
		}
	    }
	}
	# if it's a broken file and we've read too much then go back
	if ( $pos > $length ) {
	    seek $self->{'handle'}, $length-$pos, 1;
	}
    }
    elsif ( $note eq 'INFO' ) {
	my %allowed = $self -> {'tools'} -> get_info_fields();
	while ( $pos < $length ) {
	    my $head = $self -> _read_raw( 4 );
	    return undef if (!defined($head));
	    
	    $pos += 4;
	    my $bits = $self -> _read_long();    
	    return undef if (!defined($bits));
	    
	    $pos += $bits + 4;
	    my $text = $self -> _read_raw( $bits );
	    return undef if (!defined($text));

	    if ( $allowed{$head} ) {
			$text =~ s/\0+$//;
			$details -> {'info'} -> { $allowed{$head} } = $text;
	    }
	    if ($bits % 2) { # eat padding
			my $padding = $self -> _read_raw(1);
			$pos++;
	    }
	}
    } else {
	my $data = $self -> _read_raw( $length - 4 );
    }
}

sub _read_cue {
    my $self = shift;
    my $length = shift;
    my $details = shift;
    my $cues = $self -> _read_long();
    my @fields = qw( id position chunk cstart bstart offset );
    my @plain = qw( chunk );
    my $output;
    for ( 1 .. $cues ) {
	my $record = $self -> _decode_block( \@fields, \@plain );
	my $id = delete( $record -> {'id'} );
	$output -> {$id} = $record;
    }
    return $output;
}

sub _read_disp {
    my $self = shift;
    my $length = shift;
    my $type = $self -> _read_long();
    my $data = $self -> _read_raw( $length - 4 + ($length%2) );
    $data =~ s/\0+$//;
    return [ $type, $data ];
}

sub _read_sampler {
    my $self = shift;
    my $length = shift;
    my %sampler_fields = $self -> {'tools'} -> get_sampler_fields();

    my $record = $self -> _decode_block( $sampler_fields{'fields'} );

    for my $id ( 1 .. $record -> {'sample_loops'} ) {
		push @{ $record -> {'loop'} }, $self -> _decode_block( $sampler_fields{'loop'} );
    }

	$record -> {'sample_specific_data'} = _read_raw($record -> {'sample_data'});

	my $read_bytes =
		  9*4								# sampler info
		+ 6*4*$record->{'sample_loops'}		# loops
		+ $record->{'sample_data'};			# specific data


	# read any junk
	if ($read_bytes  < $length) {
		my $junk = $self->_read_raw( $length-$read_bytes );
	}

	if ($length % 2) {
		my $pad = $self->_read_raw(1);
	}

    # temporary nasty hack to gooble the last bogus 12 bytes
    #my $extra = $self -> _decode_block( $sampler_fields{'extra'} );

    return $record;
}


sub _decode_block {
    my $self = shift;
    my $fields = shift;
    my $plain = shift;
    my %plain;
    if ( $plain ) {
	foreach my $field ( @$plain ) {
	    for my $id ( 0 .. $#$fields ) {
		next unless $fields -> [$id] eq $field;
		$plain{$id} = 1;
	    }
	}
    }
    my $no_fields = scalar( @$fields );
    my %record;
    for my $id ( 0 .. $#$fields ) {
	if ( exists $plain{$id} ) {
	    $record{ $fields -> [$id] } = $self -> _read_raw( 4 );
	} else {
	    $record{ $fields -> [$id] } = $self -> _read_long();
	}
    }
    return \%record;
}

sub _read_fmt {
    my $self = shift;
    my $length = shift;
    my $data = $self -> _read_raw( $length );
    my $types = $self -> {'tools'} -> get_wav_pack();
    my $pack_str = '';
    my $fields = $types -> {'order'};
    foreach my $type ( @$fields ) {
	$pack_str .= $types -> {'types'} -> {$type};
    }
    my @data = unpack( $pack_str, $data );
    my %record;
    for my $id ( 0 .. $#$fields ) {
	$record{ $fields -> [$id] } = $data[$id];
    }
    return { %record };
}

sub _read_long {
    my $self = shift;
    my $data = $self -> _read_raw( 4 );
    return unpack( 'V', $data );
}

sub _error {
    my $self = shift;
    return $self -> {'tools'} -> error( $self -> {'file'}, @_ );
}

=head1 AUTHORS

    Nick Peskett <cpan@peskett.com>.
    Kurt George Gjerde <kurt.gjerde@media.uib.no>. (0.02)

=cut

1;
