package Slim::Utils::FileHandle;

# $Id: FileHandle.pm,v 1.2 2004/01/19 05:58:44 daniel Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use Carp;
use FileHandle;
use POSIX;

use Slim::Utils::Misc qw(msg);
use base qw(FileHandle);

our %pipe_data = ();

# public methods
sub open {
	my $class = shift;

	# not a pipeline open
	unless (@_ == 1 && ($_[0] =~ /\|$/ || $_[0] =~ /^\|/)) {
		$class->SUPER::open(@_);
		return;
	}

	my $cmdline  = shift;

	$::d_filehandle && msg("Original pipeline command: [$cmdline]\n");

	# clip off the pipe indicator
	my $readpipe = ($cmdline =~ s/\s*\|$//);

	# and tag the pipe direction
	$cmdline =~ s/\^\|\s*// unless $readpipe;

	# clip off the ampersand if present (SlimServer specific)
	$cmdline =~ s/\s*\&$//;

	if ($readpipe) {
		$pipe_data{$class}->{'pidlist'} = _buildPipeline(\*STDIN,$class,$cmdline);
	} else {
		$pipe_data{$class}->{'pidlist'} = _buildPipeline($class,\*STDOUT,$cmdline);
	}

	return $class;
}

sub close {
	my $class = shift;

	if (defined($pipe_data{$class}->{'pidlist'})) {
		kill 1, @{$pipe_data{$class}->{'pidlist'}};
		wait;
	}

	if (defined($pipe_data{$class}->{'attached_fh'})) {
		close $pipe_data{$class}->{'attached_fh'};
	}

	$pipe_data{$class} = ();
	$class->SUPER::close(@_);
}

# private
sub _buildPipeline {
	my ($beginfh, $endfh, $cmdline) = @_;

	my (@pidlist, $thispid, $infh);

	$infh = $beginfh;

	my @cmdset = split(/\s*\|\s*/, $cmdline);

	while (my $cmd = shift(@cmdset)) {

		$::d_filehandle && msg("piping $cmd\n");

		my @cmds = grep defined, $cmd =~ /"([^"]*)"|(\S+)/g;

		my $outfh;

		if(@cmdset) {
			($thispid, $outfh) = _pipelineSegment($infh,$outfh,@cmds);
		} else {
			($thispid, $outfh) = _pipelineSegment($infh,$endfh,@cmds);
		}

		push(@pidlist,$thispid);

		$infh = $outfh;
	}

	\@pidlist;
}

sub _pipelineSegment {
	my ($in,$out,@cmd) = @_;

	pipe($out, my $child_write) or die "pipe error: $!\n";

	my $pid = fork();

	unless (defined($pid)) {
		die "fork error: $!\n"
	}

	if ($pid) {

		# Parent
		CORE::close($child_write);
		return($pid,$out);

	} else {

		# child
		CORE::close($out);

		if (fileno($in) != 0) {
			CORE::close(STDIN) or die "Couldn't close STDIN: $!\n";
			POSIX::dup2(fileno($in),0) or die "Couldn't dup to stdin: $!\n";
		}

		CORE::close(STDOUT);
		POSIX::dup2(fileno($child_write),1) or die "Couldn't dup to stdout: $!\n";

		exec(@cmd) or die "exec error: $!\n";
	}
}

1;
