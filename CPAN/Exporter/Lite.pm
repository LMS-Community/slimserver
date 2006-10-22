package Exporter::Lite;

require 5.004;

# Using strict or vars almost doubles our load time.  Turn them back
# on when debugging.
#use strict 'vars';  # we're going to be doing a lot of sym refs
#use vars qw($VERSION @EXPORT);

$VERSION = 0.01;
@EXPORT = qw(import);   # we'll know pretty fast if it doesn't work :)



sub import {
    my($exporter, @imports)  = @_;
    my($caller, $file, $line) = caller;

    unless( @imports ) {        # Default import.
        @imports = @{$exporter.'::EXPORT'};
    }
    else {
        # Because @EXPORT_OK = () would indicate that nothing is
        # to be exported, we cannot simply check the length of @EXPORT_OK.
        # We must to oddness to see if the variable exists at all as
        # well as avoid autovivification.
        # XXX idea stolen from base.pm, this might be all unnecessary
        my $eokglob;
        if( $eokglob = ${$exporter.'::'}{EXPORT_OK} and *$eokglob{ARRAY} ) {
            if( @{$exporter.'::EXPORT_OK'} ) {
                # This can also be cached.
                my %ok = map { s/^&//; $_ => 1 } @{$exporter.'::EXPORT_OK'},
                                                 @{$exporter.'::EXPORT'};

                my($denied) = grep {s/^&//; !$ok{$_}} @imports;
                _not_exported($denied, $exporter, $file, $line) if $denied;
            }
            else {      # We don't export anything.
                _not_exported($imports[0], $exporter, $file, $line);
            }
        }
    }

    _export($caller, $exporter, @imports);
}



sub _export {
    my($caller, $exporter, @imports) = @_;

    # Stole this from Exporter::Heavy.  I'm sure it can be written better
    # but I'm lazy at the moment.
    foreach my $sym (@imports) {
        # shortcut for the common case of no type character
        (*{$caller.'::'.$sym} = \&{$exporter.'::'.$sym}, next)
            unless $sym =~ s/^(\W)//;

        my $type = $1;
        my $caller_sym = $caller.'::'.$sym;
        my $export_sym = $exporter.'::'.$sym;
        *{$caller_sym} =
            $type eq '&' ? \&{$export_sym} :
            $type eq '$' ? \${$export_sym} :
            $type eq '@' ? \@{$export_sym} :
            $type eq '%' ? \%{$export_sym} :
            $type eq '*' ?  *{$export_sym} :
            do { require Carp; Carp::croak("Can't export symbol: $type$sym") };
    }
}


#"#
sub _not_exported {
    my($thing, $exporter, $file, $line) = @_;
    die sprintf qq|"%s" is not exported by the %s module at %s line %d\n|,
        $thing, $exporter, $file, $line;
}

1;

__END__
=head1 NAME

Exporter::Lite - Lightweight exporting of variables

=head1 SYNOPSIS

  package Foo;
  use Exporter::Lite;

  # Just like Exporter.
  @EXPORT       = qw($This That);
  @EXPORT_OK    = qw(@Left %Right);


  # Meanwhile, in another piece of code!
  package Bar;
  use Foo;  # exports $This and &That.


=head1 DESCRIPTION

This is an alternative to Exporter intended to provide a lightweight
subset of its functionality.  It supports C<import()>, C<@EXPORT> and
C<@EXPORT_OK> and not a whole lot else.

Unlike Exporter, it is not necessary to inherit from Exporter::Lite
(ie. no C<@ISA = qw(Exporter::Lite)> mantra).  Exporter::Lite simply
exports its import() function.  This might be called a "mix-in".

Setting up a module to export its variables and functions is simple:

    package My::Module;
    use Exporter::Lite;

    @EXPORT = qw($Foo bar);

now when you C<use My::Module>, C<$Foo> and C<bar()> will show up.

In order to make exporting optional, use @EXPORT_OK.

    package My::Module;
    use Exporter::Lite;

    @EXPORT_OK = qw($Foo bar);

when My::Module is used, C<$Foo> and C<bar()> will I<not> show up.
You have to ask for them.  C<use My::Module qw($Foo bar)>.

=head1 Methods

Export::Lite has one public method, import(), which is called
automaticly when your modules is use()'d.  

In normal usage you don't have to worry about this at all.

=over 4

=item B<import>

  Some::Module->import;
  Some::Module->import(@symbols);

Works just like C<Exporter::import()> excepting it only honors
@Some::Module::EXPORT and @Some::Module::EXPORT_OK.

The given @symbols are exported to the current package provided they
are in @Some::Module::EXPORT or @Some::Module::EXPORT_OK.  Otherwise
an exception is thrown (ie. the program dies).

If @symbols is not given, everything in @Some::Module::EXPORT is
exported.

=back

=head1 DIAGNOSTICS

=over 4

=item '"%s" is not exported by the %s module'

Attempted to import a symbol which is not in @EXPORT or @EXPORT_OK.

=item 'Can\'t export symbol: %s'

Attempted to import a symbol of an unknown type (ie. the leading $@% salad
wasn't recognized).

=back

=head1 BUGS and CAVEATS

Its not yet clear if this is actually any lighter or faster than
Exporter.  I know its at least on par.

OTOH, the docs are much clearer and not having to say C<@ISA =
qw(Exporter)> is kinda nice.

=head1 AUTHORS

Michael G Schwern <schwern@pobox.com>

=head1 SEE ALSO

L<Exporter>, L<UNIVERSAL::exports>

=cut
