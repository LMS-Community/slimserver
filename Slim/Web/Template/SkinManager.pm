package Slim::Web::Template::SkinManager;

# $Id: $

# Squeezebox Server Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use base qw(Slim::Web::Template::NoWeb); 

use strict;
use File::Spec::Functions qw(:ALL);
use Template;
use URI::Escape;
use YAML::Syck qw(LoadFile);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Strings;
use Slim::Utils::Unicode;

BEGIN {
	# Use our custom Template::Context subclass
	$Template::Config::CONTEXT = 'Slim::Web::Template::Context';
}

use constant baseSkin => 'EN';

my $log = logger('network.http');
my $prefs = preferences('server');
my $absolutePathRegex = main::ISWINDOWS ? qr{^(?:/|[a-z]:)}i :  qr{^/};


sub new {
	my $class = shift;

	Slim::bootstrap::tryModuleLoad('Template::Stash::XS');

	if ($@) {

		# Pure perl is the default, so we don't need to do anything.
		$log->warn("Couldn't find Template::Stash::XS - falling back to pure perl version.");

	} else {

		main::INFOLOG && $log->info("Found Template::Stash::XS!");

		$Template::Config::STASH = 'Template::Stash::XS';
	}

	my $self = {
		skinTemplates => {},
		templateDirs => [],
	};

	bless $self, $class;
	
	push @{ $self->{templateDirs} }, Slim::Utils::OSDetect::dirsFor('HTML');
	
	my %skins = $self->skins();
	$self->{skins} = \%skins;
	
	return $self;
}

sub isaSkin {
	my $class = shift;
	my $name  = uc shift;

	# return from hash
	return $class->{skins}->{$name} if $class->{skins}->{$name};

	# otherwise reload skin hash and try again
	my %skins = $class->skins();
	$class->{skins} = \%skins;

	return $class->{skins}->{$name};
}

sub skins {
	my $class = shift;
	
	# create a hash of available skins - used for skin override and by settings page
	my $UI = shift; # return format for settings page rather than lookup cache for skins

	my %skinlist = ();

	for my $templatedir ($class->HTMLTemplateDirs()) {

		for my $dir (Slim::Utils::Misc::readDirectory($templatedir)) {

			# reject CVS, html, and .svn directories as skins
			next if $dir =~ /^(?:cvs|html|\.svn)$/i;
			next if $UI && $dir =~ /^x/;
			next if !-d catdir($templatedir, $dir);

			main::INFOLOG && $log->is_info && $log->info("skin entry: $dir");

			if ($UI) {
				
				$dir = Slim::Utils::Misc::unescape($dir);
				my $name = Slim::Utils::Strings::getString( uc($dir) . '_SKIN' );
				
				$skinlist{ $UI ? $dir : uc $dir } = ($name eq uc($dir) . '_SKIN') ? $dir : $name;
			}
			
			else {
				
				$skinlist{ uc $dir } = $dir;
			}
		}
	}

	return %skinlist;
}

sub HTMLTemplateDirs {
	my $class = shift;
	return @{ $class->{templateDirs} };
}

