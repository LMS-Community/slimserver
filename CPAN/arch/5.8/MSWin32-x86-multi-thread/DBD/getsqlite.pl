use strict;
use LWP::Simple qw(getstore);
use Fatal qw(chdir);
use ExtUtils::Command;

my $version = shift || die "Usage: getsqlite.pl <version>\n";

print("downloading http://www.sqlite.org/sqlite-$version.tar.gz\n");
if (getstore(
	"http://www.sqlite.org/sqlite-$version.tar.gz", 
	"sqlite.tar.gz") != 200) {
   die "Failed to download";
}
print("done\n");

rm_rf('sqlite');
xsystem("tar zxvf sqlite.tar.gz");
chdir("sqlite");
xsystem("sh configure --enable-utf8");
xsystem("make parse.c sqlite.h opcodes.h opcodes.c");

my %skip = map { $_ => 1 } map { chomp; $_ } <DATA>;
warn("Skip: $_\n") for keys %skip;

foreach (<*.[ch]>, `find src -name \\*.[ch]`) {
    chomp;
    next if $skip{$_};
    xsystem("cp $_ ../");
}

exit(0);

sub xsystem {
    local $, = ", ";
    print("@_\n");
    my $ret = system(@_);
    if ($ret != 0) {
       die "system(@_) failed: $?";
    }
}

__DATA__
lempar.c
src/threadtest.c
src/test1.c
src/test2.c
src/test3.c
src/tclsqlite.c
src/shell.c
src/lemon.c
src/md5.c

