# File::ReadBackwards.pm

# Copyright (C) 2003 by Uri Guttman. All rights reserved.
# mail bugs, comments and feedback to uri@stemsystems.com

package File::ReadBackwards ;

use strict ;

use vars qw( $VERSION ) ;

$VERSION = '1.04' ;

use Symbol ;
use Fcntl qw( :seek O_RDONLY ) ;
use Carp ;

my $max_read_size = 1 << 13 ;

my $default_rec_sep ;

BEGIN {

# set the default record separator according to this OS
# this needs testing and expansion.

# look for CR/LF types
# then look for CR types
# else it's a LF type

	if ( $^O =~ /win32/i || $^O =~ /vms/i ) {

		$default_rec_sep = "\015\012" ;
	}
	elsif ( $^O =~ /mac/i ) {

		$default_rec_sep = "\015" ;
	}
	else {
		$default_rec_sep = "\012" ;
	}

# the tied interface is exactly the same as the object one, so all we
# need to do is to alias the subs with typeglobs

	*TIEHANDLE = \&new ;
	*READLINE = \&readline ;
 	*EOF = \&eof ;
 	*CLOSE = \&close ;
 	*TELL = \&tell ;

# added getline alias for compatibility with IO::Handle

	*getline = \&readline ;
}


# constructor for File::ReadBackwards

sub new {

	my( $class, $filename, $rec_sep, $sep_is_regex ) = @_ ;

# check that we have a filename

	defined( $filename ) || return ;

# see if this file uses the default of a cr/lf separator
# those files will get cr/lf converted to \n

	$rec_sep ||= $default_rec_sep ;
	my $is_crlf = $rec_sep eq "\015\012" ;

# get a handle and open the file

	my $handle = gensym ;
	sysopen( $handle, $filename, O_RDONLY ) || return ;
	binmode $handle ;

# seek to the end of the file and get its size

	my $seek_pos = sysseek( $handle, 0, SEEK_END ) or return ;

# get the size of the first block to read,
# either a trailing partial one (the % size) or full sized one (max read size)

	my $read_size = $seek_pos % $max_read_size || $max_read_size ;

# create the object

	my $self = bless {
			'file_name'	=> $filename,
			'handle'	=> $handle,
			'read_size'	=> $read_size,
			'seek_pos'	=> $seek_pos,
			'lines'		=> [],
			'is_crlf'	=> $is_crlf,
			'rec_sep'	=> $rec_sep,
			'sep_is_regex'	=> $sep_is_regex,

		}, $class ;

	return( $self ) ;
}

# read the previous record from the file
# 
sub readline {

	my( $self, $line_ref ) = @_ ;

	my $read_buf ;

# get the buffer of lines

	my $lines_ref = $self->{'lines'} ;

	return unless $lines_ref ;

	while( 1 ) {

# see if there is more than 1 line in the buffer

		if ( @{$lines_ref} > 1 ) {

# we have a complete line so return it
# and convert those damned cr/lf lines to \n

			$lines_ref->[-1] =~ s/\015\012/\n/
					if $self->{'is_crlf'} ;

			return( pop @{$lines_ref} ) ;
		}

# we don't have a complete, so have to read blocks until we do

		my $seek_pos = $self->{'seek_pos'} ;

# see if we are at the beginning of the file

		if ( $seek_pos == 0 ) {

# the last read never made more lines, so return the last line in the buffer
# if no lines left then undef will be returned
# and convert those damned cr/lf lines to \n

			$lines_ref->[-1] =~ s/\015\012/\n/
					if @{$lines_ref} && $self->{'is_crlf'} ;

			return( pop @{$lines_ref} ) ;
		}

# we have to read more text so get the handle and the current read size

		my $handle = $self->{'handle'} ;
		my $read_size = $self->{'read_size'} ;

# after the first read, always read the maximum size

		$self->{'read_size'} = $max_read_size ;

# seek to the beginning of this block and save the new seek position

		$seek_pos -= $read_size ;
		sysseek( $handle, $seek_pos, SEEK_SET ) ;
		$self->{'seek_pos'} = $seek_pos ;

# read in the next (previous) block of text

		my $read_cnt = sysread( $handle, $read_buf, $read_size ) ;

# prepend the read buffer to the leftover (possibly partial) line

		my $text = $read_buf ;
		$text .= shift @{$lines_ref} if @{$lines_ref} ;

# split the buffer into a list of lines
# this may want to be $/ but reading files backwards assumes plain text and
# newline separators

		@{$lines_ref} = ( $self->{'sep_is_regex'} ) ?
	 		$text =~ /(.*?$self->{'rec_sep'}|.+)/gs :
			$text =~ /(.*?\Q$self->{'rec_sep'}\E|.+)/gs ;

#print "Lines \n=>", join( "<=\n=>", @{$lines_ref} ), "<=\n" ;

	}
}

sub eof {

	my ( $self ) = @_ ;

	my $seek_pos = $self->{'seek_pos'} ;
	my $lines_count = @{ $self->{'lines'} } ;
	return( $seek_pos == 0 && $lines_count == 0 ) ;
}

sub tell {
	my ( $self ) = @_ ;

	my $seek_pos = $self->{'seek_pos'} ;
	$seek_pos + length(join "", @{ $self->{'lines'} });
}

