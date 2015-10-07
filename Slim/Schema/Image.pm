package Slim::Schema::Image;

use strict;

use File::Basename;
use Date::Parse qw(str2time);
use Slim::Schema;
use Slim::Formats::XML;
use Slim::Utils::Misc;

# XXX DBIx::Class stuff needed?

my %orientation = (
	'top-left' =>     0,
	'top-right' =>    1,
	'bottom-right' => 2,
	'bottom-left' =>  3,
	'left-top' =>     4,
	'right-top' =>    5,
	'right-bottom' => 6,
	'left-bottom' =>  7,
);

sub updateOrCreateFromResult {
	my ( $class, $result ) = @_;
	
	my $url = Slim::Utils::Misc::fileURLFromPath($result->path);
	
	my $exifData = $result->tags;

	# Create title and album from path (if not in EXIF data)
	my $title = Slim::Formats::XML::trim($exifData->{XPTitle});
		# XXX - ImageDescription was abused by older digicams to store their name
		# using this would result in endless lists of images called "MEDION DIGITAL CAMERA" etc.
		#|| Slim::Formats::XML::trim($exifData->{ImageDescription});
		
	my ($filename, $dirs, undef) = fileparse($result->path);
	$title ||= $filename;
	
	# Album is parent directory
	$dirs =~ s{\\}{/}g;
	my ($album) = $dirs =~ m{([^/]+)/$};
	
	my $sort = Slim::Utils::Text::ignoreCaseArticles($title);
	my $search = Slim::Utils::Text::ignoreCase($title, 1);
	my $now = time();
	my $creationDate = str2time($exifData->{DateTimeOriginal}) || str2time($exifData->{DateTime}) || $result->mtime || 0;
	
	my $hash = {
		hash         => $result->hash,
		url          => $url,
		title        => $title,
		titlesearch  => $search,
		titlesort    => $sort,
		album        => $album,
		image_codec  => $result->codec,
		mime_type    => $result->mime_type,
		dlna_profile => $result->dlna_profile,
		width        => $result->width,
		height       => $result->height,
		mtime        => $result->mtime,
		added_time   => $now,
		updated_time => $now,
		original_time=> $creationDate,
		filesize     => $result->size,
		orientation  => $orientation{ lc($exifData->{Orientation} || '') } || 0,
	};
	
	return $class->updateOrCreateFromHash($hash);
}

sub updateOrCreateFromHash {
	my ( $class, $hash ) = @_;
	
	my $sth = Slim::Schema->dbh->prepare_cached('SELECT id FROM images WHERE url = ?');
	$sth->execute( $hash->{url} );
	my ($id) = $sth->fetchrow_array;
	$sth->finish;
	
	if ( !$id ) {
	    $id = Slim::Schema->_insertHash( images => $hash );
		$hash->{id} = $id;
	}
	else {
		$hash->{id} = $id;
		
		# Don't overwrite the original add time
		delete $hash->{added_time};
		
		Slim::Schema->_updateHash( images => $hash, 'id' );
	}
	
	return $hash;
}

sub findhash {
	my ( $class, $id ) = @_;
	
	my $sth = Slim::Schema->dbh->prepare_cached( qq{
		SELECT * FROM images WHERE hash = ?
	} );
	
	$sth->execute($id);
	my $hash = $sth->fetchrow_hashref;
	$sth->finish;
	
	return $hash || {};
}

1;

