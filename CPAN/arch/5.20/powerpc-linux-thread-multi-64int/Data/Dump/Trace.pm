package Data::Dump::Trace;

$VERSION = "0.02";

# Todo:
#   - prototypes
#     in/out parameters key/value style
#   - exception
#   - wrap class
#   - configurable colors
#   - show call depth using indentation
#   - show nested calls sensibly
#   - time calls

use strict;

use base 'Exporter';
our @EXPORT_OK = qw(call mcall wrap autowrap trace);

use Carp qw(croak);
use overload ();

my %obj_name;
my %autowrap_class;
my %name_count;

sub autowrap {
    while (@_) {
        my $class = shift;
        my $info = shift;
        $info = { prefix => $info } unless ref($info);
        for ($info->{prefix}) {
            unless ($_) {
                $_ = lc($class);
                s/.*:://;
            }
            $_ = '$' . $_ unless /^\$/;
        }
        $autowrap_class{$class} = $info;
    }
}

sub wrap {
    my %arg = @_;
    my $name = $arg{name} || "func";
    my $func = $arg{func};
    my $proto = $arg{proto};

    return sub {
        call($name, $func, $proto, @_);
    } if $func;

    if (my $obj = $arg{obj}) {
        $name = '$' . $name unless $name =~ /^\$/;
        $obj_name{overload::StrVal($obj)} = $name;
        return bless {
            name => $name,
            obj => $obj,
            proto => $arg{proto},
        }, "Data::Dump::Trace::Wrapper";
    }

    croak("Either the 'func' or 'obj' option must be given");
}

sub trace {
    my($symbol, $prototype) = @_;
    no strict 'refs';
    no warnings 'redefine';
    *{$symbol} = wrap(name => $symbol, func => \&{$symbol}, proto => $prototype);
}

sub call {
    my $name = shift;
    my $func = shift;
    my $proto = shift;
    my $fmt = Data::Dump::Trace::Call->new($name, $proto, \@_);
    if (!defined wantarray) {
        $func->(@_);
        return $fmt->return_void(\@_);
    }
    elsif (wantarray) {
        return $fmt->return_list(\@_, $func->(@_));
    }
    else {
        return $fmt->return_scalar(\@_, scalar $func->(@_));
    }
}

sub mcall {
    my $o = shift;
    my $method = shift;
    my $proto = shift;
    return if $method eq "DESTROY" && !$o->can("DESTROY");
    my $oname = ref($o) ? $obj_name{overload::StrVal($o)} || "\$o" : $o;
    my $fmt = Data::Dump::Trace::Call->new("$oname->$method", $proto, \@_);
    if (!defined wantarray) {
        $o->$method(@_);
        return $fmt->return_void(\@_);
    }
    elsif (wantarray) {
        return $fmt->return_list(\@_, $o->$method(@_));
    }
    else {
        return $fmt->return_scalar(\@_, scalar $o->$method(@_));
    }
}

package Data::Dump::Trace::Wrapper;

sub AUTOLOAD {
    my $self = shift;
    our $AUTOLOAD;
    my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::')+2);
    Data::Dump::Trace::mcall($self->{obj}, $method, $self->{proto}{$method}, @_);
}

package Data::Dump::Trace::Call;

use Term::ANSIColor ();
use Data::Dump ();

*_dump = \&Data::Dump::dump;

our %COLOR = (
    name => "yellow",
    output => "cyan",
    error => "red",
    debug => "red",
);

%COLOR = () unless -t STDOUT;

sub _dumpav {
    return "(" . _dump(@_) . ")" if @_ == 1;
    return _dump(@_);
}

sub _dumpkv {
    return _dumpav(@_) if @_ % 2;
    my %h = @_;
    my $str = _dump(\%h);
    $str =~ s/^\{/(/ && $str =~ s/\}\z/)/;
    return $str;
}

sub new {
    my($class, $name, $proto, $input_args) = @_;
    my $self = bless {
        name => $name,
        proto => $proto,
    }, $class;
    my $proto_arg = $self->proto_arg;
    if ($proto_arg =~ /o/) {
        for (@$input_args) {
            push(@{$self->{input_av}}, _dump($_));
        }
    }
    else {
        $self->{input} = $proto_arg eq "%" ? _dumpkv(@$input_args) : _dumpav(@$input_args);
    }
    return $self;
}

sub proto_arg {
    my $self = shift;
    my($arg, $ret) = split(/\s*=\s*/, $self->{proto} || "");
    $arg ||= '@';
    return $arg;
}

sub proto_ret {
    my $self = shift;
    my($arg, $ret) = split(/\s*=\s*/, $self->{proto} || "");
    $ret ||= '@';
    return $ret;
}

sub color {
    my($self, $category, $text) = @_;
    return $text unless $COLOR{$category};
    return Term::ANSIColor::colored($text, $COLOR{$category});
}

