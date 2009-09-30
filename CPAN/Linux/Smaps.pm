package Linux::Smaps;

use 5.008;
use strict;
use warnings FATAL=>'all';
no warnings qw(uninitialized portable);
use Class::Member::HASH qw{pid lasterror filename procdir
			   _elem -CLASS_MEMBERS};

our $VERSION = '0.06';

sub new {
  my $class=shift;
  $class=ref($class) if( ref($class) );
  my $I=bless {}=>$class;
  my %h;

  $I->procdir='/proc';
  $I->pid='self';

  if( @_==1 ) {
    $I->pid=shift;
  } else {
    our @CLASS_MEMBERS;
    %h=@_;
    foreach my $k (@CLASS_MEMBERS) {
      $I->$k=$h{$k} if( exists $h{$k});
    }
  }

  return $I if( $h{uninitialized} );

  my $rc=$I->update;
  die __PACKAGE__.": ".$I->lasterror."\n" unless( $rc );

  return $rc;
}

sub update {
  my $I=shift;

  my $name;

  # this way one can use one object to loop through a list of processes like:
  # foreach (@pids) {
  #   $smaps->pid=$_; $smaps->update;
  #   process($smaps);
  # }
  if( defined $I->filename ) {
    $name=$I->filename;
  } else {
    $name=$I->procdir.'/'.$I->pid.'/smaps';
  }

  open my $f, '<', $name or do {
    $I->lasterror="Cannot open $name: $!";
    return;
  };

  my $current;
  $I->_elem=[];
  my %cache;
  my $l;
  while( defined($l=<$f>) ) {
    if( $l=~/([\da-f]+)-([\da-f]+)\s                # range
             ([r\-])([w\-])([x\-])([sp])\s          # access mode
             ([\da-f]+)\s                           # page offset in file
             ([\da-f]+):([\da-f]+)\s                # device
             (\d+)\s*                               # inode
             (.*?)		                    # file name
	     (\s\(deleted\))?$
	    /xi ) {
      $current=Linux::Smaps::VMA->new;
      $current->vma_start=hex $1;
      $current->vma_end=hex $2;
      unless( exists $cache{$current->vma_start."\0".$current->vma_end} ) {
	$cache{$current->vma_start."\0".$current->vma_end}=1;
	push @{$I->_elem}, $current;
	$current->r=($3 eq 'r');
	$current->w=($4 eq 'w');
	$current->x=($5 eq 'x');
	$current->mayshare=($6 eq 's');
	$current->file_off=hex $7;
	$current->dev_major=hex $8;
	$current->dev_minor=hex $9;
	$current->inode=$10;
	$current->file_name=$11;
	$current->is_deleted=defined( $12 );
      }
    } elsif( $l=~/^(\w+):\s*(\d+) kB$/ ) {
      my $m=lc $1;
      $m=~s/\s/_/g;
      unless( $current->can($m) ) {
	if( $I->can($m) ) {
	  $I->lasterror=(__PACKAGE__."::$m method is already defined while ".
			 "Linux::Smaps::VMA::$m is not");
	  return;
	}

	no strict 'refs';
	*{__PACKAGE__."::$m"}=sub {
	  my $I=shift;
	  my $n=shift;
	  my $rc=0;
	  my @l;
	  if( length $n ) {
	    local $_;
	    @l=grep {$_->file_name eq $n} @{$I->_elem};
	  } else {
	    @l=@{$I->_elem};
	  }
	  foreach my $el (@l) {
	    $rc+=$el->$m;
	  }
	  return $rc;
	};

	package Linux::Smaps::VMA;
	Class::Member::HASH->import($m);
      }
      $current->$m=$2;
    } else {
      $I->lasterror="$name($.): not parsed: $l";
      return;
    }
  }

  close $f;

  return $I;
}

BEGIN {
  foreach my $n (qw{heap stack vdso vsyscall}) {
    eval <<"EOE";
    sub $n {
      my \$I=shift;
      local \$_;
      return (grep {'[$n]' eq \$_->file_name} \@{\$I->_elem})[0];
    }
EOE
    die "$@" if( $@ );
  }
}

