package Slim::Web::Pages::Progress;

use strict;

use Slim::Schema;

sub init {
	Slim::Web::HTTP::addPageFunction(qr/^progress\.(?:htm|xml)/,\&progress);
}

sub progress {
	my ($client, $params) = @_;

	my $barLen = $params->{'barlen'} || 40;

	my $args = {};

	$args->{'type'} = $params->{'type'} if $params->{'type'};

	my @progress = Slim::Schema->rs('Progress')->search( $args, { 'order_by' => 'start' } )->all;

	my $total_time = 0;

	for my $p (@progress) {

		my $bar = '';
		my $barInc = $p->total / $barLen;

		for (my $i = 0; $i < $barLen; $i++) {

			$params->{'cell_full'} = $i * $barInc < $p->done;
			$bar .= ${Slim::Web::HTTP::filltemplatefile("hitlist_bar.html", $params)};
		}

		my $runtime = ($p->finish || time()) - $p->start;
		
		my ($h0, $h1, $m0, $m1) = timeDigits($runtime);
		
		my $item = {
			'obj'  => $p,
			'bar'  => $bar,
			'time' => "$h0$h1:$m0$m1".sprintf(":%02s",($runtime % 60)),
		};

		$total_time += $runtime;

		push @{$params->{'progress_items'}}, $item;
	}

	$params->{'refresh'} = 5;

	# special message for importers once finished
	if ($params->{'type'} && $params->{'type'} eq 'importer' && !Slim::Music::Import->stillScanning) {

		$params->{'message'}    = Slim::Utils::Strings::string('PROGRESS_IMPORTER_COMPLETE_DESC');
		
		my ($h0, $h1, $m0, $m1) = timeDigits($total_time);
		$params->{'total_time'} = "$h0$h1:$m0$m1".sprintf(":%02s",($total_time % 60));

	}

	return Slim::Web::HTTP::filltemplatefile("progress.html", $params);
}

1;
