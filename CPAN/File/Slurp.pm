package File::Slurp;

use strict;

use Carp ;
use Fcntl qw( :DEFAULT :seek ) ;
use Symbol ;

use base 'Exporter' ;
use vars qw( %EXPORT_TAGS @EXPORT_OK $VERSION @EXPORT ) ;

%EXPORT_TAGS = ( 'all' => [
	qw( read_file write_file overwrite_file append_file read_dir ) ] ) ;

@EXPORT = ( @{ $EXPORT_TAGS{'all'} } );
@EXPORT_OK = qw( slurp ) ;

$VERSION = '9999.09';

*slurp = \&read_file ;

sub read_file {

	my( $file_name, %args ) = @_ ;

# set the buffer to either the passed in one or ours and init it to the null
# string

	my $buf ;
	my $buf_ref = $args{'buf_ref'} || \$buf ;
	${$buf_ref} = '' ;

	my( $read_fh, $size_left, $blk_size ) ;

# check if we are reading from a handle (glob ref or IO:: object)

	if ( ref $file_name ) {

# slurping a handle so use it and don't open anything.
# set the block size so we know it is a handle and read that amount

		$read_fh = $file_name ;
		$blk_size = $args{'blk_size'} || 1024 * 1024 ;
		$size_left = $blk_size ;

# DEEP DARK MAGIC. this checks the UNTAINT IO flag of a
# glob/handle. only the DATA handle is untainted (since it is from
# trusted data in the source file). this allows us to test if this is
# the DATA handle and then to do a sysseek to make sure it gets
# slurped correctly. on some systems, the buffered i/o pointer is not
# left at the same place as the fd pointer. this sysseek makes them
# the same so slurping with sysread will work.

		require B ;
		if ( B::svref_2object( $read_fh )->IO->IoFLAGS & 16 ) {

# set the seek position to the current tell.

			sysseek( $read_fh, tell( $read_fh ), SEEK_SET ) ||
				croak "sysseek $!" ;
		}
	}
	else {

# a regular file. set the sysopen mode

		my $mode = O_RDONLY ;
		$mode |= O_BINARY if $args{'binmode'} ;

# open the file and handle any error

		$read_fh = gensym ;
		unless ( sysopen( $read_fh, $file_name, $mode ) ) {
			@_ = ( \%args, "read_file '$file_name' - sysopen: $!");
			goto &error ;
		}

# get the size of the file for use in the read loop

		$size_left = -s $read_fh ;

		unless( $size_left ) {

			$blk_size = $args{'blk_size'} || 1024 * 1024 ;
			$size_left = $blk_size ;
		}
	}

# infinite read loop. we exit when we are done slurping

	while( 1 ) {

# do the read and see how much we got

		my $read_cnt = sysread( $read_fh, ${$buf_ref},
				$size_left, length ${$buf_ref} ) ;

		if ( defined $read_cnt ) {

# good read. see if we hit EOF (nothing left to read)

			last if $read_cnt == 0 ;

# loop if we are slurping a handle. we don't track $size_left then.

			next if $blk_size ;

# count down how much we read and loop if we have more to read.
			$size_left -= $read_cnt ;
			last if $size_left <= 0 ;
			next ;
		}

# handle the read error

		@_ = ( \%args, "read_file '$file_name' - sysread: $!");
		goto &error ;
	}

# this is the 5 returns in a row. each handles one possible
# combination of context and requested return type

# handle wanting to return an array ref of lines

	my $sep = $/ ;
	$sep = '\n\n+' if defined $sep && $sep eq '' ;

#	return [ split( m|(?<=$sep)|, ${$buf_ref} ) ] if $args{'array_ref'}  ;
	return [ length(${$buf_ref}) ? ${$buf_ref} =~ /(.*?$sep|.+)/sg : () ]
		if $args{'array_ref'}  ;

# handle wanting a list of lines (normal list context)

#	return split( m|(?<=$sep)|, ${$buf_ref} ) if wantarray ;
	return length(${$buf_ref}) ? ${$buf_ref} =~ /(.*?$sep|.+)/sg : ()
		if wantarray ;

# handle wanting to return an scalar ref to the slurped text

	return $buf_ref if $args{'scalar_ref'} ;

# handle wanting a scalar with the slurped text (normal scalar context)

	return ${$buf_ref} if defined wantarray ;

# handle when a buffer by buffer reference was passed in (normal void context)

	return ;
}

