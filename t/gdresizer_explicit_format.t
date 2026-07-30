use strict;
use warnings;

use Test::More;
use MIME::Base64 qw(decode_base64);

use lib '.';

use constant RESIZER => 1;

BEGIN {
	eval { require Image::Scale; 1 } or plan skip_all => 'Image::Scale not available';
}

require Slim::Utils::GDResizer;

# 2x1 PNG to force aspect-ratio mismatch with a square target.
my $png = decode_base64('iVBORw0KGgoAAAANSUhEUgAAACoAAAAtCAMAAADvGAnRAAAAqFBMVEVHcEz8/Pz7+/v6+vr5+fn4+Pj39/f29vb19fX09PTz8/Py8vLx8fHw8PDv7+/u7u7t7e3s7Ozr6+vq6urp6eno6Ojm5ubl5eXk5OTj4+Pi4uLh4eHg4ODf39/e3t7d3d3c3Nzb29va2trZ2dnY2NjX19fW1tbV1dXU1NTS0tLR0dHPz8/Ozs7MzMzLy8vKysrJycnIyMjHx8fFxcW5ubm2tragoKCUlJQSIvveAAAAAXRSTlMAQObYZgAAASBJREFUeNrt1LFKA0EQgOF/dmc5Y2GloqCCaKEEJfHc9+8NEn0ArS3tjuQuOW8JLLlmp0rnN+3fDAMD05g9UyLT46UMnHPi7tuPUho/d6EfhqtFIVWUoXx4u1APYKXewySInYpzCkeCnQ6lgmKnwfmgINipeq8ettipiLCBDouj77dtC21ipN2qaRpoEori2Z5IySyeZPGVonnMRqXpus5uGRPG5fkSZDdPv1+ltF4KKROc4/GdfcqYA2S+mKgCFFMBEZgEsFMRhYnHTp3TABVZ5hgLoaoqkMRINWgIsE2MVMTRwiox0r7frNewToy1uo6kwVRXe2pK7uqQ1S8U3dfZqLSMvqRVXmZxRkkqs+gw3fzkE9j+00Ok36eQHOZL/gGWoVTQy35CqgAAAABJRU5ErkJggg==');

my ($out, $format) = Slim::Utils::GDResizer->resize(
	original => \$png,
	width    => 120,
	height   => 120,
	mode     => 'm',
	format   => 'jpg',
);

ok($out && ref $out eq 'SCALAR' && length($$out), 'resize returned image data');
is($format, 'jpg', 'explicit jpg format is honored even when padding would be needed');

done_testing();
