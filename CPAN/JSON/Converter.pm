package JSON::Converter;
##############################################################################

use Carp;

$JSON::Converter::VERSION = 1.00;

##############################################################################

sub new {
    my $class = shift;
    bless {indent => 2, pretty => 0, delimiter => 2, @_}, $class;
}


sub objToJson {
	my $self = shift;
	my $obj  = shift;
	my $opt  = shift;

	local(@{$self}{qw/autoconv execcoderef skipinvalid/});
	local(@{$self}{qw/pretty indent delimiter/});

	$self->_initConvert($opt);

	return $self->toJson($obj);
}


sub toJson {
	my ($self, $obj) = @_;

	if(ref($obj) eq 'HASH'){
		return $self->hashToJson($obj);
	}
	elsif(ref($obj) eq 'ARRAY'){
		return $self->arrayToJson($obj);
	}
	else{
		return;
	}
}


sub hashToJson {
	my $self = shift;
	my $obj  = shift;
	my ($k,$v);
	my %res;

	my ($pre,$post) = $self->_upIndent() if($self->{pretty});

	if(grep { $_ == $obj } @{ $self->{_stack_myself} }){
		die "circle ref!";
	}

	push @{ $self->{_stack_myself} },$obj;

	for my $k (keys %$obj){
		my $v = $obj->{$k};
		if(ref($v) eq "HASH"){
			$res{$k} = $self->hashToJson($v);
		}
		elsif(ref($v) eq "ARRAY"){
			$res{$k} = $self->arrayToJson($v);
		}
		else{
			$res{$k} = $self->valueToJson($v);
		}
	}

	pop @{ $self->{_stack_myself} };

	$self->_downIndent() if($self->{pretty});

	if($self->{pretty}){
		my $del = $self->{_delstr};
		return "{$pre"
		 . join(",$pre", map { _stringfy($_) . $del .$res{$_} } keys %res)
		 . "$post}";
	}
	else{
		return '{'. join(',',map { _stringfy($_) .':' .$res{$_} } keys %res) .'}';
	}

}


sub arrayToJson {
	my $self = shift;
	my $obj  = shift;
	my @res;

	my ($pre,$post) = $self->_upIndent() if($self->{pretty});

	if(grep { $_ == $obj } @{ $self->{_stack_myself} }){
		die "circle ref!";
	}

	push @{ $self->{_stack_myself} },$obj;

	for my $v (@$obj){
		if(ref($v) eq "HASH"){
			push @res,$self->hashToJson($v);
		}
		elsif(ref($v) eq "ARRAY"){
			push @res,$self->arrayToJson($v);
		}
		else{
			push @res,$self->valueToJson($v);
		}
	}

	pop @{ $self->{_stack_myself} };

	$self->_downIndent() if($self->{pretty});

	if($self->{pretty}){
		return "[$pre" . join(",$pre" ,@res) . "$post]";
	}
	else{
		return '[' . join(',' ,@res) . ']';
	}
}


sub valueToJson {
	my $self  = shift;
	my $value = shift;

	return 'null' if(!defined $value);

	if($self->{autoconv} and !ref($value)){
		return $value  if($value =~ /^-?(?:0|[1-9][\d]*)(?:\.[\d]*)?$/);
		return 'true'  if($value =~ /^true$/i);
		return 'false' if($value =~ /^false$/i);
	}

	if(! ref($value) ){
		return _stringfy($value)
	}
	elsif($self->{execcoderef} and ref($value) eq 'CODE'){
		my $ret = $value->();
		return 'null' if(!defined $ret);
		return $self->toJson($ret) if(ref($ret));
		return _stringfy($ret);
	}
	elsif( ! UNIVERSAL::isa($value, 'JSON::NotString') ){
		die "Invalid value" unless($self->{skipinvalid});
		return 'null';
	}

	return defined $value->{value} ? $value->{value} : 'null';
}


%esc = (
	"\n" => '\n',
	"\r" => '\r',
	"\t" => '\t',
	"\f" => '\f',
	"\b" => '\b',
	"\"" => '\"',
	"\\" => '\\\\',
);


sub _stringfy {
	my $arg = shift;
	$arg =~ s/([\\"\n\r\t\f\b])/$esc{$1}/eg;
	$arg =~ s/([\x00-\x07\x0b\x0e-\x1f])/'\\u00' . unpack('H2',$1)/eg;
	return '"' . $arg . '"';
}


##############################################################################

sub _initConvert {
	my $self = shift;
	my %opt  = %{ $_[0] } if(@_ > 0 and ref($_[0]) eq 'HASH');

	$self->{autoconv}    = $JSON::AUTOCONVERT if(!defined $self->{autoconv});
	$self->{execcoderef} = $JSON::ExecCoderef if(!defined $self->{execcoderef});
	$self->{skipinvalid} = $JSON::SkipInvalid if(!defined $self->{skipinvalid});

	$self->{pretty}      =  $JSON::Pretty    if(!defined $self->{pretty});
	$self->{indent}      =  $JSON::Indent    if(!defined $self->{indent});
	$self->{delimiter}   =  $JSON::Delimiter if(!defined $self->{delimiter});

	for my $name (qw/autoconv execcoderef skipinvalid pretty indent delimiter/){
		$self->{$name} = $opt{$name} if(defined $opt{$name});
	}

	$self->{_stack_myself} = [];
	$self->{indent_count}  = 0;

	$self->{_delstr} = 
		$self->{delimiter} ? ($self->{delimiter} == 1 ? ': ' : ' : ') : ':';

	$self;
}


sub _upIndent {
	my $self  = shift;
	my $space = ' ' x $self->{indent};
	my ($pre,$post) = ('','');

	$post = "\n" . $space x $self->{indent_count};

	$self->{indent_count}++;

	$pre = "\n" . $space x $self->{indent_count};

	return ($pre,$post);
}


sub _downIndent { $_[0]->{indent_count}--; }

##############################################################################
1;
__END__


=head1 METHODs

=over

=item parse

alias of C<objToJson>.

=item objToJson

convert a passed perl data structure into JSON object.
can't parse bleesed object.

=item hashToJson

convert a passed hash into JSON object.

=item arrayToJson

convert a passed array into JSON array.

=item valueToJson

convert a passed data into a string of JSON.

=back

=head1 COPYRIGHT

makamaka [at] donzoko.net

This library is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<http://www.crockford.com/JSON/index.html>

=cut