sub write_file {

	my $file_name = shift ;

# get the optional argument hash ref from @_ or an empty hash ref.

	my $args = ( ref $_[0] eq 'HASH' ) ? shift : {} ;

	my( $buf_ref, $write_fh, $no_truncate, $orig_file_name ) ;

# get the buffer ref - it depends on how the data is passed into write_file
# after this if/else $buf_ref will have a scalar ref to the data.

	if ( ref $args->{'buf_ref'} eq 'SCALAR' ) {

# a scalar ref passed in %args has the data

		$buf_ref = $args->{'buf_ref'} ;
	}
	elsif ( ref $_[0] eq 'SCALAR' ) {

# the first value in @_ is the scalar ref to the data

		$buf_ref = shift ;
	}
	elsif ( ref $_[0] eq 'ARRAY' ) {

# the first value in @_ is the array ref to the data so join it.

		${$buf_ref} = join '', @{$_[0]} ;
	}
	else {

# good old @_ has all the data so join it.

		${$buf_ref} = join '', @_ ;
	}

# see if we were passed a open handle to spew to.

	if ( ref $file_name ) {

# we have a handle. make sure we don't call truncate on it.

		$write_fh = $file_name ;
		$no_truncate = 1 ;
	}
	else {

# spew to regular file.

		if ( $args->{'atomic'} ) {

# in atomic mode, we spew to a temp file so make one and save the original
# file name.
			$orig_file_name = $file_name ;
			$file_name .= ".$$" ;
		}

# set the mode for the sysopen

		my $mode = O_WRONLY | O_CREAT ;
		$mode |= O_BINARY if $args->{'binmode'} ;
		$mode |= O_APPEND if $args->{'append'} ;
		$mode |= O_EXCL if $args->{'no_clobber'} ;

# open the file and handle any error.

		$write_fh = gensym ;
		unless ( sysopen( $write_fh, $file_name, $mode ) ) {
			@_ = ( $args, "write_file '$file_name' - sysopen: $!");
			goto &error ;
		}
	}

	sysseek( $write_fh, 0, SEEK_END ) if $args->{'append'} ;

# get the size of how much we are writing and init the offset into that buffer

	my $size_left = length( ${$buf_ref} ) ;
	my $offset = 0 ;

# loop until we have no more data left to write

	do {

# do the write and track how much we just wrote

		my $write_cnt = syswrite( $write_fh, ${$buf_ref},
				$size_left, $offset ) ;

		unless ( defined $write_cnt ) {

# the write failed
			@_ = ( $args, "write_file '$file_name' - syswrite: $!");
			goto &error ;
		}

# track much left to write and where to write from in the buffer

		$size_left -= $write_cnt ;
		$offset += $write_cnt ;

	} while( $size_left > 0 ) ;

# we truncate regular files in case we overwrite a long file with a shorter file
# so seek to the current position to get it (same as tell()).

	truncate( $write_fh,
		  sysseek( $write_fh, 0, SEEK_CUR ) ) unless $no_truncate ;

	close( $write_fh ) ;

# handle the atomic mode - move the temp file to the original filename.

	rename( $file_name, $orig_file_name ) if $args->{'atomic'} ;

	return 1 ;
}

# this is for backwards compatibility with the previous File::Slurp module. 
# write_file always overwrites an existing file

*overwrite_file = \&write_file ;

# the current write_file has an append mode so we use that. this
# supports the same API with an optional second argument which is a
# hash ref of options.

sub append_file {

# get the optional args hash ref
	my $args = $_[1] ;
	if ( ref $args eq 'HASH' ) {

# we were passed an args ref so just mark the append mode

		$args->{append} = 1 ;
	}
	else {

# no args hash so insert one with the append mode

		splice( @_, 1, 0, { append => 1 } ) ;
	}

# magic goto the main write_file sub. this overlays the sub without touching
# the stack or @_

	goto &write_file
}

# basic wrapper around opendir/readdir

sub read_dir {

	my ($dir, %args ) = @_;

# this handle will be destroyed upon return

	local(*DIRH);

# open the dir and handle any errors

	unless ( opendir( DIRH, $dir ) ) {

		@_ = ( \%args, "read_dir '$dir' - opendir: $!" ) ;
		goto &error ;
	}

	my @dir_entries = readdir(DIRH) ;

	@dir_entries = grep( $_ ne "." && $_ ne "..", @dir_entries )
		unless $args{'keep_dot_dot'} ;

	return @dir_entries if wantarray ;
	return \@dir_entries ;
}

# error handling section
#
# all the error handling uses magic goto so the caller will get the
# error message as if from their code and not this module. if we just
# did a call on the error code, the carp/croak would report it from
# this module since the error sub is one level down on the call stack
# from read_file/write_file/read_dir.


