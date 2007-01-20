package Slim::Web::Pages::Progress;

use strict;

use Slim::Schema;

sub init {
	Slim::Web::HTTP::addPageFunction(qr/^progress\.(?:htm|xml)/,\&progress);
}

sub progress {
	my ($client, $params) = @_;

	my $total_time = 0;
	my $barLen = $params->{'barlen'} || 40;

	my $bar1 = ${Slim::Web::HTTP::filltemplatefile("hitlist_bar.html", { 'cell_full' => 1 })};
	my $bar0 = ${Slim::Web::HTTP::filltemplatefile("hitlist_bar.html", { 'cell_full' => 0 })};

	my $args = {};

	$args->{'type'} = $params->{'type'} if $params->{'type'};

	my @progress = Slim::Schema->rs('Progress')->search( $args, { 'order_by' => 'start' } )->all;

	for my $p (@progress) {

		my $bar;
		my $barFinish = $p->finish ? $barLen : $p->total ? $p->done / $p->total * $barLen : -1;

		for (my $i = 0; $i < $barLen; $i++) {
			$bar .= ( $i <= $barFinish ) ? $bar1 : $bar0;
		}

		my $runtime = ($p->finish || time()) - $p->start;

		my ($h0, $h1, $m0, $m1) = Slim::Utils::DateTime::timeDigits($runtime);

		my $item = {
			'obj'  => $p,
			'bar'  => $bar,
			'time' => "$h0$h1:$m0$m1".sprintf(":%02s",($runtime % 60)),
		};

		$total_time += $runtime;

		push @{$params->{'progress_items'}}, $item;
	}

	$params->{'desc'} = 1;

	# special message for importers once finished
	if ($params->{'type'} && $params->{'type'} eq 'importer' && !Slim::Music::Import->stillScanning) {

		if (@progress) {

			$params->{'message'}    = Slim::Utils::Strings::string('PROGRESS_IMPORTER_COMPLETE_DESC');

			my ($h0, $h1, $m0, $m1) = Slim::Utils::DateTime::timeDigits($total_time);
			$params->{'total_time'} = "$h0$h1:$m0$m1".sprintf(":%02s",($total_time % 60));

		} else {

			$params->{'message'}    = Slim::Utils::Strings::string('PROGRESS_IMPORTER_NO_INFO');
			$params->{'desc'} = 0;
		}
	}

	return Slim::Web::HTTP::filltemplatefile("progress.html", $params);
}

# progress bar which may be used by other pages - e.g. home page scan progress
sub progressBar {
	my $p      = shift;
	my $barLen = shift || 40;

	my $bar = '';

	my $barFinish = $p->finish ? $barLen : $p->total ? $p->done / $p->total * $barLen : -1;

	my $bar1 = ${Slim::Web::HTTP::filltemplatefile("hitlist_bar.html", { 'cell_full' => 1 })};
	my $bar0 = ${Slim::Web::HTTP::filltemplatefile("hitlist_bar.html", { 'cell_full' => 0 })};

	for (my $i = 0; $i < $barLen; $i++) {
		$bar .= ( $i <= $barFinish ) ? $bar1 : $bar0;
	}

	return $bar;
}

1;
