package Slim::Web::Template::Profiler;
use base qw(Slim::Web::Template::Context);

my @stack;
my %totals;

sub process {
	my $self = shift;
	
	my $template = $_[0];
	if (UNIVERSAL::isa($template, "Template::Document")) {
		$template = $template->name || $template;
	}
	
	push @stack, [Time::HiRes::time, times];
	
	my @return = wantarray ? $self->SUPER::process(@_) : scalar $self->SUPER::process(@_);
	
	my @delta_times = @{pop @stack};
	
	@delta_times = map { $_ - shift @delta_times } Time::HiRes::time, times;
	for (0..$#delta_times) {
		$totals{$template}[$_] += $delta_times[$_];
		for my $parent (@stack) {
			$parent->[$_] += $delta_times[$_] if @stack; # parent adjust
		}
	}
	$totals{$template}[5] ++;     # count of calls
	
	unless (@stack) {
		## top level again, time to display results
		warn "-- $template at ". localtime, ":\n";
		warn sprintf("%3s %3s %6s %6s %6s %6s %s\n", qw(cnt clk user sys cuser csys template));
		for my $template (sort keys %totals) {
			my @values = @{$totals{$template}};
			warn sprintf("%3d %3d %6.2f %6.2f %6.2f %6.2f %s\n", $values[5], @values[0..4], $template);
		}
		warn "-- end\n";
		%totals = ();               # clear out results
	}
	
	# return value from process:
	wantarray ? @return : $return[0];
}

#$Template::Config::CONTEXT = __PACKAGE__;

1;