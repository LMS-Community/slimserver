package Slim::Utils::MemoryUsage;

#
# This module is a merging of B::TerseSize and Apache::Status 
# put together to work with Logitech Media Server by Dan Sully
#
# These are not the droids you're looking for.
#
# dsully added:
# 	Usage of Devel::Size & Devel::Size::Report
# 	Data::TreeDumper as an alternative to Data::Dumper
#	Capturing STDOUT/STDERR from Devel::Peek / B::walkoptree_*
#
# Original License follows:
#
# B::TerseSize.pm
# Copyright (c) 1999 Doug MacEachern. All rights reserved.
# This module is free software; you can redistribute and/or modify
# it under the same terms as Perl itself.
#
# portions of this module are based on B::Terse, by Malcolm Beattie

use strict;

no warnings 'redefine';

use B ();
use B::Asmdata qw(@specialsv_name);
use B::Size ();
use B::LexInfo ();
use Devel::Peek ();
use Devel::Size ();
#use Devel::Size::Report ();
use Devel::Symdump ();
use Scalar::Util qw(blessed);

my $dumperClass;
{
	Slim::bootstrap::tryModuleLoad('Data::TreeDumper');

	if ($@ !~ /Can't locate/) {
		$dumperClass = 'Data::TreeDumper';
	} else {
		$@ = '';
		Slim::bootstrap::tryModuleLoad('Data::Dumper');
		$dumperClass = 'Data::Dumper';
	}
}

our $opcount;
my $opsize;
my $copsize;
my $curcop;
my $script = '/memoryusage.html';
my %b_terse_exp = ('slow' => 'syntax', 'exec' => 'execution');

# for catching stdout/stderr
my ($out, $err, $oldout, $olderr);

sub init {
	if ( main::SCANNER ) {
		$SIG{USR2} = sub {
			my $htmlref = Slim::Utils::MemoryUsage->status_memory_usage();
			open my $fh, '>', 'scanner-memory.html';
			print $fh $$htmlref;
			close $fh;
			system("open scanner-memory.html") if main::ISMAC;
		};
	}
	else {			
		Slim::Web::Pages->addPageFunction(qr/^memoryusage\.html.*/, sub {
			my ($client, $params) = @_;
	
			my $item    = $params->{'item'};
			my $type    = $params->{'type'};
			my $command = $params->{'command'};
	
			unless ($item && $command) {
	
				return Slim::Utils::MemoryUsage->status_memory_usage();
			}
	
			if (defined $item && defined $command && Slim::Utils::MemoryUsage->can($command)) {
	
				return Slim::Utils::MemoryUsage->$command($item, $type);
			}
		});
	}
}
		

sub UNIVERSAL::op_size {
	$opcount++;
	my $size = shift->size;
	$opsize += $size;
	$copsize += $size;
}

my $mouse_attr = qq( onclick='javascript: return false') .  qq( onmouseout='window.status=""; return true');

sub op_html_name {
	my($op, $sname) = @_;

	$sname =~ s/(\s+)$//;
	my $pad = $1 || "";
	my $desc = sprintf qq(onmouseover='window.status="%s"; return true'), B::OP::op_desc($op->type) || "unknown";
	my $href = $curcop ? $curcop->line : "";

	return qq(<a $desc $mouse_attr href="#$href">$sname</a>$pad);
}

sub peekop {
	my $op = shift;

	my $size = $op->size;
	$opcount++;
	$opsize += $size;
	$copsize += $size;
	my $name;
	my $addr;
	my $sname = sprintf "%-13s", $op->name;

	$name = op_html_name($op, $sname);
	$addr = "<a name=\"$addr\">$addr</a>";

	return sprintf qq(%-6s $name $addr {%d bytes}), B::class($op), $size;
}

my $hr = "=" x 60;
our %filelex = ();