my %err_func = (
	carp => \&carp,
	croak => \&croak,
) ;

sub error {

	my( $args, $err_msg ) = @_ ;

# get the error function to use

 	my $func = $err_func{ $args->{'err_mode'} || 'croak' } ;

# if we didn't find it in our error function hash, they must have set
# it to quiet and we don't do anything.

	return unless $func ;

# call the carp/croak function

	$func->($err_msg) ;

# return a hard undef (in list context this will be a single value of
# undef which is not a legal in-band value)

	return undef ;
}

1;
__END__

=head1 NAME

File::Slurp - Efficient Reading/Writing of Complete Files

=head1 SYNOPSIS

  use File::Slurp;

  my $text = read_file( 'filename' ) ;
  my @lines = read_file( 'filename' ) ;

  write_file( 'filename', @lines ) ;

  use File::Slurp qw( slurp ) ;

  my $text = slurp( 'filename' ) ;


=head1 DESCRIPTION

This module provides subs that allow you to read or write entire files
with one simple call. They are designed to be simple to use, have
flexible ways to pass in or get the file contents and to be very
efficient.  There is also a sub to read in all the files in a
directory other than C<.> and C<..>

These slurp/spew subs work for files, pipes and
sockets, and stdio, pseudo-files, and DATA.

=head2 B<read_file>

This sub reads in an entire file and returns its contents to the
caller. In list context it will return a list of lines (using the
current value of $/ as the separator including support for paragraph
mode when it is set to ''). In scalar context it returns the entire
file as a single scalar.

  my $text = read_file( 'filename' ) ;
  my @lines = read_file( 'filename' ) ;

The first argument to C<read_file> is the filename and the rest of the
arguments are key/value pairs which are optional and which modify the
behavior of the call. Other than binmode the options all control how
the slurped file is returned to the caller.

If the first argument is a file handle reference or I/O object (if ref
is true), then that handle is slurped in. This mode is supported so
you slurp handles such as C<DATA>, C<STDIN>. See the test handle.t
for an example that does C<open( '-|' )> and child process spews data
to the parant which slurps it in.  All of the options that control how
the data is returned to the caller still work in this case.

NOTE: as of version 9999.06, read_file works correctly on the C<DATA>
handle. It used to need a sysseek workaround but that is now handled
when needed by the module itself

You can optionally request that C<slurp()> is exported to your code. This
is an alias for read_file and is meant to be forward compatible with
Perl 6 (which will have slurp() built-in).

The options are:

=head3 binmode

If you set the binmode option, then the file will be slurped in binary
mode.

	my $bin_data = read_file( $bin_file, binmode => ':raw' ) ;

NOTE: this actually sets the O_BINARY mode flag for sysopen. It
probably should call binmode and pass its argument to support other
file modes.

=head3 array_ref

If this boolean option is set, the return value (only in scalar
context) will be an array reference which contains the lines of the
slurped file. The following two calls are equivalent:

	my $lines_ref = read_file( $bin_file, array_ref => 1 ) ;
	my $lines_ref = [ read_file( $bin_file ) ] ;

=head3 scalar_ref

If this boolean option is set, the return value (only in scalar
context) will be an scalar reference to a string which is the contents
of the slurped file. This will usually be faster than returning the
plain scalar.

	my $text_ref = read_file( $bin_file, scalar_ref => 1 ) ;

=head3 buf_ref

You can use this option to pass in a scalar reference and the slurped
file contents will be stored in the scalar. This can be used in
conjunction with any of the other options.

	my $text_ref = read_file( $bin_file, buf_ref => \$buffer,
					     array_ref => 1 ) ;
	my @lines = read_file( $bin_file, buf_ref => \$buffer ) ;

=head3 blk_size

You can use this option to set the block size used when slurping from an already open handle (like \*STDIN). It defaults to 1MB.

	my $text_ref = read_file( $bin_file, blk_size => 10_000_000,
					     array_ref => 1 ) ;

=head3 err_mode

You can use this option to control how read_file behaves when an error
occurs. This option defaults to 'croak'. You can set it to 'carp' or
to 'quiet to have no error handling. This code wants to carp and then
read abother file if it fails.

	my $text_ref = read_file( $file, err_mode => 'carp' ) ;
	unless ( $text_ref ) {

		# read a different file but croak if not found
		$text_ref = read_file( $another_file ) ;
	}
	
	# process ${$text_ref}

=head2 B<write_file>

