#
# Package meta, adds meta database commands to dbish
#
package DBI::Shell::Timing;

use strict;
use vars qw(@ISA $VERSION);
use Benchmark qw(timeit timestr);

$VERSION = sprintf( "%d.%02d", q$Revision: 11.91 $ =~ /(\d+)\.(\d+)/ );

sub init {
	my ($self, $sh, @arg)  = @_;


	$sh->install_options( 
	[
		[ 'timing_style' 	=> qq{auto}		],
		[ 'timing_timing'	=> 1			],  # Set the default to on
		[ 'timing_format'	=> '5.2f'		],
		[ 'timing_prefix'	=> 'Elapsed: '	],
	]);
	my $com_ref = $sh->{commands};
	$com_ref->{timing}		= { 
		hint => 
			"timing: on/off (1/0) display execute time upon completion of command",
	};
		
	return $self;
}

sub do_timing {
	my $self = shift;
	if (@_) {
		my $t = shift;
		# $self->log( qq{timing called with $t} );
		$t = 0 if ($t =~ m/off|stop|end/i);
		$t = 1 if ($t =~ m/on|start|begin/i);
		$self->{timing_timing} = ($t?1:0);
	}
	$self->print_buffer(qq{timing: } . ($self->{timing_timing}? 'on': 'off'));
return $self->{timing_timing};
}


#
# Subclass the do_go command to include the timing options.  I'm not
# sure which is better, to subclass this command or completely
# override it.
#
sub do_go {
	my $self = shift;
	my $rv = timeit( 1, sub { $self->DBI::Shell::Base::do_go( @_ ) } );
	if ($self->{timing_timing}) {
		my $str = $self->{timing_prefix} . 
			timestr( $rv, $self->{timing_style}, $self->{timing_format} );
		$self->log( $str );
	}
	return;
}

my $_unimp = qq{timing: not implemented yet};

1;
