########################################################################
package		# hide from PAUSE
	DBI;
# vim: ts=8:sw=4
########################################################################
#
# Copyright (c) 2002,2003  Tim Bunce  Ireland.
#
# See COPYRIGHT section in DBI.pm for usage and distribution rights.
#
########################################################################
#
# Please send patches and bug reports to
#
# Jeff Zucker <jeff@vpservices.com>  with cc to <dbi-dev@perl.org>
#
########################################################################

# TODO:
#	recheck code against DBI

use strict;
use Carp;
require Symbol;

$DBI::PurePerl = $ENV{DBI_PUREPERL} || 1;
$DBI::PurePerl::VERSION = sprintf "%d.%02d", '$Revision: 1.1 $ ' =~ /(\d+)\.(\d+)/;
$DBI::neat_maxlen ||= 400;

$DBI::tfh = Symbol::gensym();
open $DBI::tfh, ">&STDERR" or warn "Can't dup STDERR: $!";


%DBI::last_method_except = map { $_=>1 } qw(DESTROY _set_fbav set_err);

use constant SQL_ALL_TYPES => 0;
use constant SQL_ARRAY => 50;
use constant SQL_ARRAY_LOCATOR => 51;
use constant SQL_BINARY => (-2);
use constant SQL_BIT => (-7);
use constant SQL_BLOB => 30;
use constant SQL_BLOB_LOCATOR => 31;
use constant SQL_BOOLEAN => 16;
use constant SQL_CHAR => 1;
use constant SQL_CLOB => 40;
use constant SQL_CLOB_LOCATOR => 41;
use constant SQL_DATE => 9;
use constant SQL_DATETIME => 9;
use constant SQL_DECIMAL => 3;
use constant SQL_DOUBLE => 8;
use constant SQL_FLOAT => 6;
use constant SQL_GUID => (-11);
use constant SQL_INTEGER => 4;
use constant SQL_INTERVAL => 10;
use constant SQL_INTERVAL_DAY => 103;
use constant SQL_INTERVAL_DAY_TO_HOUR => 108;
use constant SQL_INTERVAL_DAY_TO_MINUTE => 109;
use constant SQL_INTERVAL_DAY_TO_SECOND => 110;
use constant SQL_INTERVAL_HOUR => 104;
use constant SQL_INTERVAL_HOUR_TO_MINUTE => 111;
use constant SQL_INTERVAL_HOUR_TO_SECOND => 112;
use constant SQL_INTERVAL_MINUTE => 105;
use constant SQL_INTERVAL_MINUTE_TO_SECOND => 113;
use constant SQL_INTERVAL_MONTH => 102;
use constant SQL_INTERVAL_SECOND => 106;
use constant SQL_INTERVAL_YEAR => 101;
use constant SQL_INTERVAL_YEAR_TO_MONTH => 107;
use constant SQL_LONGVARBINARY => (-4);
use constant SQL_LONGVARCHAR => (-1);
use constant SQL_MULTISET => 55;
use constant SQL_MULTISET_LOCATOR => 56;
use constant SQL_NUMERIC => 2;
use constant SQL_REAL => 7;
use constant SQL_REF => 20;
use constant SQL_ROW => 19;
use constant SQL_SMALLINT => 5;
use constant SQL_TIME => 10;
use constant SQL_TIMESTAMP => 11;
use constant SQL_TINYINT => (-6);
use constant SQL_TYPE_DATE => 91;
use constant SQL_TYPE_TIME => 92;
use constant SQL_TYPE_TIMESTAMP => 93;
use constant SQL_TYPE_TIMESTAMP_WITH_TIMEZONE => 95;
use constant SQL_TYPE_TIME_WITH_TIMEZONE => 94;
use constant SQL_UDT => 17;
use constant SQL_UDT_LOCATOR => 18;
use constant SQL_UNKNOWN_TYPE => 0;
use constant SQL_VARBINARY => (-3);
use constant SQL_VARCHAR => 12;
use constant SQL_WCHAR => (-8);
use constant SQL_WLONGVARCHAR => (-10);
use constant SQL_WVARCHAR => (-9);

# for Cursor types
use constant SQL_CURSOR_FORWARD_ONLY  => 0;
use constant SQL_CURSOR_KEYSET_DRIVEN => 1;
use constant SQL_CURSOR_DYNAMIC       => 2;
use constant SQL_CURSOR_STATIC        => 3;
use constant SQL_CURSOR_TYPE_DEFAULT  => SQL_CURSOR_FORWARD_ONLY;

