package MP3::Tag::File;

use strict;
use Fcntl;
use vars qw /$VERSION/;

$VERSION="0.40";

=pod

=head1 NAME

MP3::Tag::File - Module for reading / writing files

=head1 SYNOPSIS

  my $mp3 = MP3::Tag->new($filename);

  ($song, $artist, $no, $album) = $mp3->read_filename();

see L<MP3::Tag>

=head1 DESCRIPTION

MP3::Tag::File is designed to be called from the MP3::Tag module.

It offers possibilities to read/write data from files.

=over 4

=cut


# Constructor

sub new {
    my $class = shift;
    my $self={filename=>shift};
    return undef unless -f $self->{filename};
    bless $self, $class;
    return $self;
}

# Destructor

sub DESTROY {
    my $self=shift;
    if (exists $self->{FH} and defined $self->{FH}) {
	$self->close;
    }
}

# File subs

sub open {
    my $self=shift;
    my $mode= shift;
    if (defined $mode and $mode =~ /w/i) {
	$mode=O_RDWR;    # read/write mode
    } else {
	$mode=O_RDONLY;  # read only mode
    }
    unless (exists $self->{FH}) {
	local *FH;
	if (sysopen (FH, $self->{filename}, $mode)) {
	    $self->{FH} = *FH;
	    binmode $self->{FH};
	} else {
	    warn "Open $self->{filename} failed: $!\n";
	}
    }
    return exists $self->{FH};
}


sub close {
    my $self=shift;
    if (exists $self->{FH}) {
	close $self->{FH};
	delete $self->{FH};
    }
}

sub write {
    my ($self, $data) = @_;
    if (exists $self->{FH}) {
	print {$self->{FH}} $data;
    }
}

sub truncate {
    my ($self, $length) = @_;
    if ($length<0) {
	my @stat = stat $self->{FH};
	$length = $stat[7] + $length;
    }
    if (exists $self->{FH}) {
	truncate $self->{FH}, $length;
    }
}

sub seek {
    my ($self, $pos, $whence)=@_;
    $self->open unless exists $self->{FH};
    seek $self->{FH}, $pos, $whence;
}

sub tell {
    my ($self, $pos, $whence)=@_;
    return undef unless exists $self->{FH};
    return tell $self->{FH};
}

sub read {
    my ($self, $buf_, $length) = @_;
    $self->open unless exists $self->{FH};
    return read $self->{FH}, $$buf_, $length;
}

sub is_open {
    return exists shift->{FH};
}

# keep the old name
*isOpen = \&is_open;

# use filename to determine information about song/artist/album

=pod

=item read_filename()

  ($song, $artist, $no, $album) = $mp3->read_filename($what, $filename);

read_filename() tries to extract information about artist, song, song number
and album from the filename.

This is likely to fail for a lot of filenames, especially the album will
be often wrongly guessed, as the name of the parent directory is taken as
album name.

$what and $filename are optional. $what maybe song, track, artist or album.
If $what is defined read_filename will return only this element.

If $filename is defined this filename will be used and not the real filename
which was set by L<MP3::Tag> with C<MP3::Tag->new($filename)>.

Following formats will be hopefully recognized:

- album name/artist name - song name.mp3

- album_name/artist_name-song_name.mp3

- album.name/artist.name_song.name.mp3

- album name/(artist name) song name.mp3

- album name/01. artist name - song name.mp3

- album name/artist name - 01 - song.name.mp3

=cut

