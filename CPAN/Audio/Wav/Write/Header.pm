package Audio::Wav::Write::Header;

use strict;
use vars qw($VERSION);
$VERSION = '0.02';

sub new {
    my $class = shift;
    my $file = shift;
    my $details = shift;
    my $tools = shift;
    my $handle = shift;
    my $parent = shift;
    my $self = {
		'file'		=> $file,
		'data'		=> undef,
		'details'	=> $details,
		'tools'		=> $tools,
		'handle'	=> $handle,
		'whole_offset'	=> 4,
		'parent'	=> $parent,
	       };
    bless $self, $class;
    return $self;
}

sub start {
    my $self = shift;
    my $output = 'RIFF';
    $output .= pack( 'V', 0 );
    $output .= 'WAVE';

    my $format = $self -> _format();
    $output .= 'fmt ' . pack( 'V', length( $format ) ) . $format;
    $output .= 'data';
    my $data_off = length( $output );
    $output .= pack( 'V', 0 );

    $self -> {'data_offset'} = $data_off;
    $self -> {'total'} = length( $output ) - 8;

    return $output;
}

sub finish {
    my $self = shift;
    my $data_size = shift;
    my $handle = $self -> {'handle'};

    # padding data chunk
    my $data_pad=0;
    if ( $data_size % 2 ) {
	my $pad = "\0";
	syswrite( $handle, $pad, 1 );
	$data_pad = 1; # to add to whole_num, not data_num
    }

    my $extra = $self -> _write_list_info();
    $extra += $self -> _write_cues();
    $extra += $self -> _write_list_adtl();
    $extra += $self -> _write_display();
    $extra += $self -> _write_sampler_info();

    my $whole_num = pack( 'V', $self -> {'total'} + $data_size + $data_pad + $extra );  #includes padding
    my $len_long = length( $whole_num );

    my $parent = $self -> {'parent'};

    # RIFF-length
    my $seek_to = $self -> {'whole_offset'};
    seek( $handle, $seek_to, 0 ) || return $parent -> _error( "unable to seek to $seek_to ($!)" );
    syswrite( $handle, $whole_num, $len_long );

    # data-length
    $seek_to = $self -> {'data_offset'};
    seek( $handle, $seek_to, 0 ) || return $parent -> _error( "unable to seek to $seek_to ($!)" );
    my $data_num = pack( 'V', $data_size );
    syswrite( $handle, $data_num, $len_long );
    return 1;
}

sub add_cue {
    my $self = shift;
    my $record = shift;
    push @{ $self -> {'cues'} }, $record;
    return 1;
}

sub add_display {
    my $self = shift;
    my %hash = @_;
    unless ( exists( $hash{'id'} ) && exists( $hash{'data'} ) ) {
	return $self -> _error( "I need fields id & data to add a display block" );
    }
    push @{ $self -> {'display'} }, { map { $_ => $hash{$_} } qw( id data ) };
    return 1;
}

sub set_sampler_info {
    my $self = shift;
    my %hash = @_;
    my %defaults = $self -> {'tools'} -> get_sampler_defaults();
    foreach my $key ( keys %defaults ) {
	next if exists( $hash{$key} );
	$hash{$key} = $defaults{$key};
    }
    $hash{'sample_loops'} = 0;
    $hash{'loop'} = [];
    $self -> {'sampler'} = \%hash;
    return 1;
}

sub add_sampler_loop {
    my $self = shift;
    my %hash = @_;
    foreach my $need ( qw( start end ) ) {
	if ( exists $hash{$need} ) {
	    $hash{$need} = int $hash{$need};
	} else {
	    return $self -> _error( "missing $need field from add_sampler_loop" );
	}
    }
    my %defaults = $self -> {'tools'} -> get_sampler_loop_defaults();
    foreach my $key ( keys %defaults ) {
	next if exists( $hash{$key} );
	$hash{$key} = $defaults{$key};
    }
    unless ( exists $self -> {'sampler'} ) {
	$self -> set_sampler_info();
    }
    my $sampler = $self -> {'sampler'};
    my $id = scalar( @{ $sampler -> {'loop'} } ) + 1;
    foreach my $key ( qw( id play_count ) ) {
	next if exists( $hash{$key} );
	$hash{$key} = $id;
    }
    push @{ $sampler -> {'loop'} }, \%hash;
    $sampler -> {'sample_loops'} ++;
    return 1;
}

