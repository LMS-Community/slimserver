package Media::Scan;

use strict;

use XS::Object::Magic;

use Media::Scan::Audio;
use Media::Scan::Image;
use Media::Scan::Error;
use Media::Scan::Progress;
use Media::Scan::Video;

our $VERSION = '0.01';

require XSLoader;
XSLoader::load('Media::Scan', $VERSION);

sub new {
    my ( $class, $paths, $opts ) = @_;
    
    if ( ref $paths ne 'ARRAY' ) {
        $paths = [ $paths ];
    }
    
    $opts->{loglevel} ||= 0;
    $opts->{async}  ||= 0;
    $opts->{paths}  = $paths;
    $opts->{ignore} ||= [];
    
    if ( ref $opts->{ignore} ne 'ARRAY' ) {
        die "ignore must be an array reference";
    }
    
    my $self = bless $opts, $class;
    
    $self->xs_new();
    
    $self->xs_scan();
    
    return $self;
}

1;