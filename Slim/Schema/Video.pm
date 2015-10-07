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
	
	# Create title and album from path
	my ($title, $dirs, undef) = fileparse($result->path);
	
	# Album is parent directory
	$dirs =~ s{\\}{/}g;
	my ($album) = $dirs =~ m{([^/]+)/$};
	
	# Use video title/album tags if available
	my $tags = $result->tags;
	$title = $tags->{title} if $tags->{title}; # these keys should always be lowercase from ffmpeg
	$album = $tags->{album} if $tags->{album};
	
	my $sort = Slim::Utils::Text::ignoreCaseArticles($title);
	my $search = Slim::Utils::Text::ignoreCase($title, 1);
	my $now = time();
	
	my $hash = {
		url          => $url,
		hash         => $result->hash,
		title        => $title,
		titlesearch  => $search,
		titlesort    => $sort,
		album        => $album,
		video_codec  => $result->codec,
		audio_codec  => 'TODO',
		mime_type    => $result->mime_type,
		dlna_profile => $result->dlna_profile,
		width        => $result->width,
		height       => $result->height,
		mtime        => $result->mtime,
		added_time   => $now,
		updated_time => $now,
		filesize     => $result->size,
		secs         => $result->duration_ms / 1000,
		bitrate      => $result->bitrate,
		channels     => 'TODO',
	};
	
	return $class->updateOrCreateFromHash($hash);
}

sub updateOrCreateFromHash {
	my ( $class, $hash ) = @_;
	
	my $sth = Slim::Schema->dbh->prepare_cached('SELECT id FROM videos WHERE url = ?');
	$sth->execute( $hash->{url} );
	my ($id) = $sth->fetchrow_array;
	$sth->finish;
	
	if ( !$id ) {
	    $id = Slim::Schema->_insertHash( videos => $hash );
		$hash->{id} = $id;
	}
	else {
		$hash->{id} = $id;
		
		# Don't overwrite the original add time
		delete $hash->{added_time};
		
		Slim::Schema->_updateHash( videos => $hash, 'id' );
	}
	
	return $hash;
}

sub findhash {
	my ( $class, $id ) = @_;
	
	my $sth = Slim::Schema->dbh->prepare_cached( qq{
		SELECT * FROM videos WHERE hash = ?
	} );
	
	$sth->execute($id);
	my $hash = $sth->fetchrow_hashref;
	$sth->finish;
	
	return $hash || {};
}

1;
