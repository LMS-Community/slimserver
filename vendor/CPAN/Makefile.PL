#!/usr/bin/perl -w

use strict;
use Config;
use warnings;

## First shot at a single Perl Makefile to build all of our required Binary Perl Modules.
## This script is just going to loop through each module thats listed, with its given 
## configuration.

## This is used later to make sure that whatever Perl binary calls this script is whats
## used to build the subsequent perl modules...
my $perlBinary = $^X;

## My CWD
my $cwd = $ENV{'PWD'};

## Set some options based on our OS
my ($ldflags, $DBDoption, $make);

## Get our archname... 
my $archname = $Config::Config{'archname'};

## Temporary directory to put the statically-compiled MySQL libs... This is needed to statically
## compile DBD. 
my $mysqlStaticDir = "/tmp/mysql-static";

## Where we are going to temporarily save our files... 
my $tmpOutput = "/tmp/blib";

## Make sure that we include the MySQL Libraries that the user has set up for us
my $cflags = "-I$ENV{'MYSQLINC'} -L$tmpOutput/lib -I$tmpOutput/inc";


if ( ($archname =~ /darwin/) ) { 
	$cflags .= "-mmacosx-version-min=10.3 -arch i386 -arch ppc";
	$ldflags .= "-mmacosx-version-min=10.3 -arch i386 -arch ppc ";
	$DBDoption = "--libs=\"-L$mysqlStaticDir -lmysqlclient -lz\" ";
	$make = "make";
} 
if ( ($archname =~ /linux/) ) { 
	$cflags .= "-O2";
	$ldflags .= "";
	$make = "make";
	$archname =~ s/i[2345678]86-linux-gnu-thread-multi/i386-linux-gnu-thread-multi/g;
} 