sub package_size {
	my $package = shift;

	#local *UNIVERSAL::op_size = \&universal_op_size;

	my %retval = ();
	my $total_opsize = 0;
	my $total_opcount = 0;
	my $stash;

	local $^W = 0;

	{
		no strict;
		$stash = \%{"$package\::"};
	}

	for (keys %$stash) {
		my $name = $package . "::$_";
		my $has_code = 0;

		{
			no strict;
			$has_code = *{$name}{CODE}; #defined() expects CvROOT || CvXSUB
		}

		unless ($has_code) { #CV_walk will measure
			$total_opsize += B::Sizeof::GV + B::Sizeof::XPVGV + B::Sizeof::GP;
		}

		# measure global variables
		for my $type (qw(ARRAY HASH SCALAR)) {

			no strict;
			next if $name =~ /::$/; #stash
			next unless /^[\w_]/;
			next if /^_</;

			my $ref = *{$name}{$type} || next;
			my $obj = B::svref_2object($ref);

			next if ref($obj) eq 'B::NULL';

			# XXX - Devel::Size seems to be more accurate
			# XXX - but it crashes on a lot of code.
			my $tsize = $obj->size;
			#my $tsize = Devel::Size::total_size($ref);

			$total_opsize += $tsize;
			$retval{"*${_}{$type}"} = {'size' => $tsize};
		}

		next unless defined $has_code;

		CV_walk('slow', $name, 'op_size');

		for (keys %{ $filelex{$package} }) {
			$total_opsize += $filelex{$package}->{$_};
			$retval{"my ${_} = ...;"} = {
				'size' => $filelex{$package}->{$_},
			};
		}

		%filelex = ();
		$total_opsize  += $opsize;
		$total_opcount += $opcount;

		$retval{$_} = {
			'count' => $opcount,
			'size'  => $opsize,
		};

	}

	return (\%retval, $total_opcount, $total_opsize);
}

our $b_objsym = \&B::objsym;

sub objsym {
	my $obj = shift;
	my $value = $b_objsym->($obj);
	return unless $value;
	sprintf qq(<a href="#0x%lx">$value</a>), $$obj;
}

sub CV_walk {
	my ($order, $objname, $meth) = @_;

	$meth ||= 'terse_size';

	my $cvref = \&{$objname};
	my $cv = B::svref_2object($cvref);
	my ($package, $func) = ($objname =~ /(.*)::([^:]+)$/);

	$opsize  = B::Sizeof::GV + B::Sizeof::XPVGV + B::Sizeof::GP;
	$opcount = 0;
	$curcop = "";

	my $gv = $cv->GV;
	$opsize += length $gv->NAME;

	if (my $stash = $cv->is_alias($package)) {
		return;
	}

	$opsize += B::Sizeof::XPVCV;
	$opsize += B::Sizeof::SV;

	if ($cv->FLAGS & B::SVf_POK) {
		$opsize += B::Sizeof::XPV + length $cv->PV;
	} else {
		$opsize += B::Sizeof::XPVIV; #IVX == -1 for no prototype
	}

	init_curpad_names($cvref);

	no strict;
	local *B::objsym = \&objsym;

	# XXX - dsully added - walkoptree_* prints it's data
	catchSTDERR();

	if ($order eq 'exec') {

		B::walkoptree_exec($cv->START, $meth);

	} else {

		B::walkoptree_slow($cv->ROOT, $meth);
	}

	curcop_info() if $curcop;

	my $html = $out . $err;

	putbackSTDERR();

	my ($padsize, $padsummary) = PADLIST_size($cv);
	$opsize += $padsize;

	return join('', $html), $padsummary;
}

sub terse_size {
	my ($order, $objname) = @_;

	my ($html, $padsummary) = CV_walk($order, $objname);

	my @out = "$html\n$hr\nTotals: $opsize bytes | $opcount OPs\n$hr\n";

	if ($padsummary) {
		push @out, "\nPADLIST summary:\n";
		push @out, @$padsummary if ref($padsummary) eq 'ARRAY';
	}

	undef $padsummary;

	return join('', @out);
}

our @curpad_names = ();

sub init_curpad_names {
	my $cv = B::svref_2object(shift);

	my $padlist = $cv->PADLIST;

	return if ref($padlist) eq 'B::SPECIAL';

	@curpad_names = ($padlist->ARRAY)[0]->ARRAY;
}

sub compile {
	my $order = shift;
	my @options = @_;

	B::clearsym() if defined &B::clearsym;

	my @html = ();

	if (@options) {

		for my $objname (@options) {
			$objname = "main::$objname" unless $objname =~ /::/;
			push @html, terse_size($order, $objname);
		}

	} else {

		# redirect the output
		catchSTDERR();

		if ($order eq "exec") {
			B::walkoptree_exec(B::main_start, "terse_size");
		} else {
			B::walkoptree_exec(B::main_root, "terse_size");
		}

		curcop_info() if $curcop;

		push @html, $out, $err;

		putbackSTDERR();
	}

	return join('', @html);
}

