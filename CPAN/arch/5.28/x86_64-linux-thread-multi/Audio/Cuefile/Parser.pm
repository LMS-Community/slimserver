package Audio::Cuefile::Parser;

=head1 NAME

Audio::Cuefile::Parser

=head1 VERSION

Version 0.02

=cut

our $VERSION = '0.02';

=head1 SYNOPSIS

Class to parse a cuefile and access the chewy, nougat centre. 
Returns Audio::Cuefile::Parser::Track objects.

=head1 USAGE

use Audio::Cuefile::Parser;

my $filename = 'filename.cue';

my $cue = Audio::Cuefile::Parser->new($filename);

my ($audio_file, $cd_performer, $cd_title) = 
  ($cue->file, $cue->performer, $cue->title);

foreach my $track ($cue->tracks) {

  my ($position, $index, $performer, $title) =
    ($track->position, $track->index, $track->performer, $track->title);

  print "$position $index $performer $title";
}

=cut

use warnings;
use strict;

use Carp          qw/croak/;
use Class::Struct qw/struct/;
use IO::File;

# Class specifications
BEGIN {
  struct 'Audio::Cuefile::Parser' => {
    cuedata   => '$',
    cuefile   => '$',
    file      => '$',
    performer => '$',
    title     => '$',
    _tracks   => '@',
  };

  struct 'Audio::Cuefile::Parser::Track' => {
    index     => '$',
    performer => '$',
    position  => '$',
    title     => '$',
  };
}

{
  # Over-ride Class::Struct's constructor so
  # we can install some custom subs
  no warnings 'redefine';

  sub new {
    my $class   = shift   or croak 'usage: '.__PACKAGE__.'->new($filename)';
    my $cuefile = shift   or croak 'no cue file specified';
    -e $cuefile           or croak "$cuefile does not exist";

    my $self = bless {}, $class;

    $self->cuefile($cuefile);

    $self->_loadcue;
    $self->_parse;

    return $self;
  }
}

# Load .cue file's contents into memory
sub _loadcue {
  my $self    = shift;
  my $cuefile = $self->cuefile;

  my $data =  join "",
              IO::File->new($cuefile, 'r')->getlines;

  $self->cuedata($data);
}

# Parse text and dispatch headers and data into
# their respective methods
sub _parse {
  my $self = shift;

  my $data = $self->cuedata or return;

  my ($header, $tracks) = (
    $data =~ m{
                \A                # start of string
                (.*?)             # capture all header text
                (^ \s* TRACK .*)  # capture all tracklist text
                \z                # end of string
              }xms
  );

  $self->_parse_header($header);
  $self->_parse_tracks($tracks);
}

# Process each <keyword> <value> pair and dispatch
# value to object mutator
sub _parse_header {
  my ($self, $header) = @_;

  $header or return;

  my @lines = split /\r*\n/, $header;


  LINE:
  foreach my $line (@lines) {
    _strip_spaces($line);

    $line =~ m/\S/ or next LINE;

    my ($keyword, $data) = (
      $line =~ m/ 
        \A          # anchor at string beginning
        (\w+)       # capture keyword (e.g. FILE, PERFORMER, TITLE)
        \s+ ['"]?   # optional quotes
        (.*?)       # capture all text as keyword's value  
        (?:         # non-capture cluster
          ['"]      # quote, followed by
          (?:       
            \s+     # spacing, followed by
            \w+     # word (e.g. MP3, WAVE)
          )?        # make cluster optional
        )?          
        \z          # anchor at line end
      /xms
    );

    ($keyword && $data) or next LINE;

    $keyword = lc $keyword;

    my %ISKEYWORD = map { $_ => 1 } qw/file performer title/;

    if ( $ISKEYWORD{$keyword} ) {
      # print "\$self->$keyword($data)\n";
      $self->$keyword($data);
    }
  }
}

# Walk through the track data, line by line,
# creating track objects and populating them
# as we go
sub _parse_tracks {
  my ($self, $tracks) = @_;

  $tracks or return;

  my @lines = split /\r*\n/, $tracks;

  my @tracks;

  foreach my $line (@lines) {
    _strip_spaces($line);

    # TRACK 01
    # TRACK 02 AUDIO
    $line =~ /\A TRACK \s+ (\d+) .* \z/xms
      and push @tracks, Audio::Cuefile::Parser::Track->new(position => $1);

    next unless @tracks;

    # TITLE Track Name
    # TITLE "Track Name"
    # TITLE 'Track Name'
    $line =~ /\A TITLE \s+ ['"]? (.*?) ['"]? \z/xms
      and $tracks[-1]->title($1);

    # PERFORMER Artist Name
    # PERFORMER "Artist Name"
    # PERFORMER 'Artist Name'
    $line =~ /\A PERFORMER \s+ ['"]? (.*?) ['"]? \z/xms
      and $tracks[-1]->performer($1);

    # INDEX 01 06:32:20
    $line =~ /\A INDEX \s+ (?: \d+ \s+) ([\d:]+) \z/xms
      and $tracks[-1]->index($1);
  }

  # Store them for safe keeping
  $self->_tracks(\@tracks);
}

sub tracks {
  @{ shift->_tracks };
}

# strip leading and trailing whitespace from input string
sub _strip_spaces {
  $_[0] =~ s/
  (?: 
    \A \s+
      |
    \s+ \z
  )
  //xms;
}

=head1 CUEFILE METHODS

=head2 $cue->tracks

Returns a list of Audio::Cuefile::Parser::Track objects.

=head2 $cue->file

Returns the filename associated with the FILE keyword from 
the .cue's headers (i.e. the audio file that the .cue file 
is describing).

=head2 $cue->performer

The audio file's performer.

=head2 $cue->title

The title of the audio file.

=head1 TRACK METHODS

=head2 $track->index

Timestamp that signifies the track's beginning.

=head2 $track->performer

The track's performer.

=head2 $track->position

The track's position in the audio file.

=head2 $track->title

Track title.

=cut

=head1 AUTHOR

Matt Koscica <matt.koscica@gmail.com>

=head1 BUGS

Probably a few, the regexes are very simple.

Please report any bugs or feature requests to
C<bug-audio-cuefile-parser@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Audio-Cuefile-Parser>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 COPYRIGHT & LICENSE

Copyright 2005-2010 Matt Koscica, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Audio::Cuefile::Parser