sub unnamed {
  my $I=shift;
  if( wantarray ) {
    local $_;
    return grep {!length $_->file_name} @{$I->_elem};
  } else {
    my $sum=Linux::Smaps::VMA->new;
    $sum->size=$sum->rss=$sum->shared_clean=$sum->shared_dirty=
      $sum->private_clean=$sum->private_dirty=0;
    foreach my $el (@{$I->_elem}) {
      next if( length $el->file_name );
      $sum->size+=$el->size;
      $sum->rss+=$el->rss;
      $sum->shared_clean+=$el->shared_clean;
      $sum->shared_dirty+=$el->shared_dirty;
      $sum->private_clean+=$el->private_clean;
      $sum->private_dirty+=$el->private_dirty;
    }
    return $sum;
  }
}

sub named {
  my $I=shift;
  if( wantarray ) {
    local $_;
    return grep {length $_->file_name} @{$I->_elem};
  } else {
    my $sum=Linux::Smaps::VMA->new;
    $sum->size=$sum->rss=$sum->shared_clean=$sum->shared_dirty=
      $sum->private_clean=$sum->private_dirty=0;
    foreach my $el (@{$I->_elem}) {
      next if( !length $el->file_name );
      $sum->size+=$el->size;
      $sum->rss+=$el->rss;
      $sum->shared_clean+=$el->shared_clean;
      $sum->shared_dirty+=$el->shared_dirty;
      $sum->private_clean+=$el->private_clean;
      $sum->private_dirty+=$el->private_dirty;
    }
    return $sum;
  }
}

sub all {
  my $I=shift;
  if( wantarray ) {
    local $_;
    return @{$I->_elem};
  } else {
    my $sum=Linux::Smaps::VMA->new;
    $sum->size=$sum->rss=$sum->shared_clean=$sum->shared_dirty=
      $sum->private_clean=$sum->private_dirty=0;
    foreach my $el (@{$I->_elem}) {
      $sum->size+=$el->size;
      $sum->rss+=$el->rss;
      $sum->shared_clean+=$el->shared_clean;
      $sum->shared_dirty+=$el->shared_dirty;
      $sum->private_clean+=$el->private_clean;
      $sum->private_dirty+=$el->private_dirty;
    }
    return $sum;
  }
}

sub names {
  my $I=shift;
  local $_;
  my %h=map {($_->file_name=>1)} @{$I->_elem};
  delete @h{'','[heap]','[stack]','[vdso]'};
  return keys %h;
}

sub diff {
  my $I=shift;
  my @my_special;
  my @my=map {
    if( $_->file_name=~/\[\w+\]/ ) {
      push @my_special, $_;
      ();
    } else {
      $_;
    }
  } $I->vmas;
  my %other_special;
  my %other=map {
    if( $_->file_name=~/^(\[\w+\])$/ ) {
      $other_special{$1}=$_;
      ();
    } else {
      ($_->vma_start=>$_);
    }
  } shift->vmas;

  my @new;
  my @diff;
  my @old;

  foreach my $vma (@my_special) {
    if( exists $other_special{$vma->file_name} ) {
      my $x=delete $other_special{$vma->file_name};
      push @diff, [$vma, $x]
	if( $vma->vma_start != $x->vma_start or
	    $vma->vma_end != $x->vma_end or
	    $vma->shared_clean != $x->shared_clean or
	    $vma->shared_dirty != $x->shared_dirty or
	    $vma->private_clean != $x->private_clean or
	    $vma->private_dirty != $x->private_dirty or
	    $vma->dev_major != $x->dev_major or
	    $vma->dev_minor != $x->dev_minor or
	    $vma->r != $x->r or
	    $vma->w != $x->w or
	    $vma->x != $x->x or
	    $vma->file_off != $x->file_off or
	    $vma->inode != $x->inode or
	    $vma->mayshare != $x->mayshare );
    } else {
      push @new, $vma;
    }
  }
  @old=values %other_special;

  foreach my $vma (@my) {
    if( exists $other{$vma->vma_start} ) {
      my $x=delete $other{$vma->vma_start};
      push @diff, [$vma, $x]
	if( $vma->vma_end != $x->vma_end or
	    $vma->shared_clean != $x->shared_clean or
	    $vma->shared_dirty != $x->shared_dirty or
	    $vma->private_clean != $x->private_clean or
	    $vma->private_dirty != $x->private_dirty or
	    $vma->dev_major != $x->dev_major or
	    $vma->dev_minor != $x->dev_minor or
	    $vma->r != $x->r or
	    $vma->w != $x->w or
	    $vma->x != $x->x or
	    $vma->file_off != $x->file_off or
	    $vma->inode != $x->inode or
	    $vma->mayshare != $x->mayshare or
	    $vma->file_name ne $x->file_name );
    } else {
      push @new, $vma;
    }
  }
  push @old, sort {$a->vma_start <=> $b->vma_start} values %other;

  return \@new, \@diff, \@old;
}

