package Slim::Utils::FileHandle;

# $Id: FileHandle.pm,v 1.1 2004/01/13 00:36:12 dean Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use FileHandle;
use Carp;
use POSIX;

use Slim::Utils::Misc qw(msg);

@ISA = qw(FileHandle);

our %pipe_data;

sub open {
	my $class = shift;
	if(@_ == 1 && ($_[0] =~ /\|$/ || $_[0] =~ /^\|/)) {		# it's a pipeline open
		my $cmdline = shift;
		my $readpipe =( $cmdline =~ s/\s*\|$//);		# clip off the pipe indicator
		$cmdline =~ s/\^\|\s*// unless $readpipe;	# and tag the pipe direction
		$cmdline =~ s/\s*\&$//;	# clip off the ampersand if present (SlimServer specific)
		if($readpipe) {
			$pipe_data{$class}->{'pidlist'} = build_pipeline(STDIN,$class,$cmdline);
		} else {
			$pipe_data{$class}->{'pidlist'} = build_pipeline($class,STDOUT,$cmdline);
		}
		$class;
	} else {
		 $class->SUPER::open(@_);
	}
}

sub build_pipeline {
	my ($beginfh, $endfh, $cmdline) = @_;
	my (@pidlist, $thispid, $infh);
	$infh = $beginfh;
	my @cmdset = split(/\s*\|\s*/,$cmdline);
	while( my $cmd = shift(@cmdset)) {
		print STDERR "piping $cmd\n";
		my @cmds=grep defined, $cmd=~/"([^"]*)"|(\S+)/g;
		my $outfh;
		if(@cmdset) {
			($thispid, $outfh) = pipeline_segment($infh,$outfh,@cmds);
		} else {
			($thispid, $outfh) = pipeline_segment($infh,$endfh,@cmds);
		}
		push(@pidlist,$thispid);
		$infh = $outfh;
	}
	\@pidlist;
}

sub close {
	my $class = shift;
	if(defined($pipe_data{$class}->{'pidlist'})) {
		kill 1, @{$pipe_data{$class}->{'pidlist'}};
		wait;
	}
	if(defined($pipe_data{$class}->{'attached_fh'})) {
		close $pipe_data{$class}->{'attached_fh'};
	}
	$pipe_data{$class} = ();
	$class->SUPER::close(@_);
}

sub pipeline_segment
{
  my($in,$out,@cmd)=@_;
  my($child_write);
  pipe($out,$child_write)
    or die "pipe error: $!\n";
  my $pid = fork;
  if (!defined($pid)) { die "fork error: $!\n" };

  if ($pid)
  {
    # Parent
    CORE::close($child_write);
    return($pid,$out);
  }
  else
  {
    # child
    CORE::close($out);
    if (fileno($in) != 0)
    {
      CORE::close(STDIN)
        or die "Couldn't close STDIN: $!\n";
      POSIX::dup2(fileno($in),0)
        or die "Couldn't dup to stdin: $!\n";
    }
    CORE::close(STDOUT);
    POSIX::dup2(fileno($child_write),1)
      or die "Couldn't dup to stdout: $!\n";
    exec(@cmd)
      or die "exec error: $!\n";
  }
}


1;
