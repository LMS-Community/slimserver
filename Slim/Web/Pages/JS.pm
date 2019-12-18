package Slim::Web::Pages::JS;

# Logitech Media Server Copyright 2001-2018 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=pod
	Under some cercumstances we want to add JavaScript to the main JS files
	used in the main web UI. Those usually are handled without page handler.
	But in order for a plugin to be able to add its JS we need some more
	flexibility - given here.
=cut

use strict;

use Slim::Utils::Log;
use Slim::Web::Pages;

my $log = logger('network.http');
my (%handlers);

sub addJSFunction {
	my ( $class, $jsFile, $customJSFile ) = @_;
	
	$jsFile = lc($jsFile || '');
	$jsFile =~ s/\.html$//;
	
	if ( $jsFile && $customJSFile && $jsFile =~ /^js-?(?:main|browse)$/ ) {
		if (!$handlers{$jsFile}) {
			Slim::Web::Pages->addPageFunction("js-main\.html", \&handler);
			$handlers{$jsFile} = [];
		}
		
		push @{$handlers{$jsFile}}, $customJSFile;
	}
	else {
		$log->warn("No or invalid JS template defined");
	}
}

sub handler {
	my ($client, $params, $callback, $httpClient, $response) = @_;
	
	my ($template) = $params->{path} =~ /(js.*?)\.html/;

	# let's render those templates to include them in the main JS file
	# unfortunately we can't easily do this from the template itself
	foreach ( @{$handlers{$template} || []} ) {
		my $handler = Slim::Web::Pages->getPageFunction($_);

		if ($handler) {
			$params->{additionalJS} ||= '';
			eval {
				$params->{additionalJS} .= ${$handler->(@_)};
			};
			
			$@ && $log->warn("Failed to render JS template: $@")
		}
	}

	Slim::Web::HTTP::filltemplatefile($params->{path}, $params);
}

1;