sub get_handle {
	my ( $self ) = @_ ;

	my $handle = $self->{handle} ;
	seek( $handle, $self->tell, SEEK_SET ) ;
	return $handle ;
}

sub close {

	my ( $self ) = @_ ;

	my $handle = delete( $self->{'handle'} ) ;
	delete( $self->{'lines'} ) ;

	CORE::close( $handle ) ;
}

__END__


=head1 NAME

File::ReadBackwards.pm -- Read a file backwards by lines.
 

=head1 SYNOPSIS

    use File::ReadBackwards ;

    # Object interface

    $bw = File::ReadBackwards->new( 'log_file' ) or
			die "can't read 'log_file' $!" ;

    while( defined( $log_line = $bw->readline ) ) {
	    print $log_line ;
    }

    # ... or the alternative way of reading

    until ( $bw->eof ) {
	    print $bw->readline ;
    }

    # Tied Handle Interface

    tie *BW, 'File::ReadBackwards', 'log_file' or
			die "can't read 'log_file' $!" ;

    while( <BW> ) {
	    print ;
    }

=head1 DESCRIPTION
  

This module reads a file backwards line by line. It is simple to use,
memory efficient and fast. It supports both an object and a tied handle
interface.

It is intended for processing log and other similar text files which
typically have their newest entries appended to them. By default files
are assumed to be plain text and have a line ending appropriate to the
OS. But you can set the input record separator string on a per file
basis.


=head1 OBJECT INTERFACE
 
These are the methods in C<File::ReadBackwards>' object interface:


=head2 new( $file, [$rec_sep], [$sep_is_regex] )

C<new> takes as arguments a filename, an optional record separator and
an optional flag that marks the record separator as a regular
expression. It either returns the object on a successful open or undef
upon failure. $! is set to the error code if any.

=head2 readline

C<readline> takes no arguments and it returns the previous line in the
file or undef when there are no more lines in the file. If the file is
a non-seekable file (e.g. a pipe), then undef is returned.

=head2 getline

C<getline> is an alias for the readline method. It is here for
compatibilty with the IO::* classes which has a getline method.

=head2 eof

C<eof> takes no arguments and it returns true when readline() has
iterated through the whole file.

=head2 close

C<close> takes no arguments and it closes the handle

=head2 tell

C<tell> takes no arguments and it returns the current filehandle position.
This value may be used to seek() back to this position using a normal
file handle.

=head2 get_handle

C<get_handle> takes no arguments and it returns the internal Perl
filehandle used by the File::ReadBackwards object.  This handle may be
used to read the file forward. Its seek position will be set to the
position that is returned by the tell() method.  Note that
interleaving forward and reverse reads may produce unpredictable
results.  The only use supported at present is to read a file backward
to a certain point, then use 'handle' to extract the handle, and read
forward from that point.

=head1 TIED HANDLE INTERFACE

=head2 tie( *HANDLE, 'File::ReadBackwards', $file, [$rec_sep], [$sep_is_regex] )
 

The TIEHANDLE, READLINE, EOF, CLOSE and TELL methods are aliased to
the new, readline, eof, close and tell methods respectively so refer
to them for their arguments and API.  Once you have tied a handle to
File::ReadBackwards the only I/O operation permissible is <> which
will read the previous line. You can call eof() and close() on the
tied handle as well. All other tied handle operations will generate an
unknown method error. Do not seek, write or perform any other
unsupported operations on the tied handle.

=head1 LINE AND RECORD ENDINGS
 

Since this module needs to use low level I/O for efficiency, it can't
portably seek and do block I/O without managing line ending conversions.
This module supports the default record separators of normal line ending
strings used by the OS. You can also set the separator on a per file
basis.

The record separator is a regular expression by default, which differs
from the behavior of $/.

Only if the record separator is B<not> specified and it defaults to
CR/LF (e.g, VMS, redmondware) will it will be converted to a single
newline. Unix and MacOS files systems use only a single character for
line endings and the lines are left unchanged.  This means that for
native text files, you should be able to process their lines backwards
without any problems with line endings. If you specify a record
separator, no conversions will be done and you will get the records as
if you read them in binary mode.

=head1 DESIGN

It works by reading a large (8kb) block of data from the end of the
file.  It then splits them on the record separator and stores a list of
records in the object. Each call to readline returns the top record of
the list and if the list is empty it refills it by reading the previous
block from the file and splitting it.  When the beginning of the file is
reached and there are no more lines, undef is returned.  All boundary
conditions are handled correctly i.e. if there is a trailing partial
line (no newline) it will be the first line returned and lines larger
than the read buffer size are handled properly.


=head1 NOTES
 

There is no support for list context in either the object or tied
interfaces. If you want to slurp all of the lines into an array in
backwards order (and you don't care about memory usage) just do:

	@back_lines = reverse <FH>.

This module is only intended to read one line at a time from the end of
a file to the beginning.

=head1 AUTHOR
 

Uri Guttman, uri@stemsystems.com

=head1 COPYRIGHT
 

Copyright (C) 2003 by Uri Guttman. All rights reserved.  This program is
free software; you can redistribute it and/or modify it under the same
terms as Perl itself.

=cut
