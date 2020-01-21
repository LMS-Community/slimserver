package Slim::Music::OnlineLibraryScan;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, version 2.

use strict;

use Slim::Utils::Log;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Scanner::Local;

use constant IS_SQLITE => (Slim::Utils::OSDetect->getOS()->sqlHelperClass() =~ /SQLite/ ? 1 : 0);

my $log = logger('scan.scanner');

sub init {
	my $class = shift;

	Slim::Music::Import->addImporter( $class, {
		type         => 'file',
		weight       => 10,
		use          => 1,
		onlineLibraryOnly => 1,
	} );
}

sub startScan {
	my $class = shift;

	my $dbh = Slim::Schema->dbh;

	my $inOnlineLibrarySQL = qq{
		SELECT DISTINCT(url)
		FROM            tracks
		WHERE           url NOT LIKE 'file://%'
		AND             extid IS NOT NULL
	} . (IS_SQLITE ? '' : ' ORDER BY url');

	$log->error("Get online tracks count") unless main::SCANNER && $main::progress;
	# only remove missing tracks when looking for audio tracks
	my $inOnlineLibraryCount = 0;
	($inOnlineLibraryCount) = $dbh->selectrow_array( qq{
		SELECT COUNT(*) FROM ( $inOnlineLibrarySQL ) AS t1
	} ) if !(main::SCANNER && $main::wipe);

	my $changes = 0;
	my $paths;

	Slim::Utils::Scanner::Local->deleteTracks($dbh, \$changes, \$paths, '', {
		name  => 'online music library tracks',
		count => $inOnlineLibraryCount,
		progressName => 'online_library_deleted',
		sql   => $inOnlineLibrarySQL,
	}, {
		types    => 'audio',
		# scanName => 'directory',
		no_async => 1,
		progress => 1,
	});

	return $changes;
}

# Helper method for importer plugins to see whether they are enabled or not
sub isImportEnabled {
	my ($class, $importer) = @_;

	if ( main::SCANNER 
		? (preferences('plugin.state')->get('OnlineLibrary') || '') eq 'enabled' 
		: Slim::Utils::PluginManager->isEnabled('Slim::Plugin::OnlineLibrary::Plugin') 
	) {
		my $pluginData = Slim::Utils::PluginManager->dataForPlugin($importer);

		if ($pluginData && ref $pluginData && $pluginData->{name} && ($pluginData->{onlineLibrary} || '') eq 'true') {
			my $enabled = preferences('plugin.onlinelibrary')->get('enable_' . $pluginData->{name});
			return $enabled ? 1 : 0;
		}
	}

	return 1;
}

1;