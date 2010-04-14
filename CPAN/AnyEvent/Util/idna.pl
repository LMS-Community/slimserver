# based on RFC 3492

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use Carp ();
use List::Util ();
use integer;

sub pyc_base         () {  36 }
sub pyc_tmin         () {   1 }
sub pyc_tmax         () {  26 }
sub pyc_initial_bias () {  72 }
sub pyc_initial_n    () { 128 }

sub pyc_digits       () { "abcdefghijklmnopqrstuvwxyz0123456789" }

sub pyc_adapt($$$) {
   my ($delta, $numpoints, $firsttime) = @_;

   $delta = $firsttime ? $delta / 700 : $delta >> 1;
   $delta += $delta / $numpoints;

   my $k;

   while ($delta > (pyc_base - pyc_tmin) * pyc_tmax / 2) {
      $delta /= pyc_base - pyc_tmin;
      $k += pyc_base;
   }

   $k + $delta * (pyc_base - pyc_tmin + 1) / ($delta + 38)
}

sub punycode_encode($) {
   my ($input) = @_;

   my ($n, $bias, $delta) = (pyc_initial_n, pyc_initial_bias);

   (my $output = $input) =~ y/\x00-\x7f//cd;
   my $h = my $b = length $output;

   my @input = split '', $input;

   $output .= "-" if $b && $h < @input;

   while ($h < @input) {
      my $m = List::Util::min grep { $_ >= $n } map ord, @input;

      $m - $n <= (0x7fffffff - $delta) / ($h + 1)
         or Carp::croak "punycode_encode: overflow in punycode delta encoding";
      $delta += ($m - $n) * ($h + 1);
      $n = $m;

      for my $i (@input) {
         my $c = ord $i;
         ++$delta < 0x7fffffff
            or Carp::croak "punycode_encode: overflow in punycode delta encoding"
            if $c < $n;

         if ($c == $n) {
            my ($q, $k) = ($delta, pyc_base);

            while () {
                my $t = List::Util::min pyc_tmax, List::Util::max pyc_tmin, $k - $bias;

                last if $q < $t;

                $output .= substr pyc_digits, $t + (($q - $t) % (pyc_base - $t)), 1;

                $q = ($q - $t) / (pyc_base - $t);
                $k += pyc_base;
            }

            $output .= substr pyc_digits, $q, 1;

            $bias = pyc_adapt $delta, $h + 1, $h == $b;

            $delta = 0;
            ++$h;
         }
      }

      ++$delta;
      ++$n;
   }

   $output
}

sub punycode_decode($) {
   my ($input) = @_;

   my ($n, $bias, $i) = (pyc_initial_n, pyc_initial_bias);
   my $output;

   if ($input =~ /^(.*?)-([^-]*)$/x) {
      $output = $1;
      $input = $2;

      $output =~ /[^\x00-\x7f]/
         and Carp::croak "punycode_decode: malformed punycode";
   }

   while (length $input) {
      my $oldi = $i;
      my $w    = 1;

      for (my $k = pyc_base; ; $k += pyc_base) {
         (my $digit = index pyc_digits, substr $input, 0, 1, "")
            >= 0
            or Carp::croak "punycode_decode: malformed punycode";
      
         $i += $digit * $w;
         
         my $t = List::Util::max pyc_tmin, List::Util::min pyc_tmax, $k - $bias;
         last if $digit < $t;

         $w *= pyc_base - $t;
      }

      my $outlen = 1 + length $output;
      $bias = pyc_adapt $i - $oldi, $outlen, $oldi == 0;

      $n += $i / $outlen;
      $i %=      $outlen;

      substr $output, $i, 0, chr $n;
      ++$i;
   }

   $output
}

1
