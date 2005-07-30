package JSON::Parser;

#
# Perl implementaion of json.js
#  http://www.crockford.com/JSON/json.js
#

use vars qw($VERSION);
use strict;

$VERSION     = 0.932;

my %escapes = ( #  by Jeremy Muhlich <jmuhlich [at] bitflood.org>
  b    => "\x8",
  t    => "\x9",
  n    => "\xA",
  f    => "\xC",
  r    => "\xD",
#  '/'  => '/',
  '\\' => '\\',
);


sub new {
	my $class = shift;
	my $self  = {};
	bless $self,$class;
}


*jsonToObj = \&parse;


{ # PARSE 

	my $text;
	my $at;
	my $ch;
	my $len;

	sub parse {
		my $self = shift;
		$text = shift;
		$at   = 0;
		$ch   = '';
		$len  = length $text;
		value();
	}


	sub next_chr {
		return $ch = undef if($at >= $len);
		$ch = substr($text, $at++, 1);
	}


	sub value {
		white();
		return object() if($ch eq '{');
		return array()  if($ch eq '[');
		return string() if($ch eq '"');
		return number() if($ch eq '-');
		return $ch =~ /\d/ ? number() : word();
	}


	sub string {
		my ($i,$s,$t,$u);
		$s = '';

		if($ch eq '"'){
			OUTER: while( defined(next_chr()) ){
				if($ch eq '"'){
					next_chr();
					return $s;
				}
				elsif($ch eq '\\'){
					next_chr();
					if(exists $escapes{$ch}){
						$s .= $escapes{$ch};
					}
					elsif($ch eq 'u'){
						my $u = '';
						for(1..4){
							$ch = next_chr();
							last OUTER if($ch !~ /[\da-fA-F]/);
							$u .= $ch;
						}
						$u =~ s/^00// or error("Bad string");
						$s .= pack('H2',$u);
					}
					else{
						$s .= $ch;
					}
				}
				else{
					$s .= $ch;
				}
			}
		}

		error("Bad string");
	}


	sub white {
		while( defined $ch  ){
			if($ch le ' '){
				next_chr();
			}
			elsif($ch eq '/'){
				next_chr();
				if($ch eq '/'){
					1 while(defined(next_chr()) and $ch ne "\n" and $ch ne "\r");
				}
				elsif($ch eq '*'){
					next_chr();
					while(1){
						if(defined $ch){
							if($ch eq '*'){
								if(defined(next_chr()) and $ch eq '/'){
									next_chr();
									last;
								}
							}
							else{
								next_chr();
							}
						}
						else{
							error("Unterminated comment");
						}
					}
					next;
				}
				else{
					error("Syntax error (whitespace)");
				}
			}
			else{
				last;
			}
		}
	}


	sub object {
		my $o = {};
		my $k;

		if($ch eq '{'){
			next_chr();
			white();
			if($ch eq '}'){
				next_chr();
				return $o;
			}
			while(defined $ch){
				$k = string();
				white();

				if($ch ne ':'){
					last;
				}

				next_chr();
				$o->{$k} = value();
				white();

				if($ch eq '}'){
					next_chr();
					return $o;
				}
				elsif($ch ne ','){
					last;
				}
				next_chr();
				white();
			}

			error("Bad object");
		}
	}


	sub word {
		my $word =  substr($text,$at-1,4);

		if($word eq 'true'){
			$at += 3;
			next_chr;
			return bless {value => 'true'}, 'JSON::NotString'
		}
		elsif($word eq 'null'){
			$at += 3;
			next_chr;
			#return bless {value => undef}, 'JSON::NotString'
			return '';
		}
		elsif($word eq 'fals'){
			$at += 3;
			if(substr($text,$at,1) eq 'e'){
				$at++;
				next_chr;
				return bless {value => 'false'}, 'JSON::NotString'
			}
		}

		error("Syntax error (word)");
	}


	sub number {
		my $n    = '';
		my $v;

		if($ch eq '0'){
			my $peek = substr($text,$at,1);
			my $hex  = $peek =~ /[xX]/;

			if($hex){
				($n) = ( substr($text, $at+1) =~ /^([0-9a-fA-F]+)/);
			}
			else{
				($n) = ( substr($text, $at) =~ /^([0-7]+)/);
			}

			if(defined $n and length($n)){
				$at += length($n) + $hex;
				next_chr;
				return $hex ? hex($n) : oct($n);
			}
		}

		if($ch eq '-'){
			$n = '-';
			next_chr;
		}

		while($ch =~ /\d/){
			$n .= $ch;
			next_chr;
		}

		if($ch eq '.'){
			$n .= '.';
			while(defined(next_chr) and $ch =~ /\d/){
				$n .= $ch;
			}
		}

		$v .= $n;

		return $v;
	}


	sub array {
		my $a  = [];

		if($ch eq '['){
			next_chr();
			white();
			if($ch eq ']'){
				next_chr();
				return $a;
			}
			while(defined($ch)){
				push @$a, value();
				white();
				if($ch eq ']'){
					next_chr();
					return $a;
				}
				elsif($ch ne ','){
					last;
				}
				next_chr();
				white();
			}
		}

		error("Bad array");
	}


	sub error {
		my $error = shift;
		die "$error at $at in $text.";
	}

} # PARSE



package JSON::NotString;

use overload (
	'""'   => sub { $_[0]->{value} },
	'bool' => sub {
		  ! defined $_[0]->{value}  ? undef
		: $_[0]->{value} eq 'false' ? 0 : 1;
	},
);

1;

__END__

=head1 SEE ALSO

L<http://www.crockford.com/JSON/index.html>

This module is an implementation of L<http://www.crockford.com/JSON/json.js>.


=head1 COPYRIGHT

makamaka [at] donzoko.net

This library is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

=cut
