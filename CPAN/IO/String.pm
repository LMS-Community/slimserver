package IO::String;

# Copyright 1998-2002 Gisle Aas.
#
# This library is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

require 5.005_03;
use strict;
use vars qw($VERSION $DEBUG $IO_CONSTANTS);
$VERSION = "1.02";  # $Date: 2003/07/18 19:42:07 $

use Symbol ();

sub new
{
    my $class = shift;
    my $self = bless Symbol::gensym(), ref($class) || $class;
    tie *$self, $self;
    $self->open(@_);
    $self;
}

sub open
{
    my $self = shift;
    return $self->new(@_) unless ref($self);

    if (@_) {
	my $bufref = ref($_[0]) ? $_[0] : \$_[0];
	$$bufref = "" unless defined $$bufref;
	*$self->{buf} = $bufref;
    } else {
	my $buf = "";
	*$self->{buf} = \$buf;
    }
    *$self->{pos} = 0;
    *$self->{lno} = 0;
    $self;
}

sub pad
{
    my $self = shift;
    my $old = *$self->{pad};
    *$self->{pad} = substr($_[0], 0, 1) if @_;
    return "\0" unless defined($old) && length($old);
    $old;
}

sub dump
{
    require Data::Dumper;
    my $self = shift;
    print Data::Dumper->Dump([$self], ['*self']);
    print Data::Dumper->Dump([*$self{HASH}], ['$self{HASH}']);
}

sub TIEHANDLE
{
    print "TIEHANDLE @_\n" if $DEBUG;
    return $_[0] if ref($_[0]);
    my $class = shift;
    my $self = bless Symbol::gensym(), $class;
    $self->open(@_);
    $self;
}

sub DESTROY
{
    print "DESTROY @_\n" if $DEBUG;
}

sub close
{
    my $self = shift;
    delete *$self->{buf};
    delete *$self->{pos};
    delete *$self->{lno};
    untie *$self;
    $self;
}

sub opened
{
    my $self = shift;
    defined *$self->{buf};
}

sub getc
{
    my $self = shift;
    my $buf;
    return $buf if $self->read($buf, 1);
    return undef;
}

sub ungetc
{
    my $self = shift;
    $self->setpos($self->getpos() - 1)
}

sub eof
{
    my $self = shift;
    length(${*$self->{buf}}) <= *$self->{pos};
}

sub print
{
    my $self = shift;
    if (defined $\) {
	if (defined $,) {
	    $self->write(join($,, @_).$\);
	} else {
	    $self->write(join("",@_).$\);
	}
    } else {
	if (defined $,) {
	    $self->write(join($,, @_));
	} else {
	    $self->write(join("",@_));
	}
    }
}
*printflush = \*print;

sub printf
{
    my $self = shift;
    print "PRINTF(@_)\n" if $DEBUG;
    my $fmt = shift;
    $self->write(sprintf($fmt, @_));
}


my($SEEK_SET, $SEEK_CUR, $SEEK_END);

sub _init_seek_constants
{
    if ($IO_CONSTANTS) {
	require IO::Handle;
	$SEEK_SET = &IO::Handle::SEEK_SET;
	$SEEK_CUR = &IO::Handle::SEEK_CUR;
	$SEEK_END = &IO::Handle::SEEK_END;
    } else {
	$SEEK_SET = 0;
	$SEEK_CUR = 1;
	$SEEK_END = 2;
    }
}


sub seek
{
    my($self,$off,$whence) = @_;
    my $buf = *$self->{buf} || return;
    my $len = length($$buf);
    my $pos = *$self->{pos};

    _init_seek_constants() unless defined $SEEK_SET;

    if    ($whence == $SEEK_SET) { $pos = $off }
    elsif ($whence == $SEEK_CUR) { $pos += $off }
    elsif ($whence == $SEEK_END) { $pos = $len + $off }
    else { die "Bad whence ($whence)" }
    print "SEEK(POS=$pos,OFF=$off,LEN=$len)\n" if $DEBUG;

    $pos = 0 if $pos < 0;
    $self->truncate($pos) if $pos > $len;  # extend file
    *$self->{lno} = 0;
    *$self->{pos} = $pos;
}

