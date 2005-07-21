package YAML::Transfer;
use strict;

use YAML::Node;

package YAML::Transfer::glob;
sub yaml_dump {
    my $ynode = YAML::Node->new({}, 'perl/glob:');
    for my $type (qw(PACKAGE NAME SCALAR ARRAY HASH CODE IO)) {
        my $value = *{$_[0]}{$type};
        $value = $$value if $type eq 'SCALAR';
        if (defined $value) {
            if ($type eq 'IO') {
                my @stats = qw(device inode mode links uid gid rdev size
                               atime mtime ctime blksize blocks);
                undef $value;
                $value->{stat} = YAML::Node->new({});
                map {$value->{stat}{shift @stats} = $_} stat(*{$_[0]});
                $value->{fileno} = fileno(*{$_[0]});
                {
                    local $^W;
                    $value->{tell} = tell(*{$_[0]});
                }
            }
            $ynode->{$type} = $value; 
        }
    }
    return $ynode;
}

package YAML::Transfer::blessed;
my %sigil = (HASH => '', ARRAY => '@', SCALAR => '$');
sub yaml_dump {
    my ($value) = @_;
    my ($class, $type) = YAML::Node::info($value);
    my $family = "perl/$sigil{$type}$class";
    if ($type eq 'SCALAR') {
        $_[1] = $$value;
        YAML::Node->new($_[1], $family)
    } else {
        YAML::Node->new($value, $family)
    }
}

package YAML::Transfer::code;
my $dummy_warned = 0; 
my $default = '{ "DUMMY" }';
sub yaml_dump {
    my $code;
    my ($dumpflag, $value) = @_;
    my ($class, $type) = YAML::Node::info($value);
    $class ||= '';
    my $family = "perl/code:$class";
    if (not $dumpflag) {
        $code = $default;
    }
    else {
        bless $value, "CODE" if $class;
        eval "use B::Deparse";
        my $deparse = B::Deparse->new();
        eval {
            local $^W = 0;
            $code = $deparse->coderef2text($value);
        };
        if ($@) {
            warn YAML::YAML_DUMP_WARN_DEPARSE_FAILED() if $^W;
            $code = $default;
        }
        bless $value, $class if $class;
        chomp $code;
        $code .= "\n";
    }
    $_[2] = $code;
    YAML::Node->new($_[2], $family);
}    

package YAML::Transfer::ref;
sub yaml_dump {
    YAML::Node->new({(&YAML::VALUE, ${$_[0]})}, 'perl/ref:')
}

package YAML::Transfer::regexp;
# XXX Be sure to handle blessed regexps (if possible)
sub yaml_dump {
    my ($value) = @_;
    my ($regexp, $modifiers);
    if ("$value" =~ /^\(\?(\w*)(?:\-\w+)?\:(.*)\)$/) {
        $regexp = $2;
        $modifiers = $1 || '';
    }
    else {
        croak YAML::YAML_DUMP_ERR_BAD_REGEXP($value);
    }
    my $ynode = YAML::Node->new({}, 'perl/regexp:');
    $ynode->{REGEXP} = $regexp; 
    $ynode->{MODIFIERS} = $modifiers if $modifiers; 
    return $ynode;
}

1;
