package Log::Log4perl::Resurrector;
use warnings;
use strict;

# [rt.cpan.org #84818]
use if $^O eq "MSWin32", "Win32"; 

use File::Temp qw(tempfile);
use File::Spec;

use constant INTERNAL_DEBUG => 0;

our $resurrecting = '';

###########################################
sub import {
###########################################
    resurrector_init();
}

##################################################
sub resurrector_fh {
##################################################
    my($file) = @_;

    local($/) = undef;
    open FILE, "<$file" or die "Cannot open $file";
    my $text = <FILE>;
    close FILE;

    print "Read ", length($text), " bytes from $file\n" if INTERNAL_DEBUG;

    my($tmp_fh, $tmpfile) = tempfile( UNLINK => 1 );
    print "Opened tmpfile $tmpfile\n" if INTERNAL_DEBUG;

    $text =~ s/^\s*###l4p//mg;

    print "Text=[$text]\n" if INTERNAL_DEBUG;

    print $tmp_fh $text;
    seek $tmp_fh, 0, 0;

    return $tmp_fh;
}

###########################################
sub resurrector_loader {
###########################################
    my ($code, $module) = @_;

    print "resurrector_loader called with $module\n" if INTERNAL_DEBUG;

      # Avoid recursion
    if($resurrecting eq $module) {
        print "ignoring $module (recursion)\n" if INTERNAL_DEBUG;
        return undef;
    }
    
    local $resurrecting = $module;
    
    
      # Skip Log4perl appenders
    if($module =~ m#^Log/Log4perl/Appender#) {
        print "Ignoring $module (Log4perl-internal)\n" if INTERNAL_DEBUG;
        return undef;
    }

    my $path = $module;

      # Skip unknown files
    if(!-f $module) {
          # We might have a 'use lib' statement that modified the
          # INC path, search again.
        $path = pm_search($module);
        if(! defined $path) {
            print "File $module not found\n" if INTERNAL_DEBUG;
            return undef;
        }
        print "File $module found in $path\n" if INTERNAL_DEBUG;
    }

    print "Resurrecting module $path\n" if INTERNAL_DEBUG;

    my $fh = resurrector_fh($path);

    my $abs_path = File::Spec->rel2abs( $path );
    print "Setting %INC entry of $module to $abs_path\n" if INTERNAL_DEBUG;
    $INC{$module} = $abs_path;

    return $fh;
}

###########################################
sub pm_search {
###########################################
    my($pmfile) = @_;

    for(@INC) {
          # Skip subrefs
        next if ref($_);
        my $path = File::Spec->catfile($_, $pmfile);
        return $path if -f $path;
    }

    return undef;
}

###########################################
sub resurrector_init {
###########################################
    unshift @INC, \&resurrector_loader;
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Resurrector - Dark Magic to resurrect hidden L4p statements

=head1 DESCRIPTION

Loading C<use Log::Log4perl::Resurrector> causes subsequently loaded
modules to have their hidden

    ###l4p use Log::Log4perl qw(:easy);

    ###l4p DEBUG(...)
    ###l4p INFO(...)
    ...

statements uncommented and therefore 'resurrected', i.e. activated.

This allows for a module C<Foobar.pm> to be written with Log4perl
statements commented out and running at full speed in normal mode.
When loaded via

    use Foobar;

all hidden Log4perl statements will be ignored.

However, if a script loads the module C<Foobar> I<after> loading 
C<Log::Log4perl::Resurrector>, as in

    use Log::Log4perl::Resurrector;
    use Foobar;

then C<Log::Log4perl::Resurrector> will have put a source filter in place
that will extract all hidden Log4perl statements in C<Foobar> before 
C<Foobar> actually gets loaded. 

Therefore, C<Foobar> will then behave as if the

    ###l4p use Log::Log4perl qw(:easy);

    ###l4p DEBUG(...)
    ###l4p INFO(...)
    ...

statements were actually written like

    use Log::Log4perl qw(:easy);

    DEBUG(...)
    INFO(...)
    ...

and the module C<Foobar> will indeed be Log4perl-enabled. Whether any
activated Log4perl statement will actually trigger log
messages, is up to the Log4perl configuration, of course.

There's a startup cost to using C<Log::Log4perl::Resurrector> (all
subsequently loaded modules are examined) but once the compilation
phase has finished, the perl program will run at full speed.

Some of the techniques used in this module have been stolen from the
C<Acme::Incorporated> CPAN module, written by I<chromatic>. Long
live CPAN!
 
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

