package Slim::Web::Template::NoWeb;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use FileHandle ();
use File::Spec::Functions qw(catdir);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Strings;

my $log = logger('network.http');
my $prefs = preferences('server');
my $absolutePathRegex = main::ISWINDOWS ? qr{^(?:/|[a-z]:)}i :  qr{^/};


sub new {
	my $class = shift;

	my $self = {
		templateDirs => [],
	};

	bless $self, $class;
	
	push @{ $self->{templateDirs} }, Slim::Utils::OSDetect::dirsFor('HTML');
	
	return $self;
}

sub addTemplateDirectory {
	my ($class, $dir) = @_;

	main::INFOLOG && $log->is_info && $log->info("Adding template directory $dir");

	# reset cache
	delete $class->{skinDirs};
	
	push @{ $class->{templateDirs} }, $dir if ( not grep({$_ eq $dir} @{ $class->{templateDirs} } ));
}

sub isaSkin {
	my $class = shift;
	my $name  = uc shift;

	return $name =~ /^(?:DEFAULT|EN)$/;
}

sub _generateContentFromFile {
	my ($class, $type, $path, $params) = @_;

	my $skin = $params->{'skinOverride'} || $prefs->get('skin');

	$params->{'thumbSize'} = $prefs->get('thumbSize') unless defined $params->{'thumbSize'};
	$params->{'systemSkin'} = $skin;
	$params->{'systemLanguage'} = $prefs->get('language');
	$params->{'allLinks'} = $prefs->get('additionalPlaylistButtons');

	main::INFOLOG && $log->is_info && $log->info("generating from $path with type: $type");
	
	if ($type eq 'fill') {

		return $class->_fillTemplate($params, $path, $skin);
	}

	my ($content, $mtime, $inode, $size) = $class->_getFileContent(
		$path,
		$skin,
		1,
		$type eq 'mtime' ? 1 : 0,
		$params->{contentAsFh},
	);

	if ($type eq 'mtime') {

		return ($mtime, $inode, $size);
	}

	# some callers want the mtime for last-modified
	if (wantarray()) {
		return ($content, $mtime, $inode, $size);
	} else {
		return $content;
	}
}

sub _fillTemplate {}

# Retrieves the file specified as $path, relative to the 
# INCLUDE_PATH of the given skin.
# Uses binmode to read file if $binary is specified.
# Returns a reference to the file data.

sub _getFileContent {
	my ($class, $path, $skin, $binary, $statOnly, $contentAsFh) = @_;

	my ($content, $template, $mtime, $inode, $size);

	if ( $path !~ $absolutePathRegex  ) {
		# Fixup relative paths according to skin
		$path = $class->fixHttpPath($skin, $path) || return;
	}

	main::INFOLOG && $log->is_info && $log->info("Reading http file for ($path)");
	
	if ( $statOnly ) {
		($inode, $size, $mtime) = (stat($path))[1,7,9];
		return (\$content, $mtime, $inode, $size);
	}
	
	if ( $contentAsFh ) {
		my $fh = FileHandle->new($path);
		binmode $fh if $binary;
		return $fh;
	}

	open($template, $path);

	if ($template) {
		($inode, $size, $mtime) = (stat($template))[1,7,9];
		
		local $/ = undef;
		binmode($template) if $binary;
		$content = <$template>;
		close $template;

		if (!length($content) && $log->is_debug) {

			main::DEBUGLOG && $log->debug("File empty: $path");
		}

	} else {

		logError("Couldn't open: $path");
	}
	
	return (\$content, $mtime, $inode, $size);
}


# Finds the first occurance of a file specified by $path in the
# list of directories in the INCLUDE_PATH of the specified $skin

sub fixHttpPath {
	my ($class, $skin, $path) = @_;

	my $skindirs = $class->_getSkinDirs($skin);

	my $lang = lc($prefs->get('language'));

	for my $dir (@{$skindirs}) {

		my $fullpath = catdir($dir, $path);

		# We can have $file.$language files that need to be processed.
		my $langpath = join('.', $fullpath, $lang);
		my $found    = '';

		if ($lang ne 'en' && -f $langpath) {

			$found = $langpath;

		} elsif (-r $fullpath) {

			$found = $fullpath;
		}

		# bug 17841 - don't allow directory traversal, ignore requests to files outside the HTML base directories
		if ($found && $found =~ /\.\./) {
			# we probably don't use Cwd anywhere else
			require Cwd;
			$found = Cwd::abs_path($found);
			
			# reset path if it's outside the skin path ($dir)
			if ($found !~ m|^$dir|) {
				$found = '';
			}
		}

		if ($found) {

			main::INFOLOG && $log->is_info && $log->info("Found path $found");

			return $found;
		}
	} 

	main::INFOLOG && $log->is_info && $log->info("Couldn't find path: $path");

	return undef;
}

sub _getSkinDirs {
	my ($class) = @_;
	
	return $class->{skinDirs} if $class->{skinDirs};
	
	my @dirs = ();
	foreach my $skin ('Default', 'EN') {
		foreach ( @{ $class->{templateDirs} } ) {
			push @dirs, catdir($_, $skin);
		}
	}

	$class->{skinDirs} = \@dirs;

	return $class->{skinDirs};
}

=head2 detectBrowser ( )

Attempts to figure out what the browser is by user-agent string identification

=cut

sub detectBrowser {
	return 'unknown';
}


1;