sub vmas {return @{$_[0]->_elem};}

package Linux::Smaps::VMA;

use strict;
use Class::Member::HASH qw(vma_start vma_end r w x mayshare file_off
			   dev_major dev_minor inode file_name is_deleted);

sub new {bless {}=>(ref $_[0] ? ref $_[0] : $_[0]);}

1;
__END__

=head1 NAME

Linux::Smaps - a Perl interface to /proc/PID/smaps

=head1 SYNOPSIS

  use Linux::Smaps;
  my $map=Linux::Smaps->new($pid);
  my @maps=$map->maps;
  my $private_dirty=$map->private_dirty;
  ...

=head1 DESCRIPTION

The /proc/PID/smaps files in modern linuxes provides very detailed information
about a processes memory consumption. It particularly includes a way to
estimate the effect of copy-on-write. This module implements a Perl
interface.

=head2 CONSTRUCTOR, OBJECT INITIALIZATION, etc.

=over 4

=item B<< Linux::Smaps->new >>

=item B<< Linux::Smaps->new($pid) >>

=item B<< Linux::Smaps->new(pid=>$pid, procdir=>'/proc') >>

=item B<< Linux::Smaps->new(filename=>'/proc/self/smaps') >>

creates and initializes a C<Linux::Smaps> object. On error an exception is
thrown. C<new()> may fail if the smaps file is not readable or if the file
format is wrong.

C<new()> without parameter is equivalent to C<new('self')> or
C<< new(pid=>'self') >>. With the C<procdir> parameter the mount point of
the proc filesystem can be set if it differs from the standard C</proc>.

The C<filename> parameter sets the name of the smaps file directly. This way
also files outside the standard C</proc> tree can be analyzed.

=item B<< Linux::Smaps->new(uninitialized=>1) >>

returns an uninitialized object. This makes C<new()> simply skip the C<update()>
call after setting all parameters. Additional parameters like C<pid>,
C<procdir> or C<filename> can be passed.

=item B<< $self->pid($pid) >> or B<< $self->pid=$pid >>

=item B<< $self->procdir($dir) >> or B<< $self->procdir=$dir >>

=item B<< $self->filename($name) >> or B<< $self->filename=$name >>

get/set parameters.

If a filename is set C<update()> reads that file. Otherwize a file name is
constructed from C<< $self->procdir >>, C<< $self->pid >> and the name
C<smaps>. The constructed file name is not saved in the C<Linux::Smaps>
object to allow loops like this:

 foreach (@pids) {
     $smaps->pid=$_;
     $smaps->update;
     process $smaps;
 }

=item B<< $self->update >>

reinitializes the object; rereads the underlying file. Returns the object
or C<undef> on error. The actual reason can be obtained via C<lasterror()>.

=item B<< $self->lasterror >>

