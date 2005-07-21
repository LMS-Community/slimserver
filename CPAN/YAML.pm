package YAML; 
$VERSION = '0.39';

# This module implements a Loader and Dumper for the YAML serialization
# language, VERSION 1.0 TRIAL2. (http://www.yaml.org/spec/)

require Exporter;
@ISA = qw(Exporter);
# Basic interface is Load & Dump
@EXPORT = qw(Load Dump);
# Provide a bunch of aliases for TMTOWTDI's sake
@EXPORT_OK = qw(LoadFile DumpFile
                Dumper Eval 
                freeze thaw
                VALUE COMMENT
                Bless Blessed
               );
# Export groups
%EXPORT_TAGS = (all => [qw(Load Dump LoadFile DumpFile Bless Blessed)],
                constants => [qw(VALUE COMMENT)],
                Storable => [qw(freeze thaw)],
                POE => [qw(freeze thaw)],
               );

use strict;
use YAML::Node;
use YAML::Transfer;
use Carp;

sub PRINT { print STDERR @_, "\n" } # XXX
sub DUMP { use Data::Dumper(); print STDERR Data::Dumper::Dumper(@_) } # XXX

# Context constants
use constant LEAF => 1;
use constant COLLECTION => 2;
use constant KEY => 3;
use constant BLESSED => 4;
use constant FROMARRAY => 5;
use constant VALUE => "\x07YAML\x07VALUE\x07";
use constant COMMENT => "\x07YAML\x07COMMENT\x07";

# These are the user changable options
{
    no strict 'vars'; 
    $Indent = 2 unless defined $Indent;
    $UseHeader = 1 unless defined $UseHeader;
    $UseVersion = 0 unless defined $UseVersion;
    $SortKeys = 1 unless defined $SortKeys;
    $AnchorPrefix = '' unless defined $AnchorPrefix;
    $UseCode = 0 unless defined $UseCode;
    $DumpCode = '' unless defined $DumpCode;
    $LoadCode = '' unless defined $LoadCode;
    $UseBlock = 0 unless defined $UseBlock;
    $UseFold = 0 unless defined $UseFold;
    $CompressSeries = 1 unless defined $CompressSeries;
    $InlineSeries = 0 unless defined $InlineSeries;
    $UseAliases = 1 unless defined $UseAliases;
    $Purity = 0 unless defined $Purity;
    $DateClass = '' unless defined $DateClass;
}

# Common YAML character sets
my $WORD_CHAR = '[A-Za-z-]';
my $ESCAPE_CHAR = '[\\x00-\\x08\\x0b-\\x0d\\x0e-\\x1f]';
my $INDICATOR_CHAR = '[#-:?*&!|\\\\^@%]';
my $FOLD_CHAR = '>';
my $LIT_CHAR = '|';    
my $LIT_CHAR_RX = "\\$LIT_CHAR";    

# $o is the YAML object. It contains the complete state of the YAML.pm
# process. This is set at the file scope level so that I can avoid using
# OO syntax or passing the object around in function calls.
#
# When callback are added to YAML.pm the calling code will have to save
# the object so that it won't get clobbered. Also YAML.pm can't be subclassed.
# 
# The purpose of this is for efficiency and also for much simpler code.
my $o;

# YAML OO constructor function
sub new {
    my $class = shift;
    my $o = {
             stream => '',
             level => 0,
             anchor => 1,
             Indent => $YAML::Indent,
             UseHeader => $YAML::UseHeader,
             UseVersion => $YAML::UseVersion,
             SortKeys => $YAML::SortKeys,
             AnchorPrefix => $YAML::AnchorPrefix,
             DumpCode => $YAML::DumpCode,
             LoadCode => $YAML::LoadCode,
             UseBlock => $YAML::UseBlock,
             UseFold => $YAML::UseFold,
             CompressSeries => $YAML::CompressSeries,
             InlineSeries => $YAML::InlineSeries,
             UseAliases => $YAML::UseAliases,
             Purity => $YAML::Purity,
             DateClass => $YAML::DateClass,
            };
    bless $o, $class;
    set_default($o, 'DumpCode', $YAML::UseCode);
    set_default($o, 'LoadCode', $YAML::UseCode);
    return $o if is_valid($o);
}

my $global = {}; # A global lookup
sub Bless { YAML::bless($global, @_) }
sub Blessed { YAML::blessed($global, @_) }

sub blessed {
    my ($o, $ref) = @_;
    $ref = \$_[0] unless ref $ref;
    my (undef, undef, $node_id) = YAML::Node::info($ref);
    $o->{blessed}{$node_id};
}
    
sub bless {
    my ($o, $ref, $blessing) = @_;
    my $ynode;
    $ref = \$_[0] unless ref $ref;
    my (undef, undef, $node_id) = YAML::Node::info($ref);
    if (not defined $blessing) {
        $ynode = YAML::Node->new($ref);
    }
    elsif (ref $blessing) {
        croak unless ynode($blessing);
        $ynode = $blessing;
    }
    else {
        no strict 'refs';
        my $transfer = $blessing . "::yaml_dump";
        croak unless defined &{$transfer};
        $ynode = &{$transfer}($ref);
        croak unless ynode($ynode);
    }
    $o->{blessed}{$node_id} = $ynode;
    my $object = ynode($ynode) or croak;
    return $object;
}

sub stream {
    my ($o, $stream) = @_;
    if (not defined $stream) {
        return $o->{$stream};
    }
    elsif (ref($stream) eq 'CODE') {
        $o->{stream_fetch} = $stream;
        $o->{stream_eos} = 0;
    }
    elsif ($stream eq '') {
        $o->{stream} = '';
    }
    else {
        $o->{stream} .= $stream;
    }
}

sub set_default {
    my ($o, $option, $default) = (@_);
    return if length $o->{$option};
    if (length $default) {
        $o->{$option} = $default;
    }
    else {
        $o->{$option} = -1;
    }
}

sub is_valid { 
    my ($o) = (@_);
    croak YAML_DUMP_ERR_INVALID_INDENT($o->{Indent}) 
      unless ($o->{Indent} =~ /^(\d+)$/) and $1 > 0;
    # NOTE: Add more tests...
    return 1;
}

#==============================================================================
# Save the contents of a Dump operation to a file. If the file exists
# and has data, and a concatenation was requested, then verify the
# existing header.
sub DumpFile {
    my $filename = shift;
    local $/ = "\n"; # reset special to "sane"
    my $mode = '>';
    if ($filename =~ /^\s*(>{1,2})\s*(.*)$/) {
        ($mode, $filename) = ($1, $2);
    }
    if ($mode eq '>>' && -f $filename && -s $filename) {
        open MYYAML, "< $filename" 
            or croak YAML_LOAD_ERR_FILE_INPUT($filename, $!);
        my $line = <MYYAML>;
        close MYYAML;
        croak YAML_DUMP_ERR_FILE_CONCATENATE($filename)
          unless $line =~ /^---(\s|$)/;
    }
    open MYYAML, "$mode $filename"
      or croak YAML_DUMP_ERR_FILE_OUTPUT($filename, $!);
    print MYYAML YAML::Dump(@_);
    close MYYAML;
}
    