sub catchSTDERR {

	$out = '';
	$err = '';

	open $oldout, ">&STDOUT" or die "Can't dup STDOUT: $!";
	open $olderr, ">&STDERR" or die "Can't dup STDERR: $!";

#	close STDERR;
	close STDOUT;

#	open STDERR, '>', \$out or die "Can't open STDERR: $!";
	open STDOUT, '>', \$err or die "Can't open STDOUT: $!";

#	select STDERR; $| = 1;
	select STDOUT; $| = 1;
}

sub putbackSTDERR {
	close STDOUT;
#	close STDERR;

	open STDOUT, ">&", $oldout or die "Can't dup \$oldout: $!";
#	open STDERR, ">&", $olderr or die "Can't dup \$olderr: $!";

	$out = '';
	$err = '';
}

sub indent {
	my $level = shift;
	return "    " x $level;
}

# thanks B::Deparse
sub padname {
	my $obj = shift;
	return '?' unless ref $obj;

	my $str = $obj->PV;
	my $ix = index($str, "\0");
	$str = substr($str, 0, $ix) if $ix != -1;

	return $str;
}

sub B::OP::terse_size {
	my ($op, $level) = @_;

	my $t = $op->targ;
	my $targ = "";

	if ($t > 0) {

		my $name = B::OP::op_name($op->targ);
		my $desc = B::OP::op_desc($op->targ);

		if ($op->type == 0) { #OP_NULL

			$targ = $name eq $desc ? " [$name]" : 
			sprintf " [%s - %s]", $name, $desc;

		} else {
			$targ = sprintf " [targ %d - %s]", $t, 
			padname($curpad_names[$t]);
		}
	}

	print indent($level), peekop($op), $targ, "\n";
}

sub B::SVOP::size {
	my $obj = shift;

	if (!blessed($obj) || !blessed($obj->sv)) {
		return;
	}

	return B::Sizeof::SVOP + $obj->sv->size;
}

sub B::SVOP::terse_size {
	my ($op, $level) = @_;
	print indent($level), peekop($op), "  ";
	$op->sv->terse_size(0);
}

sub B::GVOP::terse_size {
	my ($op, $level) = @_;
	print join('', indent($level), peekop($op), "  ");
	$op->gv->terse_size(0);
}

sub B::PMOP::terse_size {
	my ($op, $level) = @_;
	my $precomp = $op->precomp;
	print indent($level), peekop($op), (defined($precomp) ? " /$precomp/\n" : " (regexp not compiled)\n");
}

sub B::PVOP::terse_size {
	my ($op, $level) = @_;
	print indent($level), peekop($op), " ", B::cstring($op->pv), "\n";
}

my $hr2 = "-" x 60;

*cop_file = B::COP->can('file') || sub {
	shift->filegv->SV->PV;
};

sub curcop_info {
	my $line    = $curcop->line;
	my $linestr = "line $line";

	if ($line > 0) {

		my $anchor = "";
		if ($line > 10) {
			$anchor = "#" . ($line - 10);
		}

		my $window = sprintf "offset=%d&len=%d", $line - 100, $line + 100;
		my $args   = sprintf "noh_fileline&filename=%s&line=%d&$window", cop_file($curcop), $line;

		$linestr = qq(<a name="$line" target=top href="$script?command=$args$anchor">$linestr</a>);
	}

	print "\n[$linestr size: $copsize bytes]\n";
}

sub B::COP::terse_size {
	my ($op, $level) = @_;

	my $label = $op->label || "";
	if ($label) {
		$label = " label ".B::cstring($label);
	}

	curcop_info() if $curcop;

	$copsize = 0;
	$curcop = $op;

	print "\n$hr2\n", indent($level), peekop($op), "$label\n";
}

sub B::PV::terse_size {
	my ($sv, $level) = @_;
	my $pv = B::cstring($sv->PV);
	B::Size::escape_html(\$pv);
	printf("%s%s %s\n", indent($level), B::class($sv), $pv);
}

sub B::AV::terse_size {
	my ($sv, $level) = @_;
	printf("%s%s FILL %d\n", indent($level), B::class($sv), $sv->FILL);
}

sub B::GV::terse_size {
	my ($gv, $level) = @_;
	my $stash = $gv->STASH->NAME;

	if ($stash eq "main") {
		$stash = "";
	} else {
		$stash = $stash . "::";
	}

	printf("%s%s *%s%s\n", indent($level), B::class($gv), $stash, $gv->NAME);
}

