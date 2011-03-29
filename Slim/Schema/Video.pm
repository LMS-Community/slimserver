package Slim::Schema::Video;

use strict;

use File::Basename;
use Slim::Schema;
use Slim::Utils::Misc;

# XXX DBIx::Class stuff needed?

sub updateOrCreateFromResult {
	my ( $class, $result ) = @_;
	
	my $id;
	my $url = Slim::Utils::Misc::fileURLFromPath($result->path);
	
	# Create title from path
	my $title = basename($result->path);
	$title =~ s/\.\w+$//;
	
	my $normalize = Slim::Utils::Text::ignoreCaseArticles($title);
	
	my $hash = {
		url          => $url,
		hash         => 0, # XXX $result->hash
		title        => $title,
		titlesearch  => $normalize,
		titlesort    => $normalize,
		video_codec  => $result->codec,
		audio_codec  => 'TODO',
		mime_type    => $result->mime_type || 'video/x-msvideo', # XXX lms must always provide this
		dlna_profile => $result->dlna_profile,
		width        => $result->width,
		height       => $result->height,
		mtime        => $result->mtime,
		added_time   => time(),
		filesize     => $result->size,
		secs         => $result->duration_ms / 1000,
		bitrate      => $result->bitrate,
		channels     => 'TODO',
	};
	
	my $sth = Slim::Schema->dbh->prepare_cached('SELECT id FROM videos WHERE url = ?');
	$sth->execute($url);
	($id) = $sth->fetchrow_array;
	$sth->finish;
	
	if ( !$id ) {
	    $id = Slim::Schema->_insertHash( videos => $hash );
	}
	else {
		$hash->{id} = $id;
		Slim::Schema->_updateHash( videos => $hash, 'id' );
	}
	
	return $id;
}

sub findhash {
	my ( $class, $id ) = @_;
	
	my $sth = Slim::Schema->dbh->prepare_cached( qq{
		SELECT * FROM videos WHERE id = ?
	} );
	
	$sth->execute($id);
	my $hash = $sth->fetchrow_hashref;
	$sth->finish;
	
	return $hash || {};
}

1;