# Serialize a list of elements
sub Dump {
    $o = YAML->new();
    $o->dump(@_);
}

# Aliases for Dump
*freeze = *freeze = \&Dump;    # alias for Storable or POE users

# OO version of Dump. YAML->new->dump($foo); 
sub dump {
    $o = shift; 
    # local $| = 1; # set buffering to "hot" (for testing) XXX
    local $/ = "\n"; # reset special to "sane" XXX (danger) fix for callbacks
    $o->{stream} = '';
    $o->{document} = 0;
    for my $document (@_) {
        $o->{document}++;
        $o->{transferred} = {};
        $o->{id_refcnt} = {};
        $o->{id_anchor} = {};
        $o->{anchor} = 1;
        $o->{level} = 0;
        $o->{offset}[0] = 0 - $o->{Indent};
        _prewalk($document);
        _emit_header($document);
        _emit_node($document);
    }
    return $o->{stream};
}

# Every YAML document in the stream must begin with a YAML header, unless
# there is only a single document and the user requests "no header".
sub _emit_header {
    my ($node) = @_;
    if (not $o->{UseHeader} and 
        $o->{document} == 1
       ) {
        croak YAML_DUMP_ERR_NO_HEADER() unless ref($node) =~ /^(HASH|ARRAY)$/;
        croak YAML_DUMP_ERR_NO_HEADER() if ref($node) eq 'HASH' and 
                                           keys(%$node) == 0;
        croak YAML_DUMP_ERR_NO_HEADER() if ref($node) eq 'ARRAY' and 
                                           @$node == 0;
        # XXX Also croak if aliased, blessed, or ynode
        $o->{headless} = 1;
        return;
    }
    $o->{stream} .= '---';
    if ($o->{UseVersion}) {
#         $o->{stream} .= " #YAML:1.0";
    }
}

# Walk the tree to be dumped and keep track of its reference counts.
# This function is where the Dumper does all its work. All transfers
# happen here.
sub _prewalk {
    my $value;
    my ($class, $type, $node_id) = YAML::Node::info(\$_[0]);
    # Handle typeglobs
    if ($type eq 'GLOB') {
        $value = $o->{transferred}{$node_id} = 
          YAML::Transfer::glob::yaml_dump($_[0]);
        return _prewalk($value);
    }
    # Handle regexps
    if (ref($_[0]) eq 'Regexp') {  
        $o->{transferred}{$node_id} = YAML::Transfer::regexp::yaml_dump($_[0]);
        return;
    }
    # Handle Purity for scalars. XXX can't find a use case yet. Might be YAGNI.
    if (not ref $_[0]) {
        $o->{id_refcnt}{$node_id}++ if $o->{Purity};
        return;
    }
    # Make a copy of original
    $value = $_[0];
    ($class, $type, $node_id) = YAML::Node::info($value);
    # Look for things already transferred.
    if ($o->{transferred}{$node_id}) {
        (undef, undef, $node_id) = (ref $o->{transferred}{$node_id})
          ? YAML::Node::info($o->{transferred}{$node_id})
          : YAML::Node::info(\ $o->{transferred}{$node_id});
        $o->{id_refcnt}{$node_id}++;
        return;
    }
    # Handle code refs
    if ($type eq 'CODE') {
        $o->{transferred}{$node_id} = 'crufty tracking reference placeholder';
        YAML::Transfer::code::yaml_dump($o->{DumpCode},
                                        $_[0], 
                                        $o->{transferred}{$node_id});
        ($class, $type, $node_id) = 
          YAML::Node::info(\ $o->{transferred}{$node_id});
        $o->{id_refcnt}{$node_id}++;
        return;
    }
    # Handle blessed things
    elsif (defined $class) {
        no strict 'refs';
        if ($class eq $o->{DateClass}) {
            $value = eval "&${class}::yaml_dump(\$value)";
        }
        elsif (defined &{$class . "::yaml_dump"}) {
            $value = eval "&${class}::yaml_dump(\$value)";
        }
        elsif ($type eq 'SCALAR') {
            $o->{transferred}{$node_id} = 'tracking reference placeholder';
            YAML::Transfer::blessed::yaml_dump
              ($_[0], $o->{transferred}{$node_id});
            ($class, $type, $node_id) =
              YAML::Node::info(\ $o->{transferred}{$node_id});
            $o->{id_refcnt}{$node_id}++;
            return;
        }
        else {
            $value = YAML::Transfer::blessed::yaml_dump($value);
        }
        $o->{transferred}{$node_id} = $value;
        (undef, $type, $node_id) = YAML::Node::info($value);
    }
    # Handle YAML Blessed things
    if (defined $global->{blessed}{$node_id}) {
        $value = $global->{blessed}{$node_id};
        $o->{transferred}{$node_id} = $value;
        ($class, $type, $node_id) = YAML::Node::info($value);
        return _prewalk($value);
    }
    # Handle hard refs
    if ($type eq 'REF' or $type eq 'SCALAR') {
        $value = YAML::Transfer::ref::yaml_dump($value);
        $o->{transferred}{$node_id} = $value;
        (undef, $type, $node_id) = YAML::Node::info($value);
    }
    # Handle ref-to-glob's
    elsif ($type eq 'GLOB') {
        my $ref_ynode = $o->{transferred}{$node_id} =
          YAML::Transfer::ref::yaml_dump($value);

        my $glob_ynode = $ref_ynode->{&VALUE} = 
          YAML::Transfer::glob::yaml_dump($$value);

        (undef, undef, $node_id) = YAML::Node::info($glob_ynode);
        $o->{transferred}{$node_id} = $glob_ynode;
        return _prewalk($glob_ynode);
    }
      
    # Increment ref count for node
    return if ++($o->{id_refcnt}{$node_id}) > 1;

    # Continue walking
    if ($type eq 'HASH') {
        _prewalk($value->{$_}) for keys %{$value};
    }
    elsif ($type eq 'ARRAY') {
        _prewalk($_) for @{$value};
    }
}

