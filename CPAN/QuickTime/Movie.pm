package QuickTime::Movie;

# $Id: Movie.pm,v 1.3 2004/03/24 18:42:40 dean Exp $

use strict;
use base qw(Exporter);

use vars qw($VERSION @EXPORT);

@EXPORT  = qw(readMovieTag);

$VERSION = '0.01';

use constant DEBUG => 0;

# Only argument is filename, with full path
sub readUserData {
	my $filename = shift;

	my $movieInfo = {};
	my $moviefile;
	open($moviefile,$filename) or return -1;
	binmode $moviefile;
	
	my $length = -s $filename;

	if (DEBUG) {
		print "Parsing QuickTime Movie $filename of size $length\n";
	}
	
	while(1) {
		my ($tag, $ends) = atom($moviefile);
			
		last if !defined($tag);
		last if $ends > $length;
		
		if (DEBUG) {
			print "top level atom: $tag [ends: $ends]\n";
		}

		# parse the data here if we like the tag
		if ($tag eq 'moov') {
			while(1) {
				my ($tag, $moovends) = atom($moviefile);
					
				last if !defined($tag);
				last if $moovends > $length;
				
				if (DEBUG) {
					print "    moov atom: $tag [ends: $moovends]\n";
				}
		
					# parse the data here if we like the tag
					if ($tag eq 'udta') {
						while(1) {
							my ($tag, $udtaends) = atom($moviefile);
								
							last if !defined($tag);
							last if $udtaends > $length;
							
							if (DEBUG) {
								print "        udta atom: $tag [ends: $udtaends]\n";
							}

							# parse the data here if we like the tag
							if ($tag eq 'meta') {
								seek $moviefile, 4, 1;
								while(1) {
									my ($tag, $metaends) = atom($moviefile);
										
									last if !defined($tag);
									last if $metaends > $length;
									
									if (DEBUG) {
										print "            meta atom: $tag [ends: $metaends]\n";
									}
									# parse the data here if we like the tag
									if ($tag eq 'ilst') {
										while(1) {
											my ($tag, $ilstends) = atom($moviefile);
												
											last if !defined($tag);
											last if $ilstends > $length;
											
											my ($payload, $dataends) = atom($moviefile);
											
											if ($payload eq 'data') {
												my $data;
												my $len =  $dataends - tell($moviefile);
												read $moviefile, $data, $len;
											
												my ($long1, $long2, $string) = unpack('NNa*', $data);

												if (DEBUG) {
													print "                payload atom: $tag [length: " . length($string) . " calculated: $len]: $long1 $long2\n";
													print " $string\n" if (length($string) < 1000)
												}

												$movieInfo->{$tag} = $string;
											} else {
												if (DEBUG) {
													print "                skipping atom: $tag\n";
												}
											}
											
											# move on to the next atom
											seek $moviefile, $ilstends, 0;
											
											last if tell $moviefile >= $metaends;
										}		
									}
							
									# move on to the next atom
									seek $moviefile, $metaends, 0;
									
									last if tell $moviefile >= $udtaends;
								}		
							}


					
							# move on to the next atom
							seek $moviefile, $udtaends, 0;
							
							last if tell $moviefile >= $moovends;
						}		
					}
		
				# move on to the next atom
				seek $moviefile, $moovends, 0;
				
				last if tell $moviefile >= $ends;
			}		
		}
		
		# move on to the next atom
		seek $moviefile, $ends, 0;
		
		last if tell $moviefile >= $length;
	}

	close $moviefile;

	return $movieInfo;
}

# private here on out
sub atom {
	my $moviefile = shift;

	read($moviefile, my $sizetag, 8) or return;

	my ($size, $tag) = unpack('Na4', $sizetag);
	
	return if $size == 1;  # we don't know how to handle 64 bit sized atoms yet
	
	return if $size < 8;
	
	my $nextatom = tell($moviefile) + $size - 8;
	
	return ($tag, $nextatom);
}	

1;

__END__

=head1 NAME

QuickTime::Movie - Perl extension for reading Movie User Data

=head1 SYNOPSIS

  use QuickTime::Movie;

  my $tag = getUserData($filename);

=head1 DESCRIPTION

Returns a hash reference of tags found in a Movie file.

=head2 EXPORT

getUserData()

=head1 SEE ALSO

L<http://developer.apple.com/documentation/QuickTime/QTFF/index.html>

=head1 AUTHOR

Dean Blackketer E<lt>dean@slimdevices.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2003 by Dean Blackketter

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.2 or,
at your option, any later version of Perl 5 you may have available.

=cut
