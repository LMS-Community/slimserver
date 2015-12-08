package Slim::Schema::ResultSet::Contributor;

# $Id$

use strict;
use base qw(Slim::Schema::ResultSet::Base);

use Slim::Utils::Prefs;

sub searchColumn {
	my $self  = shift;

	return 'namesearch';
}

sub searchNames {
	my $self  = shift;
	my $terms = shift;
	my $attrs = shift || {};

	my @joins = ();
	my $cond  = {
		'me.namesearch' => { 'like' => $terms },
	};

	# Bug: 2479 - Don't include roles if the user has them unchecked.
	if (my $roles = Slim::Schema->artistOnlyRoles('TRACKARTIST')) {

		$cond->{'contributorAlbums.role'} = { 'in' => $roles };
		push @joins, 'contributorAlbums';
	}
	
	my $collate = Slim::Utils::OSDetect->getOS()->sqlHelperClass()->collate();

	$attrs->{'order_by'} ||= "me.namesort $collate";
	$attrs->{'distinct'} ||= 'me.id';
	$attrs->{'join'}     ||= \@joins;

	return $self->search($cond, $attrs);
}

sub countTotal {
	my $self = shift;

	my $prefs = preferences('server');

	my $cond  = {};
	my @joins = ();
	my $roles = $prefs->get('useUnifiedArtistsList') ? Slim::Schema->artistOnlyRoles : [ Slim::Schema::Contributor->contributorRoleIds ];

	# The user may not want to include all the composers / conductors
	if ($roles) {
		$cond->{'contributorAlbums.role'} = { 'in' => $roles };
	}

	if ($prefs->get('useUnifiedArtistsList') && $prefs->get('variousArtistAutoIdentification')) {

		$cond->{'album.compilation'} = [ { 'is' => undef }, { '=' => 0 } ];

		push @joins, { 'contributorAlbums' => 'album' };

	} elsif ($roles) {

		push @joins, 'contributorAlbums';
	}
	
	my $collate = Slim::Utils::OSDetect->getOS()->sqlHelperClass()->collate();

	return $self->search($cond, {
		'order_by' => "me.namesort $collate",
		'group_by' => 'me.id',
		'join'     => \@joins,
	})->count();
}

1;