sub addSkinTemplate {
	my ($class, $skin) = @_;

	my @include_path = ();
	my @skinParents  = ();
	my @preprocess   = qw(hreftemplate cmdwrappers);
	my $skinSettings = '';
	
	for my $rootDir ($class->HTMLTemplateDirs()) {

		my $skinConfig = catfile($rootDir, $skin, 'skinconfig.yml');

		if (-r $skinConfig) {

			$skinSettings = eval { LoadFile($skinConfig) };

			if ($@) {
				logError("Could not load skin configuration file: $skinConfig\n$!");
			}

			last;
		}
	}

	if (ref($skinSettings) eq 'HASH') {

		for my $skinParent (@{$skinSettings->{'skinparents'}}) {
			if (my $checkedSkin = $class->isaSkin($skinParent)) {

				next if $checkedSkin eq $skin;
				next if $checkedSkin eq baseSkin;

				push @skinParents, $checkedSkin;
			}
		}
	}

	my %saw;
	my @dirs = ($skin, @skinParents, baseSkin);
	foreach my $dir (grep(!$saw{$_}++, @dirs)) {

		foreach my $rootDir ($class->HTMLTemplateDirs()) {

			my $skinDir = catdir($rootDir, $dir);

			if (-d $skinDir) {
				push @include_path, $skinDir;
			}
		}
	}
	
	if (ref($skinSettings) eq 'HASH' && ref $skinSettings->{'preprocess'} eq "ARRAY") {

		for my $checkfile (@{$skinSettings->{'preprocess'}}) {

			my $found = 0;

			DIRS: for my $checkdir (@include_path) {

				if (-r catfile($checkdir,$checkfile)) {

					push @preprocess, $checkfile;

					$found = 1;

					last DIRS;
				}
			}

			if (!$found) {
				$log->warn("$checkfile not found in include path, skipping");
			}
		}
	}

	$class->{skinTemplates}->{$skin} = Template->new({

		INCLUDE_PATH => \@include_path,
		COMPILE_DIR => $class->templateCacheDir(),
		PLUGIN_BASE => ['Slim::Plugin::TT',"HTML::$skin"],
		PRE_PROCESS => \@preprocess,
		FILTERS => {
			'string'     => [ sub {
				my ($context, @args) = @_;
				sub { Slim::Utils::Strings::string(shift, @args) }
			}, 1 ],
			'getstring'     => [ sub {
				my ($context, @args) = @_;
				sub { Slim::Utils::Strings::getString(shift, @args) }
			}, 1 ],
			'nbsp'          => \&_nonBreaking,
			'uri'           => \&URI::Escape::uri_escape_utf8,
			'unuri'         => \&URI::Escape::uri_unescape,
			'utf8decode'    => \&Slim::Utils::Unicode::utf8decode,
			'utf8encode'    => \&Slim::Utils::Unicode::utf8encode,
			'utf8on'        => \&Slim::Utils::Unicode::utf8on,
			'utf8off'       => \&Slim::Utils::Unicode::utf8off,
		},

		EVAL_PERL => 1,
		ABSOLUTE  => 1,
	});

	return $class->{skinTemplates}->{$skin};
}


sub _nonBreaking {
	my $string = shift;

	$string =~ s/\s/\&nbsp;/g;

	return $string;
}

sub _fillTemplate {
	my ($class, $params, $path, $skin) = @_;
	
	# Make sure we have a skin template for fixHttpPath to use.
	my $template = $class->{skinTemplates}->{$skin} || $class->addSkinTemplate($skin);

	my $output = '';

	$params->{'LOCALE'} = 'utf-8';

	$path = $class->fixHttpPath($skin, $path);

	if (!$template->process($path, $params, \$output)) {

		logError($template->error);
	}

	return \$output;
}

sub _getSkinDirs {
	my ($class, $skin) = @_;

	my $template = $class->{skinTemplates}->{$skin} || $class->addSkinTemplate($skin);
	return $template->context()->{'CONFIG'}->{'INCLUDE_PATH'};
}

sub templateCacheDir {
	return catdir( $prefs->get('cachedir'), 'templates' );
}


=head2 detectBrowser ( )

Attempts to figure out what the browser is by user-agent string identification

=cut

sub detectBrowser {
	my $class = shift;

	my $request = shift;
	my $return = 'unknown';
	
	return $return unless $request->header('user-agent');

	if ($request->header('user-agent') =~ /Firefox/) {
		$return = 'Firefox';
	} elsif ($request->header('user-agent') =~ /Opera/) {
		$return = 'Opera';
	} elsif ($request->header('user-agent') =~ /Safari/) {
		$return = 'Safari';
	} elsif ($request->header('user-agent') =~ /MSIE 7/) {
		$return = 'IE7';
	} elsif (
		$request->header('user-agent') =~ /MSIE/   && # does it think it's IE
        $request->header('user-agent') !~ /Opera/  && # make sure it's not Opera
        $request->header('user-agent') !~ /Linux/  && # make sure it's not Linux
        $request->header('user-agent') !~ /arm/)      # make sure it's not a Nokia tablet
	{
		$return = 'IE';
	}
	
	return $return;
}


1;