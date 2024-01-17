package Slim::Web::Template::SkinManager;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use base qw(Slim::Web::Template::NoWeb);

use strict;
use File::Slurp;
use File::Spec::Functions qw(:ALL);
use Digest::MD5 qw(md5_hex);
use Template;
use URI::Escape qw(uri_escape);
use YAML::XS;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Strings;
use Slim::Utils::Unicode;
use Slim::Web::ImageProxy;

BEGIN {
	# Use our custom Template::Context subclass
	$Template::Config::CONTEXT = 'Slim::Web::Template::Context';
	# Use Profiler instead if you want to investigate page rendering performance
#	$Template::Config::CONTEXT = 'Slim::Web::Template::Profiler';
	$Template::Provider::MAX_DIRS = 256;
	$Template::Directive::WHILE_MAX = 10000;
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

			$skinSettings = eval { YAML::XS::LoadFile($skinConfig) };

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
			'nbsp'              => \&_nonBreaking,
			'uri'               => \&URI::Escape::uri_escape_utf8,
			'unuri'             => \&URI::Escape::uri_unescape,
			'utf8decode'        => \&Slim::Utils::Unicode::utf8decode,
			'utf8decode_locale' => \&Slim::Utils::Unicode::utf8decode_locale,
			'utf8encode'        => \&Slim::Utils::Unicode::utf8encode,
			'utf8on'            => \&Slim::Utils::Unicode::utf8on,
			'utf8off'           => \&Slim::Utils::Unicode::utf8off,
			'parseURIs'         => \&_parseURIs,
			'resizeimage'       => [ \&_resizeImage, 1 ],
			'imageproxy'        => [ sub {
				return _resizeImage($_[0], $_[1], $_[2], '-');
			}, 1 ],
		},

		EVAL_PERL => 1,
		ABSOLUTE  => 1,

		# we usually don't change templates while running
		STAT_TTL  => main::NOBROWSECACHE ? 1 : 3600,
	});

	my $versionFile = catfile($class->templateCacheDir(), md5_hex("$::VERSION/$::REVISION"));
	if (-d $class->templateCacheDir() && !-f $versionFile) {
		unlink map { catdir($class->templateCacheDir(), $_) } File::Slurp::read_dir($class->templateCacheDir());
		write_file($versionFile, '');
	}

	return $class->{skinTemplates}->{$skin};
}

sub _nonBreaking {
	my $string = shift;

	$string =~ s/\s/\&nbsp;/g;

	return $string;
}

sub _parseURIs {
	my ($text) = @_;

	return $text unless $text;

	if (!($text =~ s!\b(https?://[A-Za-z0-9\-_\.\!~*'();/?:@&=+$,]+)!<a href=\"$1\" target=\"_blank\" class="link">$1</a>!igo)) {
		# handle emusic-type urls which don't have http://
		$text =~ s!\b(www\.[A-Za-z0-9\-_\.\!~*'();/?:@&=+$,]+)!<a href=\"http://$1\" target=\"_blank\">$1</a>!igo;
	}

	return $text;
}

sub _resizeImage {
	my ( $context, $width, $height, $mode, $prefix ) = @_;

	$height ||= '';
	$mode   ||= '';
	$prefix ||= '/';

	return sub {
		my $url = shift;

		# use local imageproxy to resize image (if enabled)
		$url = Slim::Web::ImageProxy::proxiedImage($url);

		my ($host) = Slim::Utils::Misc::crackURL($url);

		# don't use imageproxy on local network
		if ( $host && (Slim::Utils::Network::ip_is_private($host) || $host =~ /localhost/i) ) {
			return $url;
		}

		# $url comes with resizing parameters
		if ( $url =~ /_((?:[0-9X]+x[0-9X]+)(?:_\w)?(?:_[\da-fA-F]+)?(?:\.\w+)?)$/ ) {
			return $url;
		}

		# sometimes we'll need to prepend the webroot to our url
		$url = $prefix . $url unless $url =~ m{^/};

		# local url - use internal image resizer
		my $resizeParams = "_$width";
		$resizeParams .= "x$height" if $height;

		# music artwork
		my $webroot = $context->{STASH}->{webroot};
		if ( $url =~ m{^((?:$webroot|/)music/.*/cover)(?:\.jpg)?$} || $url =~ m{(.*imageproxy/.*/image)(?:\.(jpe?g|png|gif))} ) {
			return $1 . $resizeParams . (($mode && $mode ne '-') ? "_$mode" : '_o');
		}

		# special mode "-": don't resize local urls (some already come with resize parameters)
		if ($mode eq '-') {
			if ($url =~ m|/[a-z]+\.png$|) {
				$mode = '';
			}
			else {
				return $url;
			}
		}

		$resizeParams .= "_$mode" if $mode;

		$url =~ s/(\.png|\.gif|\.jpe?g|)$/$resizeParams$1/i;
		$url = '/' . $url unless $url =~ m{^(?:/|http)};

		return $url;
	};
}


my %empty;
sub _fillTemplate {
	my ($class, $params, $path, $skin) = @_;

	# Make sure we have a skin template for fixHttpPath to use.
	my $template = $class->{skinTemplates}->{$skin} || $class->addSkinTemplate($skin);

	my $output = '';

	$params->{'LOCALE'} = 'utf-8';

	$path = $class->fixHttpPath($skin, $path);

	return \'' if $empty{$path};

	if (!$template->process($path, $params, \$output)) {

		logError($template->error);
	}

	# don't re-read potentially empty files over and over again
	$empty{$path} = 1 if !$output && $path =~ /include\.html/;

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

1;
