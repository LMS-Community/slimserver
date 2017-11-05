package Net::IDN::Punycode::PP;

use 5.006;

use strict;
use utf8;
use warnings;

use Carp;
use Exporter;

our $VERSION = "1.101";

our @ISA = qw(Exporter);
our @EXPORT = ();
our @EXPORT_OK = qw(encode_punycode decode_punycode);
our %EXPORT_TAGS = ( 'all' => \@EXPORT_OK );

use integer;

use constant BASE => 36;
use constant TMIN => 1;
use constant TMAX => 26;
use constant SKEW => 38;
use constant DAMP => 700;
use constant INITIAL_BIAS => 72;
use constant INITIAL_N => 128;

use constant UNICODE_MIN => 0;
use constant UNICODE_MAX => 0x10FFFF;

my $Delimiter = chr 0x2D;
my $BasicRE   = "\x00-\x7f";
my $PunyRE    = "A-Za-z0-9";

sub _adapt {
    my($delta, $numpoints, $firsttime) = @_;
    $delta = int($firsttime ? $delta / DAMP : $delta / 2);
    $delta += int($delta / $numpoints);
    my $k = 0;
    while ($delta > int(((BASE - TMIN) * TMAX) / 2)) {
	$delta /= BASE - TMIN;
	$k += BASE;
    }
    return $k + (((BASE - TMIN + 1) * $delta) / ($delta + SKEW));
}

sub decode_punycode {
    die("Usage: Net::IDN::Punycode::decode_punycode(input)") unless @_;

    my $input = shift;

    my $n      = INITIAL_N;
    my $i      = 0;
    my $bias   = INITIAL_BIAS;
    my @output;

    return undef unless defined $input;
    return '' unless length $input;

    if($input =~ s/(.*)$Delimiter//os) {
      my $base_chars = $1;
      croak("non-base character in input for decode_punycode")
        if $base_chars =~ m/[^$BasicRE]/os;
      push @output, split //, $base_chars;
    }
    my $code = $input;

    croak('invalid digit in input for decode_punycode') if $code =~ m/[^$PunyRE]/os;

    utf8::downgrade($input);	## handling failure of downgrade is more expensive than
				## doing the above regexp w/ utf8 semantics

    while(length $code)
    {
	my $oldi = $i;
	my $w    = 1;
    LOOP:
	for (my $k = BASE; 1; $k += BASE) {
	    my $cp = substr($code, 0, 1, '');
	    croak("incomplete encoded code point in decode_punycode") if !defined $cp;
	    my $digit = ord $cp;
		
	    ## NB: this depends on the PunyRE catching invalid digit characters
	    ## before they turn up here
	    ##
	    $digit = $digit < 0x40 ? $digit + (26-0x30) : ($digit & 0x1f) -1;

	    $i += $digit * $w;
	    my $t =  $k - $bias;
	    $t = $t < TMIN ? TMIN : $t > TMAX ? TMAX : $t;

	    last LOOP if $digit < $t;
	    $w *= (BASE - $t);
	}
	$bias = _adapt($i - $oldi, @output + 1, $oldi == 0);
	$n += $i / (@output + 1);
	$i = $i % (@output + 1);
	croak('invalid code point') if $n < UNICODE_MIN or $n > UNICODE_MAX;
	splice(@output, $i, 0, chr($n));
	$i++;
    }
    return join '', @output;
}

sub encode_punycode {
    die("Usage: Net::IDN::Punycode::encode_punycode(input)") unless @_;

    my $input = shift;
    my $input_length = length $input;

    ## my $output = join '', $input =~ m/([$BasicRE]+)/og; ## slower
    my $output = $input; $output =~ s/[^$BasicRE]+//ogs;

    my $h = my $bb = length $output;
    $output .= $Delimiter if $bb > 0;
    utf8::downgrade($output);	## no unnecessary use of utf8 semantics

    my @input = map ord, split //, $input;
    my @chars = sort { $a<=> $b } grep { $_ >= INITIAL_N } @input;

    my $n = INITIAL_N;
    my $delta = 0;
    my $bias = INITIAL_BIAS;

    foreach my $m (@chars) {
 	next if $m < $n;
	$delta += ($m - $n) * ($h + 1);
	$n = $m;
	for(my $i = 0; $i < $input_length; $i++)
	{
	    my $c = $input[$i];
	    $delta++ if $c < $n;
	    if ($c == $n) {
		my $q = $delta;
	    LOOP:
		for (my $k = BASE; 1; $k += BASE) {
		    my $t = $k - $bias;
	            $t = $t < TMIN ? TMIN : $t > TMAX ? TMAX : $t;

		    last LOOP if $q < $t;

                    my $o = $t + (($q - $t) % (BASE - $t));
                    $output .= chr $o + ($o < 26 ? 0x61 : 0x30-26);

		    $q = int(($q - $t) / (BASE - $t));
		}
		croak("input exceeds punycode limit") if $q > BASE;
                $output .= chr $q + ($q < 26 ? 0x61 : 0x30-26);

		$bias = _adapt($delta, $h + 1, $h == $bb);
		$delta = 0;
		$h++;
	    }
	}
	$delta++;
	$n++;
    }
    return $output;
}

1;
__END__

=head1 NAME

Net::IDN::Punycode::PP - pure-perl implementation of Net::IDN::Punycode

=head1 DESCRIPTION

See L<Net::IDN::Punycode>.

=head1 AUTHORS

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt> (versions 0.01 to 0.02)

Claus FE<auml>rber E<lt>CFAERBER@cpan.orgE<gt> (from version 1.00)

=head1 LICENSE

Copyright 2002-2004 Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt>

Copyright 2007-2010 Claus FE<auml>rber E<lt>CFAERBER@cpan.orgE<gt>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

S<RFC 3492> (L<http://www.ietf.org/rfc/rfc3492.txt>),
L<IETF::ACE>, L<Convert::RACE>

=cut
