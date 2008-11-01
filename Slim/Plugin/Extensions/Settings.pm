package Slim::Plugin::Extensions::Settings;

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Digest::MD5;

my $prefs = preferences('plugin.extensions');
my $log   = logger('plugin.extensions');

$prefs->init({ 'repos' => [] });

my $rand = Digest::MD5->new->add( 'ExtensionDownloader', preferences('server')->get('securitySecret') )->hexdigest;

sub name {
	return Slim::Web::HTTP::protectName('PLUGIN_EXTENSIONS');
}

sub page {
	return Slim::Web::HTTP::protectURI('plugins/Extensions/settings/basic.html');
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	# Simplistic anti CSRF protection in case the main server protection is off
	if ($params->{'saveSettings'} && (!$params->{'rand'} || $params->{'rand'} ne $rand)) {

		$log->error("attempt to set params with band random number - ignoring");

		delete $params->{'saveSettings'};
	}

	if ($params->{'saveSettings'}) {

		# handle changes to repos immediately before we search repos

		my @new = grep { $_ =~ /^http:\/\/.*\.xml/ } (ref $params->{'repos'} eq 'ARRAY' ? @{$params->{'repos'}} : $params->{'repos'});

		my %current = map { $_ => 1 } @{ $prefs->get('repos') || [] };
		my %new     = map { $_ => 1 } @new;
		my $changed;

		for my $repo (keys %new) {
			if (!$current{$repo}) {
				$changed = 1;
				Slim::Plugin::Extensions::Plugin->addRepo($repo);
			}
		}
		for my $repo (keys %current) {
			if (!$new{$repo}) {
				$changed = 1;
				Slim::Plugin::Extensions::Plugin->removeRepo($repo);
			}
		}

		$prefs->set('repos', \@new) if $changed;
	}

	# get plugin info from defined repos

	Slim::Plugin::Extensions::Plugin->getPlugins( \&_gotPluginInfo, [ $class, $client, $params, $callback, \@args ] );
}

sub _gotPluginInfo {
	my ($class, $client, $params, $callback, $args, $plugins) = @_;

	if ($params->{'saveSettings'}) {

		# handle plugins for removal

		if (my $remove = $params->{'remove'}) {

			for my $remove ( ref $remove ? @$remove : ( $remove ) ) {

				my ($name, $version, $title) = $remove =~ /(.*):(.*):(.*)/;

				Slim::Plugin::Extensions::PluginDownloader->remove( { 
					name    => $name,
					title   => $title,
					version => $version,
				} );
			}
		}

		# handle plugins for installation

		my @install;

		if (my $install = $params->{'install'}) {

			for my $install ( ref $install ? @$install : ( $install ) ) {

				my ($name, $version) = $install =~ /(.*):(.*)/;

				my @match = grep { $name eq $_->{'name'} && $version eq $_->{'version'} } @$plugins;

				push @install, $match[0];
			}
		}

		my $downloads = { remaining => scalar @install };

		for my $plugin (@install) {
			
			Slim::Plugin::Extensions::PluginDownloader->download( {
				name    => $plugin->{'name'},
				title   => $plugin->{'title'},
				url     => $plugin->{'url'},
				version => $plugin->{'version'},
				digest  => $plugin->{'sha'},
				cb      => \&_downloadDone,
				pt      => [ $class, $client, $params, $callback, $args, $plugins, $downloads ]
			} );
		}

		return if @install; # wait for download(s) to complete page build
	}

	my $body = $class->_addInfo($client, $params, $plugins);

	$callback->( $client, $params, $body, @$args );
}

sub _downloadDone {
	my ($class, $client, $params, $callback, $args, $plugins, $downloads) = @_;

	# wait for all downloads to complete before returning the page
	if (--$downloads->{'remaining'}) {
		return;
	}

	my $body = $class->_addInfo($client, $params, $plugins);

	$callback->( $client, $params, $body, @$args );
}

sub _addInfo {
	my ($class, $client, $params, $plugins) = @_;

	my $status = Slim::Plugin::Extensions::PluginDownloader->status;

	my %installed; # plugins installed by downloader
	my %manual;    # plugins manually installed by other means

	for my $module (keys %{Slim::Utils::PluginManager->allPlugins}) {

		if ($module =~ /Plugins::(.*)::/) {

			my $name = $1;

			if (Slim::Utils::PluginManager->dataForPlugin($module)->{'basedir'} =~ /InstalledPlugins/) {

				$installed{$name} = $module;

			} else {

				$manual{$name} = 1;
			}
		}
	}

	my @upgrade;
	my @install;
	my @remove;

	for my $plugin (sort { $a->{'title'} cmp $b->{'title'} } @$plugins) {

		my $module = $installed{ $plugin->{'name'} };

		if ($status->{ $plugin->{'name'} }) {
			# plugin has already been installed/removed so remove from lists until restart
			next;
		}

		if ($manual{ $plugin->{'name'} }) {
			$log->info("ignoring plugin $plugin->{name} as it is already installed manually");
			next;
		}
		
		if ($module) {

			$plugin->{'current'} = Slim::Utils::PluginManager->dataForPlugin($module)->{'version'};

			if ($plugin->{'current'} ne $plugin->{'version'}) {

				push @upgrade, $plugin;
			}

		} else {

			push @install, $plugin;
		}
	}

	for my $plugin (keys %installed) {
		
		my $data = Slim::Utils::PluginManager->dataForPlugin($installed{$plugin});

		if (!$status->{ $plugin }) {

			push @remove, { name => $plugin, title => Slim::Utils::Strings::string($data->{'name'}), current => $data->{'version'} };
		}
	}

	my @repos = ( @{$prefs->get('repos')}, '' );

	$params->{'repos'}   = \@repos;
	$params->{'upgrade'} = \@upgrade;
	$params->{'install'} = \@install;
	$params->{'remove'}  = \@remove;
	$params->{'rand'}    = $rand;
	$params->{'warning'} = '';

	if (keys %$status) {

		my $warn = '';
		my $restart;

		for my $plugin (sort { $a->{'title'} cmp $b->{'title'} } (values %$status)) {

			$params->{'warning'} .= "$plugin->{title} (v$plugin->{version})  -  " . 
				                    Slim::Utils::Strings::string ('PLUGIN_EXTENSIONS_' . $plugin->{'status'} ) . "<p/>";

			$restart ||= ( $plugin->{'status'} =~ /extracted|removed|bad_extraction/ ? 1 : 0 );
		}

		if ($restart) {
			$params->{'warning'} .= Slim::Utils::Strings::string('PLUGIN_EXTENSIONS_RESTART_MSG');
		}
	}
	
	return $class->SUPER::handler($client, $params);
}

1;