C<update()> and C<new()> return C<undef> on failure. C<lasterror()> returns
a more verbose reason. Also C<$!> can be checked.

=back

=head2 INFORMATION RETRIEVAL

=over 4

=item B<< $self->vmas >>

returns a list of C<Linux::Smaps::VMA> objects each describing a vm area,
see below.

=item B<< $self->size >>

=item B<< $self->rss >>

=item B<< $self->shared_clean >>

=item B<< $self->shared_dirty >>

=item B<< $self->private_clean >>

=item B<< $self->private_dirty >>

these methods compute the sums of the corresponding values of all vmas.

C<size>, C<rss>, C<shared_clean>, C<shared_dirty>, C<private_clean> and
C<private_dirty> methods are unknown until the first call to
C<Linux::Smaps::update()>. They are created on the fly. This is to make
the module extendable as new features are added to the smaps file by the
kernel. As long as the corresponding smaps file lines match
C<^(\w+):\s*(\d+) kB$> new accessor methods are created.

At the time of this writing at least one new field (C<referenced>) is on
the way but all my kernels still lack it.

=item B<< $self->stack >>

=item B<< $self->heap >>

=item B<< $self->vdso >>

these are shortcuts to the corresponding C<Linux::Smaps::VMA> objects.

=item B<< $self->all >>

=item B<< $self->named >>

=item B<< $self->unnamed >>

In array context these functions return a list of C<Linux::Smaps::VMA>
objects representing named or unnamed maps or simply all vmas. Thus, in
array context C<all()> is equivalent to C<vmas()>.

In scalar context these functions create a fake C<Linux::Smaps::VMA> object
containing the summaries of the C<size>, C<rss>, C<shared_clean>,
C<shared_dirty>, C<private_clean> and C<private_dirty> fields.

=item B<< $self->names >>

returns a list of vma names, i.e. the files that are mapped.

=item B<< ($new, $diff, $old)=$self->diff( $other ) >>

$other is assumed to be also a C<Linux::Smaps> instance. 3 arrays are
returned. The first one ($new) is a list of vmas that are contained in
$self but not in $other. The second one ($diff) contains a list of pairs
(2-element arrays) of vmas that differ between $self and $other. The
3rd one ($old) is a list of vmas that are contained in $other but not in
$self.

Vmas are identified as corresponding if their C<vma_start> fields match.
They are considered different if they differ in one of the following fields:
C<vma_end>, C<r>, C<w>, C<x>, C<mayshare>, C<file_off>, C<dev_major>,
C<dev_minor>, C<inode>, C<file_name>, C<shared_clean>, C<shared_diry>,
C<private_clean> and C<private_dirty>.

=back

=head1 Linux::Smaps::VMA objects

normally these objects represent a single vm area:

=over 4

=item B<< $self->vma_start >>

=item B<< $self->vma_end >>

start and end address

=item B<< $self->r >>

=item B<< $self->w >>

=item B<< $self->x >>

=item B<< $self->mayshare >>

these correspond to the VM_READ, VM_WRITE, VM_EXEC and VM_MAYSHARE flags.
see Linux kernel for more information.

=item B<< $self->file_off >>

=item B<< $self->dev_major >>

=item B<< $self->dev_minor >>

=item B<< $self->inode >>

=item B<< $self->file_name >>

describe the file area that is mapped.

=item B<< $self->size >>

the same as vma_end - vma_start but in kB.

=item B<< $self->rss >>

what part is resident.

=item B<< $self->shared_clean >>

=item B<< $self->shared_dirty >>

=item B<< $self->private_clean >>

=item B<< $self->private_dirty >>

C<shared> means C<< page_count(page)>=2 >> (see Linux kernel), i.e. the page
is shared between several processes. C<private> pages belong only to one
process.

C<dirty> pages are written to in RAM but not to the corresponding file.

=back

