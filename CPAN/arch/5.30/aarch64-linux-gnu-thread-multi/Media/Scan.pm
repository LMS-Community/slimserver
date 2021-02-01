package Media::Scan;

use strict;
use base qw(Exporter);

use Media::Scan::Audio;
use Media::Scan::Image;
use Media::Scan::Error;
use Media::Scan::Progress;
use Media::Scan::Video;

# Log levels
use constant MS_LOG_ERR    => 1;
use constant MS_LOG_WARN   => 2;
use constant MS_LOG_INFO   => 3;
use constant MS_LOG_DEBUG  => 4;
use constant MS_LOG_MEMORY => 9;

# Flags
use constant MS_USE_EXTENSION   => 1;
use constant MS_FULL_SCAN       => 1 << 1;
use constant MS_RESCAN          => 1 << 2;
use constant MS_INCLUDE_DELETED => 1 << 3;
use constant MS_WATCH_CHANGES   => 1 << 4;
use constant MS_CLEARDB         => 1 << 5;

our $VERSION = '0.01';

our @EXPORT = qw(
    MS_LOG_ERR MS_LOG_WARN MS_LOG_INFO MS_LOG_DEBUG MS_LOG_MEMORY
    MS_USE_EXTENSION MS_FULL_SCAN MS_RESCAN MS_INCLUDE_DELETED
    MS_WATCH_CHANGES MS_CLEARDB
);

require XSLoader;
XSLoader::load('Media::Scan', $VERSION);

=head2 new( \@paths, \%options )

Create a new Media::Scan instance and begin scanning.

paths may be a single scalar path, or an array reference with multiple paths.

options include:

=over 4

=item loglevel (default: MS_LOG_ERR)

One of the following levels:

    MS_LOG_ERR
    MS_LOG_WARN
    MS_LOG_INFO
    MS_LOG_DEBUG
    MS_LOG_MEMORY

=item async (default: 0)

If set to 1, all scanning is performed in a background thread, and the call to new() will
return immediately. Make sure to keep a reference to the Media::Scan object, or
the scan will be aborted at DESTROY-time.

=item cachedir (default: current dir)

An optional path for libmediascan to store some cache files.

=item flags (default: MS_USE_EXTENSION | MS_FULL_SCAN)

An OR'ed list of flags, the possible flags are:

    MS_USE_EXTENSION   - Use a file's extension to determine how to scan it.
    MS_FULL_SCAN       - Perform a full scan on every file.
    MS_RESCAN          - Only scan files that are new or have changed since the last scan.
    MS_INCLUDE_DELETED - The result callback will be called for files that have been deleted
                         since the last scan.
    MS_WATCH_CHANGES   - Continue watching for changes after the scan has completed.
    MS_CLEARDB         - Wipe the internal libmediascan database before scanning.

=item ignore (default: none)

An array reference of file extensions that should be skipped. You may also specify 3 special types:

    AUDIO - Ignore all audio files.
    IMAGE - Ignore all image files.
    VIDEO - Ignore all video files.

=item ignore_dirs (default: none)

An array reference of directory substrings that should be skipped, for example the iTunes container
directories ".ite" and ".itlp" or the Windows directory "RECYCLER". The substrings are case-sensitive.

=item thumbnails (default: none)

An arrayref of hashes with one or more thumbnail specifications. Thumbnails are created during the
scanning process and are available within the result callback.

The format of a thumbnail spec is:

    { format => 'AUTO', # or JPEG or PNG
      width => 100,
      height => 100,
      keep_aspect => 1,
      bgcolor => 0xffffff,
      quality => 90,
    }

Most values are optional, however at least width or height must be specified.

=item on_result

A callback that will be called for each scanned file. The function will be passed
a L<Media::Scan::Audio>, L<Media::Scan::Video>, or L<Media::Scan::Image> depending on the
file type. This callback is required.

=item on_error

An callback that will be called when a scanning error occurs. It is passed a
L<Media::Scan::Error>.

=item on_progress

An optional callback that will be passed a L<Media::Scan::Progress> at regular intervals
during scanning.

=item on_finish

An optional callback that is called when scanning has finished. Nothing is currently passed
to this callback, eventually a scanning summary and overall stats might be included here.

=cut

sub new {
    my ( $class, $paths, $opts ) = @_;
    
    if ( ref $paths ne 'ARRAY' ) {
        $paths = [ $paths ];
    }
    
    $opts->{loglevel}    ||= MS_LOG_ERR;
    $opts->{async}       ||= 0;
    $opts->{flags}       ||= MS_USE_EXTENSION | MS_FULL_SCAN;
    $opts->{paths}         = $paths;
    $opts->{ignore}      ||= [];
    $opts->{ignore_dirs} ||= [];
    $opts->{thumbnails}  ||= [];
    
    if ( ref $opts->{ignore} ne 'ARRAY' ) {
        die "ignore must be an array reference";
    }
    
    my $self = bless $opts, $class;
    
    $self->xs_new();
    
    $self->xs_scan();
    
    return $self;
}

1;