sub _write_list_adtl {
    my $self = shift;
    return 0 unless $self -> {'cues'};
    my $cues = $self -> {'cues'};
    my %adtl;
    foreach my $id ( 0 .. $#$cues ) {
	my $cue = $cues -> [$id];
	my $cue_id = $id + 1;
	if ( exists $cue -> {'label'} ) {
	    $adtl{'labl'} -> {$cue_id} = $cue -> {'label'};
	}
	if ( exists $cue -> {'note'} ) {
	    $adtl{'note'} -> {$cue_id}  = $cue -> {'note'};
	}
    }

    return 0 unless ( keys %adtl );
    my $adtl = 'adtl';

    foreach my $type ( sort keys %adtl ) {
	foreach my $id ( sort { $a <=> $b } keys %{ $adtl{$type} } ) {
	    $adtl .= $self -> _make_chunk( $type, pack( 'V', $id ) . $adtl{$type} -> {$id} . "\0" );
	}
    }
    return $self -> _write_block( 'LIST', $adtl );
}

sub _write_list_info {
    my $self = shift;
    return 0 unless keys %{ $self -> {'details'} -> {'info'} };
    my $info = $self -> {'details'} -> {'info'};
    my %allowed = $self -> {'tools'} -> get_rev_info_fields();
    my $list='INFO';
    foreach my $key ( keys %$info ) {
		next unless $allowed{$key};  # don't write unknown info-chunks
        $list .= $self -> _make_chunk( $allowed{$key}, $info -> {$key} . "\0" );
    }
    return $self -> _write_block( 'LIST', $list );
}

sub _write_cues {
    my $self = shift;
    return 0 unless $self -> {'cues'};
    my $cues = $self -> {'cues'};
    my @fields = qw( id position chunk cstart bstart offset );
    my %plain = map { $_, 1 } qw( chunk );
    my %defaults;
    my $output = pack( 'V', scalar( @$cues ) );
    foreach my $id ( 0 .. $#$cues ) {
	my $cue = $cues -> [$id];
	my $pos = $cue -> {'pos'};
	my %record =	(
			'id'		=> $id + 1,
			'position'	=> $pos,
			'chunk'		=> 'data',
			'cstart'	=> 0,
			'bstart'	=> 0,
			'offset'	=> $pos,
			);
	foreach my $field ( @fields ) {
	    my $data = $record{$field};
	    $data = pack( 'V', $data ) unless exists( $plain{$field} );
	    $output .= $data;
	}
    }
    my $data_len = length( $output );
    return 0 unless $data_len;
    $output = 'cue ' . pack( 'V', $data_len ) . $output;
    $data_len += 8;
    syswrite( $self -> {'handle'}, $output, $data_len );
    return $data_len;
}

sub _write_sampler_info {
    my $self = shift;
    return 0 unless exists( $self -> {'sampler'} );
    my $sampler = $self -> {'sampler'};
    my %sampler_fields = $self -> {'tools'} -> get_sampler_fields();
    my $output = '';
    foreach my $field ( @{ $sampler_fields{'fields'} } ) {
	$output .= pack( 'V', $sampler -> {$field} );
    }
    foreach my $loop ( @{ $sampler -> {'loop'} } ) {
	foreach my $loop_field ( @{ $sampler_fields{'loop'} } ) {
	    $output .= pack( 'V', $loop -> {$loop_field} );
	}
    }
    return $self -> _write_block( 'smpl', $output );
}

sub _write_display {
    my $self = shift;
    return 0 unless exists( $self -> {'display'} );
    my $total = 0;
    foreach my $display ( @{ $self -> {'display'} } ) {
	my $data = $display -> {'data'};
	my $output =  pack( 'V', $display -> {'id'} ) . $data;
	my $data_size = length $data;
	$total .= $self -> _write_block( 'DISP', $output );
    }
    return $total;
}

sub _write_block {
    my $self = shift;
    my $header = shift;
    my $output = shift;
    return unless $output;
    $output = $self->_make_chunk( $header, $output );
    return syswrite( $self -> {'handle'}, $output, length( $output ) );
}

sub _make_chunk {
    my $self = shift;
    my $header = shift;
    my $output = shift;
    my $data_len = length($output);
    return '' unless $data_len;
    $output .= "\0" if $data_len % 2; # pad byte
    return $header . pack( 'V', $data_len ) . $output;
}

sub _format {
    my $self = shift;
    my $details = $self -> {'details'};
    my $types = $self -> {'tools'} -> get_wav_pack();
    $details -> {'format'} = 1;
    my $output;
    foreach my $type ( @{ $types -> {'order'} } ) {
	$output .= pack( $types -> {'types'} -> {$type}, $details -> {$type} );
    }
    return $output;
}

sub _error {
    my $self = shift;
    return $self -> {'tools'} -> error( $self -> {'file'}, @_ );
}

1;

