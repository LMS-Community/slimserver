#!/usr/local/bin/perl

package DBI::Shell::FindSqlFile;

use strict;
use File::Find ();
use File::Basename;
use File::Spec;

use vars qw($VERSION);

$VERSION = sprintf( "%d.%02d", q$Revision: 11.91 $ =~ /(\d+)\.(\d+)/ );

# Set the variable $File::Find::dont_use_nlink if you're using AFS,
# since AFS cheats.

# for the convenience of &wanted calls, including -eval statements:
use vars qw/*name *dir *prune @found $to_find_file $debug/;
*name   = *File::Find::name;
*dir    = *File::Find::dir;
*prune  = *File::Find::prune;

@found = ();
$to_find_file = undef;
$debug = 0;

sub look_for_file {
	my $self = shift;
	my $file = shift;
	my ($base, $dir, $ext) = fileparse($file,'\..*?');

	$debug = $self->{debug};

	# print "file $file : concat $dir$base$ext\n";

	# Work-around to fileparse adding current directory.
	$dir = undef unless ( $file eq "$dir$base$ext" );

	unless ($ext) {
		$ext = q{.sql};
	}
	# If a directory is defined, return to caller
	if ($dir) {
		return ( "$dir$base$ext" );
	};

	$to_find_file = qq{$base$ext};

	$self->log("calling find with $to_find_file") if $self->{debug};


# Split the sqlpath, then determine if any of the directories are valid.
	my @search_path = map { -d $_ ? $_ : () } split(/:/,
		   defined $self->{sqlpath} ? $self->{sqlpath} : ()
		   );
		# ,  (exists $ENV{DBISH_SQL_PATH} ?  $ENV{DBISH_SQL_PATH} : ()) );

	$self->log( "search path: " . join( "\n", @search_path ) )
		if $self->{debug};

	# Traverse desired filesystems
	File::Find::find(
		{
			  wanted 	=> \&wanted
			, no_chrdir 	=> 1
			, bydepth	=> 0
		}, 
		@search_path);


	return shift @found if @found;

return;
}

sub wanted {
    (/^.*$to_find_file\z/is && print "Found $to_find_file file
	$name\n" ) if $debug;
    /^.*$to_find_file\z/is && push @found, $name;
    $prune = 1 if ( -d $dir and -d $name and $dir ne $name );
}

1;

__END__