# Every data element and sub data element is a node. Everything emitted
# goes through this function.
sub _emit_node {
    my ($type, $node_id);
    my $ref = ref($_[0]);
    if ($ref and $ref ne 'Regexp') {
        (undef, $type, $node_id) = YAML::Node::info($_[0]);
    }
    else {
        $type = $ref || 'SCALAR';
        (undef, undef, $node_id) = YAML::Node::info(\$_[0]);
    }

    my ($ynode, $family) = ('') x 2;
    my ($value, $context) = (@_, 0); # XXX don't copy scalars
    if (defined $o->{transferred}{$node_id}) {
        $value = $o->{transferred}{$node_id};
        $ynode = ynode($value);
        if (ref $value) {
            $family = defined $ynode ? $ynode->family->short : '';
            (undef, $type, $node_id) = YAML::Node::info($value);
        }
        else {
            $family = ynode($o->{transferred}{$node_id})->family->short;
            $type = 'SCALAR';
            (undef, undef, $node_id) = 
              YAML::Node::info(\ $o->{transferred}{$node_id});
        }
    }
    elsif ($ynode = ynode($value)) {
        $family = $ynode->family->short;
    }

    if ($o->{UseAliases}) {
        $o->{id_refcnt}{$node_id} ||= 0;
        if ($o->{id_refcnt}{$node_id} > 1) {
            if (defined $o->{id_anchor}{$node_id}) {
                $o->{stream} .= ' *' . $o->{id_anchor}{$node_id} . "\n";
                return;
            }
            my $anchor = $o->{AnchorPrefix} . $o->{anchor}++;
            $o->{stream} .= ' &' . $anchor;
            $o->{id_anchor}{$node_id} = $anchor;
        }
    }

    return _emit_scalar($value, $family) if $type eq 'SCALAR' and $family;
    return _emit_str($value) if $type eq 'SCALAR';
    return _emit_mapping($value, $family, $node_id, $context) if $type eq 'HASH';
    return _emit_sequence($value, $family) if $type eq 'ARRAY';
    warn YAML_DUMP_WARN_BAD_NODE_TYPE($type) if $^W;
    return _emit_str("$value");
}

# A YAML mapping is akin to a Perl hash. 
sub _emit_mapping {
    my ($value, $family, $node_id, $context) = @_;
    $o->{stream} .= " !$family" if $family;

    # Sometimes 'keys' fails. Like on a bad tie implementation.
    my $empty_hash = not(eval {keys %$value});
    warn YAML_EMIT_WARN_KEYS($@) if $^W and $@;
    return ($o->{stream} .= " {}\n") if $empty_hash;
        
    # If CompressSeries is on (default) and legal is this context, then
    # use it and make the indent level be 2 for this node.
    if ($context == FROMARRAY and $o->{CompressSeries} and
        not (defined $o->{id_anchor}{$node_id} or $family or $empty_hash)
       ) {
        $o->{stream} .= ' ';
        $o->{offset}[$o->{level}+1] = $o->{offset}[$o->{level}] + 2;
    }
    else {
        $context = 0;
        $o->{stream} .= "\n" unless $o->{headless} && not($o->{headless} = 0);
        $o->{offset}[$o->{level}+1] = $o->{offset}[$o->{level}] + $o->{Indent};
    }

    $o->{level}++;
    my @keys;
    if ($o->{SortKeys} == 1) {
        if (ynode($value)) {
            @keys = keys %$value;
        }
        else {
            @keys = sort keys %$value;
        }
    }
    elsif ($o->{SortKeys} == 2) {
        @keys = sort keys %$value;
    }
    # XXX This is hackish but sometimes handy. Not sure whether to leave it in.
    elsif (ref($o->{SortKeys}) eq 'ARRAY') {
        my $i = 1;
        my %order = map { ($_, $i++) } @{$o->{SortKeys}};
        @keys = sort {
            (defined $order{$a} and defined $order{$b})
              ? ($order{$a} <=> $order{$b})
              : ($a cmp $b);
        } keys %$value;
    }
    else {
        @keys = keys %$value;
    }
    # Force the YAML::VALUE ('=') key to sort last.
    if (exists $value->{&VALUE}) {
        for (my $i = 0; $i < @keys; $i++) {
            if ($keys[$i] eq &VALUE) {
                splice(@keys, $i, 1);
                push @keys, &VALUE;
                last;
            }
        }
    }

    for my $key (@keys) {
        _emit_key($key, $context);
        $context = 0;
        $o->{stream} .= ':';
        _emit_node($value->{$key});
    }
    $o->{level}--;
}

# A YAML series is akin to a Perl array.
sub _emit_sequence {
    my ($value, $family) = @_;
    $o->{stream} .= " !$family" if $family;

    return ($o->{stream} .= " []\n") if @$value == 0;
        
    $o->{stream} .= "\n" unless $o->{headless} && not($o->{headless} = 0);

    # XXX Really crufty feature. Better implemented by ynodes.
    if ($o->{InlineSeries} and
        @$value <= $o->{InlineSeries} and
        not (scalar grep {ref or /\n/} @$value)
       ) {
        $o->{stream} =~ s/\n\Z/ /;
        $o->{stream} .= '[';
        for (my $i = 0; $i < @$value; $i++) {
            _emit_str($value->[$i], KEY);
            last if $i == $#{$value};
            $o->{stream} .= ', ';
        }
        $o->{stream} .= "]\n";
        return;
    }

    $o->{offset}[$o->{level} + 1] = $o->{offset}[$o->{level}] + $o->{Indent};
    $o->{level}++;
    for my $val (@$value) {
        $o->{stream} .= ' ' x $o->{offset}[$o->{level}];
        $o->{stream} .= '-';
        _emit_node($val, FROMARRAY);
    }
    $o->{level}--;
}

# Emit a mapping key
sub _emit_key {
    my ($value, $context) = @_;
    $o->{stream} .= ' ' x $o->{offset}[$o->{level}]
      unless $context == FROMARRAY;
    _emit_str($value, KEY);
}

# Emit a blessed SCALAR
sub _emit_scalar {
    my ($value, $family) = @_;
    $o->{stream} .= " !$family";
    _emit_str($value, BLESSED);
}

sub _emit {
    $o->{stream} .= join '', @_;
}

# Emit a string value. YAML has many scalar styles. This routine attempts to
# guess the best style for the text.
sub _emit_str {
    my $type = $_[1] || 0;

    # Use heuristics to find the best scalar emission style.
    $o->{offset}[$o->{level} + 1] = $o->{offset}[$o->{level}] + $o->{Indent};
    $o->{level}++;

    my $sf = $type == KEY ? '' : ' ';
    my $sb = $type == KEY ? '? ' : ' ';
    my $ef = $type == KEY ? '' : "\n";
    my $eb = "\n";

    while (1) {
        _emit($sf), _emit_plain($_[0]), _emit($ef), last 
          if not defined $_[0];
        _emit($sf, '=', $ef), last
          if $_[0] eq VALUE;
        _emit($sf), _emit_double($_[0]), _emit($ef), last
          if $_[0] =~ /$ESCAPE_CHAR/;
        if ($_[0] =~ /\n/) {
            _emit($sb), _emit_block($LIT_CHAR, $_[0]), _emit($eb), last
              if $o->{UseBlock};
            _emit($sb), _emit_block($FOLD_CHAR, $_[0]), _emit($eb), last
              if $o->{UseFold};
            _emit($sf), _emit_double($_[0]), _emit($ef), last
              if length $_[0] <= 30;
            _emit($sb), _emit_block($FOLD_CHAR, $_[0]), _emit($eb), last
              if $_[0] =~ /^\S[^\n]{76}/m;
            _emit($sf), _emit_double($_[0]), _emit($ef), last
              if $_[0] !~ /\n\s*\S/;
            _emit($sb), _emit_block($LIT_CHAR, $_[0]), _emit($eb), last;
        }
        _emit($sf), _emit_plain($_[0]), _emit($ef), last
          if is_valid_plain($_[0]);
        _emit($sf), _emit_double($_[0]), _emit($ef), last
          if $_[0] =~ /'/;
        _emit($sf), _emit_single($_[0]), _emit($ef);
        last;
    }

    $o->{level}--;

    return;
}

