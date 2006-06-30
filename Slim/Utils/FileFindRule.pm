package Slim::Utils::FileFindRule;

# $Id$

# Simple subclass to override ->in() and return an array ref.

use strict;
use base qw(File::Find::Rule);

use Cwd;
use File::Spec;

sub in {
    my $self     = File::Find::Rule::_force_object(shift);

    my @found    = ();
    my $fragment = $self->_compile( $self->{subs} );
    my @subs     = @{ $self->{subs} };

    warn "relative mode handed multiple paths - that's a bit silly\n"
      if $self->{relative} && @_ > 1;

    my $topdir;
    my $code = 'sub {
        (my $path = $File::Find::name)  =~ s#^\./##;
        my @args = ($_, $File::Find::dir, $path);
        my $maxdepth = $self->{maxdepth};
        my $mindepth = $self->{mindepth};
        my $relative = $self->{relative};

        # figure out the relative path and depth
        my $relpath = $File::Find::name;
        $relpath =~ s{^\Q$topdir\E/?}{};
        my $depth = scalar File::Spec->splitdir($relpath);

        defined $maxdepth && $depth >= $maxdepth and $File::Find::prune = 1;
        defined $mindepth && $depth < $mindepth and return;

        my $discarded;
        return unless ' . $fragment . ';
        return if $discarded;
        if ($relative) {
            push @found, $relpath if $relpath ne "";
        } else {
            push @found, $path;
        }
    }';

    my $sub = eval "$code" or die "compile error '$code' $@";
    my $cwd = getcwd;
    for my $path (@_) {
        # $topdir is used for relative and maxdepth
        $topdir = $path;
        $self->_call_find( { %{ $self->{extras} }, wanted => $sub }, $path );
    }
    chdir $cwd;

    return wantarray ? @found : \@found;
}

1;

__END__