sub pos
{
    my $self = shift;
    my $old = *$self->{pos};
    if (@_) {
	my $pos = shift || 0;
	my $buf = *$self->{buf};
	my $len = $buf ? length($$buf) : 0;
	$pos = $len if $pos > $len;
	*$self->{lno} = 0;
	*$self->{pos} = $pos;
    }
    $old;
}

sub getpos { shift->pos; }

*sysseek = \&seek;
*setpos  = \&pos;
*tell    = \&getpos;



sub getline
{
    my $self = shift;
    my $buf  = *$self->{buf} || return;
    my $len  = length($$buf);
    my $pos  = *$self->{pos};
    return if $pos >= $len;

    unless (defined $/) {  # slurp
	*$self->{pos} = $len;
	return substr($$buf, $pos);
    }

    unless (length $/) {  # paragraph mode
	# XXX slow&lazy implementation using getc()
	my $para = "";
	my $eol = 0;
	my $c;
	while (defined($c = $self->getc)) {
	    if ($c eq "\n") {
		$eol++;
	    } elsif ($eol > 1) {
		$self->ungetc($c);
		last;
	    }
	    $para .= $c;
	}
	return $para;   # XXX wantarray
    }

    my $idx = index($$buf,$/,$pos);
    if ($idx < 0) {
	# return rest of it
	*$self->{pos} = $len;
	$. = ++ *$self->{lno};
	return substr($$buf, $pos);
    }
    $len = $idx - $pos + length($/);
    *$self->{pos} += $len;
    $. = ++ *$self->{lno};
    return substr($$buf, $pos, $len);
}

sub getlines
{
    die "getlines() called in scalar context\n" unless wantarray;
    my $self = shift;
    my($line, @lines);
    push(@lines, $line) while defined($line = $self->getline);
    return @lines;
}

sub READLINE
{
    goto &getlines if wantarray;
    goto &getline;
}

sub input_line_number
{
    my $self = shift;
    my $old = *$self->{lno};
    *$self->{lno} = shift if @_;
    $old;
}

sub truncate
{
    my $self = shift;
    my $len = shift || 0;
    my $buf = *$self->{buf};
    if (length($$buf) >= $len) {
	substr($$buf, $len) = '';
	*$self->{pos} = $len if $len < *$self->{pos};
    } else {
	$$buf .= ($self->pad x ($len - length($$buf)));
    }
    $self;
}

sub read
{
    my $self = shift;
    my $buf = *$self->{buf};
    return unless $buf;

    my $pos = *$self->{pos};
    my $rem = length($$buf) - $pos;
    my $len = $_[1];
    $len = $rem if $len > $rem;
    if (@_ > 2) { # read offset
	substr($_[0],$_[2]) = substr($$buf, $pos, $len);
    } else {
	$_[0] = substr($$buf, $pos, $len);
    }
    *$self->{pos} += $len;
    return $len;
}

sub write
{
    my $self = shift;
    my $buf = *$self->{buf};
    return unless $buf;

    my $pos = *$self->{pos};
    my $slen = length($_[0]);
    my $len = $slen;
    my $off = 0;
    if (@_ > 1) {
	$len = $_[1] if $_[1] < $len;
	if (@_ > 2) {
	    $off = $_[2] || 0;
	    die "Offset outside string" if $off > $slen;
	    if ($off < 0) {
		$off += $slen;
		die "Offset outside string" if $off < 0;
	    }
	    my $rem = $slen - $off;
	    $len = $rem if $rem < $len;
	}
    }
    substr($$buf, $pos, $len) = substr($_[0], $off, $len);
    *$self->{pos} += $len;
    $len;
}

*sysread = \&read;
*syswrite = \&write;

sub stat
{
    my $self = shift;
    return unless $self->opened;
    return 1 unless wantarray;
    my $len = length ${*$self->{buf}};

    return (
     undef, undef,  # dev, ino
     0666,          # filemode
     1,             # links
     $>,            # user id
     $),            # group id
     undef,         # device id
     $len,          # size
     undef,         # atime
     undef,         # mtime
     undef,         # ctime
     512,           # blksize
     int(($len+511)/512)  # blocks
    );
}

sub FILENO {
    return undef;   # XXX perlfunc says this means the file is closed
}

