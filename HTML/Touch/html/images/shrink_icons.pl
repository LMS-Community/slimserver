#!/usr/bin/perl

my %files;
$files{'statistics'}++;
$files{'artist'}++;
$files{'radio'}++;
$files{'album'}++;
$files{'playlist'}++;
$files{'search'}++;
$files{'genre'}++;
$files{'artwork'}++;
$files{'folder'}++;
$files{'random'}++;
$files{'favorites'}++;
$files{'new_music'}++;

my $dimension = $ARGV[0] || 120;
my $command = "/usr/bin/convert -geometry ${dimension}x${dimension} ";
opendir(DIR,".");
while(my $file = readdir(DIR)) {
	for my $key (sort keys %files) {
		if ($file eq "${key}_active.gif" || $file eq "${key}.gif") {
			print "$file\n";
			my $convert = $command . $file . " " . "smaller/$file";
			print $convert . "\n";
			`$convert`;
		}
	}
}
closedir(DIR);
