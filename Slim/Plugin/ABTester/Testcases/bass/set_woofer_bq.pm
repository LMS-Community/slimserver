package set_woofer_bq;

use strict;
use IO::Socket;
use FileHandle;
use Data::Dumper;
use File::Spec::Functions qw(:ALL);
# Send woofer/sub crossover data via the Squeezecenter CLI to Boom DSP.

sub read_config_file
{
    my ($filename) = @_;
    my $f = new FileHandle($filename);
    my $result = [];
    while (my $line = <$f>) {
	chomp($line);
	if ($line =~ m/(^[0-9.]+) : ([0-9A-Fa-f ]+)$/) {
	    my $frequency = $1;
	    my $commands = $2;
	    my @commands = split(/ /, $commands);
	    push @$result, [$frequency, \@commands];
	}
    }
    $f->close();
    return $result;
}


sub get_i2c_data
{
    my ($cfg, $frequency) = @_;
    my $closest_frequency = $cfg->[0][0];
    my $closest = $cfg->[0];
    foreach my $d (@$cfg) {
	my $f = @$d[0];
	if (abs($frequency-$f) < abs($frequency - $closest_frequency)) {
	    $closest_frequency = $f;
	    $closest = $d;
	}
    }
    return $closest;
}

sub asc2i2c
{
    my ($asc_data) = @_;
    my $len = length($asc_data);
    my $result = '';
    for (my $i = 0; $i < $len; $i+=2) {
	$result = $result . "%" . substr($asc_data, $i, 2);
    }
    return $result;
}

sub main {
    my $playername = shift;
    my $frequency  = shift;
    my $directory = shift;

    my $configFile = "woofer_biquad.cfg";
    if($directory) {
        $configFile = catfile($directory,$configFile);
    }
    my $cfg = read_config_file($configFile);

    # Find the closest frequency in $cfg
    my $i2c_data = get_i2c_data($cfg, $frequency);
    
    my $sock = new IO::Socket::INET(
    			  PeerAddr => 'localhost',
    			  PeerPort => '9090',
    			  Proto    => 'tcp',
    			  );
    
    unless ($sock) {
        print "Couldn't open socket $!\n";
        return -1;
    }
    
    my $highpass_frequency = $i2c_data->[0];
    my @i2c_sequences = @{$i2c_data->[1]};
    print "Setting woofer/sub crossover frequency to $highpass_frequency\n";
    foreach my $data (@i2c_sequences) {
        my $cmd = "$playername boomdac " . asc2i2c($data) . "\n";
        print $cmd;
        print $sock $cmd;
    }
    close($sock);
    return 0;}

1;

__END__
