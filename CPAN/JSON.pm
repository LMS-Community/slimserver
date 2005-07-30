package JSON;

use strict;
use base qw(Exporter);
use JSON::Parser;
use JSON::Converter;

@JSON::EXPORT = qw(objToJson jsonToObj);

use vars qw($AUTOCONVERT $VERSION
            $ExecCoderef $SkipInvalid $Pretty $Indent $Delimiter);

$VERSION     = 0.99;

$AUTOCONVERT = 1;
$ExecCoderef = 0;
$SkipInvalid = 0;
$Indent      = 2; # (pretty-print)
$Delimiter   = 2; # (pretty-print)  0 => ':', 1 => ': ', 2 => ' : '

my $parser; # JSON => Perl
my $conv;   # Perl => JSON

##############################################################################
# CONSTRCUTOR - JSON objects delegate all processes
#                   to JSON::Converter and JSON::Parser.
##############################################################################

sub new {
	my $class = shift;
	my %opt   = @_;
	bless {
		conv   => undef,  # JSON::Converter [perl => json]
		parser => undef,  # JSON::Parser    [json => perl]
		# below fields are for JSON::Converter
		autoconv    => 1,
		skipinvalid => 0,
		execcoderef => 0,
		pretty      => 0, # pretty-print mode switch
		indent      => 2, # for pretty-print
		delimiter   => 2, # for pretty-print
		# overwrite
		%opt,
	}, $class;
}


##############################################################################
# METHODS
##############################################################################

sub jsonToObj {
	my $self = shift;
	my $js   = shift;

	if(!ref($self)){ # class method
		$js = $self;
		$parser ||= new JSON::Parser;
		$parser->jsonToObj($js);
	}
	else{ # instance method
		$self->{parser} ||= ($parser ||= JSON::Parser->new);
		$self->{parser}->jsonToObj($js);
	}
}


sub objToJson {
	my $self = shift || return;
	my $obj  = shift;

	if(ref($self) !~ /JSON/){ # class method
		my $opt = __PACKAGE__->_getDefaultParms($obj);
		$obj  = $self;
		$conv ||= JSON::Converter->new();
		$conv->objToJson($obj, $opt);
	}
	else{ # instance method
		my $opt = $self->_getDefaultParms($_[0]);
		$self->{conv}
		 ||= JSON::Converter->new( %$opt );
		$self->{conv}->objToJson($obj, $opt);
	}
}


#######################

sub _getDefaultParms {
	my $self = shift;
	my $opt  = shift;
	my $params;

	if(ref($self)){ # instance
		my @names = qw(pretty indent delimiter autoconv);
		my ($pretty, $indent, $delimiter, $autoconv) = @{$self}{ @names };
		$params = {
			pretty => $pretty, indent => $indent,
			delimiter => $delimiter, autoconv => $autoconv,
		};
	}
	else{ # class
		$params = {pretty => $Pretty, indent => $Indent, delimiter => $Delimiter};
	}

	if($opt and ref($opt) eq 'HASH'){ %$params = ( %$opt ); }

	return $params;
}

##############################################################################
# ACCESSOR
##############################################################################

sub autoconv { $_[0]->{autoconv} = $_[1] if(defined $_[1]); $_[0]->{autoconv} }

sub pretty { $_[0]->{pretty} = $_[1] if(defined $_[1]); $_[0]->{pretty} }

sub indent { $_[0]->{indent} = $_[1] if(defined $_[1]); $_[0]->{indent} }

sub delimiter { $_[0]->{delimiter} = $_[1] if(defined $_[1]); $_[0]->{delimiter} }

##############################################################################
# NON STRING DATA
##############################################################################

# See JSON::Parser for JSON::NotString.

sub Number {
	my $num = shift;
	if(!defined $num or $num !~ /^-?(0|[1-9][\d]*)(\.[\d]+)?$/){
		return undef;
	}
	bless {value => $num}, 'JSON::NotString';
}

sub True {
	bless {value => 'true'}, 'JSON::NotString';
}

sub False {
	bless {value => 'false'}, 'JSON::NotString';
}

sub Null {
	bless {value => undef}, 'JSON::NotString';
}

##############################################################################
1;
__END__

=pod

=head1 NAME

JSON - parse and convert to JSON (JavaScript Object Notation).

=head1 SYNOPSIS

 use JSON;
 
 $obj = {
    id   => ["foo", "bar", { aa => 'bb'}],
    hoge => 'boge'
 };
 
 $js  = objToJson($obj);
 # this is {"id":["foo","bar",{"aa":"bb"}],"hoge":"boge"}.
 $obj = jsonToObj($js);
 # the data structure was restored.
 
 # OOP
 
 my $json = new JSON;
 
 $obj = {id => 'foo', method => 'echo', params => ['a','b']}
 $js  = $json->objToJson($obj);
 $obj = $json->jsonToObj($js);
 
 # pretty-printing
 $js = $json->objToJson($obj, {pretty => 1, indent => 2});

 $json = JSON->new(pretty => 1, delimiter => 0);
 $json->objToJson($obj);


=head1 DESCRIPTION

This module converts between JSON (JavaScript Object Notation) and Perl
data structure into each other.
For JSON, See to http://www.crockford.com/JSON/.


=head1 METHODS

=over 4

=item new()

=item new( %options )

returns a JSON object. The object delegates the converting and parsing process
to L<JSON::Converter> and L<JSON::Parser>.

 my $json = new JSON;

C<new> can take some options.

 my $json = new JSON (autoconv => 0, pretty => 1);

Following options are supported:

=over 4

=item autoconv

See L</AUTOCONVERT> for more info.

=item skipinvalid

