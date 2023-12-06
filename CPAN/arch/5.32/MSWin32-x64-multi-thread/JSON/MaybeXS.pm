package JSON::MaybeXS;

use strict;
use warnings FATAL => 'all';
use base qw(Exporter);

our $VERSION = '1.004003';
$VERSION =~ tr/_//d;

sub _choose_json_module {
    return 'Cpanel::JSON::XS' if $INC{'Cpanel/JSON/XS.pm'};
    return 'JSON::XS'         if $INC{'JSON/XS.pm'} && eval { JSON::XS->VERSION(3.0); 1 };

    my @err;

    return 'Cpanel::JSON::XS' if eval { require Cpanel::JSON::XS; 1; };
    push @err, "Error loading Cpanel::JSON::XS: $@";

    return 'JSON::XS' if eval { require JSON::XS; JSON::XS->VERSION(3.0); 1; };
    push @err, "Error loading JSON::XS: $@";

    return 'JSON::PP' if eval { require JSON::PP; 1 };
    push @err, "Error loading JSON::PP: $@";

    die join( "\n", "Couldn't load a JSON module:", @err );

}

BEGIN {
    our $JSON_Class = _choose_json_module();
    $JSON_Class->import(qw(encode_json decode_json));
    no strict 'refs';
    *$_ = $JSON_Class->can($_)
      for qw(true false);
}

our @EXPORT = qw(encode_json decode_json JSON);
my @EXPORT_ALL = qw(is_bool);
our @EXPORT_OK = qw(is_bool to_json from_json);
our %EXPORT_TAGS = ( all => [ @EXPORT, @EXPORT_ALL ],
                     legacy => [ @EXPORT, @EXPORT_OK ],
                   );

sub JSON () { our $JSON_Class }

sub new {
  shift;
  my %args = @_ == 1 ? %{$_[0]} : @_;
  my $new = (our $JSON_Class)->new;
  $new->$_($args{$_}) for keys %args;
  return $new;
}

use Scalar::Util ();

sub is_bool {
  die 'is_bool is not a method' if $_[1];

  Scalar::Util::blessed($_[0])
    and ($_[0]->isa('JSON::XS::Boolean')
      or $_[0]->isa('Cpanel::JSON::XS::Boolean')
      or $_[0]->isa('JSON::PP::Boolean'));
}

# (mostly) CopyPasta from JSON.pm version 2.90
use Carp ();

sub from_json ($@) {
    if ( ref($_[0]) =~ /^JSON/ or $_[0] =~ /^JSON/ ) {
        Carp::croak "from_json should not be called as a method.";
    }
    my $json = JSON()->new;

    if (@_ == 2 and ref $_[1] eq 'HASH') {
        my $opt  = $_[1];
        for my $method (keys %$opt) {
            $json->$method( $opt->{$method} );
        }
    }

    return $json->decode( $_[0] );
}

sub to_json ($@) {
    if (
        ref($_[0]) =~ /^JSON/
        or (@_ > 2 and $_[0] =~ /^JSON/)
          ) {
               Carp::croak "to_json should not be called as a method.";
    }
    my $json = JSON()->new;

    if (@_ == 2 and ref $_[1] eq 'HASH') {
        my $opt  = $_[1];
        for my $method (keys %$opt) {
            $json->$method( $opt->{$method} );
        }
    }

    $json->encode($_[0]);
}

1;

=head1 NAME

JSON::MaybeXS - Use L<Cpanel::JSON::XS> with a fallback to L<JSON::XS> and L<JSON::PP>

=head1 SYNOPSIS

  use JSON::MaybeXS;

  my $data_structure = decode_json($json_input);

  my $json_output = encode_json($data_structure);

  my $json = JSON()->new;

  my $json_with_args = JSON::MaybeXS->new(utf8 => 1); # or { utf8 => 1 }

=head1 DESCRIPTION

This module first checks to see if either L<Cpanel::JSON::XS> or
L<JSON::XS> (at at least version 3.0)
is already loaded, in which case it uses that module. Otherwise
it tries to load L<Cpanel::JSON::XS>, then L<JSON::XS>, then L<JSON::PP>
in order, and either uses the first module it finds or throws an error.

It then exports the C<encode_json> and C<decode_json> functions from the
loaded module, along with a C<JSON> constant that returns the class name
for calling C<new> on.

If you're writing fresh code rather than replacing L<JSON.pm|JSON> usage, you might
want to pass options as constructor args rather than calling mutators, so
we provide our own C<new> method that supports that.

=head1 EXPORTS

C<encode_json>, C<decode_json> and C<JSON> are exported by default; C<is_bool>
is exported on request.

To import only some symbols, specify them on the C<use> line:

  use JSON::MaybeXS qw(encode_json decode_json is_bool); # functions only

  use JSON::MaybeXS qw(JSON); # JSON constant only

To import all available sensible symbols (C<encode_json>, C<decode_json>, and
C<is_bool>), use C<:all>:

  use JSON::MaybeXS ':all';

To import all symbols including those needed by legacy apps that use L<JSON::PP>:

  use JSON::MaybeXS ':legacy';

This imports the C<to_json> and C<from_json> symbols as well as everything in
C<:all>.  NOTE: This is to support legacy code that makes extensive
use of C<to_json> and C<from_json> which you are not yet in a position to
refactor.  DO NOT use this import tag in new code, in order to avoid
the crawling horrors of getting UTF-8 support subtly wrong.  See the
documentation for L<JSON> for further details.

=head2 encode_json

This is the C<encode_json> function provided by the selected implementation
module, and takes a perl data structure which is serialised to JSON text.

  my $json_text = encode_json($data_structure);

=head2 decode_json

This is the C<decode_json> function provided by the selected implementation
module, and takes a string of JSON text to deserialise to a perl data structure.

  my $data_structure = decode_json($json_text);

=head2 to_json, from_json

See L<JSON> for details.  These are included to support legacy code
B<only>.

=head2 JSON

The C<JSON> constant returns the selected implementation module's name for
use as a class name - so:

  my $json_obj = JSON()->new; # returns a Cpanel::JSON::XS or JSON::PP object

and that object can then be used normally:

  my $data_structure = $json_obj->decode($json_text); # etc.

The use of parentheses here is optional, and only used as a hint to the reader
that this use of C<JSON> is a I<subroutine> call, I<not> a class name.

=head2 is_bool

  $is_boolean = is_bool($scalar)

Returns true if the passed scalar represents either C<true> or
C<false>, two constants that act like C<1> and C<0>, respectively
and are used to represent JSON C<true> and C<false> values in Perl.

Since this is a bare sub in the various backend classes, it cannot be called as
a class method like the other interfaces; it must be called as a function, with
no invocant.  It supports the representation used in all JSON backends.

Available since version 1.002004.

=head1 CONSTRUCTOR

=head2 new

With L<JSON::PP>, L<JSON::XS> and L<Cpanel::JSON::XS> you are required to call
mutators to set options, such as:

  my $json = $class->new->utf8(1)->pretty(1);

Since this is a trifle irritating and noticeably un-perlish, we also offer:

  my $json = JSON::MaybeXS->new(utf8 => 1, pretty => 1);

which works equivalently to the above (and in the usual tradition will accept
a hashref instead of a hash, should you so desire).

The resulting object is blessed into the underlying backend, which offers (at
least) the methods C<encode> and C<decode>.

=head1 BOOLEANS

To include JSON-aware booleans (C<true>, C<false>) in your data, just do:

    use JSON::MaybeXS;
    my $true = JSON()->true;
    my $false = JSON()->false;

The booleans are also available as subs or methods on JSON::MaybeXS.

    use JSON::MaybeXS ();
    my $true = JSON::MaybeXS::true;
    my $true = JSON::MaybeXS->true;
    my $false = JSON::MaybeXS::false;
    my $false = JSON::MaybeXS->false;

=head1 CONVERTING FROM JSON::Any

L<JSON::Any> used to be the favoured compatibility layer above the various
JSON backends, but over time has grown a lot of extra code to deal with legacy
backends (e.g. L<JSON::Syck>) that are no longer needed.  This is a rough guide of translating such code:

Change code from:

    use JSON::Any;
    my $json = JSON::Any->new->objToJson($data);    # or to_json($data), or Dump($data)

to:

    use JSON::MaybeXS;
    my $json = encode_json($data);


Change code from:

    use JSON::Any;
    my $data = JSON::Any->new->jsonToObj($json);    # or from_json($json), or Load($json)

to:

    use JSON::MaybeXS;
    my $json = decode_json($data);

=head1 CAVEATS

The C<new()> method in this module is technically a factory, not a
constructor, because the objects it returns will I<NOT> be blessed into the
C<JSON::MaybeXS> class.

If you are using an object returned by this module as a Moo(se) attribute,
this type constraint code:

    is 'json' => ( isa => 'JSON::MaybeXS' );

will I<NOT> do what you expect. Instead, either rely on the C<JSON> class
constant described above, as so:

    is 'json' => ( isa => JSON::MaybeXS::JSON() );

Alternatively, you can use duck typing:

    use Moose::Util::TypeConstraints 'duck_type';
    is 'json' => ( isa => Object , duck_type([qw/ encode decode /]));

=head1 INSTALLATION

At installation time, F<Makefile.PL> will attempt to determine if you have a
working compiler available, and therefore whether you are able to run XS code.
If so, L<Cpanel::JSON::XS> will be added to the prerequisite list, unless
L<JSON::XS> is already installed at a high enough version. L<JSON::XS> may
also be upgraded to fix any incompatibility issues.

Because running XS code is not mandatory and L<JSON::PP> (which is in perl
core) is used as a fallback backend, this module is safe to be used in a suite
of code that is fatpacked or installed into a restricted-resource environment.

You can also prevent any XS dependencies from being installed by setting
C<PUREPERL_ONLY=1> in F<Makefile.PL> options (or in the C<PERL_MM_OPT>
environment variable), or using the C<--pp> or C<--pureperl> flags with the
L<cpanminus client|cpanm>.

=head1 AUTHOR

mst - Matt S. Trout (cpan:MSTROUT) <mst@shadowcat.co.uk>

=head1 CONTRIBUTORS

=over 4

=item * Clinton Gormley <drtech@cpan.org>

=item * Karen Etheridge <ether@cpan.org>

=item * Kieren Diment <diment@gmail.com>

=back

=head1 COPYRIGHT

Copyright (c) 2013 the C<JSON::MaybeXS> L</AUTHOR> and L</CONTRIBUTORS>
as listed above.

=head1 LICENSE

This library is free software and may be distributed under the same terms
as perl itself.

=cut
