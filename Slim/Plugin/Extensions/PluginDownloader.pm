package Slim::Plugin::Extensions::PluginDownloader;

# Package to download and extract zip files containing plugins
# Plugins are downloaded to <cachedir>/DownloadedPlugins and then extracted to <cachedir>/InstalledPlugins/Plugins/
#
# Plugins zip files should not include any additional path information - i.e. they include the install.xml file at the top level
# The plugin 'name' must match the package naming of the plugin, i.e. name 'MyPlugin' equates to package 'Plugins::MyPlugin::Plugin'

use strict;

use File::Spec::Functions qw(:ALL);
use File::Path;
use Archive::Zip qw(:ERROR_CODES);
use Digest::SHA1;

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Prefs;
use Slim::Utils::Log;

my $log = logger('plugin.extensions');

my $downloadTo;
my $extractTo;

my $status = {}; # store the status of all tasks in progress and completed by name

sub init {
	my $class = shift;

	if (my $cache = preferences('server')->get('cachedir')) {

		$downloadTo = catdir($cache, 'DownloadedPlugins');
		$extractTo  = catdir($cache, 'InstalledPlugins');

		mkdir $downloadTo unless -d $downloadTo;
		mkdir $extractTo  unless -d $extractTo;

		if (-w $downloadTo && -w $extractTo) {

			$log->debug("downloading to $downloadTo");
			$log->debug("extracting to $extractTo");

		} else {

			$log->warn("unable to create download locations $downloadTo $extractTo");
		}
	}
}

sub status {
	return $status;
}

sub remove {
	my $class = shift;
	my $args  = shift;

	my $name = $args->{'name'};

	my $dir = catdir($extractTo, 'Plugins', $name);

	if (-d $dir) {

		$log->info("removing $name from $dir");

		rmtree $dir;

	} else {

		$log->warn("trying to remove $name from non existant dir $dir");
	}

	$status->{$name} = { status => 'removed', title => $args->{'title'}, version => $args->{'version'} };
}

sub download {
	my $class = shift;
	my $args  = shift;

	my $name = $args->{'name'};
	my $url  = $args->{'url'} || '';

	my $file = catdir($downloadTo, "$name.zip");

	unlink $file;

	my $http = Slim::Networking::SimpleAsyncHTTP->new( \&_downloadDone, \&_downloadError, { saveAs => $file, args => $args } );
	
	$log->info("downloading $name from $url");

	$status->{$name} = { status => 'downloading', version => $args->{'version'}, title => $args->{'title'} };
	
	$http->get($url);
}

sub _downloadDone {
	my $http  = shift;

	my $file  = $http->params('saveAs');
	my $args  = $http->params('args');

	my $name  = $args->{'name'};
	my $digest= $args->{'digest'};
	my $cb    = $args->{'cb'};
	my $pt    = $args->{'pt'};
	my $url   = $http->url;

	$log->info("downloaded $name to $file");

	if (-r $file) {

		my $sha1 = Digest::SHA1->new;
		
		open my $fh, $file;
		
		$sha1->addfile($fh);
		
		close $fh;
		
		if ($digest ne $sha1->hexdigest) {
			
			$log->warn("digest does not match $file - $name will not be installed");

			$status->{$name}->{'status'} = 'bad_digest';
			
			unlink $file;
			
		} else {

			$log->info("digest matches - extracting $name");

			my $zip = Archive::Zip->new();

			# While we do this in a plugin, we extract the zip at download time.
			# Later this may be moved into PluginManager to do at startup time
			# this will cater for the case where an existing file may be in use at this time.

			if (my $zipstatus = $zip->read($file)) {

				$log->warn("error reading zip file $file status: $zipstatus");

				$status->{$name}->{'status'} = 'bad_zip';

			} else {
				
				my $dest = catdir($extractTo, 'Plugins', $name);

				if (-r $dest) {

					rmtree $dest;
				}

				if ( ($zipstatus = $zip->extractTree(undef, "$dest/")) == AZ_OK ) {
					
					$log->info("extracted $name to $dest");

					$status->{$name}->{'status'} = 'extracted';

				} else {

					$log->warn("failed to extract $name to $dest - $zipstatus");

					$status->{$name}->{'status'} = 'bad_extraction';

					rmtree $dest;
				}
			}
		}

		unlink $file;
	}

	$cb->( @$pt );
}

sub _downloadError {
	my $http  = shift;
	my $error = shift;

	my $args  = $http->params('args');
	my $name  = $args->{'name'};
	my $cb    = $args->{'cb'};
	my $pt    = $args->{'pt'};
	my $url   = $http->url;

	$log->warn("unable to download $name from $url - $error");

	$status->{$name}->{'status'} = 'bad_download';

	$cb->( @$pt );
}

1;