# Check whether or not a scalar should be emitted as an plain scalar.
sub is_valid_plain {
    return 0 unless length $_[0];
    # refer: parse_inline_simple()
    return 0 if $_[0] =~ /^[\s\{\[\~\`\'\"\!\@\#\%\&\*\^]/;
    return 0 if $_[0] =~ /[\{\[\]\},]/;
    return 0 if $_[0] =~ /[:\-\?]\s/;
    return 0 if $_[0] =~ /\s#/;
    return 0 if $_[0] =~ /\:(\s|$)/;
    return 0 if $_[0] =~ /\s$/;
    return 1;
}

# A nested scalar is either block or folded 
sub _emit_block {
    my ($indicator, $value) = @_;
    $o->{stream} .= $indicator;
    $value =~ /(\n*)\Z/;
    my $chomp = length $1 ? (length $1 > 1) ? '+' : '' : '-';
    $value = '~' if not defined $value;
    $o->{stream} .= $chomp;
    $o->{stream} .= $o->{Indent} if $value =~ /^\s/;
    if ($indicator eq $FOLD_CHAR) {
        $value = fold($value);
        chop $value unless $chomp eq '+';
    }
    $o->{stream} .= indent($value);
}

# Plain means that the scalar is unquoted.
sub _emit_plain {
    $o->{stream} .= defined $_[0] ? $_[0] : '~';
}

# Double quoting is for single lined escaped strings.
sub _emit_double {
    (my $escaped = escape($_[0])) =~ s/"/\\"/g;
    $o->{stream} .= qq{"$escaped"};
}

# Single quoting is for single lined unescaped strings.
sub _emit_single {
    my $item = shift;
    $item =~ s{'}{''}g;
    $o->{stream} .= "'$item'";
}

#==============================================================================
# Read a YAML stream from a file and call Load on it.
sub LoadFile {
    my $filename = shift;
    local $/ = "\n"; # reset special to "sane"
    open MYYAML, $filename or croak YAML_LOAD_ERR_FILE_INPUT($filename, $!);
    my $yaml = join '', <MYYAML>;
    close MYYAML;
    return Load($yaml);
}

# Deserialize a YAML stream into a list of data elements
sub Load {
    croak YAML_LOAD_USAGE() unless @_ == 1;
    $o = YAML->new;
    $o->{stream} = defined $_[0] ? $_[0] : '';
    return load();
}

# Aliases for Load
*Undent = *Undent = \&Load;
*Eval = *Eval = \&Load;
*thaw = *thaw = \&Load;

# OO version of Load
sub load {
    # local $| = 1; # set buffering to "hot" (for testing)
    local $/ = "\n"; # reset special to "sane"
    return _parse();
}

# Top level function for parsing. Parse each document in order and
# handle processing for YAML headers.
sub _parse {
    my (%directives, $preface);
    $o->{stream} =~ s|\015\012|\012|g;
    $o->{stream} =~ s|\015|\012|g;
    $o->{line} = 0;
    croak YAML_PARSE_ERR_BAD_CHARS() 
      if $o->{stream} =~ /$ESCAPE_CHAR/;
    croak YAML_PARSE_ERR_NO_FINAL_NEWLINE() 
      if length($o->{stream}) and 
         $o->{stream} !~ s/(.)\n\Z/$1/s;
    @{$o->{lines}} = split /\x0a/, $o->{stream}, -1;
    $o->{line} = 1;
    # Throw away any comments or blanks before the header (or start of
    # content for headerless streams)
    _parse_throwaway_comments();
    $o->{document} = 0;
    $o->{documents} = [];
    # Add an "assumed" header if there is no header and the stream is
    # not empty (after initial throwaways).
    if (not $o->{eos}) {
        if ($o->{lines}[0] !~ /^---(\s|$)/) {
            unshift @{$o->{lines}}, '---';
            $o->{line}--;
        }
    }

    # Main Loop. Parse out all the top level nodes and return them.
    while (not $o->{eos}) {
        $o->{anchor2node} = {};
        $o->{document}++;
        $o->{done} = 0;
        $o->{level} = 0;
        $o->{offset}[0] = -1;

        if ($o->{lines}[0] =~ /^---\s*(.*)$/) {
            my @words = split /\s+/, $1;
            %directives = ();
            while (@words && $words[0] =~ /^#(\w+):(\S.*)$/) {
                my ($key, $value) = ($1, $2);
                shift(@words);
                if (defined $directives{$key}) {
                    warn YAML_PARSE_WARN_MULTIPLE_DIRECTIVES
                      ($key, $o->{document}) if $^W;
                    next;
                }
                $directives{$key} = $value;
            }
            $o->{preface} = join ' ', @words;
        }
        else {
            croak YAML_PARSE_ERR_NO_SEPARATOR();
        }

        if (not $o->{done}) {
            _parse_next_line(COLLECTION);
        }
        if ($o->{done}) {
            $o->{indent} = -1;
            $o->{content} = '';
        }

        $directives{YAML} ||= '1.0';
        $directives{TAB} ||= 'NONE';
        ($o->{major_version}, $o->{minor_version}) = 
          split /\./, $directives{YAML}, 2;
        croak YAML_PARSE_ERR_BAD_MAJOR_VERSION($directives{YAML})
          if ($o->{major_version} ne '1');
        warn YAML_PARSE_WARN_BAD_MINOR_VERSION($directives{YAML})
          if ($^W and $o->{minor_version} ne '0');
        croak "Unrecognized TAB policy"  # XXX add to ::Error
          unless $directives{TAB} =~ /^(NONE|\d+)(:HARD)?$/;
        

        push @{$o->{documents}}, _parse_node();
    }
    return wantarray ? @{$o->{documents}} : $o->{documents}[-1];
}

# This function is the dispatcher for parsing each node. Every node
# recurses back through here. (Inlines are an exception as they have
# their own sub-parser.)
sub _parse_node {
# ??????????????????????????????????????    
# $|=1;
# print <<END;
# _parse_node ${\++$YAML::x}
# indent  - $o->{indent}
# preface - $o->{preface}
# content - $o->{content}
# level   - $o->{level}
# offsets - @{$o->{offset}}
# END
# ??????????????????????????????????????    
    my $preface = $o->{preface};
    $o->{preface} = '';
    my ($node, $type, $indicator, $escape, $chomp) = ('') x 5;
    my ($anchor, $alias, $explicit, $implicit, $class) = ('') x 5;
    ($anchor, $alias, $explicit, $implicit, $class, $preface) = 
      _parse_qualifiers($preface);
    if ($anchor) {
        $o->{anchor2node}{$anchor} = CORE::bless [], 'YAML-anchor2node';
    }
    $o->{inline} = '';
    while (length $preface) {
        my $line = $o->{line} - 1;
        # XXX rking suggests refactoring the following regex and its evil twin
        if ($preface =~ s/^($FOLD_CHAR|$LIT_CHAR_RX)(-|\+)?\d*\s*//) { 
            $indicator = $1;
            $chomp = $2 if defined($2);
        }
        else {
            croak YAML_PARSE_ERR_TEXT_AFTER_INDICATOR() if $indicator;
            $o->{inline} = $preface;
            $preface = '';
        }
    }
    if ($alias) {
        croak YAML_PARSE_ERR_NO_ANCHOR($alias) 
          unless defined $o->{anchor2node}{$alias};
        if (ref($o->{anchor2node}{$alias}) ne 'YAML-anchor2node') {
            $node = $o->{anchor2node}{$alias};
        }
        else {
            $node = do {my $sv = "*$alias"};
            push @{$o->{anchor2node}{$alias}}, [\$node, $o->{line}]; 
        }
    }
    elsif (length $o->{inline}) {
        $node = _parse_inline(1, $implicit, $explicit, $class);
        if (length $o->{inline}) {
            croak YAML_PARSE_ERR_SINGLE_LINE(); 
        }
    }
    elsif ($indicator eq $LIT_CHAR) {
        $o->{level}++;
        $node = _parse_block($chomp);
        $node = _parse_implicit($node) if $implicit;
        $o->{level}--; 
    }
    elsif ($indicator eq $FOLD_CHAR) {
        $o->{level}++;
        $node = _parse_unfold($chomp);
        $node = _parse_implicit($node) if $implicit;
        $o->{level}--;
    }
    else {
        $o->{level}++;
        $o->{offset}[$o->{level}] ||= 0;
        if ($o->{indent} == $o->{offset}[$o->{level}]) {
            if ($o->{content} =~ /^-( |$)/) {
                $node = _parse_seq($anchor);
            }
            elsif ($o->{content} =~ /(^\?|\:( |$))/) {
                $node = _parse_mapping($anchor);
            }
            elsif ($preface =~ /^\s*$/) {
                $node = _parse_implicit('');
            }
            else {
                croak YAML_PARSE_ERR_BAD_NODE();
            }
        }
        else {
            $node = '';
        }
        $o->{level}--;
    }
    $#{$o->{offset}} = $o->{level};

    if ($explicit) {
        if ($class) {
            if (not ref $node) {
                my $copy = $node;
                undef $node;
                $node = \$copy;
            }
            CORE::bless $node, $class;
        }
        else {
            $node = _parse_explicit($node, $explicit);
        }
    }
    if ($anchor) {
        if (ref($o->{anchor2node}{$anchor}) eq 'YAML-anchor2node') {
            # XXX Can't remember what this code actually does
            for my $ref (@{$o->{anchor2node}{$anchor}}) {
                ${$ref->[0]} = $node;
                warn YAML_LOAD_WARN_UNRESOLVED_ALIAS($anchor, $ref->[1]) if $^W;
            }
        }
        $o->{anchor2node}{$anchor} = $node;
    }
    return $node;
}

# Preprocess the qualifiers that may be attached to any node.
sub _parse_qualifiers {
    my ($preface) = @_;
    my ($anchor, $alias, $explicit, $implicit, $class, $token) = ('') x 6;
    $o->{inline} = '';
    while ($preface =~ /^[&*!]/) {
        my $line = $o->{line} - 1;
        if ($preface =~ s/^\!(\S+)\s*//) {
            croak YAML_PARSE_ERR_MANY_EXPLICIT() if $explicit;
            $explicit = $1;
        }
        elsif ($preface =~ s/^\!\s*//) {
            croak YAML_PARSE_ERR_MANY_IMPLICIT() if $implicit;
            $implicit = 1;
        }
        elsif ($preface =~ s/^\&([^ ,:]+)\s*//) {
            $token = $1;
            croak YAML_PARSE_ERR_BAD_ANCHOR() 
              unless $token =~ /^[a-zA-Z0-9]+$/;
            croak YAML_PARSE_ERR_MANY_ANCHOR() if $anchor;
            croak YAML_PARSE_ERR_ANCHOR_ALIAS() if $alias;
            $anchor = $token;
        }
        elsif ($preface =~ s/^\*([^ ,:]+)\s*//) {
            $token = $1;
            croak YAML_PARSE_ERR_BAD_ALIAS() unless $token =~ /^[a-zA-Z0-9]+$/;
            croak YAML_PARSE_ERR_MANY_ALIAS() if $alias;
            croak YAML_PARSE_ERR_ANCHOR_ALIAS() if $anchor;
            $alias = $token;
        }
    }
    return ($anchor, $alias, $explicit, $implicit, $class, $preface); 
}

# Morph a node to it's explicit type  
sub _parse_explicit {
    my ($node, $explicit) = @_;
    if ($explicit =~ m{^(int|float|bool|date|time|datetime|binary)$}) {
        my $handler = "YAML::_load_$1";
        no strict 'refs';
        return &$handler($node);
    }
    elsif ($explicit =~ m{^perl/(glob|regexp|code|ref)\:(\w(\w|\:\:)*)?$}) {
        my ($type, $class) = (($1 || ''), ($2 || ''));
        my $handler = "YAML::_load_perl_$type";
        no strict 'refs';
        if (defined &$handler) {
            return &$handler($node, $class);
        }
        else {
            croak YAML_LOAD_ERR_NO_CONVERT('XXX', $explicit);
        }
    }
    elsif ($explicit =~ m{^perl/(\@|\$)?([a-zA-Z](\w|::)+)$}) {
        my ($package) = ($2);
        my $handler = "${package}::yaml_load";
        no strict 'refs';
        if (defined &$handler) {
            return &$handler(YAML::Node->new($node, $explicit));
        }
        else {
            return CORE::bless $node, $package;
        }
    }
    elsif ($explicit !~ m|/|) {
        croak YAML_LOAD_ERR_NO_CONVERT('XXX', $explicit);
    }
    else {
        return YAML::Node->new($node, $explicit);
    }
}

# Morph to a perl reference
sub _load_perl_ref {
    my ($node) = @_;
    croak YAML_LOAD_ERR_NO_DEFAULT_VALUE('ptr') unless exists $node->{&VALUE};
    return \$node->{&VALUE};
}

# Morph to a perl regexp
sub _load_perl_regexp {
    my ($node) = @_;
    my ($regexp, $modifiers);
    if (defined $node->{REGEXP}) {
        $regexp = $node->{REGEXP};
        delete $node->{REGEXP};
    }
    else {
        warn YAML_LOAD_WARN_NO_REGEXP_IN_REGEXP() if $^W;
        return undef;
    }
    if (defined $node->{MODIFIERS}) {
        $modifiers = $node->{MODIFIERS};
        delete $node->{MODIFIERS};
    } else {
        $modifiers = '';
    }
    for my $elem (sort keys %$node) {
        warn YAML_LOAD_WARN_BAD_REGEXP_ELEM($elem) if $^W;
    }
    my $value = eval "qr($regexp)$modifiers";
    if ($@) {
        warn YAML_LOAD_WARN_REGEXP_CREATE($regexp, $modifiers, $@) if $^W;
        return undef;
    }
    return $value;
}

# Morph to a perl glob
sub _load_perl_glob {
    my ($node) = @_;
    my ($name, $package);
    if (defined $node->{NAME}) {
        $name = $node->{NAME};
        delete $node->{NAME};
    }
    else {
        warn YAML_LOAD_WARN_GLOB_NAME() if $^W;
        return undef;
    }
    if (defined $node->{PACKAGE}) {
        $package = $node->{PACKAGE};
        delete $node->{PACKAGE};
    } else {
        $package = 'main';
    }
    no strict 'refs';
    if (exists $node->{SCALAR}) {
        *{"${package}::$name"} = \$node->{SCALAR};
        delete $node->{SCALAR};
    }
    for my $elem (qw(ARRAY HASH CODE IO)) {
        if (exists $node->{$elem}) {
            if ($elem eq 'IO') {
                warn YAML_LOAD_WARN_GLOB_IO() if $^W;
                delete $node->{IO};
                next;
            }
            *{"${package}::$name"} = $node->{$elem};
            delete $node->{$elem};
        }
    }
    for my $elem (sort keys %$node) {
        warn YAML_LOAD_WARN_BAD_GLOB_ELEM($elem) if $^W;
    }
    return *{"${package}::$name"};
}

# Special support for an empty mapping
#sub _parse_str_to_map {
#    my ($node) = @_;
#    croak YAML_LOAD_ERR_NON_EMPTY_STRING('mapping') unless $node eq '';
#    return {};
#}

# Special support for an empty sequence
#sub _parse_str_to_seq {
#    my ($node) = @_;
#    croak YAML_LOAD_ERR_NON_EMPTY_STRING('sequence') unless $node eq '';
#    return [];
#}

# Support for sparse sequences
#sub _parse_map_to_seq {
#    my ($node) = @_;
#    my $seq = [];
#    for my $index (keys %$node) {
#        croak YAML_LOAD_ERR_BAD_MAP_TO_SEQ($index) unless $index =~ /^\d+/;
#        $seq->[$index] = $node->{$index};
#    }
#    return $seq;
#}

# Support for !int
sub _load_int {
    my ($node) = @_;
    croak YAML_LOAD_ERR_BAD_STR_TO_INT() unless $node =~ /^-?\d+$/;
    return $node;
}

# Support for !date
sub _load_date {
    my ($node) = @_;
    croak YAML_LOAD_ERR_BAD_STR_TO_DATE() unless $node =~ /^\d\d\d\d-\d\d-\d\d$/;
    return $node;
}

# Support for !time
sub _load_time {
    my ($node) = @_;
    croak YAML_LOAD_ERR_BAD_STR_TO_TIME() unless $node =~ /^\d\d:\d\d:\d\d$/;
    return $node;
}

# Support for !perl/code;deparse
sub _load_perl_code {
    my ($node, $class) = @_;
    if ($o->{LoadCode}) {
        my $code = eval "package main; sub $node";
        if ($@) {
            warn YAML_LOAD_WARN_PARSE_CODE($@) if $^W;
            return sub {};
        }
        else {
            CORE::bless $code, $class if $class;
            return $code;
        }
    }
    else {
        return sub {};
    }
}

# Parse a YAML mapping into a Perl hash
sub _parse_mapping {
    my ($anchor) = @_;
    my $mapping = {};
    $o->{anchor2node}{$anchor} = $mapping;
    my $key;
    while (not $o->{done} and $o->{indent} == $o->{offset}[$o->{level}]) {
        # If structured key:
        if ($o->{content} =~ s/^\?\s*//) {
            $o->{preface} = $o->{content};
            _parse_next_line(COLLECTION);
            $key = _parse_node();
            $key = "$key";
        }
        # If "default" key (equals sign) 
        elsif ($o->{content} =~ s/^\=\s*//) {
            $key = VALUE;
        }
        # If "comment" key (slash slash)
        elsif ($o->{content} =~ s/^\=\s*//) {
            $key = COMMENT;
        }
        # Regular scalar key:
        else {
            $o->{inline} = $o->{content};
            $key = _parse_inline();
            $key = "$key";
            $o->{content} = $o->{inline};
            $o->{inline} = '';
        }
            
        unless ($o->{content} =~ s/^:\s*//) {
            croak YAML_LOAD_ERR_BAD_MAP_ELEMENT();
        }
        $o->{preface} = $o->{content};
        my $line = $o->{line};
        _parse_next_line(COLLECTION);
        my $value = _parse_node();
        if (exists $mapping->{$key}) {
            warn YAML_LOAD_WARN_DUPLICATE_KEY() if $^W;
        }
        else {
            $mapping->{$key} = $value;
        }
    }
    return $mapping;
}

# Parse a YAML sequence into a Perl array
sub _parse_seq {
    my ($anchor) = @_;
    my $seq = [];
    $o->{anchor2node}{$anchor} = $seq;
    while (not $o->{done} and $o->{indent} == $o->{offset}[$o->{level}]) {
        if ($o->{content} =~ /^-(?: (.*))?$/) {
            $o->{preface} = defined($1) ? $1 : '';
        }
        else {
            croak YAML_LOAD_ERR_BAD_SEQ_ELEMENT();
        }
        if ($o->{preface} =~ /^(\s*)(\w.*\:(?: |$).*)$/) {
            $o->{indent} = $o->{offset}[$o->{level}] + 2 + length($1);
            $o->{content} = $2;
            $o->{offset}[++$o->{level}] = $o->{indent};
            $o->{preface} = '';
            push @$seq, _parse_mapping('');
            $o->{level}--;
            $#{$o->{offset}} = $o->{level};
        }
        else {
            _parse_next_line(COLLECTION);
            push @$seq, _parse_node();
        }
    }
    return $seq;
}

# Parse an inline value. Since YAML supports inline collections, this is
# the top level of a sub parsing.
sub _parse_inline {
    my ($top, $top_implicit, $top_explicit, $top_class) = (@_, '', '', '', '');
    $o->{inline} =~ s/^\s*(.*)\s*$/$1/; # OUCH - mugwump
    my ($node, $anchor, $alias, $explicit, $implicit, $class) = ('') x 6;
    ($anchor, $alias, $explicit, $implicit, $class, $o->{inline}) = 
      _parse_qualifiers($o->{inline});
    if ($anchor) {
        $o->{anchor2node}{$anchor} = CORE::bless [], 'YAML-anchor2node';
    }
    $implicit ||= $top_implicit;
    $explicit ||= $top_explicit;
    $class ||= $top_class;
    ($top_implicit, $top_explicit, $top_class) = ('', '', '');
    if ($alias) {
        croak YAML_PARSE_ERR_NO_ANCHOR($alias) 
          unless defined $o->{anchor2node}{$alias};
        if (ref($o->{anchor2node}{$alias}) ne 'YAML-anchor2node') {
            $node = $o->{anchor2node}{$alias};
        }
        else {
            $node = do {my $sv = "*$alias"};
            push @{$o->{anchor2node}{$alias}}, [\$node, $o->{line}]; 
        }
    }
    elsif ($o->{inline} =~ /^\{/) {
        $node = _parse_inline_mapping($anchor);
    }
    elsif ($o->{inline} =~ /^\[/) {
        $node = _parse_inline_seq($anchor);
    }
    elsif ($o->{inline} =~ /^"/) {
        $node = _parse_inline_double_quoted();
        $node = _unescape($node);
        $node = _parse_implicit($node) if $implicit;
    }
    elsif ($o->{inline} =~ /^'/) {
        $node = _parse_inline_single_quoted();
        $node = _parse_implicit($node) if $implicit;
    }
    else {
        if ($top) {
            $node = $o->{inline};
            $o->{inline} = '';
        }
        else {
            $node = _parse_inline_simple();
        }
        $node = _parse_implicit($node) unless $explicit;
    }
    if ($explicit) {
        if ($class) {
            if (not ref $node) {
                my $copy = $node;
                undef $node;
                $node = \$copy;
            }
            CORE::bless $node, $class;
        }
        else {
            $node = _parse_explicit($node, $explicit);
        }
    }
    if ($anchor) {
        if (ref($o->{anchor2node}{$anchor}) eq 'YAML-anchor2node') {
            for my $ref (@{$o->{anchor2node}{$anchor}}) {
                ${$ref->[0]} = $node;
                warn YAML_LOAD_WARN_UNRESOLVED_ALIAS($anchor, $ref->[1]) if $^W;
            }
        }
        $o->{anchor2node}{$anchor} = $node;
    }
    return $node;
}

# Parse the inline YAML mapping into a Perl hash
sub _parse_inline_mapping {
    my ($anchor) = @_;
    my $node = {};
    $o->{anchor2node}{$anchor} = $node;

    croak YAML_PARSE_ERR_INLINE_MAP() unless $o->{inline} =~ s/^\{\s*//;
    while (not $o->{inline} =~ s/^\}//) {
        my $key = _parse_inline();
        croak YAML_PARSE_ERR_INLINE_MAP() unless $o->{inline} =~ s/^\: \s*//;
        my $value = _parse_inline();
        if (exists $node->{$key}) {
            warn YAML_LOAD_WARN_DUPLICATE_KEY() if $^W;
        }
        else {
            $node->{$key} = $value;
        }
        next if $o->{inline} =~ /^\}/;
        croak YAML_PARSE_ERR_INLINE_MAP() unless $o->{inline} =~ s/^\,\s*//;
    }
    return $node;
}

# Parse the inline YAML sequence into a Perl array
sub _parse_inline_seq {
    my ($anchor) = @_;
    my $node = [];
    $o->{anchor2node}{$anchor} = $node;

    croak YAML_PARSE_ERR_INLINE_SEQUENCE() unless $o->{inline} =~ s/^\[\s*//;
    while (not $o->{inline} =~ s/^\]//) {
        my $value = _parse_inline();
        push @$node, $value;
        next if $o->{inline} =~ /^\]/;
        croak YAML_PARSE_ERR_INLINE_SEQUENCE() 
          unless $o->{inline} =~ s/^\,\s*//;
    }
    return $node;
}

# Parse the inline double quoted string.
sub _parse_inline_double_quoted {
    my $node;
    if ($o->{inline} =~ /^"((?:\\"|[^"])*)"\s*(.*)$/) {
        $node = $1;
        $o->{inline} = $2;
        $node =~ s/\\"/"/g;
    } else {
        croak YAML_PARSE_ERR_BAD_DOUBLE();
    }
    return $node;
}


# Parse the inline single quoted string.
sub _parse_inline_single_quoted {
    my $node;
    if ($o->{inline} =~ /^'((?:''|[^'])*)'\s*(.*)$/) {
        $node = $1;
        $o->{inline} = $2;
        $node =~ s/''/'/g;
    } else {
        croak YAML_PARSE_ERR_BAD_SINGLE();
    }
    return $node;
}

# Parse the inline unquoted string and do implicit typing.
sub _parse_inline_simple {
    my $value;
    if ($o->{inline} =~ /^(|[^!@#%^&*].*?)(?=[\[\]\{\},]|, |: |- |:\s*$|$)/) {
        $value = $1;
        substr($o->{inline}, 0, length($1)) = '';
    }
    else {
        croak YAML_PARSE_ERR_BAD_INLINE_IMPLICIT($value);
    }
    return $value;
}

sub _parse_implicit {
    my ($value) = @_;
    $value =~ s/\s*$//;
    return $value if $value eq '';
    return undef if $value =~ /^~$/;
    return $value
      unless $value =~ /^[\@\`\^]/ or
             $value =~ /^[\-\?]\s/;
    croak YAML_PARSE_ERR_BAD_IMPLICIT($value);
}

# Unfold a YAML multiline scalar into a single string.
sub _parse_unfold {
    my ($chomp) = @_;
    my $node = '';
    my $space = 0;
    while (not $o->{done} and $o->{indent} == $o->{offset}[$o->{level}]) {
        $node .= "$o->{content}\n";
        _parse_next_line(LEAF);
    }
    $node =~ s/^(\S.*)\n(?=\S)/$1 /gm;
    $node =~ s/^(\S.*)\n(\n+\S)/$1$2/gm;
    $node =~ s/\n*\Z// unless $chomp eq '+';
    $node .= "\n" unless $chomp;
    return $node;
}

# Parse a YAML block style scalar. This is like a Perl here-document.
sub _parse_block {
    my ($chomp) = @_;
    my $node = '';
    while (not $o->{done} and $o->{indent} == $o->{offset}[$o->{level}]) {
        $node .= $o->{content} . "\n";
        _parse_next_line(LEAF);
    }
    return $node if '+' eq $chomp;
    $node =~ s/\n*\Z/\n/;
    $node =~ s/\n\Z// if $chomp eq '-';
    return $node;
}

# Handle Perl style '#' comments. Comments must be at the same indentation
# level as the collection line following them.
sub _parse_throwaway_comments {
    while (@{$o->{lines}} and
           $o->{lines}[0] =~ m{^\s*(\#|$)}
          ) {
        shift @{$o->{lines}};
        $o->{line}++;
    }
    $o->{eos} = $o->{done} = not @{$o->{lines}};
}

# This is the routine that controls what line is being parsed. It gets called
# once for each line in the YAML stream.
#
# This routine must:
# 1) Skip past the current line
# 2) Determine the indentation offset for a new level
# 3) Find the next _content_ line
#   A) Skip over any throwaways (Comments/blanks)
#   B) Set $o->{indent}, $o->{content}, $o->{line}
# 4) Expand tabs appropriately  
sub _parse_next_line {
    my ($type) = @_;
    my $level = $o->{level};
    my $offset = $o->{offset}[$level];
    croak YAML_EMIT_ERR_BAD_LEVEL() unless defined $offset;
    shift @{$o->{lines}};
    $o->{eos} = $o->{done} = not @{$o->{lines}};
    return if $o->{eos};
    $o->{line}++;

    # Determine the offset for a new leaf node
    if ($o->{preface} =~ qr/(?:$FOLD_CHAR|$LIT_CHAR_RX)(?:-|\+)?(\d*)\s*$/) {
        croak YAML_PARSE_ERR_ZERO_INDENT() if length($1) and $1 == 0;
        $type = LEAF;
        if (length($1)) {
            $o->{offset}[$level + 1] = $offset + $1;
        }
        else {
            # First get rid of any comments.
            while (@{$o->{lines}} && ($o->{lines}[0] =~ /^\s*#/)) {
                $o->{lines}[0] =~ /^( *)/ or die;
                last unless length($1) <= $offset;
                shift @{$o->{lines}};
                $o->{line}++;
            }
            $o->{eos} = $o->{done} = not @{$o->{lines}};
            return if $o->{eos};
            if ($o->{lines}[0] =~ /^( *)\S/ and length($1) > $offset) {
                $o->{offset}[$level+1] = length($1);
            }
            else {
                $o->{offset}[$level+1] = $offset + 1;
            }
        }
        $offset = $o->{offset}[++$level];
    }
    # Determine the offset for a new collection level
    elsif ($type == COLLECTION and 
           $o->{preface} =~ /^(\s*(\!\S*|\&\S+))*\s*$/) {
        _parse_throwaway_comments();
        if ($o->{eos}) {
            $o->{offset}[$level+1] = $offset + 1;
            return;
        }
        else {
            $o->{lines}[0] =~ /^( *)\S/ or die;
            if (length($1) > $offset) {
                $o->{offset}[$level+1] = length($1);
            }
            else {
                $o->{offset}[$level+1] = $offset + 1;
            }
        }
        $offset = $o->{offset}[++$level];
    }
        
    if ($type == LEAF) {
        while (@{$o->{lines}} and
               $o->{lines}[0] =~ m{^( *)(\#)} and
               length($1) < $offset
              ) {
            shift @{$o->{lines}};
            $o->{line}++;
        }
        $o->{eos} = $o->{done} = not @{$o->{lines}};
    }
    else {
        _parse_throwaway_comments();
    }
    return if $o->{eos}; 
    
    if ($o->{lines}[0] =~ /^---(\s|$)/) {
        $o->{done} = 1;
        return;
    }
    if ($type == LEAF and 
        $o->{lines}[0] =~ /^ {$offset}(.*)$/
       ) {
        $o->{indent} = $offset;
        $o->{content} = $1;
    }
    elsif ($o->{lines}[0] =~ /^\s*$/) {
        $o->{indent} = $offset;
        $o->{content} = '';
    }
    else {
        $o->{lines}[0] =~ /^( *)(\S.*)$/;
# print "   indent(${\length($1)})  offsets(@{$o->{offset}}) \n";
        while ($o->{offset}[$level] > length($1)) {
            $level--;
        }
        croak YAML_PARSE_ERR_INCONSISTENT_INDENTATION() 
          if $o->{offset}[$level] != length($1);
        $o->{indent} = length($1);
        $o->{content} = $2;
    }
    croak YAML_PARSE_ERR_INDENTATION() if $o->{indent} - $offset > 1;
}

#==============================================================================
# Utility subroutines.
#==============================================================================

# Indent a scalar to the current indentation level.
sub indent {
    my ($text) = @_;
    return $text unless length $text;
    $text =~ s/\n\Z//;
    my $indent = ' ' x $o->{offset}[$o->{level}];
    $text =~ s/^/$indent/gm;
    $text = "\n$text";
    return $text;
}

# Fold a paragraph to fit within a certain columnar restraint.
sub fold {
    my ($text) = @_;
    my $folded = '';
    $text =~ s/^(\S.*)\n(?=\S)/$1\n\n/gm;
    while (length $text > 0) {
        if ($text =~ s/^([^\n]{0,76})(\n|\Z)//) {
            $folded .= $1;
        }
        elsif ($text =~ s/^(.{0,76})\s//) { 
            $folded .= $1;
        }
        else {
            croak "bad news" unless $text =~ s/(.*?)(\s|\Z)//;
            $folded .= $1;
        }
        $folded .= "\n";
    }
    return $folded;
}

# Escapes for unprintable characters
my @escapes = qw(\z   \x01 \x02 \x03 \x04 \x05 \x06 \a
                 \x08 \t   \n   \v   \f   \r   \x0e \x0f
                 \x10 \x11 \x12 \x13 \x14 \x15 \x16 \x17
                 \x18 \x19 \x1a \e   \x1c \x1d \x1e \x1f
                );

# Escape the unprintable characters
sub escape {
    my ($text) = @_;
    $text =~ s/\\/\\\\/g;
    $text =~ s/([\x00-\x1f])/$escapes[ord($1)]/ge;
    return $text;
}

# Printable characters for escapes
my %unescapes = 
  (
   z => "\x00", a => "\x07", t => "\x09",
   n => "\x0a", v => "\x0b", f => "\x0c",
   r => "\x0d", e => "\x1b", '\\' => '\\',
  );
   
# Transform all the backslash style escape characters to their literal meaning
sub _unescape {
    my ($node) = @_;
    $node =~ s/\\([never\\fartz]|x([0-9a-fA-F]{2}))/
              (length($1)>1)?pack("H2",$2):$unescapes{$1}/gex;
    return $node;
}

sub DESTROY () {}

sub AUTOLOAD {
    (my $autoload = $YAML::AUTOLOAD) =~ s/^YAML:://;
    if ($autoload =~ /^[A-Z]/ and 
        ref($_[0]) eq 'YAML' and
        defined $_[0]->{$autoload}
       ) {
        defined($_[1]) ? (($_[0]->{$autoload} = $_[1]), return $_[0]) 
                       : return $_[0]->{$autoload};
        return;
    }
        
    croak "Can't autoload '$YAML::AUTOLOAD'\n"
      unless $autoload =~ /^YAML_(PARSE|LOAD|DUMP|EMIT)_(ERR|WARN|USAGE)/;
    require YAML::Error;  
    $o->{error} = YAML::Error->new($autoload, $o->{line}, $o->{document}, @_);
    my $o_save = $o;
    my $dump = $o->{error}->dump;
    $o = $o_save;
    return "$dump...\n";
}

1;
