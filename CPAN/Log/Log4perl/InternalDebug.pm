package Log::Log4perl::InternalDebug;
use warnings;
use strict;

use File::Temp qw(tempfile);
use File::Spec;

require Log::Log4perl::Resurrector;

###########################################
sub enable {
###########################################
    unshift @INC, \&internal_debug_loader;
}

##################################################
sub internal_debug_fh {
##################################################
    my($file) = @_;

    local($/) = undef;
    open FILE, "<$file" or die "Cannot open $file";
    my $text = <FILE>;
    close FILE;

    my($tmp_fh, $tmpfile) = tempfile( UNLINK => 1 );

    $text =~ s/_INTERNAL_DEBUG(?!\s*=>)/1/g;

    print $tmp_fh $text;
    seek $tmp_fh, 0, 0;

    return $tmp_fh;
}

###########################################
sub internal_debug_loader {
###########################################
    my ($code, $module) = @_;

      # Skip non-Log4perl modules
    if($module !~ m#^Log/Log4perl#) {
        return undef;
    }

    my $path = $module;
    if(!-f $path) {
        $path = Log::Log4perl::Resurrector::pm_search( $module );
    }

    my $fh = internal_debug_fh($path);

    my $abs_path = File::Spec->rel2abs( $path );
    $INC{$module} = $abs_path;

    return $fh;
}

###########################################
sub resurrector_init {
###########################################
    unshift @INC, \&resurrector_loader;
}

###########################################
sub import {
###########################################
    # enable it on import
  enable();
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::InternalDebug - Dark Magic to enable _INTERNAL_DEBUG

=head1 DESCRIPTION

When called with

    perl -MLog::Log4perl::InternalDebug t/001Test.t

scripts will run with _INTERNAL_DEBUG set to a true value and hence
print internal Log4perl debugging information.

=head1 LICENSE

Copyright 2002-2013 by Mike Schilli E<lt>m@perlmeister.comE<gt> 
and Kevin Goess E<lt>cpan@goess.orgE<gt>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=head1 AUTHOR

Please contribute patches to the project on Github:

    http://github.com/mschilli/log4perl

Send bug reports or requests for enhancements to the authors via our

MAILING LIST (questions, bug reports, suggestions/patches): 
log4perl-devel@lists.sourceforge.net

Authors (please contact them via the list above, not directly):
Mike Schilli <m@perlmeister.com>,
Kevin Goess <cpan@goess.org>

Contributors (in alphabetical order):
Ateeq Altaf, Cory Bennett, Jens Berthold, Jeremy Bopp, Hutton
Davidson, Chris R. Donnelly, Matisse Enzer, Hugh Esco, Anthony
Foiani, James FitzGibbon, Carl Franks, Dennis Gregorovic, Andy
Grundman, Paul Harrington, Alexander Hartmaier  David Hull, 
Robert Jacobson, Jason Kohles, Jeff Macdonald, Markus Peter, 
Brett Rann, Peter Rabbitson, Erik Selberg, Aaron Straup Cope, 
Lars Thegler, David Viner, Mac Yang.