sub B::IV::terse_size {
	my ($sv, $level) = @_;
	printf("%s%s %d\n", indent($level), B::class($sv), $sv->IV);
}

sub B::NV::terse_size {
	my ($sv, $level) = @_;
	printf("%s%s %s\n", indent($level), B::class($sv), $sv->NV);
}

sub B::RV::terse_size {
	my ($sv, $level) = @_;
	printf("%s%s \n", indent($level), B::class($sv));
}

sub B::NULL::terse_size {
	my ($sv, $level) = @_;
	printf("%s%s \n", indent($level), B::class($sv));
}
    
sub B::SPECIAL::terse_size {
	my ($sv, $level) = @_;
	printf("%s%s #%d %s\n", indent($level), B::class($sv), $$sv, $specialsv_name[$$sv]);
}

my $padname_max = 0;

sub PADLIST_size {
	my $cv = shift;
	my $obj = UNIVERSAL::isa($cv, "B::CV") ? $cv : B::svref_2object($cv);

	my $size = (B::Sizeof::AV + B::Sizeof::XPVAV) * 3; #padlist, names, values

	if ($obj->PADLIST->isa('B::SPECIAL')) {
		return B::Sizeof::AV; #XXX???
	}

	my ($padnames, $padvals) = $obj->PADLIST->ARRAY;
	my @names = $padnames->ARRAY;
	$padname_max = 0;

	my @names_pv = map {
		my $pv = padname($_);
		$padname_max = length($pv) > $padname_max ?  length($pv) : $padname_max;
		$pv;
	} @names;

	my @vals = $padvals->ARRAY;
	my $fill = $padnames->FILL;
	my $fill_len = length $fill;
	my @retval = ();
	my $wantarray = wantarray;

	for (my $i = 0; $i <= $fill; $i++) {

		my $entsize = $names[$i]->size;
		my $is_fake = $names[$i]->FLAGS & B::SVf_FAKE;

		if ($is_fake) {

			$entsize += B::Sizeof::SV; # just a reference to outside scope

			if (B::class($obj->OUTSIDE->GV) eq 'SPECIAL') {
				$filelex{ $obj->GV->STASH->NAME }->{ $names_pv[$i] } = $vals[$i]->size;

			} else { 
				#XXX nested/anonsubs
			}

		} else {

			$entsize += $vals[$i]->size;
		}

		$size += $entsize;
		next unless $wantarray;

		my $class = B::class($vals[$i]);
		my $byteinfo = sprintf "[%-4s %3d bytes]", $class, $entsize;

		no warnings;
		push @retval, sprintf "%${fill_len}d: %${padname_max}s %s %s\n", $i, $names_pv[$i], $byteinfo, 
			($is_fake ? '__SvFAKE__' : (defined $vals[$i] ? 0 : $vals[$i]->sizeval));
	}

	@names = ();
	@names_pv = ();
	@vals  = ();
	$fill = undef;

	if ($wantarray) {
		return ($size, \@retval);
	}

	@retval = ();
	return $size;
}

sub max {
	my ($cur, $maybe) = @_;
	$maybe > $cur ? $maybe : $cur;
}

sub b_lexinfo_link {
	my $name = shift;

	return qq(\n<a href="$script?item=$name&command=noh_b_lexinfo">Lexical Info</a>\n);
}

sub b_terse_size_link {
	my $name = shift;

	my @retval = ();

	for (qw(exec slow)) {
		my $exp = "$b_terse_exp{$_} order";
		push @retval, qq(\n<a href="$script?type=$_&item=$name&command=noh_b_terse_size">Syntax Tree Size ($exp)</a>\n);
	}

	join '', @retval;
}

sub b_package_size_link {
	my $name = shift;

	return qq(<a href="$script?item=$name&command=noh_b_package_size">Memory Usage</a>\n);
}

sub b_deparse_link {
	my $name = shift;

	return qq(\n<a href="$script?item=$name&command=noh_b_deparse">Deparse</a>\n);
}

sub peek_link {
	my $name = shift;
	my $type = shift;

	return qq(\n<a href="$script?item=$name&type=$type&command=noh_peek">Peek Dump</a>\n);
}