use constant IMA_HAS_USAGE	=> 0x0001; #/* check parameter usage	*/
use constant IMA_FUNC_REDIRECT	=> 0x0002; #/* is $h->func(..., "method")*/
use constant IMA_KEEP_ERR	=> 0x0004; #/* don't reset err & errstr	*/
use constant IMA_KEEP_ERR_SUB	=> 0x0008; #/*  '' if in nested call */
use constant IMA_NO_TAINT_IN   	=> 0x0010; #/* don't check for tainted args*/
use constant IMA_NO_TAINT_OUT   => 0x0020; #/* don't taint results	*/
use constant IMA_COPY_STMT   	=> 0x0040; #/* copy sth Statement to dbh */
use constant IMA_END_WORK	=> 0x0080; #/* set on commit & rollback	*/
use constant IMA_STUB		=> 0x0100; #/* donothing eg $dbh->connected */
#define IMA_CLEAR_STMT             0x0200  /* clear Statement before call  */
#define IMA_PROF_EMPTY_STMT        0x0400  /* profile as empty Statement   */
use constant IMA_NOT_FOUND_OKAY	=> 0x0800; #/* not error if not found */
use constant IMA_EXECUTE	=> 0x1000; #/* do/execute: DBIcf_Executed   */

my %is_flag_attribute = map {$_ =>1 } qw(
	Active
	AutoCommit
	ChopBlanks
	CompatMode
	Executed
	Taint
	TaintIn
	TaintOut
	InactiveDestroy
	LongTruncOk
	MultiThread
	PrintError
	PrintWarn
	RaiseError
	ShowErrorStatement
	Warn
);
my %is_valid_attribute = map {$_ =>1 } (keys %is_flag_attribute, qw(
	ActiveKids
	Attribution
	BegunWork
	CachedKids
	CursorName
	Database
	DebugDispatch
	Driver
	ErrCount
	FetchHashKeyName
	HandleError
	HandleSetErr
	ImplementorClass
	Kids
	LongReadLen
	NAME NAME_uc NAME_lc NAME_uc_hash NAME_lc_hash
	NULLABLE
	NUM_OF_FIELDS
	NUM_OF_PARAMS
	Name
	PRECISION
	ParamValues
	Profile
	Provider
	RootClass
	RowCacheSize
	RowsInCache
	SCALE
	Statement
	TYPE
	TraceLevel
	Username
	Version
));

sub valid_attribute {
    my $attr = shift;
    return 1 if $is_valid_attribute{$attr};
    return 1 if $attr =~ m/^[a-z]/; # starts with lowercase letter
    return 0
}

my $initial_setup;
sub initial_setup {
    $initial_setup = 1;
    print $DBI::tfh  __FILE__ . " version " . $DBI::PurePerl::VERSION . "\n"
	if $DBI::dbi_debug & 0xF;
    untie $DBI::err;
    untie $DBI::errstr;
    untie $DBI::state;
    untie $DBI::rows;
    #tie $DBI::lasth,  'DBI::var', '!lasth';  # special case: return boolean
}