sub blocking {
    my $self = shift;
    my $old = *$self->{blocking} || 0;
    *$self->{blocking} = shift if @_;
    $old;
}

my $notmuch = sub { return };

*fileno    = $notmuch;
*error     = $notmuch;
*clearerr  = $notmuch; 
*sync      = $notmuch;
*flush     = $notmuch;
*setbuf    = $notmuch;
*setvbuf   = $notmuch;

*untaint   = $notmuch;
*autoflush = $notmuch;
*fcntl     = $notmuch;
*ioctl     = $notmuch;

*GETC   = \&getc;
*PRINT  = \&print;
*PRINTF = \&printf;
*READ   = \&read;
*WRITE  = \&write;
*SEEK   = \&seek;
*TELL   = \&getpos;
*EOF    = \&eof;
*CLOSE  = \&close;

*BINMODE = $notmuch;


sub string_ref
{
    my $self = shift;
    *$self->{buf};
}
*sref = \&string_ref;

1;

__END__

=head1 NAME

IO::String - Emulate IO::File interface for in-core strings

=head1 SYNOPSIS

 use IO::String;
 $io = IO::String->new;
 $io = IO::String->new($var);
 tie *IO, 'IO::String';

 # read data
 <$io>;
 $io->getline;
 read($io, $buf, 100);

 # write data
 print $io "string\n";
 $io->print(@data);
 syswrite($io, $buf, 100);

 select $io;
 printf "Some text %s\n", $str;

 # seek
 $pos = $io->getpos;
 $io->setpos(0);        # rewind
 $io->seek(-30, -1);
 seek($io, 0, 0);

=head1 DESCRIPTION

The C<IO::String> module provide the C<IO::File> interface for in-core
strings.  An C<IO::String> object can be attached to a string, and
will make it possible to use the normal file operations for reading or
writing data, as well as seeking to various locations of the string.
The main reason you might want to do this, is if you have some other
library module that only provide an interface to file handles, and you
want to keep all the stuff in memory.

The C<IO::String> module provide an interface compatible with
C<IO::File> as distributed with F<IO-1.20>, but the following methods
are not available; new_from_fd, fdopen, format_write,
format_page_number, format_lines_per_page, format_lines_left,
format_name, format_top_name.

The following methods are specific for the C<IO::String> class:

=over 4

=item $io = IO::String->new( [$string] )

The constructor returns a newly created C<IO::String> object.  It
takes an optional argument which is the string to read from or write
into.  If no $string argument is given, then an internal buffer
(initially empty) is allocated.

The C<IO::String> object returned will be tied to itself.  This means
that you can use most perl IO builtins on it too; readline, <>, getc,
print, printf, syswrite, sysread, close.

=item $io->open( [$string] )

Attach an existing IO::String object to some other $string, or
allocate a new internal buffer (if no argument is given).  The
position is reset back to 0.

=item $io->string_ref

This method will return a reference to the string that is attached to
the C<IO::String> object.  Most useful when you let the C<IO::String>
create an internal buffer to write into.

=item $io->pad( [$char] )

The pad() method makes it possible to specify the padding to use if
the string is extended by either the seek() or truncate() methods.  It
is a single character and defaults to "\0".

=item $io->pos( [$newpos] )

Yet another interface for reading and setting the current read/write
position within the string (the normal getpos/setpos/tell/seek
methods are also available).  The pos() method will always return the
old position, and if you pass it an argument it will set the new
position.

There is (deliberately) a difference between the setpos() and seek()
methods in that seek() will extend the string (with the specified
padding) if you go to a location past the end, while setpos() will
just snap back to the end.  If truncate() is used to extend the string,
then it works as seek().

=back

One more difference compared to IO::Handle, is that the write() and
syswrite() methods allow the length argument to be left out.

=head1 BUGS

The perl version < 5.6 the TIEHANDLE interface was still not complete.
If you use such a perl seek(), tell(), eof(), fileno(), binmode() will
not do anything on a C<IO::String> handle.  See L<perltie> for
details.

=head1 SEE ALSO

L<IO::File>, L<IO::Stringy>

=head1 COPYRIGHT

Copyright 1998-2002 Gisle Aas.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