C<size>, C<rss>, C<shared_clean>, C<shared_dirty>, C<private_clean> and
C<private_dirty> methods are unknown until the first call to
C<Linux::Smaps::update()>. They are created on the fly. This is to make
the module extendable as new features are added to the smaps file by the
kernel. As long as the corresponding smaps file lines match
C<^(\w+):\s*(\d+) kB$> new accessor methods are created.

At the time of this writing at least one new field (C<referenced>) is on
the way but all my kernels still lack it.

=head1 Example: The copy-on-write effect

 use strict;
 use Linux::Smaps;

 my $x="a"x(1024*1024);		# a long string of "a"
 if( fork ) {
   my $s=Linux::Smaps->new($$);
   my $before=$s->all;
   $x=~tr/a/b/;			# change "a" to "b" in place
   #$x="b"x(1024*1024);		# assignment
   $s->update;
   my $after=$s->all;
   foreach my $n (qw{rss size shared_clean shared_dirty
                     private_clean private_dirty}) {
     print "$n: ",$before->$n," => ",$after->$n,": ",
            $after->$n-$before->$n,"\n";
   }
   wait;
 } else {
   sleep 1;
 }

This script may give the following output:

 rss: 4160 => 4252: 92
 size: 6916 => 7048: 132
 shared_clean: 1580 => 1596: 16
 shared_dirty: 2412 => 1312: -1100
 private_clean: 0 => 0: 0
 private_dirty: 168 => 1344: 1176

C<$x> is changed in place. Hence, the overall process size (size and rss)
would not grow much. But before the C<tr> operation C<$x> was shared by
copy-on-write between the 2 processes. Hence, we see a loss of C<shared_dirty>
(only a little more than our 1024 kB string) and almost the same growth of
C<private_dirty>.

Exchanging the C<tr>-operation to an assingment of a MB of "b" yields the
following figures:

 rss: 4160 => 5276: 1116
 size: 6916 => 8076: 1160
 shared_clean: 1580 => 1592: 12
 shared_dirty: 2432 => 1304: -1128
 private_clean: 0 => 0: 0
 private_dirty: 148 => 2380: 2232

Now we see the overall process size grows a little more than a MB.
C<shared_dirty> drops almost a MB and C<private_dirty> adds almost 2 MB.
That means perl first constructs a 1 MB string of C<b>. This adds 1 MB to
C<size>, C<rss> and C<private_dirty> and then copies it to C<$x>. This
takes another MB from C<shared_dirty> and adds it to C<private_dirty>.

=head1 A special note on copy on write measurements

The proc filesystem reports a page as shared if it belongs multiple
processes and as private if it belongs to only one process. But there
is an exception. If a page is currently paged out (that means it is not
in core) all its attributes including the reference count are paged out
as well. So the reference count cannot be read without paging in the page.
In this case a page is neither reported as private nor as shared. It is
only included in the process size.

Thus, to exaclty measure which pages are shared among N processes at least
one of them must be completely in core. This way all pages that can
possibly be shared are in core and their reference counts are accessible.

The L<mlockall(2)> syscall may help in this situation. It locks all pages
of a process to main memory:

 require 'syscall.ph';
 require 'sys/mmap.ph';

 0==syscall &SYS_mlockall, &MCL_CURRENT | &MCL_FUTURE or
     die "ERROR: mlockall failed: $!\n";

This snippet in one of the processes locks it to the main memory. If all
processes are created from the same parent it is executed best just before
the parent starts to fork off children. The memory lock is not inherited
by the children. So all private pages of the children are swappable.

Since we are talking about Linux only the snippet can be shortened:

 0==syscall 152, 3 or die "ERROR: mlockall failed: $!\n";

which removes the dependencies from F<syscall.ph> and F<sys/mmap.ph>.

=head1 EXPORT

Not an Exporter;

=head1 SEE ALSO

Linux Kernel.

=head1 AUTHOR

Torsten Foertsch, E<lt>torsten.foertsch@gmx.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005-2007 by Torsten Foertsch

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.5 or,
at your option, any later version of Perl 5 you may have available.


=cut