sub noh_peek {
	my $class = shift;
	my $name = shift;
	my $type = shift;

	no strict 'refs';

	$type =~ s/^FUNCTION$/CODE/;

	my $html = "<pre>Peek Dump of $name $type\n\n";

	my $args = {
		indend => "    ",
		summary => 1,
		class => 1,
		addr => 1,
		total => 1,
		terse => 1,
	};

	if ($type eq 'HASH') {

		$html .= Devel::Size::Report::report_size(\%{$name}, $args);

	} elsif ($type eq 'ARRAY') {

		$html .= Devel::Size::Report::report_size(\@{$name}, $args);

	} elsif ($type eq 'SCALAR') {

		$html .= Devel::Size::Report::report_size(\${$name}, $args);
	}

	#$html .= Devel::Size::Report::report_size(*{$name}, $args);
	$html .= "<br>\n";

	# Devel::Peek spews to STDERR
	catchSTDERR();
	Devel::Peek::Dump(*{$name}{$type});
	$html .= $out . $err . '<br>Possibly truncated - see perldoc Devel::Peek</pre>';
	putbackSTDERR();

	return \$html;
}

sub cv_file {
	my $obj = shift;
	$obj->can('FILEGV') ? $obj->FILEGV->SV->PV : $obj->FILE;
}

sub cv_dump {
	my $class = shift;
	my $name = shift;
	my $type = shift;

	no strict 'refs';

	# could be another child, which doesn't have this symbol table?
	return unless *$name{CODE};

	my @retval = "<p>Subroutine info for <b>$name</b></p>\n<pre>\n";
	my $obj    = B::svref_2object(*$name{CODE});
	my $file   = cv_file($obj);
	my $stash  = $obj->GV->STASH->NAME;

	push @retval, "File: ", (-e $file ? qq(<a href="file:$file">$file</a>) : $file), "\n";

	my $cv    = $obj->GV->CV;
	my $proto = $cv->PV if $cv->can('PV');

	push @retval, qq(Package: $stash\n);
	push @retval, "Line: ",      $obj->GV->LINE, "\n";
	push @retval, "Prototype: ", $proto || "none", "\n";
	push @retval, "XSUB: ",      $obj->XSUB ? "yes" : "no", "\n";
	push @retval, peek_link($name, $type);
	push @retval, b_lexinfo_link($name);
	push @retval, b_terse_size_link($name);
	push @retval, b_deparse_link($name);
	push @retval, "</pre>";

	my $html = join('', @retval);

	return \$html;
}

sub escape_html {
	my $str = shift;

	$str =~ s/&/&amp;/g;
	$str =~ s/</&lt;/g;
	$str =~ s/>/&gt;/g;

	return $str;
}

sub data_dump {
	my $class = shift;
	my $name = shift;
	my $type = shift;

	no strict 'refs';

	my @retval = (
		"<p>\nData Dump of $name $type\n</p>\n\n",
		peek_link($name, $type), '<br>',
	);

	if ($dumperClass eq 'Data::Dumper') {

		my $str = Data::Dumper->Dump([*$name{$type}], ['*'.$name]);
		   $str = escape_html($str);
		   $str =~ s/= \\/= /; #whack backwack

		push @retval, "<pre>$str</pre>\n";

	} else {

		push @retval, Data::TreeDumper::DumpTree([*$name{$type}], 'Tree', RENDERER => 'DHTML');
	}

	my $html = join('', @retval);

	undef @retval;

	return \$html;
}

sub noh_b_package_size {
	my $class = shift;
	my $package = shift;

	my @html = "<pre>Memory Usage for package $package\n\n";

	no strict 'refs';

	my ($subs, $opcount, $opsize) = package_size($package);

	push @html, "Totals: $opsize bytes | $opcount OPs\n\n";

	my $nlen = 0;
	my @keys = map { $nlen = length > $nlen ? length : $nlen; $_ } (sort { $subs->{$b}->{'size'} <=> $subs->{$a}->{'size'} } keys %$subs);

	my $clen = length $subs->{$keys[0]}->{'count'};
	my $slen = length $subs->{$keys[0]}->{'size'};

	for my $name (@keys) {

		my $stats = $subs->{$name};

		if ($name =~ /^my /) {

			push @html, sprintf("%-${nlen}s</a> %${slen}d bytes", $name, $stats->{'size'});

		} elsif ($name =~ /^\*(\w+)\{(\w+)\}/) {

			my $item = "$package\::$1";
			my $type = $2;
			my $link = qq(<a href="$script?item=$item&type=$type&command=data_dump">);

			push @html, sprintf("$link%-${nlen}s</a> %${slen}d bytes", $name, $stats->{'size'});

			#push @html, sprintf(" |   0 OPs | %d bytes data", Devel::Size::total_size(*{"$package\::$1"}));

			if ($type eq 'HASH') {

				push @html, sprintf(" |   0 OPs | %d bytes data", Devel::Size::total_size(\%{$item}));

			} elsif ($type eq 'ARRAY') {

				push @html, sprintf(" |   0 OPs | %d bytes data", Devel::Size::total_size(\@{$item}));

			} elsif ($type eq 'SCALAR') {

				push @html, sprintf(" |   0 OPs | %d bytes data", Devel::Size::total_size(\${$item}));
			}

		} else {

			my $link = qq(<a href="$script?item=$package\::$name&command=noh_b_terse_size&type=slow">);
			push @html, sprintf("$link%-${nlen}s</a> %${slen}d bytes | %${clen}d OPs", $name, $stats->{'size'}, $stats->{'count'});
		}

		push @html, "\n";
	}

	my $html = join('', @html);

	undef @html;

	return \$html;
}

