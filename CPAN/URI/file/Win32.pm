package URI::file::Win32;

require URI::file::Base;
@ISA=qw(URI::file::Base);

use strict;
use URI::Escape qw(uri_unescape);

# the authority is always null in Win32 file URLs.
sub extract_authority
{
    return '';
}

sub extract_path
{
    my($class, $path) = @_;
    $path =~ s,\\,/,g;
    $path =~ s,//+,/,g;
    $path =~ s,(/\.)+/,/,g;
    $path;
}

sub file
{
    my $class = shift;
    my $uri = shift;
    my $auth = $uri->authority;
    my $rel; # is filename relative to drive specified in authority
    if (defined $auth) {
        $auth = uri_unescape($auth);
	if ($auth =~ /^([a-zA-Z])[:|](relative)?/) {
	    $auth = uc($1) . ":";
	    $rel++ if $2;
	} elsif (lc($auth) eq "localhost") {
	    $auth = "";
	} elsif (length $auth) {
	    $auth = "\\\\" . $auth;  # UNC
	}
    } else {
	$auth = "";
    }

    my @path = $uri->path_segments;
    for (@path) {
	return if /\0/;
	return if /\//;
	#return if /\\/;        # URLs with "\" is not uncommon
	
    }
    return unless $class->fix_path(@path);

    my $path = join("\\", @path);
    $path =~ s/^\\// if $rel;
    $path = $auth . $path;
    $path =~ s,^\\([a-zA-Z])[:|],\u$1:,;
    $path;
}

sub fix_path { 1; }

1;
