#!/usr/bin/perl

my %files;
$files{'play'}++;
$files{'pause'}++;
$files{'stop'}++;
$files{'next'}++;
$files{'prev'}++;
$files{'rew'}++;
$files{'ffw'}++;
$files{'next'}++;

my $command = '/usr/bin/convert -geometry 25x25 ';
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
my $command = 'convert -geometry 100x100 ';