sub noh_b_terse_size {
	my $class = shift;
	my $name = shift;
	my $type = shift;

	my $html = join('',
		'<pre>',
		sprintf("Syntax Tree Size ($b_terse_exp{$type} order) for %s\n\n", 
			qq{<a href="$script?item=$name&type=CODE&command=cv_dump">$name</a>}
		),

		compile($type, $name),
	);

	return \$html;
}

sub noh_b_deparse {
	my $class = shift;
	my $name = shift;

	no strict 'refs';

	# Deparse is a memory hog
	Slim::bootstrap::tryModuleLoad('B::Deparse');

	my $deparse = B::Deparse->new('-si8T');
	my $body = $deparse->coderef2text(\&{$name});

	my $html = "<pre>Deparse of $name\n\nsub $name $body\n</pre>";

	return \$html;
}

sub noh_b_lexinfo {
	my $class = shift;
	my $name = shift;

	no strict 'refs';

	my $lexi = B::LexInfo->new;
	my $info = $lexi->cvlexinfo($name);

	my $html = join('<pre>', "Lexical Info for $name\n\n", ${ $lexi->dumper($info) }, '</pre>');

	return \$html;
}

use Memoize;
memoize('status_memory_usage');

sub status_memory_usage {
	my $class = shift;

	$| = 1;

	my $stab = Devel::Symdump->rnew('main');

	my %total;
	my @retval = ();
	my ($clen, $slen, $nlen);

	for my $package ('main', sort $stab->packages) {

		next if $package =~ /Slim::Utils::MemoryUsage/;
		next if $package =~ /^B::/;
		next if $package =~ /^B$/;
		next if $package =~ /^NS/;
		next if $package =~ /^Devel::/;
		next if $package =~ /^Data::\w*?Dumper/;
		next if $package =~ /::SUPER$/;
		next if $package =~ /::ISA::CACHE$/;

		my ($subs, $opcount, $opsize) = package_size($package);

		$total{$package} = {'count' => $opcount, 'size' => $opsize};
		
		main::idleStreams();
		
		$nlen = max($nlen, length $package);
		$slen = max($slen, length $opsize);
		$clen = max($clen, length $opcount);
	}

	my $totalBytes   = 0;
	my $totalOpCodes = 0;

	for (sort { $total{$b}->{'size'} <=> $total{$a}->{'size'} } keys %total) {

		my $link = qq(<a href="$script?item=$_&command=noh_b_package_size">);

		push @retval, sprintf "$link%-${nlen}s</a> %${slen}d bytes | %${clen}d OPs\n", $_, $total{$_}->{size}, $total{$_}->{count};
		#printf "%-${nlen}s %${slen}d bytes | %${clen}d OPs\n", $_, $total{$_}->{size}, $total{$_}->{count};

		$totalBytes   += $total{$_}->{'size'};
		$totalOpCodes += $total{$_}->{'count'};
	}

	#printf("%d total in bytes\n", $totalBytes),
	#printf("%6.2lf total in megabytes\n", ($totalBytes / 1048576)),

	unshift @retval, (
		'<pre>',
		sprintf("%d total in bytes<br>\n", $totalBytes),
		sprintf("%6.2lf total in megabytes<br>\n", ($totalBytes / 1048576)),
		sprintf("%d total OPs<br><br>\n", $totalOpCodes),
		'Not including Slim::Utils::MemoryUsage in the count.<br>',
		'<hr>'
	);

	my $html = join('', @retval, '</pre>');

	return \$html;
}

1;

__END__
