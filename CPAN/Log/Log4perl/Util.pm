package Log::Log4perl::Util;

require Exporter;
our @EXPORT_OK = qw( params_check );
our @ISA       = qw( Exporter );

use File::Spec;

###########################################
sub params_check {
###########################################
    my( $hash, $required, $optional ) = @_;

    my $pkg       = caller();
    my %hash_copy = %$hash;

    if( defined $required ) {
        for my $p ( @$required ) {
            if( !exists $hash->{ $p } or
                !defined $hash->{ $p } ) {
                die "$pkg: Required parameter $p missing.";
            }
            delete $hash_copy{ $p };
        }
    }

    if( defined $optional ) {
        for my $p ( @$optional ) {
            delete $hash_copy{ $p };
        }
        if( scalar keys %hash_copy ) {
            die "$pkg: Unknown parameter: ", join( ",", keys %hash_copy );
        }
    }
}

##################################################
sub module_available {  # Check if a module is available
##################################################
    my($full_name) = @_;
      # Weird cases like "strict;" (including the semicolon) would 
      # succeed with the eval below, so check those up front. 
      # I can't believe Perl doesn't have a proper way to check if a 
      # module is available or not!
    return 0 if $full_name =~ /[^\w:]/;
    $full_name =~ s#::#/#g;
    $full_name .= '.pm';
    return 1 if $INC{$full_name};
    eval {
        local $SIG{__DIE__} = sub {};
        require $full_name;
    };
    return !$@;
}

##################################################
sub tmpfile_name {  # File::Temp without the bells and whistles
##################################################

    my $name = File::Spec->catfile(File::Spec->tmpdir(), 
                              'l4p-tmpfile-' . 
                              "$$-" .
                              int(rand(9999999)));

        # Some crazy versions of File::Spec use backslashes on Win32
    $name =~ s#\\#/#g;
    return $name;
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Util - Internal utility functions

=head1 DESCRIPTION

Only internal functions here. Don't peek.

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

