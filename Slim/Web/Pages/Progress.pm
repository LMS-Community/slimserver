package Slim::Web::Pages::Progress;

use strict;

use Slim::Schema;

sub init {
	Slim::Web::HTTP::addPageFunction(qr/^progress\.(?:htm|xml)/,\&progress);
}

sub progress {
	my ($client, $params) = @_;

	my $args = {};

	$args->{'type'} = $params->{'type'} if $params->{'type'};
	$args->{'name'} = $params->{'name'} if $params->{'name'};
	$args->{'active'} = $params->{'active'} if $params->{'active'};

	my @progress = Slim::Schema->rs('Progress')->search( $args )->all;

	for my $p (@progress) {

		my $bar = '';

		for (my $i = 0; $i < $p->total; $i += $p->total / 25) {

			$params->{'cell_full'} = $i < $p->done;
			$bar .= ${Slim::Web::HTTP::filltemplatefile("hitlist_bar.html", $params)};
		}

		my $item = {
			'obj'  => $p,
			'bar'  => $bar,
			'time' => ($p->finish || time()) - $p->start,
		};

		push @{$params->{'progress_items'}}, $item;
	}

	$params->{'refresh'} = 5;

	# special message for importers once finished
	if ($params->{'type'} && $params->{'type'} eq 'importer' && !Slim::Music::Import->stillScanning) {

		$params->{'message'} = Slim::Utils::Strings::string('PROGRESS_IMPORTER_COMPLETE_DESC');

	}

	return Slim::Web::HTTP::filltemplatefile("progress.html", $params);
}

1;