## Here's the magic data... all of the info we need to build each of our modules
my @moduleData = ( 
	{name => "AutoXS-Header-0.03", source => "AutoXS-Header-0.03.tar.gz", buildCommand => "$perlBinary Makefile.PL; $make", cleanupCommand => "cp -R blib/* $tmpOutput; $make clean"},
	{name => "Class-XSAccessor-Array-0.05", source => "Class-XSAccessor-Array-0.05.tar.gz", buildCommand => "PERL5LIB=\"$tmpOutput/lib:$tmpOutput/arch\" $perlBinary Makefile.PL; PERL5LIB=\"$tmpOutput/lib:$tmpOutput/arch\" $make", cleanupCommand => "cp -R blib/* $tmpOutput; $make clean"},
	{name => "Compress-Zlib-1.41", source => "Compress-Zlib-1.41.tar.gz", buildCommand => "$perlBinary Makefile.PL; $make", cleanupCommand => "cp -R blib/* $tmpOutput; $make clean"},
	{name => "DBI-1.604", source => "DBI-1.604.tar.gz", buildCommand => "$perlBinary Makefile.PL; $make", cleanupCommand => "cp -R blib/* $tmpOutput; $make clean"},
	{	name => "DBD-mysql-3.0002", 
		source => "DBD-mysql-3.0002.tar.gz", 
		buildCommand => "mkdir -p $mysqlStaticDir; \
				cp $ENV{'MYSQLLIB'}/*.a $mysqlStaticDir; \
				PATH=\"$ENV{'MYSQLBIN'}:\$PATH\" PERL5LIB=\"$tmpOutput/lib/:$tmpOutput/arch\" DBI_INSTARCH_DIR=$tmpOutput/arch/auto/DBI/ $perlBinary Makefile.PL --cflags=\"$cflags -L$tmpOutput/lib -I$ENV{'MYSQLINC'}\" $DBDoption; \
				 $make ",
		cleanupCommand => "cp -R blib/* $tmpOutput; $make clean; rm -rf /tmp/mysql-static",
		testCommand => "$make test"
	},
	{name => "Digest-SHA1-2.11", source => "Digest-SHA1-2.11.tar.gz", buildCommand => "$perlBinary Makefile.PL; $make", cleanupCommand => "cp -R blib/* $tmpOutput; $make clean"},
	{name => "Encode-Detect-1.00", source => "Encode-Detect-1.00.tar.gz", buildCommand => "$perlBinary Makefile.PL; $make", cleanupCommand => "cp -R blib/* $tmpOutput; $make clean"},
	{	name => "jpeg-6b",
		source => "jpegsrc.v6b.tar.gz",
		buildCommand => "$make clean; LDFLAGS=\"$ldflags\" CFLAGS=\"$cflags\" ./configure -disable-dependency-tracking; $make",
		cleanupCommand => "cp libjpeg* $tmpOutput/lib/"
	},
	{	name => "libpng-1.2.32",
		source => "libpng-1.2.32.tar.gz",
		buildCommand => "$make clean; LDDFLAGS=\"$ldflags\" LDFLAGS=\"$ldflags\" CFLAGS=\"$cflags\" ./configure -disable-dependency-tracking --prefix=\$PWD; $make; $make install",
		cleanupCommand => ""
	},
	{name => "freetype-2.3.7", source => "freetype-2.3.7.tar.gz", buildCommand => "CFLAGS=\"$cflags\" LDFLAGS=\"$ldflags\" sh configure --prefix=\$PWD; $make; $make install" },
	{name => "fontconfig-2.6.0", source => "fontconfig-2.6.0.tar.gz", buildCommand => "PATH=\"$cwd/libpng-1.2.32/bin:$cwd/freetype-2.3.7/bin:\$PATH\" CFLAGS=\"$cflags\" LDFLAGS=\"$ldflags\" sh configure --prefix=\$PWD -disable-dependency-tracking; $make; $make install"},
	{	name => "gd-2.0.35",
		source => "gd-2.0.35.tar.gz",
		buildCommand => "$make clean;  \ 
				export PATH=\"$cwd/fontconfig-2.6.0/bin:$cwd/libpng-1.2.32/bin:$cwd/freetype-2.3.7/bin:\$PATH\"; \
				LDDFLAGS=\"$ldflags\" LDFLAGS=\"$ldflags -L$cwd/libpng-1.2.32/lib -L$cwd/jpeg-6b/ -L$cwd/fontconfig-2.6.0/lib -L$cwd/freetype-2.3.7/lib \" CFLAGS=\"$cflags -I$cwd/libpng-1.2.32/include -I$cwd/freetype-2.3.7/include -I$cwd/fontconfig-2.6.0/include -I$cwd/jpeg-6b/ \" ./configure --enable-static --prefix=\$PWD -disable-dependency-tracking --with-fontconfig=$cwd/fontconfig-2.6.0/ --without-xpm ; \
				$make; \
				$make install",
		cleanupCommand => ""
	},
	{	name => "GD-2.35",
		source => "GD-2.35.tar.gz",
		buildCommandMac => "$make clean; \
				LDDFLAGS=\"$ldflags\" LDFLAGS=\"$ldflags\" CFLAGS=\"$cflags\" $perlBinary Makefile.PL -options \"JPEG,PNG,GIF,FT\" -lib_gd_path $cwd/gd-2.0.35/ -lib_png_path $cwd/libpng-1.2.32/ --lib_jpeg_path $tmpOutput --lib_ft_path $cwd/freetype-2.3.7/; \
				$make; \
				LD_RUN_PATH=\"/usr/X11R6/lib:/usr/lib:/usr/local/lib\" cc -mmacosx-version-min=10.3 -arch i386 -arch ppc -bundle -all_load -undefined dynamic_lookup -L/usr/local/lib GD.o  -o blib/arch/auto/GD/GD.bundle  $cwd/jpeg-6b/libjpeg.a  $cwd/libpng-1.2.32/lib/libpng12.a  $cwd/gd-2.0.35/lib/libgd.a  $cwd/fontconfig-2.6.0/lib/libfontconfig.a $cwd/freetype-2.3.7/lib/libfreetype.a /Developer/SDKs/MacOSX10.4u.sdk/usr/X11R6/lib/libexpat.a /Developer/SDKs/MacOSX10.4u.sdk/usr/lib/libiconv.dylib -framework CoreServices  -framework ApplicationServices  -lz -liconv",
		buildCommandLin => "$make clean; \ 
				cat Makefile.PL | sed s/WriteMakefile\\(/\@LIBS\\ =\\ \\(\\'-lz\\',\\'-lm\\',\\'-lfreetype\\'\\)\\;\\\\nWriteMakefile\\(/g > Makefile2.PL;  \
				LDDFLAGS=\"$ldflags\" LDFLAGS=\"$ldflags\" CFLAGS=\"$cflags\" $perlBinary Makefile2.PL -options \"JPEG,PNG,GIF,FT\" -lib_gd_path $cwd/gd-2.0.35/ -lib_png_path $cwd/libpng-1.2.32/ --lib_jpeg_path $tmpOutput --lib_ft_path $cwd/freetype-2.3.7/; \	
				MYEXTLIB=\"$cwd/gd-2.0.35/lib/libgd.a $cwd/jpeg-6b/libjpeg.a $cwd/libpng-1.2.32/lib/libpng12.a $cwd/freetype-2.3.7/lib/libfreetype.a $cwd/fontconfig-2.6.0/lib/libfontconfig.a /usr/lib/libexpat.a\" $make; \
				 ",
		buildCommandWin => "",
		cleanupCommand => "cp -R blib/* $tmpOutput",
		testCommand => "$make test"
	},


	{name => "HTML-Parser-3.48", source => "HTML-Parser-3.48.tar.gz", buildCommand => "$perlBinary Makefile.PL; $make", cleanupCommand => "cp -R blib/* $tmpOutput; $make clean"},
	{name => "JSON-XS-1.5", source => "JSON-XS-1.5.tar.gz", buildCommand => "$perlBinary Makefile.PL; $make", cleanupCommand => "cp -R blib/* $tmpOutput; $make clean"},
	{name => "Locale-Hebrew-1.04", source => "Locale-Hebrew-1.04.tar.gz", buildCommand => "$perlBinary Makefile.PL; $make", cleanupCommand => "cp -R blib/* $tmpOutput; $make clean"},
	{name => "POE-XS-Queue-Array-0.002", source => "POE-XS-Queue-Array-0.002.tar.gz", buildCommand => "$perlBinary Makefile.PL; $make", cleanupCommand => "cp -R blib/* $tmpOutput; $make clean"},
	{	name => "Template-Toolkit-2.15", 
		source => "Template-Toolkit-2.15.tar.gz", 
		buildCommand => "$perlBinary Makefile.PL TT_DOCS=n TT_SPASH=n TT_THEME=n TT_EXAMPLES=n TT_EXTRAS=n TT_QUIET=n TT_ACCEPT=y TT_DBI=n TT_LATEX=n ; $make", 
		cleanupCommand => "cp -R blib/* $tmpOutput; $make clean"
	},
	{name => "Time-HiRes-1.86", source => "Time-HiRes-1.86.tar.gz", buildCommand => "$perlBinary Makefile.PL; $make", cleanupCommand => "cp -R blib/* $tmpOutput; $make clean"},
	{name => "XML-Parser-2.34", source => "XML-Parser-2.34.tar.gz", buildCommand => "$perlBinary Makefile.PL; $make", cleanupCommand => "cp -R blib/* $tmpOutput; $make clean"},
	{name => "YAML-Syck-0.64", source => "YAML-Syck-0.64.tar.gz", buildCommand => "$perlBinary Makefile.PL; $make", cleanupCommand => "cp -R blib/* $tmpOutput; $make clean"},
);

##############################################################################################
## Verify that certain local paths are correct
##############################################################################################
sub checkEnv { 
	if (!$ENV{'MYSQLLIB'}) { die("Please set ENV value MYSQLLIB to the location of your MySQL libraries...\n"); }
	if (!$ENV{'MYSQLINC'}) { die("Please set ENV value MYSQLINC to the location of your MySQL include files...\n"); }
	if (!$ENV{'MYSQLBIN'}) { die("Please set ENV value MYSQLBIN to the location of your MySQL binaries...\n"); }
}

##############################################################################################
## Logging Mechanism
##############################################################################################
sub logme {
	my $whoCalled = ( caller(1) )[3];
	print "($whoCalled) $_[0]";
}

##############################################################################################
## Print out all of our runtime information... 						    ##
##############################################################################################
sub printRuntime { 
	logme "\$perlBinary: $perlBinary\n";
	logme "\$archname: $archname\n";
}

##############################################################################################
## This walks through all of our modules in @moduleData and calls buildModule() for each one##
##############################################################################################
sub buildAllModules {
	
	if (-e "$tmpOutput") { 
		## First, remove blib directory to start from scratch...
		logme "Removing old blib directory... Making new structure\n";
		system ("rm -rf $tmpOutput");
	}

	system ("mkdir $tmpOutput; mkdir $tmpOutput/bin; mkdir $tmpOutput/lib");

	my $moduleCount = scalar (@moduleData);
	for (my $i=0; $i < $moduleCount; $i++) { 
		logme("Calling: buildModule() for: $moduleData[$i]{'name'}\n");
		buildModule($moduleData[$i]);
	}
}		

##############################################################################################
## Just a quick removal of all of the directories when we're done
##############################################################################################
sub cleanAllModules {
        my $moduleCount = scalar (@moduleData);
        for (my $i=0; $i < $moduleCount; $i++) {
                logme("Removing Source Dir: $moduleData[$i]{'name'}\n");
                system("rm -rf $moduleData[$i]{'name'}");
        }
}

##############################################################################################
## This is the routine that does most of the leg work... compiles an individual module	    ##
##############################################################################################
sub buildModule {
	if ( $_[0] || die("Problem: Not all of the variables were passed to the buildModule function...") ) {
		my %module = %{$_[0]};

		logme "Called with data: \n";
		logme "	module name: $module{'name'}\n";
		logme "	module source: $module{'source'}\n";
		if ($module{'buildCommand'}) { 
			logme "	module buildCommand: $module{'buildCommand'}\n";
		}
		if ($module{'buildCommandMac'}) { 
			logme" module buildCommandMac: $module{'buildCommandMac'}\n";
		}
		if ($module{'buildCommandWin'}) { 
			logme" module buildCommandWin: $module{'buildCommandWin'}\n";
		}
		if ($module{'buildCommandLin'}) { 
			logme" module buildCommandLin: $module{'buildCommandLin'}\n";
		}
		if ($module{'cleanupCommand'}) { 
			logme "	module cleanupCommand: $module{'cleanupCommand'}\n";
		}	
		## First check that the source is here
		if ( !( -e $module{'source'} ) ) {
			die("Problem: The source file (module{'source'}) does not exist... quitting!");
		}

		## Now, remove the directory
		if ( (-e $module{'name'}) ) { 
			system ("rm -rf $module{'name'}");
		}

		## Now that we have it, untar it
		logme "Untarring the source package ($module{'source'})...\n";
		system ("tar -zxf $module{'source'}");
	
		## Go into the directory and run the build Command
		logme "Beginning build process...\n";

		if ( ($module{'buildCommand'}) ) { 
			system ("cd $module{'name'}; $module{'buildCommand'}");
		} else { 	
			## Check for any platform-specific build options
			if ( ($archname =~ /darwin/) && $module{'buildCommandMac'} ) { 
				logme "Found a specific build command for this architecture ... running it.\n";
				system("cd $module{'name'}; $module{'buildCommandMac'}"); 
			} 
			if ( ($archname =~ /Win/) && $module{'buildCommandWin'}) {
				logme "Found a specific build command for this architecture ... running it.\n";
				system("cd $module{'name'}; $module{'buildCommandWin'}"); 
			}
			if ( ($archname =~ /linux/) && $module{'buildCommandLin'}) {
				logme "Found a specific build command for this architecture ... running it.\n";
				system("cd $module{'name'}; $module{'buildCommandLin'}"); 
			}
		}

		## Now, if theres a testCommand defined, lets run it... output is not parsed, so needs to be viewed by the user
		if ( $module{'testCommand'} ) { 
			logme "Found a \$testCommand... running it.\n";
			system("cd $module{'name'}; $module{'testCommand'}");
		}

		## Final cleanup
		if ($module{'cleanupCommand'}) { 
			logme "Running cleanup instructions...\n";
			system ("cd $module{'name'}; $module{'cleanupCommand'}");
		}

	}			
}


##############################################################################################
## Now that the files are built, lets package the important ones up...			    ##
##############################################################################################
sub createPackage {
	if (-e "$cwd/$archname.tgz") { 
		logme("Found old package [$cwd/$archname.tgz]... removing it to make room for the new one. \n");
		system ("rm $cwd/$archname.tgz");
	}

	logme("Creating package [$archname.tgz] with the important files...\n");
	system("cd $tmpOutput/arch/auto; tar -zcvf $cwd/$archname.tgz \`find . -type f | grep -v exists | grep -v \.bs\`");

	logme("Here are the contents of the package...\n");
	system("tar -ztvf $cwd/$archname.tgz");
}


##############################################################################################
## Walkthrough of the subs								    ##
##############################################################################################
printRuntime();
checkEnv();
buildAllModules();
createPackage();
cleanAllModules();
