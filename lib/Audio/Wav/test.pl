use strict;

$| = 1;

my $started = time;

my $out_dir = 'test_output';

unless ( -d $out_dir ) {
    mkdir( $out_dir, 0777 ) ||
	    die "unable to make test output directory '$out_dir' - ($!)";
}

use Audio::Wav;

my $cnt = 0;

print "1..4\n\n";

### Wav Creation

print "\nTesting wav creation\n";

my %wav_options = ( # these are optional & default to 0
		    '.01compatible'	=> 0,
		    'oldcooledithack'	=> 0,
		    'debug'		=> 0,
		  );


my $wav = Audio::Wav -> new( %wav_options );

my $file_out = $out_dir . '/testout.wav';
my $file_copy = $out_dir . '/testcopy.wav';
my $sample_rate = 11025;
my $bits_sample = 8;
my $length = 2;
my $channels = 1;

my $details =	{
		'bits_sample'	=> $bits_sample,
		'sample_rate'	=> $sample_rate,
		'channels'	=> $channels,
		};

my $write = $wav -> write( $file_out, $details );

&add_slide( 50, 300, $length );

$write -> set_info( 'software' => 'Audio::Wav' );

my $marks = $length / 3;
foreach my $xpos ( 1 .. 2 ) {
    my $ypos = &seconds_to_samples( $xpos * $marks );
    $write -> add_cue( $ypos, "label $xpos", "note $xpos" );
    print "Cue $xpos at $ypos\n";
}

my $sec_samps = &seconds_to_samples( 1 );
$write -> add_cue( $sec_samps, "onesec", "one second" );
print "Cue 3 at $sec_samps\n";

my %samp_loop = (
		'start'	=> &seconds_to_samples( $length * .25 ),
		'end'	=> &seconds_to_samples( $length * .75 ),
		);

$write -> add_sampler_loop( %samp_loop );

my %display = (
		'id'	=> 1,
		'data'	=> 'Submarine Captain',
	      );

$write -> add_display( %display );

$write -> finish();

$cnt ++;
print "ok $cnt\n";

### Wav Copying

print "\nTesting wav copying\n";

my $read = $wav -> read( $file_out );

# print Data::Dumper->Dump([ $read -> details() ]);

$write = $wav -> write( $file_copy, $read -> details() );

my $cues = $read -> get_cues();

for my $id ( 1 .. 3 ) {
    print "Cue $id at ", $cues -> {$id} -> {'position'}, "\n";
}

my $buffer = 512;
my $total = 0;
$length = $read -> length();

while ( $total < $length ) {
    my $left = $length - $total;
    $buffer = $left unless $left > $buffer;
    my $data = $read -> read_raw( $buffer );
    last unless defined( $data );
    $write -> write_raw( $data, $buffer );
    $total += $buffer;
}

$write -> finish();

$cnt ++;
print "ok $cnt\n";

### Wav Comparing

print "\nComparing wav files $file_out & $file_copy\n";

my $file_orig = $file_out;

open ORIG, $file_orig or die "Can't open file '$file_orig': $!\n";
binmode ORIG;

my $data_orig;
while (<ORIG>) {
  $data_orig.=$_;
}
close ORIG;

open COPY, $file_copy or die "Can't open file '$file_copy': $!\n";
binmode COPY;

my $data_copy;
while (<COPY>) {
  $data_copy.=$_;
}
close COPY;


if (length($data_copy) ne length($data_orig)) {
    die "Wav files ARE NOT identical; they are of different lengths";
}


if ($data_copy ne $data_orig) {
    die "Wav files ARE NOT identical";
}

$cnt ++;
print "ok $cnt\n";

print "\nTesting sample wav file\n";

if ( &test_wav() ) {
    print "sample wav file was read correctly\n";
} else {
    die "sample wav file was not read correctly\n";
}

$cnt ++;
print "ok $cnt\n";

print "took ", int( time - $started ), " seconds";

sub test_wav {
    my $file = 'test_tone.wav';
    my $cued_sample = -15;
    my %match_details = (
			'bits_sample'	=> 8,
			'length'	=> '0.5',
			'block_align'	=> 1,
			'bytes_sec'	=> 8000,
			'total_length'	=> 4152,
			'channels'	=> 1,
			'sample_rate'	=> 8000,
			'data_length'	=> 4000,
			'data_start'	=> '44',
			);
    my $read = $wav -> read( $file );
    my $details = $read -> details();
    foreach my $key ( keys %match_details ) {
	my( $want, $is ) = ( $details -> {$key}, $match_details{$key} );
	next if $details -> {$key} eq $match_details{$key};
	warn "mismatched value for $key, wanted $want, but got $is\n";
	return 0;
    }
    my $cues = $read -> get_cues();
    unless ( exists $cues -> {'1'} ) {
	warn "no cues found in $file\n";
	return 0;
    }
    my $pos = $cues -> {'1'} -> {'position'};
    unless ( $read -> move_to( $pos ) ) {
	warn "unable to move to sample $pos\n";
	return 0;
    }
    my( $sample ) = $read -> read();
    unless ( $cued_sample == $sample ) {
	warn "sample at position $pos does not match $cued_sample\n";
	return 0;
    }
    return 1;
}

sub add_slide {
    my $from_hz = shift;
    my $to_hz = shift;
    my $length = shift;
    my $volume = .5;
    my $diff_hz = $to_hz - $from_hz;
    my $pi = ( 22 / 7 ) * 2;
    $length *= $sample_rate;
    my $max_no =  ( 2 ** $bits_sample ) / 2;
    my $half = int( $length / 2 );
    my $pos = 0;
    foreach my $rev ( 0, 1 ) {
	my $target = $half;
	$target *= 2 if $rev;
	while ( $pos < $target ) {
	    $pos ++;
	    my $rev_pos = $rev ? ( $half - ( $pos - $half ) ) : $pos;
	    my $prog = $rev_pos / $half;
	    my $hz = $from_hz + ( $diff_hz * $prog );
	    my $cycle = $sample_rate / $hz;
	    my $mult = $rev_pos / $cycle;
	    my $samp = sin( $pi * $mult ) * $max_no;
	    $samp *= $volume;
	    $write -> write( map $samp, 1 .. $channels );
	}
    }

}

sub seconds_to_samples {
    my $time = shift;
    return $time * $sample_rate;
}