This sub writes out an entire file in one call.

  write_file( 'filename', @data ) ;

The first argument to C<write_file> is the filename. The next argument
is an optional hash reference and it contains key/values that can
modify the behavior of C<write_file>. The rest of the argument list is
the data to be written to the file.

  write_file( 'filename', {append => 1 }, @data ) ;
  write_file( 'filename', {binmode => ':raw' }, $buffer ) ;

As a shortcut if the first data argument is a scalar or array
reference, it is used as the only data to be written to the file. Any
following arguments in @_ are ignored. This is a faster way to pass in
the output to be written to the file and is equivilent to the
C<buf_ref> option. These following pairs are equivilent but the pass
by reference call will be faster in most cases (especially with larger
files).

  write_file( 'filename', \$buffer ) ;
  write_file( 'filename', $buffer ) ;

  write_file( 'filename', \@lines ) ;
  write_file( 'filename', @lines ) ;

If the first argument is a file handle reference or I/O object (if ref
is true), then that handle is slurped in. This mode is supported so
you spew to handles such as \*STDOUT. See the test handle.t for an
example that does C<open( '-|' )> and child process spews data to the
parant which slurps it in.  All of the options that control how the
data is passes into C<write_file> still work in this case.

C<write_file> returns 1 upon successfully writing the file or undef if
it encountered an error.

The options are:

=head3 binmode

If you set the binmode option, then the file will be written in binary
mode.

	write_file( $bin_file, {binmode => ':raw'}, @data ) ;

NOTE: this actually sets the O_BINARY mode flag for sysopen. It
probably should call binmode and pass its argument to support other
file modes.

=head3 buf_ref

You can use this option to pass in a scalar reference which has the
data to be written. If this is set then any data arguments (including
the scalar reference shortcut) in @_ will be ignored. These are
equivilent:

	write_file( $bin_file, { buf_ref => \$buffer } ) ;
	write_file( $bin_file, \$buffer ) ;
	write_file( $bin_file, $buffer ) ;

=head3 atomic

If you set this boolean option, the file will be written to in an
atomic fashion. A temporary file name is created by appending the pid
($$) to the file name argument and that file is spewed to. After the
file is closed it is renamed to the original file name (and rename is
an atomic operation on most OS's). If the program using this were to
crash in the middle of this, then the file with the pid suffix could
be left behind.

=head3 append

If you set this boolean option, the data will be written at the end of
the current file.

	write_file( $file, {append => 1}, @data ) ;

C<write_file> croaks if it cannot open the file. It returns true if it
succeeded in writing out the file and undef if there was an
error. (Yes, I know if it croaks it can't return anything but that is
for when I add the options to select the error handling mode).

=head3 no_clobber

If you set this boolean option, an existing file will not be overwritten.

	write_file( $file, {no_clobber => 1}, @data ) ;

=head3 err_mode

You can use this option to control how C<write_file> behaves when an
error occurs. This option defaults to 'croak'. You can set it to
'carp' or to 'quiet' to have no error handling other than the return
value. If the first call to C<write_file> fails it will carp and then
write to another file. If the second call to C<write_file> fails, it
will croak.

	unless ( write_file( $file, { err_mode => 'carp', \$data ) ;

		# write a different file but croak if not found
		write_file( $other_file, \$data ) ;
	}

=head2 overwrite_file

This sub is just a typeglob alias to write_file since write_file
always overwrites an existing file. This sub is supported for
backwards compatibility with the original version of this module. See
write_file for its API and behavior.

=head2 append_file

This sub will write its data to the end of the file. It is a wrapper
around write_file and it has the same API so see that for the full
documentation. These calls are equivilent:

	append_file( $file, @data ) ;
	write_file( $file, {append => 1}, @data ) ;

=head2 read_dir

This sub reads all the file names from directory and returns them to
the caller but C<.> and C<..> are removed by default.

	my @files = read_dir( '/path/to/dir' ) ;

It croaks if it cannot open the directory.

In a list context C<read_dir> returns a list of the entries in the
directory. In a scalar context it returns an array reference which has
the entries.

=head3 keep_dot_dot

If this boolean option is set, C<.> and C<..> are not removed from the
list of files.

	my @all_files = read_dir( '/path/to/dir', keep_dot_dot => 1 ) ;

=head2 EXPORT

  read_file write_file overwrite_file append_file read_dir

=head2 SEE ALSO

An article on file slurping 

=head1 AUTHOR

Uri Guttman, E<lt>uri@stemsystems.comE<gt>

=cut
