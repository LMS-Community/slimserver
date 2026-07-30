##################################################
package Log::Log4perl::Appender::RRDs;
##################################################
our @ISA = qw(Log::Log4perl::Appender);

use warnings;
use strict;
use RRDs;

##################################################
sub new {
##################################################
    my($class, @options) = @_;

    my $self = {
        name             => "unknown name",
        dbname           => undef,
        rrdupd_params => [],
        @options,
    };

    die "Mandatory parameter 'dbname' missing" unless
        defined $self->{dbname};

    bless $self, $class;

    return $self;
}

##################################################
sub log {
##################################################
    my($self, %params) = @_;

    #print "UPDATE: '$self->{dbname}' - '$params{message}'\n";

    RRDs::update($self->{dbname}, 
                 @{$params{rrdupd_params}},
                 $params{message}) or
        die "Cannot update rrd $self->{dbname} ",
            "with $params{message} ($!)";
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Appender::RRDs - Log to a RRDtool Archive
    
=head1 SYNOPSIS
    
    use Log::Log4perl qw(get_logger);
    use RRDs;
    
    my $DB = "myrrddb.dat";
    
    RRDs::create(
      $DB, "--step=1",
      "DS:myvalue:GAUGE:2:U:U",
      "RRA:MAX:0.5:1:120");
    
    print time(), "\n";
    
    Log::Log4perl->init(\qq{
      log4perl.category = INFO, RRDapp
      log4perl.appender.RRDapp = Log::Log4perl::Appender::RRDs
      log4perl.appender.RRDapp.dbname = $DB
      log4perl.appender.RRDapp.layout = Log::Log4perl::Layout::PatternLayout
      log4perl.appender.RRDapp.layout.ConversionPattern = N:%m
    });
    
    my $logger = get_logger();
    
    for(10, 15, 20, 25) {
        $logger->info($_);
        sleep 1;
    }
   
=head1 DESCRIPTION

C<Log::Log4perl::Appender::RRDs> appenders facilitate writing data
to RRDtool round-robin archives via Log4perl. For documentation
on RRD and its Perl interface C<RRDs> (which comes with the distribution),
check out L<http://rrdtool.org>.

Messages sent to Log4perl's RRDs appender are expected to be numerical values
(ints or floats), which then are used to run a C<rrdtool update> command
on an existing round-robin database. The name of this database needs to
be set in the appender's C<dbname> configuration parameter.

If there's more parameters you wish to pass to the C<update> method,
use the C<rrdupd_params> configuration parameter:

    log4perl.appender.RRDapp.rrdupd_params = --template=in:out

To read out the round robin database later on, use C<rrdtool fetch>
or C<rrdtool graph> for graphic displays.

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

