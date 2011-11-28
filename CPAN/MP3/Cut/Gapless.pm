package MP3::Cut::Gapless;

use strict;

our $VERSION = '0.03';

require XSLoader;
XSLoader::load('MP3::Cut::Gapless', $VERSION);

sub new {
    my ( $class, %args ) = @_;
    
    if ( !$args{file} && !$args{cue} ) {
        die "Either file or cue argument must be specified";
    }
    
    my $self = bless \%args, $class;
    
    if ( $self->{cue} ) {
        $self->_parse_cue;
    }
    
    if ( !-f $self->{file} ) {
        die "Invalid file: $self->{file}";
    }
    
    if ( $self->{cache_dir} ) {
        require Digest::MD5;
        require File::Spec;
        
        if ( !-d $self->{cache_dir} ) {
            require File::Path;
            File::Path::mkpath( $self->{cache_dir} );
        }
        
        # Cache key is filename + size + mtime so if the file changes
        # we will not read a stale cache file.
        my ($size, $mtime) = (stat $self->{file})[7, 9];
        $self->{cache_file} = File::Spec->catfile(
            $self->{cache_dir},
            Digest::MD5::md5_hex( $self->{file} . $size . $mtime ) . '.mllt'
        );
    }
    
    # Pre-scan the file for the range we will be cutting
    $self->_init;
    
    return $self;
}

sub tracks {
    my $self = shift;
    
    return @{ $self->{_tracks} || [] };
}

sub write {
    my ( $self, $track, $filename ) = @_;
    
    if ( !$filename ) {
        # Default filename is "position - performer - title.mp3"
        $filename = join(' - ', $track->{position}, $track->{performer}, $track->{title}) . '.mp3';
    }
    
    if ( -e $filename ) {
        warn "$filename already exists, will not overwrite\n";
        return;
    }
    
    # Reset XS counter for read()
    $self->__reset_read();
    
    delete $self->{start_ms};
    delete $self->{end_ms};
    
    $self->{start_ms} = $track->{start_ms};
    $self->{end_ms}   = $track->{end_ms} if $track->{end_ms};
    
    print "Writing $filename...\n";
    
    open my $fh, '>', $filename;
    while ( $self->read( my $buf, 65536 ) ) {
        syswrite $fh, $buf;
    }
    close $fh;
}

# read() is implemented in XS

sub _init {
    my $self = shift;
    
    open $self->{_fh}, '<', $self->{file} || die "Unable to open $self->{file} for reading";
    
    binmode $self->{_fh};
    
    # XS init
    $self->{_mp3c} = $self->__init(@_);
}

sub _parse_cue {
    my $self = shift;
    
    require Audio::Cuefile::Parser;
    require MP3::Cut::Gapless::Track;
    require File::Spec;
    
    my $cue = Audio::Cuefile::Parser->new( $self->{cue} );
    
    if ( !$self->{file} ) {
        $self->{file} = $cue->file || die "No FILE entry found in cue sheet";
        
        # Handle relative path
        my ($vol, $dirs, $file) = File::Spec->splitpath( $self->{file} );
        if ( $dirs !~ m{^[/\\]} ) {
            my ($cvol, $cdirs, undef) = File::Spec->splitpath( File::Spec->rel2abs( $self->{cue} ) );
            $self->{file} = File::Spec->rel2abs( $self->{file}, File::Spec->catdir($cvol, $cdirs) );
        }
    }
    
    $self->{_tracks} = [];
    for my $track ( $cue->tracks ) {
        push @{ $self->{_tracks} }, MP3::Cut::Gapless::Track->new($track);
    }
    
    # Set end_ms values, last track will fill to the end
    for ( my $i = 0; $i < scalar @{ $self->{_tracks} } - 1; $i++ ) {
        $self->{_tracks}->[$i]->{end_ms} = $self->{_tracks}->[$i + 1]->{start_ms};
    }
}

sub DESTROY {
    my $self = shift;
    
    close $self->{_fh};
    
    $self->__cleanup( $self->{_mp3c} ) if exists $self->{_mp3c};
}

1;
__END__

=head1 NAME

MP3::Cut::Gapless - Split an MP3 file without gaps (based on pcutmp3)

=head1 SYNOPSIS

    use MP3::Cut::Gapless;
    
    # Cut file using a cue sheet
    my $cut = MP3::Cut::Gapless->new(
        cue => 'file.cue'
    );
    for my $track ( $cut->tracks ) {
        $cut->write( $track );
    }
    
    # Or, cut at defined points and stream the rewritten file
    my $cut = MP3::Cut::Gapless->new(
        file      => 'long.mp3',
        cache_dir => '/var/cache/mp3cut',
        start_ms  => 15000,
        end_ms    => 30000,
    );
    open my $out, '>', '15-30.mp3';
    while ( $cut->read( my $buf, 4096 ) ) {
        syswrite $out, $buf;
    }
    close $out;

=head1 DESCRIPTION

This module performs sample-granular splitting of an MP3 file.  Most MP3 splitters only split
on frame boundaries which can leave gaps or noise between files due to MP3's bit reservoir.
This module, which is based on the Java pcutmp3 tool, rewrites the LAME tag and adjusts the
audio frames as necessary to make the split completely gapless when played with a compatible
decoder that supports LAME encoder delay and padding.

There are two main ways to use this module.

1. Using a cue sheet, you can split a large input file into a series of tracks.

2. Realtime transcoding can be performed by specifying an input file and a start/end time,
after which the rewritten MP3 can be streamed to an audio device.

=head1 METHODS

=head2 new( %args )

Arguments:

=over 4

    cue => $cue_sheet

Optional. Cue sheet to use to determine cut points.

    file => $file_to_cut

If not specified, the FILE entry from the cue will be used.

    start_ms => $start_time_in_milliseconds
    end_ms   => $end_time_in_milliseconds

Optional, can be used to manually define cut points.

    cache_dir => "/path/to/cache/dir"

Optional. When new() is called, a complete scan must be done of the
MP3 file to determine the number of frames and their locations. This 
can be somewhat time-consuming depending on the size of the file,
disk/network speed, and so on. A cache file can be created to avoid this
operation if the file needs to be cut a second time. This is most useful
when manually cutting a file several times.

=back

=head2 tracks()

Returns an array of L<MP3::Cut::Gapless::Track> objects. Only available if a cue sheet was used.

=head2 write( $track, [ $filename ] )

Write the given L<MP3::Cut::Gapless::Track> object to a file. If no filename is provided, the
default filename is "<position> - <performer> - <title>.mp3". If the file already exists, it
will not be overwritten.

=head2 read( $buf, $block_size_hint )

Reads a chunk of the rewritten MP3 file into $buf. Returns the number of bytes read.
Only complete MP3 frames are returned, so you may receive more or less data than $block_size_hint.

=head1 SEE ALSO

pcutmp3 originally by Sebastian Gesemann L<http://wiki.themixingbowl.org/Pcutmp3>

L<Audio::Scan>

=head1 AUTHOR

Andy Grundman, E<lt>andy@slimdevices.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 Logitech, Inc.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

=cut