sub print_call {
    my $self = shift;
    my $outarg = shift;
    print $self->color("name", "$self->{name}");
    if (my $input = $self->{input}) {
        $input = "" if $input eq "()" && $self->{name} =~ /->/;
        print $self->color("input", $input);
    }
    else {
        my $proto_arg = $self->proto_arg;
        print "(";
        my $i = 0;
        for (@{$self->{input_av}}) {
            print ", " if $i;
            my $proto = substr($proto_arg, 0, 1, "");
            if ($proto ne "o") {
                print $self->color("input", $_);
            }
            if ($proto eq "o" || $proto eq "O") {
                print " = " if $proto eq "O";
                print $self->color("output", _dump($outarg->[$i]));
            }
        }
        continue {
            $i++;
        }
        print ")";
    }
}

sub return_void {
    my $self = shift;
    my $arg = shift;
    $self->print_call($arg);
    print "\n";
    return;
}

sub return_scalar {
    my $self = shift;
    my $arg = shift;
    $self->print_call($arg);
    my $s = shift;
    my $name;
    my $proto_ret = $self->proto_ret;
    my $wrap = $autowrap_class{ref($s)};
    if ($proto_ret =~ /^\$\w+\z/ && ref($s) && ref($s) !~ /^(?:ARRAY|HASH|CODE|GLOB)\z/) {
        $name = $proto_ret;
    }
    else {
        $name = $wrap->{prefix} if $wrap;
    }
    if ($name) {
        $name .= $name_count{$name} if $name_count{$name}++;
        print " = ", $self->color("output", $name), "\n";
        $s = Data::Dump::Trace::wrap(name => $name, obj => $s, proto => $wrap->{proto});
    }
    else {
        print " = ", $self->color("output", _dump($s));
        if (!$s && $proto_ret =~ /!/ && $!) {
            print " ", $self->color("error", errno($!));
        }
        print "\n";
    }
    return $s;
}

sub return_list {
    my $self = shift;
    my $arg = shift;
    $self->print_call($arg);
    print " = ", $self->color("output", $self->proto_ret eq "%" ? _dumpkv(@_) : _dumpav(@_)), "\n";
    return @_;
}

sub errno {
    my $t = "";
    for (keys %!) {
        if ($!{$_}) {
            $t = $_;
            last;
        }
    }
    my $n = int($!);
    return "$t($n) $!";
}

1;

__END__

=head1 NAME

Data::Dump::Trace - Helpers to trace function and method calls

=head1 SYNOPSIS

  use Data::Dump::Trace qw(autowrap mcall);

  autowrap("LWP::UserAgent" => "ua", "HTTP::Response" => "res");

  use LWP::UserAgent;
  $ua = mcall(LWP::UserAgent => "new");      # instead of LWP::UserAgent->new;
  $ua->get("http://www.example.com")->dump;

=head1 DESCRIPTION

The following functions are provided:

=over

=item autowrap( $class )

=item autowrap( $class => $prefix )

=item autowrap( $class1 => $prefix1,  $class2 => $prefix2, ... )

=item autowrap( $class1 => \%info1, $class2 => \%info2, ... )

Register classes whose objects are are automatically wrapped when
returned by one of the call functions below.  If $prefix is provided
it will be used as to name the objects.

Alternative is to pass an %info hash for each class.  The recognized keys are:

=over

=item prefix => $string

The prefix string used to name objects of this type.

=item proto => \%hash

A hash of prototypes to use for the methods when an object is wrapped.

=back

=item wrap( name => $str, func => \&func, proto => $proto )

=item wrap( name => $str, obj => $obj, proto => \%hash )

Returns a wrapped function or object.  When a wrapped function is
invoked then a trace is printed after the underlying function has returned.
When a method on a wrapped object is invoked then a trace is printed
after the methods on the underlying objects has returned.

See L</"Prototypes"> for description of the C<proto> argument.

=item call( $name, \&func, $proto, @ARGS )

Calls the given function with the given arguments.  The trace will use
$name as the name of the function.

See L</"Prototypes"> for description of the $proto argument.

=item mcall( $class, $method, $proto, @ARGS )

=item mcall( $object, $method, $proto, @ARGS )

Calls the given method with the given arguments.

See L</"Prototypes"> for description of the $proto argument.

=item trace( $symbol, $prototype )

Replaces the function given by $symbol with a wrapped function.

=back

=head2 Prototypes

B<Note: The prototype string syntax described here is experimental and
likely to change in revisions of this interface>.

The $proto argument to call() and mcall() can optionally provide a
prototype for the function call.  This give the tracer hints about how
to best format the argument lists and if there are I<in/out> or I<out>
arguments.  The general form for the prototype string is:

   <arguments> = <return_value>

The default prototype is "@ = @"; list of values as input and list of
values as output.

The value '%' can be used for both arguments and return value to say
that key/value pair style lists are used.

Alternatively, individual positional arguments can be listed each
represented by a letter:

=over

=item C<i>

input argument

=item C<o>

output argument

=item C<O>

both input and output argument

=back

If the return value prototype has C<!> appended, then it signals that
this function sets errno ($!) when it returns a false value.  The
trace will display the current value of errno in that case.

If the return value prototype looks like a variable name (with C<$>
prefix), and the function returns a blessed object, then the variable
name will be used as prefix and the returned object automatically
traced.

=head1 SEE ALSO

L<Data::Dump>

=head1 AUTHOR

Copyright 2009 Gisle Aas.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
