#!/usr/bin/perl

# Copyright Ben Maurer 
# you can distribute this under the MIT/X11 License

use lib qw(CPAN);

use Linux::Smaps;

my $pid=shift @ARGV;
unless ($pid) {
	print "./smem.pl <pid>\n";
	exit 1;
}
my $map=Linux::Smaps->new($pid);
my @VMAs = $map->vmas;

format STDOUT =
VMSIZE:  @######## kb
$map->size
RSS:     @######## kb total
$map->rss
         @######## kb shared
$map->shared_clean + $map->shared_dirty
         @######## kb private clean
$map->private_clean
         @######## kb private dirty
$map->private_dirty
.

write;
    
printPrivateMappings ();
printSharedMappings ();

sub sharedMappings () {
    return grep { ($_->shared_clean  + $_->shared_dirty) > 0 } @VMAs;
}

sub privateMappings () {
    return grep { ($_->private_clean  + $_->private_dirty) > 0 } @VMAs;
}

sub printPrivateMappings ()
{
    $TYPE = "PRIVATE MAPPINGS";
    $^ = 'SECTION_HEADER';
    $~ = 'SECTION_ITEM';
    $- = 0;
    $= = 100000000;
    foreach  $vma (sort {-($a->private_dirty <=> $b->private_dirty)} 
				   privateMappings ()) {
	$size  = $vma->size;
	$dirty = $vma->private_dirty;
	$clean = $vma->private_clean;
	$file  = $vma->file_name;
	write;
    }
}

sub printSharedMappings ()
{
    $TYPE = "SHARED MAPPINGS";
    $^ = 'SECTION_HEADER';
    $~ = 'SECTION_ITEM';
    $- = 0;
    $= = 100000000;
    
    foreach  $vma (sort {-(($a->shared_clean + $a->shared_dirty)
			   <=>
			   ($b->shared_clean + $b->shared_dirty))} 
		   sharedMappings ()) {
	
	$size  = $vma->size;
	$dirty = $vma->shared_dirty;
	$clean = $vma->shared_clean;
	$file  = $vma->file_name;
	write;
	
	
    }
}

format SECTION_HEADER =
@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$TYPE
@>>>>>>>>>> @>>>>>>>>>>  @>>>>>>>>>   @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
"vmsize" "rss clean" "rss dirty" "file"
.

format SECTION_ITEM =
@####### kb @####### kb @####### kb   @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$size $clean $dirty $file
.
