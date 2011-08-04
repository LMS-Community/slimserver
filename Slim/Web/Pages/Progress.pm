package Slim::Web::Pages::Progress;

use strict;

use Slim::Schema;
use Slim::Utils::Strings qw(string);

sub init {
	Slim::Web::Pages->addPageFunction(qr/^progress\.(?:htm|xml)/,\&progress);
}

sub progress {
	my ($client, $params) = @_;

	if ($params->{'abortScan'}) {
		Slim::Music::Import->abortScan();
	}
	
	return undef if !Slim::Schema::hasLibrary();

	my $total_time = 0;
	my $barLen = $params->{'barlen'} || 40;

	my $bar1 = ${Slim::Web::HTTP::filltemplatefile("hitlist_bar.html", { cell_full => 1, webroot => $params->{webroot} })};
	my $bar0 = ${Slim::Web::HTTP::filltemplatefile("hitlist_bar.html", { cell_full => 0, webroot => $params->{webroot} })};

	my $args = {};

	$args->{'type'} = $params->{'type'} if $params->{'type'};

	my @progress = Slim::Schema->rs('Progress')->search( $args, { 'order_by' => 'start,id' } )->all;

	my $finished;
	my $failure;

	for my $p (@progress) {

		unless ($p->name eq 'failure') {

			my $bar;
			my $barFinish = $p->finish ? $barLen : $p->total ? $p->done / $p->total * $barLen : -1;
	
			for (my $i = 0; $i < $barLen; $i++) {
				$bar .= ( $i <= $barFinish ) ? $bar1 : $bar0;
			}
	
			my $runtime = ((!$p->active && $p->finish) ? $p->finish : time()) - $p->start;
	
			my $hrs  = int($runtime / 3600);
			my $mins = int(($runtime - $hrs * 3600)/60);
			my $sec  = $runtime - 3600 * $hrs - 60 * $mins;
	
			my $item = {
				'obj'  => {},
				'bar'  => $bar,
				'time' => sprintf("%02d:%02d:%02d", $hrs, $mins, $sec),
			};
			
			foreach ($p->columns) {
				$item->{obj}->{$_} = $p->$_();
			}
			
			if ($p->name =~ /(.*)\|(.*)/) {
				$item->{fullname} = string($2 . '_PROGRESS') . string('COLON') . ' ' . $1;
				$item->{obj}->{name} = $2;
			}
	
			$total_time += $runtime;
	
			push @{$params->{'progress_items'}}, $item;

		}
		else {
			$failure = $p->info || 1;
		}
		
		$finished = $p->finish;
	}

	$params->{'desc'} = 1;

	# special message for importers once finished
	if ($params->{'type'} && $params->{'type'} eq 'importer' && !Slim::Music::Import->stillScanning) {

		if (@progress) {

			if ($failure) {
				$params->{'message'} = '?';
				
				if ($failure eq 'SCAN_ABORTED') {
					$params->{'message'} = string($failure); 
				}
				elsif ($failure ne '1') {
					$params->{'message'} = string('FAILURE_PROGRESS', string($failure . '_PROGRESS')); 
				}
				
				$params->{'failed'} = $failure;
			}
			else {
				$params->{'message'} = string('PROGRESS_IMPORTER_COMPLETE_DESC');
			}
				
			
			my $hrs  = int($total_time / 3600);
			my $mins = int(($total_time - $hrs * 3600)/60);
			my $sec  = $total_time - 3600 * $hrs - 60 * $mins;
			
			$params->{'total_time'} = sprintf("%02d:%02d:%02d", $hrs, $mins, $sec);
			$params->{'total_time'} .= '&nbsp;(' . Slim::Utils::DateTime::longDateF($finished) . ' / ' . Slim::Utils::DateTime::timeF($finished) . ')' if $finished;

		} else {

			$params->{'message'} = string('PROGRESS_IMPORTER_NO_INFO');
			$params->{'desc'} = 0;
		}
	}

	$params->{'scanning'} = Slim::Music::Import->stillScanning();

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
