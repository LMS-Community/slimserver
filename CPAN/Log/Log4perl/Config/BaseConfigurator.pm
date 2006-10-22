package Log::Log4perl::Config::BaseConfigurator;

use warnings;
use strict;

################################################
sub new {
################################################
    my($class, %options) = @_;

    my $self = { 
        %options,
               };

    $self->file($self->{file}) if exists $self->{file};
    $self->text($self->{text}) if exists $self->{text};

    bless $self, $class;
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

    open FILE, "<$filename" or die "Cannot open $filename ($!)";
    $self->{text} = [<FILE>];
    close FILE;
}

################################################
sub parse {
################################################
    die __PACKAGE__ . "::parse() is a virtual method. " .
        "It must be implemented " .
        "in a derived class (currently: ", ref(shift), ")";
}

1;

__END__

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

=head1 AUTHOR

Mike Schilli, <m@perlmeister.com>, 2004
Kevin Goess, <cpan@goess.org> Jan-2003

=cut
