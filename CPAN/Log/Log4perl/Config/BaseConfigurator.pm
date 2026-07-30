package Log::Log4perl::Config::BaseConfigurator;

use warnings;
use strict;
use constant _INTERNAL_DEBUG => 0;

*eval_if_perl      = \&Log::Log4perl::Config::eval_if_perl;
*compile_if_perl   = \&Log::Log4perl::Config::compile_if_perl;
*leaf_path_to_hash = \&Log::Log4perl::Config::leaf_path_to_hash;

################################################
sub new {
################################################
    my($class, %options) = @_;

    my $self = { 
        utf8 => 0,
        %options,
    };

    bless $self, $class;

    $self->file($self->{file}) if exists $self->{file};
    $self->text($self->{text}) if exists $self->{text};

    return $self;
}

################################################
sub text {
################################################
    my($self, $text) = @_;

        # $text is an array of scalars (lines)
    if(defined $text) {
        if(ref $text eq "ARRAY") {
            $self->{text} = $text;
        } else {
            $self->{text} = [split "\n", $text];
        }
    }

    return $self->{text};
}

################################################
sub file {
################################################
    my($self, $filename) = @_;

    open my $fh, "$filename" or die "Cannot open $filename ($!)";

    if( $self->{ utf8 } ) {
        binmode $fh, ":utf8";
    }

    $self->file_h_read( $fh );
    close $fh;
}

################################################
sub file_h_read {
################################################
    my($self, $fh) = @_;

        # Dennis Gregorovic <dgregor@redhat.com> added this
        # to protect apps which are tinkering with $/ globally.
    local $/ = "\n";

    $self->{text} = [<$fh>];
}

################################################
sub parse {
################################################
    die __PACKAGE__ . "::parse() is a virtual method. " .
        "It must be implemented " .
        "in a derived class (currently: ", ref(shift), ")";
}

################################################
sub parse_post_process {
################################################
    my($self, $data, $leaf_paths) = @_;
    
    #   [
    #     'category',
    #     'value',
    #     'WARN, Logfile'
    #   ],
    #   [
    #     'appender',
    #     'Logfile',
    #     'value',
    #     'Log::Log4perl::Appender::File'
    #   ],
    #   [
    #     'appender',
    #     'Logfile',
    #     'filename',
    #     'value',
    #     'test.log'
    #   ],
    #   [
    #     'appender',
    #     'Logfile',
    #     'layout',
    #     'value',
    #     'Log::Log4perl::Layout::PatternLayout'
    #   ],
    #   [
    #     'appender',
    #     'Logfile',
    #     'layout',
    #     'ConversionPattern',
    #     'value',
    #     '%d %F{1} %L> %m %n'
    #   ]

    for my $path ( @{ Log::Log4perl::Config::leaf_paths( $data )} ) {

        print "path=@$path\n" if _INTERNAL_DEBUG;

        if(0) {
        } elsif( 
            $path->[0] eq "appender" and
            $path->[2] eq "trigger"
          ) {
            my $ref = leaf_path_to_hash( $path, $data );
            my $code = compile_if_perl( $$ref );

            if(_INTERNAL_DEBUG) {
                if($code) {
                    print "Code compiled: $$ref\n";
                } else {
                    print "Not compiled: $$ref\n";
                }
            }

            $$ref = $code if defined $code;
        } elsif (
            $path->[0] eq "filter"
          ) {
            # do nothing
        } elsif (
            $path->[0] eq "appender" and
            $path->[2] eq "warp_message"
          ) {
            # do nothing
        } elsif (
            $path->[0] eq "appender" and
            $path->[3] eq "cspec" or
            $path->[1] eq "cspec"
          ) {
              # could be either
              #    appender appndr layout cspec
              # or 
              #    PatternLayout cspec U value ...
              #
            # do nothing
        } else {
            my $ref = leaf_path_to_hash( $path, $data );

            if(_INTERNAL_DEBUG) {
                print "Calling eval_if_perl on $$ref\n";
            }

            $$ref = eval_if_perl( $$ref );
        }
    }

    return $data;
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Config::BaseConfigurator - Configurator Base Class

=head1 SYNOPSIS

This is a virtual base class, all configurators should be derived from it.

=head1 DESCRIPTION

=head2 METHODS

=over 4

=item C<< new >>

Constructor, typically called like

    my $config_parser = SomeConfigParser->new(
        file => $file,
    );

    my $data = $config_parser->parse();

Instead of C<file>, the derived class C<SomeConfigParser> may define any 
type of configuration input medium (e.g. C<url =E<gt> 'http://foobar'>).
It just has to make sure its C<parse()> method will later pull the input
data from the medium specified.

The base class accepts a filename or a reference to an array
of text lines:

=over 4

=item C<< file >>

Specifies a file which the C<parse()> method later parses.

=item C<< text >>

Specifies a reference to an array of scalars, representing configuration
records (typically lines of a file). Also accepts a simple scalar, which it 
splits at its newlines and transforms it into an array:

    my $config_parser = MyYAMLParser->new(
        text => ['foo: bar',
                 'baz: bam',
                ],
    );

    my $data = $config_parser->parse();

=back

If either C<file> or C<text> parameters have been specified in the 
constructor call, a later call to the configurator's C<text()> method
will return a reference to an array of configuration text lines.
This will typically be used by the C<parse()> method to process the 
input.

=item C<< parse >>

Virtual method, needs to be defined by the derived class.

=back

=head2 Parser requirements

=over 4

=item *

If the parser provides variable substitution functionality, it has
to implement it.

=item *

The parser's C<parse()> method returns a reference to a hash of hashes (HoH). 
The top-most hash contains the
top-level keywords (C<category>, C<appender>) as keys, associated
with values which are references to more deeply nested hashes.

=item *

The C<log4perl.> prefix (e.g. as used in the PropertyConfigurator class)
is stripped, it's not part in the HoH structure.

=item *

Each Log4perl config value is indicated by the C<value> key, as in

    $data->{category}->{Bar}->{Twix}->{value} = "WARN, Logfile"

=back

=head2 EXAMPLES

The following Log::Log4perl configuration:

    log4perl.category.Bar.Twix        = WARN, Screen
    log4perl.appender.Screen          = Log::Log4perl::Appender::File
    log4perl.appender.Screen.filename = test.log
    log4perl.appender.Screen.layout   = Log::Log4perl::Layout::SimpleLayout

needs to be transformed by the parser's C<parse()> method 
into this data structure:

    { appender => {
        Screen  => {
          layout => { 
            value  => "Log::Log4perl::Layout::SimpleLayout" },
            value  => "Log::Log4perl::Appender::Screen",
        },
      },
      category => { 
        Bar => { 
          Twix => { 
            value => "WARN, Screen" } 
        } }
    }

For a full-fledged example, check out the sample YAML parser implementation 
in C<eg/yamlparser>. It uses a simple YAML syntax to specify the Log4perl 
configuration to illustrate the concept.

=head1 SEE ALSO

Log::Log4perl::Config::PropertyConfigurator

Log::Log4perl::Config::DOMConfigurator

Log::Log4perl::Config::LDAPConfigurator (tbd!)

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