sub  _install_method {
    my ( $caller, $method, $from, $param_hash ) = @_;
    initial_setup() unless $initial_setup;

    my ($class, $method_name) = $method =~ /^[^:]+::(.+)::(.+)$/;
    my $bitmask = $param_hash->{'O'} || 0;
    my @pre_call_frag;

    return if $method_name eq 'can';

    push @pre_call_frag, q{
	return if $h_inner; # ignore DESTROY for outer handle
	# copy err/errstr/state up to driver so $DBI::err etc still work
	if ($h->{err} and my $drh = $h->{Driver}) {
	    $drh->{$_} = $h->{$_} for ('err','errstr','state');
	}
    } if $method_name eq 'DESTROY';

    push @pre_call_frag, q{
	return $h->{$_[0]} if exists $h->{$_[0]};
    } if $method_name eq 'FETCH' && !exists $ENV{DBI_TRACE}; # XXX ?

    push @pre_call_frag, "return;"
	if IMA_STUB & $bitmask;

    push @pre_call_frag, q{
	#$method_name = $imp . '::' . pop @_;
	$method_name = pop @_;
    } if IMA_FUNC_REDIRECT & $bitmask;

    push @pre_call_frag, q{
	my $parent_dbh = $h->{Database};
    } if (IMA_COPY_STMT|IMA_EXECUTE) & $bitmask;

    push @pre_call_frag, q{
	warn "No Database set for $h on $method_name!" unless $parent_dbh; # eg proxy problems
	$parent_dbh->{Statement} = $h->{Statement} if $parent_dbh;
    } if IMA_COPY_STMT & $bitmask;

    push @pre_call_frag, q{
	$h->{Executed} = 1;
	$parent_dbh->{Executed} = 1 if $parent_dbh;
    } if IMA_EXECUTE & $bitmask;

    if (IMA_KEEP_ERR & $bitmask) {
	push @pre_call_frag, q{
	    my $keep_error = 1;
	};
    }
    else {
	my $ke_init = (IMA_KEEP_ERR_SUB & $bitmask)
		? q{= $h->{_parent}->{_call_depth} }
		: "";
	push @pre_call_frag, qq{
	    my \$keep_error $ke_init;
	};
	my $keep_error_code = q{
	    #warn "$method_name cleared err";
	    $h->{err}    = $DBI::err    = undef;
	    $h->{errstr} = $DBI::errstr = undef;
	    $h->{state}  = $DBI::state  = '';
	};
	$keep_error_code = q{
	    printf $DBI::tfh "    !! %s: %s CLEARED by call to }.$method_name.q{ method\n".
		    $h->{err}, $h->{err}
		if defined $h->{err} && $DBI::dbi_debug & 0xF;
	}. $keep_error_code
	    if exists $ENV{DBI_TRACE};
	push @pre_call_frag, ($ke_init)
		? qq{ unless (\$keep_error) { $keep_error_code }}
		: $keep_error_code
	    unless $method_name eq 'set_err';
    }

    push @pre_call_frag, q{
	my $ErrCount = $h->{ErrCount};
    };

    push @pre_call_frag, q{
        if (($DBI::dbi_debug & 0xF) >= 2) {
	    local $^W;
	    my $args = join " ", map { DBI::neat($_) } ($h, @_);
	    printf $DBI::tfh "    > $method_name in $imp ($args) [$@]\n";
	}
    } if exists $ENV{DBI_TRACE};	# note use of 'exists'

    push @pre_call_frag, q{
        $h->{'_last_method'} = $method_name;
    } unless exists $DBI::last_method_except{$method_name};

    # --- post method call code fragments ---
    my @post_call_frag;

    push @post_call_frag, q{
        if (my $trace_level = ($DBI::dbi_debug & 0xF)) {
	    if ($h->{err}) {
		printf $DBI::tfh "    !! ERROR: %s %s\n", $h->{err}, $h->{errstr};
	    }
	    my $ret = join " ", map { DBI::neat($_) } @ret;
	    my $msg = "    < $method_name= $ret";
	    $msg = ($trace_level >= 2) ? Carp::shortmess($msg) : "$msg\n";
	    print $DBI::tfh $msg;
	}
    } if exists $ENV{DBI_TRACE}; # note use of exists

    push @post_call_frag, q{
	$h->{Executed} = 0;
	if ($h->{BegunWork}) {
	    $h->{BegunWork}  = 0;
	    $h->{AutoCommit} = 1;
	}
    } if IMA_END_WORK & $bitmask;

    push @post_call_frag, q{
	$keep_error = 0 if $keep_error && $h->{ErrCount} > $ErrCount;

        if ( !$keep_error
	&& defined(my $err = $h->{err})
	&& ($call_depth <= 1 && !$h->{_parent}{_call_depth})
	) {

	    my($pe,$pw,$re,$he) = @{$h}{qw(PrintError PrintWarn RaiseError HandleError)};
	    my $msg;

	    if ($err && ($pe || $re || $he)	# error
	    or (!$err && length($err) && $pw)	# warning
	    ) {
		my $last = ($DBI::last_method_except{$method_name})
		    ? ($h->{'_last_method'}||$method_name) : $method_name;
		my $errstr = $h->{errstr} || $DBI::errstr || $err || '';
		my $msg = sprintf "%s %s %s: %s", $imp, $last,
			($err eq "0") ? "warning" : "failed", $errstr;

		if ($h->{'ShowErrorStatement'} and my $Statement = $h->{Statement}) {
		    $msg .= ' for [``' . $Statement . "''";
		    if (my $ParamValues = $h->FETCH('ParamValues')) {
			my $pv_idx = 0;
			$msg .= " with params: ";
			while ( my($k,$v) = each %$ParamValues ) {
			    $msg .= sprintf "%s%s=%s", ($pv_idx++==0) ? "" : ", ", $k, DBI::neat($v);
			}
		    }
		    $msg .= "]";
		}
		if ($DBI::err eq "0") { # is 'warning' (not info)
		    carp $msg if $pw;
		}
		else {
		    my $do_croak = 1;
		    if (my $subsub = $h->{'HandleError'}) {
			$do_croak = 0 if &$subsub($msg,$h,$ret[0]);
		    }
		    if ($do_croak) {
			printf $DBI::tfh "    $method_name has failed ($h->{PrintError},$h->{RaiseError})\n"
				if ($DBI::dbi_debug & 0xF) >= 4;
			carp  $msg if $pe;
			die $msg if $h->{RaiseError};
		    }
		}
	    }
	}
    };


    my $method_code = q[
      sub {
        my $h = shift;
	my $h_inner = tied(%$h);
	$h = $h_inner if $h_inner;

        my $imp;
	if ($method_name eq 'DESTROY') {
	    # during global destruction, $h->{...} can trigger "Can't call FETCH on an undef value"
	    # implying that tied() above lied to us, so we need to use eval
	    local $@;	 # protect $@
	    $imp = eval { $h->{"ImplementorClass"} } or return; # probably global destruction
	}
	else {
	    $imp = $h->{"ImplementorClass"} or return; # probably global destruction
	}

	] . join("\n", '', @pre_call_frag, '') . q[

	my $call_depth = $h->{'_call_depth'} + 1;
	local ($h->{'_call_depth'}) = $call_depth;

	my @ret;
        my $sub = $imp->can($method_name);
	if ($sub) {
	    (wantarray) ? (@ret = &$sub($h,@_)) : (@ret = scalar &$sub($h,@_));
	}
	else {
	    # XXX could try explicit fallback to $imp->can('AUTOLOAD') etc
	    # which would then let Multiplex pass PurePerl tests, but some
	    # hook into install_method may be better.
	    croak "Can't find DBI method $method_name for $h (via $imp)"
		if ] . ((IMA_NOT_FOUND_OKAY & $bitmask) ? 0 : 1) . q[;
	}

	] . join("\n", '', @post_call_frag, '') . q[

	return (wantarray) ? @ret : $ret[0];
      }
    ];
    no strict qw(refs);
    my $code_ref = eval qq{#line 1 "$method"\n$method_code};
    warn "$@\n$method_code\n" if $@;
    die "$@\n$method_code\n" if $@;
    *$method = $code_ref;
    if (0 && $method =~ /set_err/) { # debuging tool
	my $l=0; # show line-numbered code for method
	warn "*$method = ".join("\n", map { ++$l.": $_" } split/\n/,$method_code);
    }
}

sub _setup_handle {
    my($h, $imp_class, $parent, $imp_data) = @_;
    my $h_inner = tied(%$h) || $h;
    if (($DBI::dbi_debug & 0xF) >= 4) {
	local $^W;
	print $DBI::tfh "      _setup_handle(@_)\n";
    }
    $h_inner->{"imp_data"} = $imp_data;
    $h_inner->{"ImplementorClass"} = $imp_class;
    $h_inner->{"Kids"} = $h_inner->{"ActiveKids"} = 0;	# XXX not maintained
    if ($parent) {
	foreach (qw(
	    RaiseError PrintError PrintWarn HandleError HandleSetErr
	    Warn LongTruncOk ChopBlanks AutoCommit
	    ShowErrorStatement FetchHashKeyName LongReadLen CompatMode
	)) {
	    $h_inner->{$_} = $parent->{$_}
		if exists $parent->{$_} && !exists $h_inner->{$_};
	}
	if (ref($parent) =~ /::db$/) {
	    $h_inner->{Database} = $parent;
	    $parent->{Statement} = $h_inner->{Statement};
	    $h_inner->{NUM_OF_PARAMS} = 0;
	}
	elsif (ref($parent) =~ /::dr$/){
	    $h_inner->{Driver} = $parent;
	}
	$h_inner->{_parent} = $parent;
    }
    else {	# setting up a driver handle
        $h_inner->{Warn}		= 1;
        $h_inner->{PrintWarn}		= $^W;
        $h_inner->{AutoCommit}		= 1;
        $h_inner->{TraceLevel}		= 0;
        $h_inner->{CompatMode}		= (1==0);
	$h_inner->{FetchHashKeyName}	||= 'NAME';
	$h_inner->{LongReadLen}		||= 80;
    }
    $h_inner->{"_call_depth"} = 0;
    $h_inner->{ErrCount} = 0;
    $h_inner->{Active} = 1;
}
sub constant {
    warn "constant @_"; return;
}
sub trace {
    my ($h, $level, $file) = @_;
    $level = $h->parse_trace_flags($level)
	if defined $level and !DBI::looks_like_number($level);
    my $old_level = $DBI::dbi_debug;
    _set_trace_file($file);
    if (defined $level) {
	$DBI::dbi_debug = $level;
	print $DBI::tfh "    DBI $DBI::VERSION (PurePerl) "
                . "dispatch trace level set to $DBI::dbi_debug\n"
		if $DBI::dbi_debug & 0xF;
        if ($level==0 and fileno($DBI::tfh)) {
	    _set_trace_file("");
        }
    }
    return $old_level;
}
sub _set_trace_file {
    my ($file) = @_;
    return unless defined $file;
    if (!$file || $file eq 'STDERR') {
	open $DBI::tfh, ">&STDERR" or warn "Can't dup STDERR: $!";
	return 1;
    }
    if ($file eq 'STDOUT') {
	open $DBI::tfh, ">&STDOUT" or warn "Can't dup STDOUT: $!";
	return 1;
    }
    open $DBI::tfh, ">>$file" or carp "Can't open $file: $!";
    select((select($DBI::tfh), $| = 1)[0]);
    return 1;
}
sub _get_imp_data {  shift->{"imp_data"}; }
sub _svdump       { }
sub dump_handle   {
    my ($h,$msg,$level) = @_;
    $msg||="dump_handle $h";
    print $DBI::tfh "$msg:\n";
    for my $attrib (sort keys %$h) {
	print $DBI::tfh "\t$attrib => ".DBI::neat($h->{$attrib})."\n";
    }
}

sub _handles {
    my $h = shift;
    my $h_inner = tied %$h;
    if ($h_inner) {	# this is okay
	return $h unless wantarray;
	return ($h, $h_inner);
    }
    # XXX this isn't okay... we have an inner handle but
    # currently have no way to get at its outer handle,
    # so we just warn and return the inner one for both...
    Carp::carp("Can't return outer handle from inner handle using DBI::PurePerl");
    return $h unless wantarray;
    return ($h,$h);
}

sub hash {
    my ($key, $type) = @_;
    my ($hash);
    if (!$type) {
        $hash = 0;
        # XXX The C version uses the "char" type, which could be either
        # signed or unsigned.  I use signed because so do the two
        # compilers on my system.
        for my $char (unpack ("c*", $key)) {
            $hash = $hash * 33 + $char;
        }
        $hash &= 0x7FFFFFFF;    # limit to 31 bits
        $hash |= 0x40000000;    # set bit 31
        return -$hash;          # return negative int
    }
    elsif ($type == 1) {	# Fowler/Noll/Vo hash
        # see http://www.isthe.com/chongo/tech/comp/fnv/
        require Math::BigInt;   # feel free to reimplement w/o BigInt!
	my $version = $Math::BigInt::VERSION || 0;
	if ($version >= 1.56) {
	    $hash = Math::BigInt->new(0x811c9dc5);
	    for my $uchar (unpack ("C*", $key)) {
		# multiply by the 32 bit FNV magic prime mod 2^64
		$hash = ($hash * 0x01000193) & 0xffffffff;
		# xor the bottom with the current octet
		$hash ^= $uchar;
	    }
	    # cast to int
	    return unpack "i", pack "i", $hash;
	}
	croak("DBI::PurePerl doesn't support hash type 1 without Math::BigInt >= 1.56 (available on CPAN)");
    }
    else {
        croak("bad hash type $type");
    }
}
sub looks_like_number {
    my @new = ();
    for my $thing(@_) {
        if (!defined $thing or $thing eq '') {
            push @new, undef;
        }
        else {
            push @new, ($thing =~ /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/) ? 1 : 0;
        }
    }
    return (@_ >1) ? @new : $new[0];
}
sub neat {
    my $v = shift;
    return "undef" unless defined $v;
    return $v if (($v & ~ $v) eq "0"); # is SvNIOK
    my $maxlen = shift || $DBI::neat_maxlen;
    if ($maxlen && $maxlen < length($v) + 2) {
	$v = substr($v,0,$maxlen-5);
	$v .= '...';
    }
    return "'$v'";
}

package
	DBI::var;

sub FETCH {
    my($key)=shift;
    return $DBI::err     if $$key eq '*err';
    return $DBI::errstr  if $$key eq '&errstr';
    Carp::confess("FETCH $key not supported when using DBI::PurePerl");
}

package
	DBD::_::common;

sub trace {	# XXX should set per-handle level, not global
    my ($h, $level, $file) = @_;
    $level = $h->parse_trace_flags($level)
	if defined $level and !DBI::looks_like_number($level);
    my $old_level = $DBI::dbi_debug;
    DBI::_set_trace_file($file) if defined $file;
    if (defined $level) {
	$DBI::dbi_debug = $level;
	if ($DBI::dbi_debug) {
	    printf $DBI::tfh
		"    %s trace level set to %d in DBI $DBI::VERSION (PurePerl)\n",
		$h, $DBI::dbi_debug;
	    print $DBI::tfh "    Full trace not available because DBI_TRACE is not in environment\n"
		unless exists $ENV{DBI_TRACE};
	}
    }
    return $old_level;
}
*debug = \&trace; *debug = \&trace; # twice to avoid typo warning

sub FETCH {
    my($h,$key)= @_;
    my $v = $h->{$key};
#warn ((exists $h->{$key}) ? "$key=$v\n" : "$key NONEXISTANT\n");
    return $v if defined $v;
    if ($key =~ /^NAME_.c$/) {
        my $cols = $h->FETCH('NAME');
        return undef unless $cols;
        my @lcols = map { lc $_ } @$cols;
        $h->STORE('NAME_lc', \@lcols);
        my @ucols = map { uc $_ } @$cols;
        $h->STORE('NAME_uc',\@ucols);
        return $h->FETCH($key);
    }
    if ($key =~ /^NAME.*_hash$/) {
        my $i=0;
        for my $c(@{$h->FETCH('NAME')||[]}) {
            $h->{'NAME_hash'}->{$c}    = $i;
            $h->{'NAME_lc_hash'}->{"\L$c"} = $i;
            $h->{'NAME_uc_hash'}->{"\U$c"} = $i;
            $i++;
        }
        return $h->{$key};
    }
    if (!defined $v && !exists $h->{$key}) {
	return ($h->FETCH('TaintIn') && $h->FETCH('TaintOut')) if $key eq'Taint';
	return (1==0) if $is_flag_attribute{$key}; # return perl-style sv_no, not undef
	return $DBI::dbi_debug if $key eq 'TraceLevel';
	if (!$is_valid_attribute{$key} and $key =~ m/^[A-Z]/) {
	    local $^W; # hide undef warnings
	    Carp::carp( sprintf "Can't get %s->{%s}: unrecognised attribute (@{[ %$h ]})",$h,$key )
	}
    }
    return $v;
}
sub STORE {
    my ($h,$key,$value) = @_;
    if ($key eq 'AutoCommit') {
	croak("DBD driver has not implemented the AutoCommit attribute")
	    unless $value == -900 || $value == -901;
	$value = ($value == -901);
    }
    elsif ($key =~ /^Taint/ ) {
	Carp::croak(sprintf "Can't set %s->{%s}: Taint mode not supported by DBI::PurePerl",$h,$key)
		if $value;
    }
    elsif ($key eq 'TraceLevel') {
	$h->trace($value);
	return 1;
    }
    elsif (!$is_valid_attribute{$key} && $key =~ /^[A-Z]/ && !exists $h->{$key}) {
       Carp::carp(sprintf "Can't set %s->{%s}: unrecognised attribute or invalid value %s",
	    $h,$key,$value);
    }
    $h->{$key} = $is_flag_attribute{$key} ? !!$value : $value;
    return 1;
}
sub err    { return shift->{err}    }
sub errstr { return shift->{errstr} }
sub state  { return shift->{state}  }
sub set_err {
    my ($h, $errnum,$msg,$state, $method, $rv) = @_;
    $h = tied(%$h) || $h;

    if (my $hss = $h->{HandleSetErr}) {
	return if $hss->($h, $errnum, $msg, $state, $method);
    }

    if (!defined $errnum) {
	$h->{err}    = $DBI::err    = undef;
	$h->{errstr} = $DBI::errstr = undef;
	$h->{state}  = $DBI::state  = '';
        return;
    }

    if ($h->{errstr}) {
	$h->{errstr} .= sprintf " [err was %s now %s]", $h->{err}, $errnum
		if $h->{err} && $errnum;
	$h->{errstr} .= sprintf " [state was %s now %s]", $h->{state}, $state
		if $h->{state} and $h->{state} ne "S1000" && $state;
	$h->{errstr} .= "\n$msg";
	$DBI::errstr = $h->{errstr};
    }
    else {
	$h->{errstr} = $DBI::errstr = $msg;
    }

    # assign if higher priority: err > "0" > "" > undef
    my $err_changed;
    if ($errnum			# new error: so assign
	or !defined $h->{err}	# no existing warn/info: so assign
           # new warn ("0" len 1) > info ("" len 0): so assign
	or defined $errnum && length($errnum) > length($h->{err})
    ) {
        $h->{err} = $DBI::err = $errnum;
	++$h->{ErrCount} if $errnum;
	++$err_changed;
    }

    if ($err_changed) {
	$state ||= "S1000" if $DBI::err;
	$h->{state} = $DBI::state = ($state eq "00000") ? "" : $state
	    if $state;
    }

    if (my $p = $h->{Database}) { # just sth->dbh, not dbh->drh (see ::db::DESTROY)
	$p->{err}    = $DBI::err;
	$p->{errstr} = $DBI::errstr;
	$p->{state}  = $DBI::state;
    }

    $h->{'_last_method'} = $method;
    return $rv; # usually undef
}
sub trace_msg {
    my ($h, $msg, $minlevel)=@_;
    $minlevel = 1 unless $minlevel;
    return unless $minlevel <= ($DBI::dbi_debug & 0xF);
    print $DBI::tfh $msg;
    return 1;
}
sub private_data {
    warn "private_data @_";
}
sub take_imp_data {
    undef;
}
sub rows {
    return -1; # always returns -1 here, see DBD::_::st::rows below
}
sub DESTROY {
}

package
	DBD::_::st;

sub fetchrow_arrayref	{
    my $h = shift;
    # if we're here then driver hasn't implemented fetch/fetchrow_arrayref
    # so we assume they've implemented fetchrow_array and call that instead
    my @row = $h->fetchrow_array or return;
    return $h->_set_fbav(\@row);
}
# twice to avoid typo warning
*fetch = \&fetchrow_arrayref;  *fetch = \&fetchrow_arrayref;

sub fetchrow_array	{
    my $h = shift;
    # if we're here then driver hasn't implemented fetchrow_array
    # so we assume they've implemented fetch/fetchrow_arrayref
    my $row = $h->fetch or return;
    return @$row;
}
*fetchrow = \&fetchrow_array; *fetchrow = \&fetchrow_array;

sub fetchrow_hashref {
    my $h         = shift;
    my $row       = $h->fetch or return;
    my $FetchCase = shift;
    my $FetchHashKeyName = $FetchCase || $h->{'FetchHashKeyName'} || 'NAME';
    my $FetchHashKeys    = $h->FETCH($FetchHashKeyName);
    my %rowhash;
    @rowhash{ @$FetchHashKeys } = @$row;
    return \%rowhash;
}
sub dbih_setup_fbav {
    my $h = shift;
    return $h->{'_fbav'} || do {
        $DBI::rows = $h->{'_rows'} = 0;
        my $fields = $h->{'NUM_OF_FIELDS'}
                  or DBI::croak("NUM_OF_FIELDS not set");
        my @row = (undef) x $fields;
        \@row;
    };
}
sub _get_fbav {
    my $h = shift;
    my $av = $h->{'_fbav'} ||= dbih_setup_fbav($h);
    $DBI::rows = ++$h->{'_rows'};
    return $av;
}
sub _set_fbav {
    my $h = shift;
    my $fbav = $h->{'_fbav'};
    if ($fbav) {
	$DBI::rows = ++$h->{'_rows'};
    }
    else {
	$fbav = $h->_get_fbav;
    }
    my $row = shift;
    if (my $bc = $h->{'_bound_cols'}) {
        for my $i (0..@$row-1) {
            my $bound = $bc->[$i];
            $fbav->[$i] = ($bound) ? ($$bound = $row->[$i]) : $row->[$i];
        }
    }
    else {
        @$fbav = @$row;
    }
    return $fbav;
}
sub bind_col {
    my ($h, $col, $value_ref,$from_bind_columns) = @_;
    $col-- unless $from_bind_columns; # XXX fix later
    DBI::croak("bind_col($col,$value_ref) needs a reference to a scalar")
	unless ref $value_ref eq 'SCALAR';
    my $fbav = $h->_get_fbav;
    $h->{'_bound_cols'}->[$col] = $value_ref;
    return 1;
}
sub finish {
    my $h = shift;
    $h->{'_fbav'} = undef;
    $h->{'Active'} = 0;
    return 1;
}
sub rows {
    my $h = shift;
    my $rows = $h->{'_rows'};
    return -1 unless defined $rows;
    return $rows;
}

1;
__END__


=head1 NAME

 DBI::PurePerl -- a DBI emulation using pure perl (no C/XS compilation required)

=head1 SYNOPSIS

 BEGIN { $ENV{DBI_PUREPERL} = 2 }
 use DBI;

=head1 DESCRIPTION

This is a pure perl emulation of the DBI internals.  In almost all
cases you will be better off using standard DBI since the portions
of the standard version written in C make it *much* faster.

However, if you are in a situation where it isn't possible to install
a compiled version of standard DBI, and you're using pure-perl DBD
drivers, then this module allows you to use most common features
of DBI without needing any changes in your scripts.

=head1 EXPERIMENTAL STATUS

DBI::PurePerl is new so please treat it as experimental pending
more extensive testing.  So far it has passed all tests with DBD::CSV,
DBD::AnyData, DBD::XBase, DBD::Sprite, DBD::mysqlPP.  Please send
bug reports to Jeff Zucker at <jeff@vpservices.com> with a cc to
<dbi-dev@perl.org>.

=head1 USAGE

The usage is the same as for standard DBI with the exception
that you need to set the enviornment variable DBI_PUREPERL if
you want to use the PurePerl version.

 DBI_PUREPERL == 0 (the default) Always use compiled DBI, die
                   if it isn't properly compiled & installed

 DBI_PUREPERL == 1 Use compiled DBI if it is properly compiled
                   & installed, otherwise use PurePerl

 DBI_PUREPERL == 2 Always use PurePerl

You may set the enviornment variable in your shell (e.g. with
set or setenv or export, etc) or else set it in your script like
this:

 BEGIN { $ENV{DBI_PUREPERL}=2 }

before you C<use DBI;>.

=head1 INSTALLATION

In most situations simply install DBI (see the DBI pod for details).

In the situation in which you can not install DBI itself, you
may manually copy DBI.pm and PurePerl.pm into the appropriate
directories.

For example:

 cp DBI.pm      /usr/jdoe/mylibs/.
 cp PurePerl.pm /usr/jdoe/mylibs/DBI/.

Then add this to the top of scripts:

 BEGIN {
   $ENV{DBI_PUREPERL} = 1;	# or =2
   unshift @INC, '/usr/jdoe/mylibs';
 }

(Or should we perhaps patch Makefile.PL so that if DBI_PUREPERL
is set to 2 prior to make, the normal compile process is skipped
and the files are installed automatically?)

=head1 DIFFERENCES BETWEEN DBI AND DBI::PurePerl

=head2 Attributes

Boolean attributes still return boolean values but the actual values
used may be different, i.e., 0 or undef instead of an empty string.

Some handle attributes are either not supported or have very limited
functionality:

  ActiveKids
  InactiveDestroy
  Kids
  Taint
  TaintIn
  TaintOut

(and probably others)

=head2 Tracing

Trace functionality is more limited and the code to handle tracing is
only embeded into DBI:PurePerl if the DBI_TRACE environment variable
is defined.  To enable total tracing you can set the DBI_TRACE
environment variable as usual.  But to enable individual handle
tracing using the trace() method you also need to set the DBI_TRACE
environment variable, but set it to 0.

=head2 Parameter Usage Checking

The DBI does some basic parameter count checking on method calls.
DBI::PurePerl doesn't.

=head2 Speed

DBI::PurePerl is slower. Although, with some drivers in some
contexts this may not be very significant for you.

By way of example... the test.pl script in the DBI source
distribution has a simple benchmark that just does:

    my $null_dbh = DBI->connect('dbi:NullP:','','');
    my $i = 10_000;
    $null_dbh->prepare('') while $i--;

In other words just prepares a statement, creating and destroying
a statement handle, over and over again.  Using the real DBI this
runs at ~4550 handles per second whereas DBI::PurePerl manages
~2800 per second on the same machine (not too bad really).

=head2 May not fully support hash()

If you want to use type 1 hash, i.e., C<hash($string,1)> with
DBI::PurePerl, you'll need version 1.56 or higher of Math::BigInt
(available on CPAN).

=head2 Doesn't support preparse()

The DBI->preparse() method isn't supported in DBI::PurePerl.

=head2 Doesn't support DBD::Proxy

There's a subtle problem somewhere I've not been able to identify.
DBI::ProxyServer seem to work fine with DBI::PurePerl but DBD::Proxy
does not work 100% (which is sad because that would be far more useful :)
Try re-enabling t/80proxy.t for DBI::PurePerl to see if the problem
that remains will affect you're usage.

=head2 Others

  can() - doesn't have any special behaviour

Please let us know if you find any other differences between DBI
and DBI::PurePerl.

=head1 AUTHORS

Tim Bunce and Jeff Zucker.

Tim provided the direction and basis for the code.  The original
idea for the module and most of the brute force porting from C to
Perl was by Jeff. Tim then reworked some core parts to boost the
performance and accuracy of the emulation. Thanks also to Randal
Schwartz and John Tobey for patches.

=head1 COPYRIGHT

Copyright (c) 2002  Tim Bunce  Ireland.

See COPYRIGHT section in DBI.pm for usage and distribution rights.

=cut