sub read_filename {
    my ($self,$what,$filename) = @_;
    my $pathandfile=$filename || $self->{filename};
    
    # prepare pathandfile for easier use
    $pathandfile =~ s/\.mp3$//; # remove .mp3-extension
    $pathandfile =~ s/ +/ /g; # replace several spaces by one space
    
    # split pathandfile in path and file
    my $file = $pathandfile;
    $file =~ s/.*\\//; # for windows-filenames
    $file =~ s/.*\///; # for unix-filenames
    my $path = substr $pathandfile,0,length($pathandfile)-length($file);
    chop $path;
    $path =~ s/.*\\//; # for windows-filenames
    $path =~ s/.*\///; # for unix-filenames

    # check wich chars are used for seperating words
    #   assumption: spaces between words
    
    unless ($file =~/ /) {
	# no spaces used, find word seperator
	my $Ndot = $file =~ tr/././;
	my $Nunderscore = $file =~ tr/_/_/;
	my $Ndash = $file =~ tr/-/-/;
	if (($Ndot>$Nunderscore) && ($Ndot>1)) {
	    $file =~ s/\./ /g;
	}
	elsif ($Nunderscore > 1) {
	    $file =~ s/_/ /g;
	}
	elsif ($Ndash>2) {
	    $file =~ s/-/ /g;
	}
    }

    # check wich chars are used for seperating parts
    #   assumption: " - " is used
    
    my $partsep = " - ";
    
    unless ($file =~ / - /) {
	if ($file =~ /-/) {
	    $partsep = "-";
	} elsif ($file =~ /^\(.*\)/) {
	    # replace brackets by -
	    $file =~ s/^\((.*?)\)/$1 - /;
	    $file =~ s/ +/ /;
	    $partsep = " - ";
	} elsif ($file =~ /_/) {
	    $partsep = "_";
	} else {
	    $partsep = "DoesNotExist";
	}
    }

    # get parts of name
    my ($song, $artist, $no, $album)=("","","","");

    # try to find a track-number in front of filename
    if ($file =~ /^ *(\d+)\W/) {
	$no=$1;                 # store number
	$file =~ s/^ *\d+//; # and delete it
	$file =~ s/^$partsep// || $file =~ s/^.//;
	$file =~ s/^ +//;
    }

    $file =~ s/_+/ /g unless $partsep =~ /_/; #remove underscore unless they are needed for part seperation
    my @parts = split /$partsep/, $file;
    if ($#parts==0) {
	$song=$parts[0];
    } elsif ($#parts==1) {
	$artist=$parts[0];
	$song=$parts[1];
    } elsif ($#parts>1) {
	my $temp = "";
	$artist = shift @parts;
	foreach (@parts) {
	    if (/^ *(\d+)\.? *$/) {
		$artist.= $partsep . $temp if $temp;
		$temp="";
		$no=$1;
	    } else {
		$temp .= $partsep if $temp;
		$temp .= $_;
	    }
	}
	$song=$temp;
    }
    
    $song =~ s/ +$//;
    $artist =~ s/ +$//;
    $no =~ s/ +$//;
    $no =~ s/^0+//;
    
    if ($path) {
	unless ($artist) {
	    $artist = $path;
	} else {
	    $album = $path;
	}
    }
    
    if (defined $what) {
	return $album if $what =~/^al/i;
	return $artist if $what =~/^a/i;
	return $no if $what =~/^t/i;
	return $song;
    }
    
    if (wantarray) {
	return ($song, $artist, $no, $album);
    }
    
    return {artist=>$artist, song=>$song, no=>$no, album=>$album};
}


=pod

=item song()

 $song = $mp3->song($filename);

Returns the song name, guessed from the filename. See also read_filename()

$filename is optional and will be used instead of the real filename if defined.

=cut

sub song {
    return read_filename(shift, "song", shift);
}

=pod

=item artist()

 $artist = $mp3->artist($filename);

Returns the artist name, guessed from the filename. See also read_filename()

$filename is optional and will be used instead of the real filename if defined.

=cut

sub artist {
    return read_filename(shift, "artist", shift);
}

=pod

=item track()

 $track = $mp3->track($filename);

Returns the track number, guessed from the filename. See also read_filename()

$filename is optional and will be used instead of the real filename if defined.

=cut

sub track {
    return read_filename(shift, "track", shift);
}

=pod

=item album()

 $album = $mp3->artist($album);

Returns the album name, guessed from the filename. See also read_filename()
The album name is guessed from the parent directory, so it is very likely to fail.

$filename is optional and will be used instead of the real filename if defined.

=cut

sub album {
    return read_filename(shift, "album", shift);
}

1;