C<objToJson()> does C<die()> when it encounters any invalid data
(for instance, coderefs). If C<skipinvalid> is set with true,
the function convets these invalid data into JSON format's C<null>.

=item execcoderef

C<objToJson()> does C<die()> when it encounters any code reference.
However, if C<execcoderef> is set with true, executes the coderef
and uses returned value.

=item pretty

See L</PRETY PRINTING> for more info.

=item indent

See L</PRETY PRINTING> for more info.

=item delimiter

See L</PRETY PRINTING> for more info.

=back 


=item objToJson( $object )

=item objToJson( $object, $hashref )

takes perl data structure (basically, they are scalars, arrayrefs and hashrefs)
and returns JSON formated string.

 my $obj = [1, 2, {foo => bar}];
 my $js  = $json->objToJson($obj);
 # [1,2,{"foo":"bar"}]

By default, returned string is one-line. However, you can get pretty-printed
data with C<pretty> option. Please see below L</PRETY PRINTING>.

 my $js  = $json->objToJson($obj, {pretty => 1, indent => 2});
 # [
 #   1,
 #   2,
 #   {
 #     "foo" : "bar"
 #   }
 # ]

=item jsonToObj( $js )

takes a JSON formated data and returns a perl data structure.


=item autoconv()

=item autoconv($bool)

This is an accessor to C<autoconv>. See L</AUTOCONVERT> for more info.

=item pretty()

=item pretty($bool)

This is an accessor to C<pretty>. It takes true or false.
When prrety is true, C<objToJson()> returns prrety-printed string.
See L</PRETY PRINTING> for more info.

=item indent()

=item indent($integer)

This is an accessor to C<indent>.
See L</PRETY PRINTING> for more info.

=item delimiter()

This is an accessor to C<delimiter>.
See L</PRETY PRINTING> for more info.


=back

=head1 MAPPING

 (JSON) {"param" : []}
 ( => Perl) {'param' => []};
 
 (JSON) {"param" : {}}
 ( => Perl) {'param' => {}};
 
 (JSON) {"param" : "string"}
 ( => Perl) {'param' => 'string'};
 
 (JSON) {"param" : null}
 ( => Perl) {'param' => bless( {'value' => undef}, 'JSON::NotString' )};
 
 (JSON) {"param" : true}
 ( => Perl) {'param' => bless( {'value' => 'true'}, 'JSON::NotString' )};
 
 (JSON) {"param" : false}
 ( => Perl) {'param' => bless( {'value' => 'false'}, 'JSON::NotString' )};
 
 (JSON) {"param" : -1.23}
 ( => Perl) {'param' => bless( {'value' => '-1.23'}, 'JSON::NotString' )};

 (JSON) {"param" : 0xff}
 ( => Perl) {'param' => 255};

 (JSON) {"param" : 010}
 ( => Perl) {'param' => 8};

These JSON::NotString objects are overloaded so you don't care about.

Perl's C<undef> is converted to 'null'.


=head1 PRETY PRINTING

If you'd like your JSON output to be pretty-printed, pass the C<pretty>
parameter to objToJson(). You can affect the indentation (which defaults to 2)
by passing the C<indent> parameter to objToJson().

  my $str = $json->objToJson($obj, {pretty => 1, indent => 4});

In addition, you can set some number to C<delimiter> option.
The available numbers are only 0, 1 and 2.
In pretty-printing mode, when C<delimiter> is 1, one space is added
after ':' in object keys. If C<delimiter> is 2, it is ' : ' and
0 is ':' (default is 2). If you give 3 or more to it, the value
is taken as 2.


=head1 AUTOCONVERT

By default, $JSON::AUTOCONVERT is true.

 (Perl) {num => 10.02}
 ( => JSON) {"num" : 10.02}

it is not C<{"num" : "10.02"}>.

But set false value with $JSON::AUTOCONVERT:

 (Perl) {num => 10.02}
 ( => JSON) {"num" : "10.02"}

it is not C<{"num" : 10.02}>.

You can explicitly sepcify:

 $obj = {
 	id     => JSON::Number(10.02),
 	bool1  => JSON::True,
 	bool2  => JSON::False,
 	noval  => JSON::Null,
 };

 $json->objToJson($obj);
 # {"noval" : null, "bool2" : false, "bool1" : true, "id" : 10.02}

C<JSON::Number()> returns C<undef> when an argument invalid format.


=head1 EXPORT

C<objToJson>, C<jsonToObj>.

=head1 TODO

C<JSONRPC::Transport::HTTP::Daemon> in L<JSON> 1.00


=head1 SEE ALSO

L<http://www.crockford.com/JSON/>, L<JSON::Parser>, L<JSON::Converter>


=head1 ACKNOWLEDGEMENTS

SHIMADA pointed out many problems to me.

Mike Castle E<lt>dalgoda[at]ix.netcom.comE<gt> suggested
better packaging way.

Jeremy Muhlich E<lt>jmuhlich[at]bitflood.orgE<gt> help me
escaped character handling in JSON::Parser.

Adam Sussman E<lt>adam.sussman[at]ticketmaster.comE<gt>
suggested the octal and hexadecimal formats as number.

Tatsuhiko Miyagawa E<lt>miyagawa[at]bulknews.netE<gt>
taught a terrible typo and gave some suggestions.

David Wheeler E<lt>david[at]kineticode.comE<gt>
suggested me supporting pretty-printing and
gave a part of L<PRETY PRINTING>.

And Thanks very much to JSON by JSON.org (Douglas Crockford) and
JSON-RPC by http://json-rpc.org/


=head1 AUTHOR

Makamaka Hannyaharamitu, E<lt>makamaka[at]cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2005 by Makamaka Hannyaharamitu

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut


