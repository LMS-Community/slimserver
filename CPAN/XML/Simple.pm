package XML::Simple;
$XML::Simple::VERSION = '2.25';
=head1 NAME

XML::Simple - An API for simple XML files

=head1 SYNOPSIS

PLEASE DO NOT USE THIS MODULE IN NEW CODE.  If you ignore this
warning and use it anyway, the C<qw(:strict)> mode will save you a little pain.

    use XML::Simple qw(:strict);

    my $ref = XMLin([<xml file or string>] [, <options>]);

    my $xml = XMLout($hashref [, <options>]);

Or the object oriented way:

    require XML::Simple qw(:strict);

    my $xs = XML::Simple->new([<options>]);

    my $ref = $xs->XMLin([<xml file or string>] [, <options>]);

    my $xml = $xs->XMLout($hashref [, <options>]);

(or see L<"SAX SUPPORT"> for 'the SAX way').

Note, in these examples, the square brackets are used to denote optional items
not to imply items should be supplied in arrayrefs.

=cut

# See after __END__ for more POD documentation


# Load essentials here, other modules loaded on demand later

use strict;
use warnings;
use warnings::register;
use Carp;
use Scalar::Util qw();
require Exporter;


##############################################################################
# Define some constants
#

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK $PREFERRED_PARSER);

@ISA               = qw(Exporter);
@EXPORT            = qw(XMLin XMLout);
@EXPORT_OK         = qw(xml_in xml_out);

my %StrictMode     = ();

my @KnownOptIn     = qw(keyattr keeproot forcecontent contentkey noattr
                        searchpath forcearray cache suppressempty parseropts
                        grouptags nsexpand datahandler varattr variables
                        normalisespace normalizespace valueattr strictmode);

my @KnownOptOut    = qw(keyattr keeproot contentkey noattr
                        rootname xmldecl outputfile noescape suppressempty
                        grouptags nsexpand handler noindent attrindent nosort
                        valueattr numericescape strictmode);

my @DefKeyAttr     = qw(name key id);
my $DefRootName    = qq(opt);
my $DefContentKey  = qq(content);
my $DefXmlDecl     = qq(<?xml version='1.0' standalone='yes'?>);

my $xmlns_ns       = 'http://www.w3.org/2000/xmlns/';
my $bad_def_ns_jcn = '{' . $xmlns_ns . '}';     # LibXML::SAX workaround


##############################################################################
# Globals for use by caching routines
#

my %MemShareCache  = ();
my %MemCopyCache   = ();


##############################################################################
# Wrapper for Exporter - handles ':strict'
#

sub import {
  # Handle the :strict tag

  my($calling_package) = caller();
  _strict_mode_for_caller(1) if grep(/^:strict$/, @_);

  # Pass everything else to Exporter.pm

  @_ = grep(!/^:strict$/, @_);
  goto &Exporter::import;
}


##############################################################################
# Constructor for optional object interface.
#

sub new {
  my $class = shift;

  if(@_ % 2) {
    croak "Default options must be name=>value pairs (odd number supplied)";
  }

  my %known_opt;
  @known_opt{@KnownOptIn, @KnownOptOut} = ();

  my %raw_opt = @_;
  $raw_opt{strictmode} = _strict_mode_for_caller()
    unless exists $raw_opt{strictmode};
  my %def_opt;
  while(my($key, $val) = each %raw_opt) {
    my $lkey = lc($key);
    $lkey =~ s/_//g;
    croak "Unrecognised option: $key" unless(exists($known_opt{$lkey}));
    $def_opt{$lkey} = $val;
  }
  my $self = { def_opt => \%def_opt };

  return(bless($self, $class));
}


##############################################################################
# Sub: _strict_mode_for_caller()
#
# Gets or sets the XML::Simple :strict mode flag for the calling namespace.
# Walks back through call stack to find the calling namespace and sets the
# :strict mode flag for that namespace if an argument was supplied and returns
# the flag value if not.
#

sub _strict_mode_for_caller {
  my $set_mode = @_;
  my $frame = 1;
  while(my($package) = caller($frame++)) {
    next if $package eq 'XML::Simple';
    $StrictMode{$package} = 1 if $set_mode;
    return $StrictMode{$package};
  }
  return(0);
}


##############################################################################
# Sub: _get_object()
#
# Helper routine called from XMLin() and XMLout() to create an object if none
# was provided.  Note, this routine does mess with the caller's @_ array.
#

sub _get_object {
  my $self;
  if($_[0]  and  UNIVERSAL::isa($_[0], 'XML::Simple')) {
    $self = shift;
  }
  else {
    $self = XML::Simple->new();
  }

  return $self;
}


##############################################################################
# Sub/Method: XMLin()
#
# Exported routine for slurping XML into a hashref - see pod for info.
#
# May be called as object method or as a plain function.
#
# Expects one arg for the source XML, optionally followed by a number of
# name => value option pairs.
#

sub XMLin {
  my $self = &_get_object;      # note, @_ is passed implicitly

  my $target = shift;


  # Work out whether to parse a string, a file or a filehandle

  if(not defined $target) {
    return $self->parse_file(undef, @_);
  }

  elsif($target eq '-') {
    local($/) = undef;
    $target = <STDIN>;
    return $self->parse_string(\$target, @_);
  }

  elsif(my $type = ref($target)) {
    if($type eq 'SCALAR') {
      return $self->parse_string($target, @_);
    }
    else {
      return $self->parse_fh($target, @_);
    }
  }

  elsif($target =~ m{<.*?>}s) {
    return $self->parse_string(\$target, @_);
  }

  else {
    return $self->parse_file($target, @_);
  }
}


##############################################################################
# Sub/Method: parse_file()
#
# Same as XMLin, but only parses from a named file.
#

sub parse_file {
  my $self = &_get_object;      # note, @_ is passed implicitly

  my $filename = shift;

  $self->handle_options('in', @_);

  $filename = $self->default_config_file if not defined $filename;

  $filename = $self->find_xml_file($filename, @{$self->{opt}->{searchpath}});

  # Check cache for previous parse

  if($self->{opt}->{cache}) {
    foreach my $scheme (@{$self->{opt}->{cache}}) {
      my $method = 'cache_read_' . $scheme;
      my $opt = $self->$method($filename);
      return($opt) if($opt);
    }
  }

  my $ref = $self->build_simple_tree($filename, undef);

  if($self->{opt}->{cache}) {
    my $method = 'cache_write_' . $self->{opt}->{cache}->[0];
    $self->$method($ref, $filename);
  }

  return $ref;
}


##############################################################################
# Sub/Method: parse_fh()
#
# Same as XMLin, but only parses from a filehandle.
#

sub parse_fh {
  my $self = &_get_object;      # note, @_ is passed implicitly

  my $fh = shift;
  croak "Can't use " . (defined $fh ? qq{string ("$fh")} : 'undef') .
        " as a filehandle" unless ref $fh;

  $self->handle_options('in', @_);

  return $self->build_simple_tree(undef, $fh);
}


##############################################################################
# Sub/Method: parse_string()
#
# Same as XMLin, but only parses from a string or a reference to a string.
#

sub parse_string {
  my $self = &_get_object;      # note, @_ is passed implicitly

  my $string = shift;

  $self->handle_options('in', @_);

  return $self->build_simple_tree(undef, ref $string ? $string : \$string);
}


##############################################################################
# Method: default_config_file()
#
# Returns the name of the XML file to parse if no filename (or XML string)
# was provided.
#

sub default_config_file {
  my $self = shift;

  require File::Basename;

  my($basename, $script_dir, $ext) = File::Basename::fileparse($0, '\.[^\.]+');

  # Add script directory to searchpath

  if($script_dir) {
    unshift(@{$self->{opt}->{searchpath}}, $script_dir);
  }

  return $basename . '.xml';
}


##############################################################################
# Method: build_simple_tree()
#
# Builds a 'tree' data structure as provided by XML::Parser and then
# 'simplifies' it as specified by the various options in effect.
#

sub build_simple_tree {
  my $self = shift;

  my $tree = eval {
    $self->build_tree(@_);
  };
  Carp::croak("$@XML::Simple called") if $@;

  return $self->{opt}->{keeproot}
         ? $self->collapse({}, @$tree)
         : $self->collapse(@{$tree->[1]});
}


##############################################################################
# Method: build_tree()
#
# This routine will be called if there is no suitable pre-parsed tree in a
# cache.  It parses the XML and returns an XML::Parser 'Tree' style data
# structure (summarised in the comments for the collapse() routine below).
#
# XML::Simple requires the services of another module that knows how to parse
# XML.  If XML::SAX is installed, the default SAX parser will be used,
# otherwise XML::Parser will be used.
#
# This routine expects to be passed a filename as argument 1 or a 'string' as
# argument 2.  The 'string' might be a string of XML (passed by reference to
# save memory) or it might be a reference to an IO::Handle.  (This
# non-intuitive mess results in part from the way XML::Parser works but that's
# really no excuse).
#

sub build_tree {
  my $self     = shift;
  my $filename = shift;
  my $string   = shift;


  my $preferred_parser = $PREFERRED_PARSER;
  unless(defined($preferred_parser)) {
    $preferred_parser = $ENV{XML_SIMPLE_PREFERRED_PARSER} || '';
  }
  if($preferred_parser eq 'XML::Parser') {
    return($self->build_tree_xml_parser($filename, $string));
  }

  eval { require XML::SAX; };      # We didn't need it until now
  if($@) {                         # No XML::SAX - fall back to XML::Parser
    if($preferred_parser) {        # unless a SAX parser was expressly requested
      croak "XMLin() could not load XML::SAX";
    }
    return($self->build_tree_xml_parser($filename, $string));
  }

  $XML::SAX::ParserPackage = $preferred_parser if($preferred_parser);

  my $sp = XML::SAX::ParserFactory->parser(Handler => $self);

  $self->{nocollapse} = 1;
  my($tree);
  if($filename) {
    $tree = $sp->parse_uri($filename);
  }
  else {
    if(ref($string) && ref($string) ne 'SCALAR') {
      $tree = $sp->parse_file($string);
    }
    else {
      $tree = $sp->parse_string($$string);
    }
  }

  return($tree);
}


##############################################################################
# Method: build_tree_xml_parser()
#
# This routine will be called if XML::SAX is not installed, or if XML::Parser
# was specifically requested.  It takes the same arguments as build_tree() and
# returns the same data structure (XML::Parser 'Tree' style).
#

sub build_tree_xml_parser {
  my $self     = shift;
  my $filename = shift;
  my $string   = shift;


  eval {
    local($^W) = 0;      # Suppress warning from Expat.pm re File::Spec::load()
    require XML::Parser; # We didn't need it until now
  };
  if($@) {
    croak "XMLin() requires either XML::SAX or XML::Parser";
  }

  if($self->{opt}->{nsexpand}) {
    carp "'nsexpand' option requires XML::SAX";
  }

  my $xp = $self->new_xml_parser();

  my($tree);
  if($filename) {
    # $tree = $xp->parsefile($filename);  # Changed due to prob w/mod_perl
    open(my $xfh, '<', $filename) || croak qq($filename - $!);
    $tree = $xp->parse($xfh);
  }
  else {
    $tree = $xp->parse($$string);
  }

  return($tree);
}


##############################################################################
# Method: new_xml_parser()
#
# Simply calls the XML::Parser constructor.  Override this method to customise
# the behaviour of the parser.
#

sub new_xml_parser {
  my($self) = @_;

  my $xp = XML::Parser->new(Style => 'Tree', @{$self->{opt}->{parseropts}});
  $xp->setHandlers(ExternEnt => sub {return $_[2]});

  return $xp;
}


##############################################################################
# Method: cache_write_storable()
#
# Wrapper routine for invoking Storable::nstore() to cache a parsed data
# structure.
#

sub cache_write_storable {
  my($self, $data, $filename) = @_;

  my $cachefile = $self->storable_filename($filename);

  require Storable;           # We didn't need it until now

  if ('VMS' eq $^O) {
    Storable::nstore($data, $cachefile);
  }
  else {
    # If the following line fails for you, your Storable.pm is old - upgrade
    Storable::lock_nstore($data, $cachefile);
  }

}


##############################################################################
# Method: cache_read_storable()
#
# Wrapper routine for invoking Storable::retrieve() to read a cached parsed
# data structure.  Only returns cached data if the cache file exists and is
# newer than the source XML file.
#

sub cache_read_storable {
  my($self, $filename) = @_;

  my $cachefile = $self->storable_filename($filename);

  return unless(-r $cachefile);
  return unless((stat($cachefile))[9] > (stat($filename))[9]);

  require Storable;           # We didn't need it until now

  if ('VMS' eq $^O) {
    return(Storable::retrieve($cachefile));
  }
  else {
    return(Storable::lock_retrieve($cachefile));
  }

}


##############################################################################
# Method: storable_filename()
#
# Translates the supplied source XML filename into a filename for the storable
# cached data.  A '.stor' suffix is added after stripping an optional '.xml'
# suffix.
#

sub storable_filename {
  my($self, $cachefile) = @_;

  $cachefile =~ s{(\.xml)?$}{.stor};
  return $cachefile;
}


##############################################################################
# Method: cache_write_memshare()
#
# Takes the supplied data structure reference and stores it away in a global
# hash structure.
#

sub cache_write_memshare {
  my($self, $data, $filename) = @_;

  $MemShareCache{$filename} = [time(), $data];
}


##############################################################################
# Method: cache_read_memshare()
#
# Takes a filename and looks in a global hash for a cached parsed version.
#

sub cache_read_memshare {
  my($self, $filename) = @_;

  return unless($MemShareCache{$filename});
  return unless($MemShareCache{$filename}->[0] > (stat($filename))[9]);

  return($MemShareCache{$filename}->[1]);

}


##############################################################################
# Method: cache_write_memcopy()
#
# Takes the supplied data structure and stores a copy of it in a global hash
# structure.
#

sub cache_write_memcopy {
  my($self, $data, $filename) = @_;

  require Storable;           # We didn't need it until now

  $MemCopyCache{$filename} = [time(), Storable::dclone($data)];
}


##############################################################################
# Method: cache_read_memcopy()
#
# Takes a filename and looks in a global hash for a cached parsed version.
# Returns a reference to a copy of that data structure.
#

sub cache_read_memcopy {
  my($self, $filename) = @_;

  return unless($MemCopyCache{$filename});
  return unless($MemCopyCache{$filename}->[0] > (stat($filename))[9]);

  return(Storable::dclone($MemCopyCache{$filename}->[1]));

}


##############################################################################
# Sub/Method: XMLout()
#
# Exported routine for 'unslurping' a data structure out to XML.
#
# Expects a reference to a data structure and an optional list of option
# name => value pairs.
#

sub XMLout {
  my $self = &_get_object;      # note, @_ is passed implicitly

  croak "XMLout() requires at least one argument" unless(@_);
  my $ref = shift;

  $self->handle_options('out', @_);


  # If namespace expansion is set, XML::NamespaceSupport is required

  if($self->{opt}->{nsexpand}) {
    require XML::NamespaceSupport;
    $self->{nsup} = XML::NamespaceSupport->new();
    $self->{ns_prefix} = 'aaa';
  }


  # Wrap top level arrayref in a hash

  if(UNIVERSAL::isa($ref, 'ARRAY')) {
    $ref = { anon => $ref };
  }


  # Extract rootname from top level hash if keeproot enabled

  if($self->{opt}->{keeproot}) {
    my(@keys) = keys(%$ref);
    if(@keys == 1) {
      $ref = $ref->{$keys[0]};
      $self->{opt}->{rootname} = $keys[0];
    }
  }

  # Ensure there are no top level attributes if we're not adding root elements

  elsif($self->{opt}->{rootname} eq '') {
    if(UNIVERSAL::isa($ref, 'HASH')) {
      my $refsave = $ref;
      $ref = {};
      foreach (keys(%$refsave)) {
        if(ref($refsave->{$_})) {
          $ref->{$_} = $refsave->{$_};
        }
        else {
          $ref->{$_} = [ $refsave->{$_} ];
        }
      }
    }
  }


  # Encode the hashref and write to file if necessary

  $self->{_ancestors} = {};
  my $xml = $self->value_to_xml($ref, $self->{opt}->{rootname}, '');
  delete $self->{_ancestors};

  if($self->{opt}->{xmldecl}) {
    $xml = $self->{opt}->{xmldecl} . "\n" . $xml;
  }

  if($self->{opt}->{outputfile}) {
    if(ref($self->{opt}->{outputfile})) {
      my $fh = $self->{opt}->{outputfile};
      if(UNIVERSAL::isa($fh, 'GLOB') and !UNIVERSAL::can($fh, 'print')) {
        eval { require IO::Handle; };
        croak $@ if $@;
      }
      return($fh->print($xml));
    }
    else {
      open(my $out, '>', "$self->{opt}->{outputfile}") ||
        croak "open($self->{opt}->{outputfile}): $!";
      binmode($out, ':utf8') if($] >= 5.008);
      print $out $xml or croak "print: $!";
      close $out or croak "close: $!";
    }
  }
  elsif($self->{opt}->{handler}) {
    require XML::SAX;
    my $sp = XML::SAX::ParserFactory->parser(
               Handler => $self->{opt}->{handler}
             );
    return($sp->parse_string($xml));
  }
  else {
    return($xml);
  }
}


##############################################################################
# Method: handle_options()
#
# Helper routine for both XMLin() and XMLout().  Both routines handle their
# first argument and assume all other args are options handled by this routine.
# Saves a hash of options in $self->{opt}.
#
# If default options were passed to the constructor, they will be retrieved
# here and merged with options supplied to the method call.
#
# First argument should be the string 'in' or the string 'out'.
#
# Remaining arguments should be name=>value pairs.  Sets up default values
# for options not supplied.  Unrecognised options are a fatal error.
#

sub handle_options  {
  my $self = shift;
  my $dirn = shift;


  # Determine valid options based on context

  my %known_opt;
  if($dirn eq 'in') {
    @known_opt{@KnownOptIn} = @KnownOptIn;
  }
  else {
    @known_opt{@KnownOptOut} = @KnownOptOut;
  }


  # Store supplied options in hashref and weed out invalid ones

  if(@_ % 2) {
    croak "Options must be name=>value pairs (odd number supplied)";
  }
  my %raw_opt  = @_;
  my $opt      = {};
  $self->{opt} = $opt;

  while(my($key, $val) = each %raw_opt) {
    my $lkey = lc($key);
    $lkey =~ s/_//g;
    croak "Unrecognised option: $key" unless($known_opt{$lkey});
    $opt->{$lkey} = $val;
  }


  # Merge in options passed to constructor

  foreach (keys(%known_opt)) {
    unless(exists($opt->{$_})) {
      if(exists($self->{def_opt}->{$_})) {
        $opt->{$_} = $self->{def_opt}->{$_};
      }
    }
  }


  # Set sensible defaults if not supplied

  if(exists($opt->{rootname})) {
    unless(defined($opt->{rootname})) {
      $opt->{rootname} = '';
    }
  }
  else {
    $opt->{rootname} = $DefRootName;
  }

  if($opt->{xmldecl}  and  $opt->{xmldecl} eq '1') {
    $opt->{xmldecl} = $DefXmlDecl;
  }

  if(exists($opt->{contentkey})) {
    if($opt->{contentkey} =~ m{^-(.*)$}) {
      $opt->{contentkey} = $1;
      $opt->{collapseagain} = 1;
    }
  }
  else {
    $opt->{contentkey} = $DefContentKey;
  }

  unless(exists($opt->{normalisespace})) {
    $opt->{normalisespace} = $opt->{normalizespace};
  }
  $opt->{normalisespace} = 0 unless(defined($opt->{normalisespace}));

  # Cleanups for values assumed to be arrays later

  if($opt->{searchpath}) {
    unless(ref($opt->{searchpath})) {
      $opt->{searchpath} = [ $opt->{searchpath} ];
    }
  }
  else  {
    $opt->{searchpath} = [ ];
  }

  if($opt->{cache}  and !ref($opt->{cache})) {
    $opt->{cache} = [ $opt->{cache} ];
  }
  if($opt->{cache}) {
    $_ = lc($_) foreach (@{$opt->{cache}});
    foreach my $scheme (@{$opt->{cache}}) {
      my $method = 'cache_read_' . $scheme;
      croak "Unsupported caching scheme: $scheme"
        unless($self->can($method));
    }
  }

  if(exists($opt->{parseropts})) {
    if(warnings::enabled()) {
      carp "Warning: " .
           "'ParserOpts' is deprecated, contact the author if you need it";
    }
  }
  else {
    $opt->{parseropts} = [ ];
  }


  # Special cleanup for {forcearray} which could be regex, arrayref or boolean
  # or left to default to 0

  if(exists($opt->{forcearray})) {
    if(ref($opt->{forcearray}) eq 'Regexp') {
      $opt->{forcearray} = [ $opt->{forcearray} ];
    }

    if(ref($opt->{forcearray}) eq 'ARRAY') {
      my @force_list = @{$opt->{forcearray}};
      if(@force_list) {
        $opt->{forcearray} = {};
        foreach my $tag (@force_list) {
          if(ref($tag) eq 'Regexp') {
            push @{$opt->{forcearray}->{_regex}}, $tag;
          }
          else {
            $opt->{forcearray}->{$tag} = 1;
          }
        }
      }
      else {
        $opt->{forcearray} = 0;
      }
    }
    else {
      $opt->{forcearray} = ( $opt->{forcearray} ? 1 : 0 );
    }
  }
  else {
    if($opt->{strictmode}  and  $dirn eq 'in') {
      croak "No value specified for 'ForceArray' option in call to XML$dirn()";
    }
    $opt->{forcearray} = 0;
  }


  # Special cleanup for {keyattr} which could be arrayref or hashref or left
  # to default to arrayref

  if(exists($opt->{keyattr}))  {
    if(ref($opt->{keyattr})) {
      if(ref($opt->{keyattr}) eq 'HASH') {

        # Make a copy so we can mess with it

        $opt->{keyattr} = { %{$opt->{keyattr}} };


        # Convert keyattr => { elem => '+attr' }
        # to keyattr => { elem => [ 'attr', '+' ] }

        foreach my $el (keys(%{$opt->{keyattr}})) {
          if($opt->{keyattr}->{$el} =~ /^(\+|-)?(.*)$/) {
            $opt->{keyattr}->{$el} = [ $2, ($1 ? $1 : '') ];
            if($opt->{strictmode}  and  $dirn eq 'in') {
              next if($opt->{forcearray} == 1);
              next if(ref($opt->{forcearray}) eq 'HASH'
                      and $opt->{forcearray}->{$el});
              croak "<$el> set in KeyAttr but not in ForceArray";
            }
          }
          else {
            delete($opt->{keyattr}->{$el}); # Never reached (famous last words?)
          }
        }
      }
      else {
        if(@{$opt->{keyattr}} == 0) {
          delete($opt->{keyattr});
        }
      }
    }
    else {
      $opt->{keyattr} = [ $opt->{keyattr} ];
    }
  }
  else  {
    if($opt->{strictmode}) {
      croak "No value specified for 'KeyAttr' option in call to XML$dirn()";
    }
    $opt->{keyattr} = [ @DefKeyAttr ];
  }


  # Special cleanup for {valueattr} which could be arrayref or hashref

  if(exists($opt->{valueattr})) {
    if(ref($opt->{valueattr}) eq 'ARRAY') {
      $opt->{valueattrlist} = {};
      $opt->{valueattrlist}->{$_} = 1 foreach(@{ delete $opt->{valueattr} });
    }
  }

  # make sure there's nothing weird in {grouptags}

  if($opt->{grouptags}) {
    croak "Illegal value for 'GroupTags' option - expected a hashref"
      unless UNIVERSAL::isa($opt->{grouptags}, 'HASH');

    while(my($key, $val) = each %{$opt->{grouptags}}) {
      next if $key ne $val;
      croak "Bad value in GroupTags: '$key' => '$val'";
    }
  }


  # Check the {variables} option is valid and initialise variables hash

  if($opt->{variables} and !UNIVERSAL::isa($opt->{variables}, 'HASH')) {
    croak "Illegal value for 'Variables' option - expected a hashref";
  }

  if($opt->{variables}) {
    $self->{_var_values} = { %{$opt->{variables}} };
  }
  elsif($opt->{varattr}) {
    $self->{_var_values} = {};
  }

}


##############################################################################
# Method: find_xml_file()
#
# Helper routine for XMLin().
# Takes a filename, and a list of directories, attempts to locate the file in
# the directories listed.
# Returns a full pathname on success; croaks on failure.
#

sub find_xml_file  {
  my $self = shift;
  my $file = shift;
  my @search_path = @_;


  require File::Basename;
  require File::Spec;

  my($filename, $filedir) = File::Basename::fileparse($file);

  if($filename ne $file) {        # Ignore searchpath if dir component
    return($file) if(-e $file);
  }
  else {
    my($path);
    foreach $path (@search_path)  {
      my $fullpath = File::Spec->catfile($path, $file);
      return($fullpath) if(-e $fullpath);
    }
  }

  # If user did not supply a search path, default to current directory

  if(!@search_path) {
    return($file) if(-e $file);
    croak "File does not exist: $file";
  }

  croak "Could not find $file in ", join(':', @search_path);
}


##############################################################################
# Method: collapse()
#
# Helper routine for XMLin().  This routine really comprises the 'smarts' (or
# value add) of this module.
#
# Takes the parse tree that XML::Parser produced from the supplied XML and
# recurses through it 'collapsing' unnecessary levels of indirection (nested
# arrays etc) to produce a data structure that is easier to work with.
#
# Elements in the original parser tree are represented as an element name
# followed by an arrayref.  The first element of the array is a hashref
# containing the attributes.  The rest of the array contains a list of any
# nested elements as name+arrayref pairs:
#
#  <element name>, [ { <attribute hashref> }, <element name>, [ ... ], ... ]
#
# The special element name '0' (zero) flags text content.
#
# This routine cuts down the noise by discarding any text content consisting of
# only whitespace and then moves the nested elements into the attribute hash
# using the name of the nested element as the hash key and the collapsed
# version of the nested element as the value.  Multiple nested elements with
# the same name will initially be represented as an arrayref, but this may be
# 'folded' into a hashref depending on the value of the keyattr option.
#

sub collapse {
  my $self = shift;


  # Start with the hash of attributes

  my $attr  = shift;
  if($self->{opt}->{noattr}) {                    # Discard if 'noattr' set
    $attr = $self->new_hashref;
  }
  elsif($self->{opt}->{normalisespace} == 2) {
    while(my($key, $value) = each %$attr) {
      $attr->{$key} = $self->normalise_space($value)
    }
  }


  # Do variable substitutions

  if(my $var = $self->{_var_values}) {
    while(my($key, $val) = each(%$attr)) {
      $val =~ s^\$\{([\w.]+)\}^ $self->get_var($1) ^ge;
      $attr->{$key} = $val;
    }
  }


  # Roll up 'value' attributes (but only if no nested elements)

  if(!@_  and  keys %$attr == 1) {
    my($k) = keys %$attr;
    if($self->{opt}->{valueattrlist}  and $self->{opt}->{valueattrlist}->{$k}) {
      return $attr->{$k};
    }
  }


  # Add any nested elements

  my($key, $val);
  while(@_) {
    $key = shift;
    $val = shift;
    $val = '' if not defined $val;

    if(ref($val)) {
      $val = $self->collapse(@$val);
      next if(!defined($val)  and  $self->{opt}->{suppressempty});
    }
    elsif($key eq '0') {
      next if($val =~ m{^\s*$}s);  # Skip all whitespace content

      $val = $self->normalise_space($val)
        if($self->{opt}->{normalisespace} == 2);

      # do variable substitutions

      if(my $var = $self->{_var_values}) {
        $val =~ s^\$\{(\w+)\}^ $self->get_var($1) ^ge;
      }


      # look for variable definitions

      if(my $var = $self->{opt}->{varattr}) {
        if(exists $attr->{$var}) {
          $self->set_var($attr->{$var}, $val);
        }
      }


      # Collapse text content in element with no attributes to a string

      if(!%$attr  and  !@_) {
        return($self->{opt}->{forcecontent} ?
          { $self->{opt}->{contentkey} => $val } : $val
        );
      }
      $key = $self->{opt}->{contentkey};
    }


    # Combine duplicate attributes into arrayref if required

    if(exists($attr->{$key})) {
      if(UNIVERSAL::isa($attr->{$key}, 'ARRAY')) {
        push(@{$attr->{$key}}, $val);
      }
      else {
        $attr->{$key} = [ $attr->{$key}, $val ];
      }
    }
    elsif(defined($val)  and  UNIVERSAL::isa($val, 'ARRAY')) {
      $attr->{$key} = [ $val ];
    }
    else {
      if( $key ne $self->{opt}->{contentkey}
          and (
            ($self->{opt}->{forcearray} == 1)
            or (
              (ref($self->{opt}->{forcearray}) eq 'HASH')
              and (
                $self->{opt}->{forcearray}->{$key}
                or (grep $key =~ $_, @{$self->{opt}->{forcearray}->{_regex}})
              )
            )
          )
        ) {
        $attr->{$key} = [ $val ];
      }
      else {
        $attr->{$key} = $val;
      }
    }

  }


  # Turn arrayrefs into hashrefs if key fields present

  if($self->{opt}->{keyattr}) {
    while(($key,$val) = each %$attr) {
      if(defined($val)  and  UNIVERSAL::isa($val, 'ARRAY')) {
        $attr->{$key} = $self->array_to_hash($key, $val);
      }
    }
  }


  # disintermediate grouped tags

  if($self->{opt}->{grouptags}) {
    while(my($key, $val) = each(%$attr)) {
      next unless(UNIVERSAL::isa($val, 'HASH') and (keys %$val == 1));
      next unless(exists($self->{opt}->{grouptags}->{$key}));

      my($child_key, $child_val) =  %$val;

      if($self->{opt}->{grouptags}->{$key} eq $child_key) {
        $attr->{$key}= $child_val;
      }
    }
  }


  # Fold hashes containing a single anonymous array up into just the array

  my $count = scalar keys %$attr;
  if($count == 1
     and  exists $attr->{anon}
     and  UNIVERSAL::isa($attr->{anon}, 'ARRAY')
  ) {
    return($attr->{anon});
  }


  # Do the right thing if hash is empty, otherwise just return it

  if(!%$attr  and  exists($self->{opt}->{suppressempty})) {
    if(defined($self->{opt}->{suppressempty})  and
       $self->{opt}->{suppressempty} eq '') {
      return('');
    }
    return(undef);
  }


  # Roll up named elements with named nested 'value' attributes

  if($self->{opt}->{valueattr}) {
    while(my($key, $val) = each(%$attr)) {
      next unless($self->{opt}->{valueattr}->{$key});
      next unless(UNIVERSAL::isa($val, 'HASH') and (keys %$val == 1));
      my($k) = keys %$val;
      next unless($k eq $self->{opt}->{valueattr}->{$key});
      $attr->{$key} = $val->{$k};
    }
  }

  return($attr)

}


##############################################################################
# Method: set_var()
#
# Called when a variable definition is encountered in the XML.  (A variable
# definition looks like <element attrname="name">value</element> where attrname
# matches the varattr setting).
#

sub set_var {
  my($self, $name, $value) = @_;

  $self->{_var_values}->{$name} = $value;
}


##############################################################################
# Method: get_var()
#
# Called during variable substitution to get the value for the named variable.
#

sub get_var {
  my($self, $name) = @_;

  my $value = $self->{_var_values}->{$name};
  return $value if(defined($value));

  return '${' . $name . '}';
}


##############################################################################
# Method: normalise_space()
#
# Strips leading and trailing whitespace and collapses sequences of whitespace
# characters to a single space.
#

sub normalise_space {
  my($self, $text) = @_;

  $text =~ s/^\s+//s;
  $text =~ s/\s+$//s;
  $text =~ s/\s\s+/ /sg;

  return $text;
}


##############################################################################
# Method: array_to_hash()
#
# Helper routine for collapse().
# Attempts to 'fold' an array of hashes into an hash of hashes.  Returns a
# reference to the hash on success or the original array if folding is
# not possible.  Behaviour is controlled by 'keyattr' option.
#

sub array_to_hash {
  my $self     = shift;
  my $name     = shift;
  my $arrayref = shift;

  my $hashref  = $self->new_hashref;

  my($i, $key, $val, $flag);


  # Handle keyattr => { .... }

  if(ref($self->{opt}->{keyattr}) eq 'HASH') {
    return($arrayref) unless(exists($self->{opt}->{keyattr}->{$name}));
    ($key, $flag) = @{$self->{opt}->{keyattr}->{$name}};
    for($i = 0; $i < @$arrayref; $i++)  {
      if(UNIVERSAL::isa($arrayref->[$i], 'HASH') and
         exists($arrayref->[$i]->{$key})
      ) {
        $val = $arrayref->[$i]->{$key};
        if(ref($val)) {
          $self->die_or_warn("<$name> element has non-scalar '$key' key attribute");
          return($arrayref);
        }
        $val = $self->normalise_space($val)
          if($self->{opt}->{normalisespace} == 1);
        $self->die_or_warn("<$name> element has non-unique value in '$key' key attribute: $val")
          if(exists($hashref->{$val}));
        $hashref->{$val} = $self->new_hashref( %{$arrayref->[$i]} );
        $hashref->{$val}->{"-$key"} = $hashref->{$val}->{$key} if($flag eq '-');
        delete $hashref->{$val}->{$key} unless($flag eq '+');
      }
      else {
        $self->die_or_warn("<$name> element has no '$key' key attribute");
        return($arrayref);
      }
    }
  }


  # Or assume keyattr => [ .... ]

  else {
    my $default_keys =
      join(',', @DefKeyAttr) eq join(',', @{$self->{opt}->{keyattr}});

    ELEMENT: for($i = 0; $i < @$arrayref; $i++)  {
      return($arrayref) unless(UNIVERSAL::isa($arrayref->[$i], 'HASH'));

      foreach $key (@{$self->{opt}->{keyattr}}) {
        if(defined($arrayref->[$i]->{$key}))  {
          $val = $arrayref->[$i]->{$key};
          if(ref($val)) {
            $self->die_or_warn("<$name> element has non-scalar '$key' key attribute")
              if not $default_keys;
            return($arrayref);
          }
          $val = $self->normalise_space($val)
            if($self->{opt}->{normalisespace} == 1);
          $self->die_or_warn("<$name> element has non-unique value in '$key' key attribute: $val")
            if(exists($hashref->{$val}));
          $hashref->{$val} = $self->new_hashref( %{$arrayref->[$i]} );
          delete $hashref->{$val}->{$key};
          next ELEMENT;
        }
      }

      return($arrayref);    # No keyfield matched
    }
  }

  # collapse any hashes which now only have a 'content' key

  if($self->{opt}->{collapseagain}) {
    $hashref = $self->collapse_content($hashref);
  }

  return($hashref);
}


##############################################################################
# Method: die_or_warn()
#
# Takes a diagnostic message and does one of three things:
# 1. dies if strict mode is enabled
# 2. warns if warnings are enabled but strict mode is not
# 3. ignores message and returns silently if neither strict mode nor warnings
#    are enabled
#

sub die_or_warn {
  my $self = shift;
  my $msg  = shift;

  croak $msg if($self->{opt}->{strictmode});
  if(warnings::enabled()) {
    carp "Warning: $msg";
  }
}


##############################################################################
# Method: new_hashref()
#
# This is a hook routine for overriding in a sub-class.  Some people believe
# that using Tie::IxHash here will solve order-loss problems.
#

sub new_hashref {
  my $self = shift;

  return { @_ };
}


##############################################################################
# Method: collapse_content()
#
# Helper routine for array_to_hash
#
# Arguments expected are:
# - an XML::Simple object
# - a hashref
# the hashref is a former array, turned into a hash by array_to_hash because
# of the presence of key attributes
# at this point collapse_content avoids over-complicated structures like
# dir => { libexecdir    => { content => '$exec_prefix/libexec' },
#          localstatedir => { content => '$prefix' },
#        }
# into
# dir => { libexecdir    => '$exec_prefix/libexec',
#          localstatedir => '$prefix',
#        }

sub collapse_content {
  my $self       = shift;
  my $hashref    = shift;

  my $contentkey = $self->{opt}->{contentkey};

  # first go through the values,checking that they are fit to collapse
  foreach my $val (values %$hashref) {
    return $hashref unless (     (ref($val) eq 'HASH')
                             and (keys %$val == 1)
                             and (exists $val->{$contentkey})
                           );
  }

  # now collapse them
  foreach my $key (keys %$hashref) {
    $hashref->{$key}=  $hashref->{$key}->{$contentkey};
  }

  return $hashref;
}


##############################################################################
# Method: value_to_xml()
#
# Helper routine for XMLout() - recurses through a data structure building up
# and returning an XML representation of that structure as a string.
#
# Arguments expected are:
# - the data structure to be encoded (usually a reference)
# - the XML tag name to use for this item
# - a string of spaces for use as the current indent level
#

sub value_to_xml {
  my $self = shift;;


  # Grab the other arguments

  my($ref, $name, $indent) = @_;

  my $named = (defined($name) and $name ne '' ? 1 : 0);

  my $nl = "\n";

  my $is_root = $indent eq '' ? 1 : 0;   # Warning, dirty hack!
  if($self->{opt}->{noindent}) {
    $indent = '';
    $nl     = '';
  }


  # Convert to XML

  my $refaddr = Scalar::Util::refaddr($ref);
  if($refaddr) {
    croak "circular data structures not supported"
      if $self->{_ancestors}->{$refaddr};
    $self->{_ancestors}->{$refaddr} = $ref;  # keep ref alive until we delete it
  }
  else {
    if($named) {
      return(join('',
              $indent, '<', $name, '>',
              ($self->{opt}->{noescape} ? $ref : $self->escape_value($ref)),
              '</', $name, ">", $nl
            ));
    }
    else {
      return("$ref$nl");
    }
  }


  # Unfold hash to array if possible

  if(UNIVERSAL::isa($ref, 'HASH')      # It is a hash
     and keys %$ref                    # and it's not empty
     and $self->{opt}->{keyattr}       # and folding is enabled
     and !$is_root                     # and its not the root element
  ) {
    $ref = $self->hash_to_array($name, $ref);
  }


  my @result = ();
  my($key, $value);


  # Handle hashrefs

  if(UNIVERSAL::isa($ref, 'HASH')) {

    # Reintermediate grouped values if applicable

    if($self->{opt}->{grouptags}) {
      $ref = $self->copy_hash($ref);
      while(my($key, $val) = each %$ref) {
        if($self->{opt}->{grouptags}->{$key}) {
          $ref->{$key} = $self->new_hashref(
            $self->{opt}->{grouptags}->{$key} => $val
          );
        }
      }
    }


    # Scan for namespace declaration attributes

    my $nsdecls = '';
    my $default_ns_uri;
    if($self->{nsup}) {
      $ref = $self->copy_hash($ref);
      $self->{nsup}->push_context();

      # Look for default namespace declaration first

      if(exists($ref->{xmlns})) {
        $self->{nsup}->declare_prefix('', $ref->{xmlns});
        $nsdecls .= qq( xmlns="$ref->{xmlns}");
        delete($ref->{xmlns});
      }
      $default_ns_uri = $self->{nsup}->get_uri('');


      # Then check all the other keys

      foreach my $qname (keys(%$ref)) {
        my($uri, $lname) = $self->{nsup}->parse_jclark_notation($qname);
        if($uri) {
          if($uri eq $xmlns_ns) {
            $self->{nsup}->declare_prefix($lname, $ref->{$qname});
            $nsdecls .= qq( xmlns:$lname="$ref->{$qname}");
            delete($ref->{$qname});
          }
        }
      }

      # Translate any remaining Clarkian names

      foreach my $qname (keys(%$ref)) {
        my($uri, $lname) = $self->{nsup}->parse_jclark_notation($qname);
        if($uri) {
          if($default_ns_uri  and  $uri eq $default_ns_uri) {
            $ref->{$lname} = $ref->{$qname};
            delete($ref->{$qname});
          }
          else {
            my $prefix = $self->{nsup}->get_prefix($uri);
            unless($prefix) {
              # $self->{nsup}->declare_prefix(undef, $uri);
              # $prefix = $self->{nsup}->get_prefix($uri);
              $prefix = $self->{ns_prefix}++;
              $self->{nsup}->declare_prefix($prefix, $uri);
              $nsdecls .= qq( xmlns:$prefix="$uri");
            }
            $ref->{"$prefix:$lname"} = $ref->{$qname};
            delete($ref->{$qname});
          }
        }
      }
    }


    my @nested = ();
    my $text_content = undef;
    if($named) {
      push @result, $indent, '<', $name, $nsdecls;
    }

    if(keys %$ref) {
      my $first_arg = 1;
      foreach my $key ($self->sorted_keys($name, $ref)) {
        my $value = $ref->{$key};
        next if(substr($key, 0, 1) eq '-');
        if(!defined($value)) {
          next if $self->{opt}->{suppressempty};
          unless(exists($self->{opt}->{suppressempty})
             and !defined($self->{opt}->{suppressempty})
          ) {
            carp 'Use of uninitialized value' if warnings::enabled();
          }
          if($key eq $self->{opt}->{contentkey}) {
            $text_content = '';
          }
          else {
            $value = exists($self->{opt}->{suppressempty}) ? {} : '';
          }
        }

        if(!ref($value)
           and $self->{opt}->{valueattr}
           and $self->{opt}->{valueattr}->{$key}
        ) {
          $value = $self->new_hashref(
            $self->{opt}->{valueattr}->{$key} => $value
          );
        }

        if(ref($value)  or  $self->{opt}->{noattr}) {
          push @nested,
            $self->value_to_xml($value, $key, "$indent  ");
        }
        else {
          if($key eq $self->{opt}->{contentkey}) {
            $value = $self->escape_value($value) unless($self->{opt}->{noescape});
            $text_content = $value;
          }
          else {
            $value = $self->escape_attr($value) unless($self->{opt}->{noescape});
            push @result, "\n$indent " . ' ' x length($name)
              if($self->{opt}->{attrindent}  and  !$first_arg);
            push @result, ' ', $key, '="', $value , '"';
            $first_arg = 0;
          }
        }
      }
    }
    else {
      $text_content = '';
    }

    if(@nested  or  defined($text_content)) {
      if($named) {
        push @result, ">";
        if(defined($text_content)) {
          push @result, $text_content;
          $nested[0] =~ s/^\s+// if(@nested);
        }
        else {
          push @result, $nl;
        }
        if(@nested) {
          push @result, @nested, $indent;
        }
        push @result, '</', $name, ">", $nl;
      }
      else {
        push @result, @nested;             # Special case if no root elements
      }
    }
    else {
      push @result, " />", $nl;
    }
    $self->{nsup}->pop_context() if($self->{nsup});
  }


  # Handle arrayrefs

  elsif(UNIVERSAL::isa($ref, 'ARRAY')) {
    foreach $value (@$ref) {
      next if !defined($value) and $self->{opt}->{suppressempty};
      if(!ref($value)) {
        push @result,
             $indent, '<', $name, '>',
             ($self->{opt}->{noescape} ? $value : $self->escape_value($value)),
             '</', $name, ">$nl";
      }
      elsif(UNIVERSAL::isa($value, 'HASH')) {
        push @result, $self->value_to_xml($value, $name, $indent);
      }
      else {
        push @result,
               $indent, '<', $name, ">$nl",
               $self->value_to_xml($value, 'anon', "$indent  "),
               $indent, '</', $name, ">$nl";
      }
    }
  }

  else {
    croak "Can't encode a value of type: " . ref($ref);
  }


  delete $self->{_ancestors}->{$refaddr};

  return(join('', @result));
}


##############################################################################
# Method: sorted_keys()
#
# Returns the keys of the referenced hash sorted into alphabetical order, but
# with the 'key' key (as in KeyAttr) first, if there is one.
#

sub sorted_keys {
  my($self, $name, $ref) = @_;

  return keys %$ref if $self->{opt}->{nosort};

  my %hash = %$ref;
  my $keyattr = $self->{opt}->{keyattr};

  my @key;

  if(ref $keyattr eq 'HASH') {
    if(exists $keyattr->{$name} and exists $hash{$keyattr->{$name}->[0]}) {
      push @key, $keyattr->{$name}->[0];
      delete $hash{$keyattr->{$name}->[0]};
    }
  }
  elsif(ref $keyattr eq 'ARRAY') {
    foreach (@{$keyattr}) {
      if(exists $hash{$_}) {
        push @key, $_;
        delete $hash{$_};
        last;
      }
    }
  }

  return(@key, sort keys %hash);
}

##############################################################################
# Method: escape_value()
#
# Helper routine for automatically escaping values for XMLout().
# Expects a scalar data value.  Returns escaped version.
#

sub escape_value {
  my($self, $data) = @_;

  return '' unless(defined($data));

  $data =~ s/&/&amp;/sg;
  $data =~ s/</&lt;/sg;
  $data =~ s/>/&gt;/sg;
  $data =~ s/"/&quot;/sg;

  my $level = $self->{opt}->{numericescape} or return $data;

  return $self->numeric_escape($data, $level);
}

sub numeric_escape {
  my($self, $data, $level) = @_;

  if($self->{opt}->{numericescape} eq '2') {
    $data =~ s/([^\x00-\x7F])/'&#' . ord($1) . ';'/gse;
  }
  else {
    $data =~ s/([^\x00-\xFF])/'&#' . ord($1) . ';'/gse;
  }

  return $data;
}

##############################################################################
# Method: escape_attr()
#
# Helper routine for escaping attribute values.  Defaults to escape_value(),
# but may be overridden by a subclass to customise behaviour.
#

sub escape_attr {
  my $self = shift;

  return $self->escape_value(@_);
}


##############################################################################
# Method: hash_to_array()
#
# Helper routine for value_to_xml().
# Attempts to 'unfold' a hash of hashes into an array of hashes.  Returns a
# reference to the array on success or the original hash if unfolding is
# not possible.
#

sub hash_to_array {
  my $self    = shift;
  my $parent  = shift;
  my $hashref = shift;

  my $arrayref = [];

  my($key, $value);

  my @keys = $self->{opt}->{nosort} ? keys %$hashref : sort keys %$hashref;
  foreach $key (@keys) {
    $value = $hashref->{$key};
    return($hashref) unless(UNIVERSAL::isa($value, 'HASH'));

    if(ref($self->{opt}->{keyattr}) eq 'HASH') {
      return($hashref) unless(defined($self->{opt}->{keyattr}->{$parent}));
      push @$arrayref, $self->copy_hash(
        $value, $self->{opt}->{keyattr}->{$parent}->[0] => $key
      );
    }
    else {
      push(@$arrayref, { $self->{opt}->{keyattr}->[0] => $key, %$value });
    }
  }

  return($arrayref);
}


##############################################################################
# Method: copy_hash()
#
# Helper routine for hash_to_array().  When unfolding a hash of hashes into
# an array of hashes, we need to copy the key from the outer hash into the
# inner hash.  This routine makes a copy of the original hash so we don't
# destroy the original data structure.  You might wish to override this
# method if you're using tied hashes and don't want them to get untied.
#

sub copy_hash {
  my($self, $orig, @extra) = @_;

  return { @extra, %$orig };
}

##############################################################################
# Methods required for building trees from SAX events
##############################################################################

sub start_document {
  my $self = shift;

  $self->handle_options('in') unless($self->{opt});

  $self->{lists} = [];
  $self->{curlist} = $self->{tree} = [];
}


sub start_element {
  my $self    = shift;
  my $element = shift;

  my $name = $element->{Name};
  if($self->{opt}->{nsexpand}) {
    $name = $element->{LocalName} || '';
    if($element->{NamespaceURI}) {
      $name = '{' . $element->{NamespaceURI} . '}' . $name;
    }
  }
  my $attributes = {};
  if($element->{Attributes}) {  # Might be undef
    foreach my $attr (values %{$element->{Attributes}}) {
      if($self->{opt}->{nsexpand}) {
        my $name = $attr->{LocalName} || '';
        if($attr->{NamespaceURI}) {
          $name = '{' . $attr->{NamespaceURI} . '}' . $name
        }
        $name = 'xmlns' if($name eq $bad_def_ns_jcn);
        $attributes->{$name} = $attr->{Value};
      }
      else {
        $attributes->{$attr->{Name}} = $attr->{Value};
      }
    }
  }
  my $newlist = [ $attributes ];
  push @{ $self->{lists} }, $self->{curlist};
  push @{ $self->{curlist} }, $name => $newlist;
  $self->{curlist} = $newlist;
}


sub characters {
  my $self  = shift;
  my $chars = shift;

  my $text  = $chars->{Data};
  my $clist = $self->{curlist};
  my $pos = $#$clist;

  if ($pos > 0 and $clist->[$pos - 1] eq '0') {
    $clist->[$pos] .= $text;
  }
  else {
    push @$clist, 0 => $text;
  }
}


sub end_element {
  my $self    = shift;

  $self->{curlist} = pop @{ $self->{lists} };
}


sub end_document {
  my $self = shift;

  delete($self->{curlist});
  delete($self->{lists});

  my $tree = $self->{tree};
  delete($self->{tree});


  # Return tree as-is to XMLin()

  return($tree) if($self->{nocollapse});


  # Or collapse it before returning it to SAX parser class

  if($self->{opt}->{keeproot}) {
    $tree = $self->collapse({}, @$tree);
  }
  else {
    $tree = $self->collapse(@{$tree->[1]});
  }

  if($self->{opt}->{datahandler}) {
    return($self->{opt}->{datahandler}->($self, $tree));
  }

  return($tree);
}

*xml_in  = \&XMLin;
*xml_out = \&XMLout;

1;

__END__

=head1 STATUS OF THIS MODULE

The use of this module in new code is B<strongly discouraged>.  Other modules
are available which provide more straightforward and consistent interfaces.  In
particular, L<XML::LibXML> is highly recommended and you can refer to
L<Perl XML::LibXML by Example|http://grantm.github.io/perl-libxml-by-example/>
for a tutorial introduction.

L<XML::Twig> is another excellent alternative.

The major problems with this module are the large number of options (some of
which have unfortunate defaults) and the arbitrary ways in which these options
interact - often producing unexpected results.

Patches with bug fixes and documentation fixes are welcome, but new features
are unlikely to be added.

=head1 QUICK START

Say you have a script called B<foo> and a file of configuration options
called B<foo.xml> containing the following:

  <config logdir="/var/log/foo/" debugfile="/tmp/foo.debug">
    <server name="sahara" osname="solaris" osversion="2.6">
      <address>10.0.0.101</address>
      <address>10.0.1.101</address>
    </server>
    <server name="gobi" osname="irix" osversion="6.5">
      <address>10.0.0.102</address>
    </server>
    <server name="kalahari" osname="linux" osversion="2.0.34">
      <address>10.0.0.103</address>
      <address>10.0.1.103</address>
    </server>
  </config>

The following lines of code in B<foo>:

  use XML::Simple qw(:strict);

  my $config = XMLin(undef, KeyAttr => { server => 'name' }, ForceArray => [ 'server', 'address' ]);

will 'slurp' the configuration options into the hashref $config (because no
filename or XML string was passed as the first argument to C<XMLin()> the name
and location of the XML file will be inferred from name and location of the
script).  You can dump out the contents of the hashref using Data::Dumper:

  use Data::Dumper;

  print Dumper($config);

which will produce something like this (formatting has been adjusted for
brevity):

  {
      'logdir'        => '/var/log/foo/',
      'debugfile'     => '/tmp/foo.debug',
      'server'        => {
          'sahara'        => {
              'osversion'     => '2.6',
              'osname'        => 'solaris',
              'address'       => [ '10.0.0.101', '10.0.1.101' ]
          },
          'gobi'          => {
              'osversion'     => '6.5',
              'osname'        => 'irix',
              'address'       => [ '10.0.0.102' ]
          },
          'kalahari'      => {
              'osversion'     => '2.0.34',
              'osname'        => 'linux',
              'address'       => [ '10.0.0.103', '10.0.1.103' ]
          }
      }
  }

Your script could then access the name of the log directory like this:

  print $config->{logdir};

similarly, the second address on the server 'kalahari' could be referenced as:

  print $config->{server}->{kalahari}->{address}->[1];

Note: If the mapping between the output of Data::Dumper and the print
statements above is not obvious to you, then please refer to the 'references'
tutorial (AKA: "Mark's very short tutorial about references") at L<perlreftut>.

In this example, the C<< ForceArray >> option was used to list elements that
might occur multiple times and should therefore be represented as arrayrefs
(even when only one element is present).

The C<< KeyAttr >> option was used to indicate that each C<< <server> >>
element has a unique identifier in the C<< name >> attribute.  This allows you
to index directly to a particular server record using the name as a hash key
(as shown above).

For simple requirements, that's really all there is to it.  If you want to
store your XML in a different directory or file, or pass it in as a string or
even pass it in via some derivative of an IO::Handle, you'll need to check out
L<"OPTIONS">.  If you want to turn off or tweak the array folding feature (that
neat little transformation that produced $config->{server}) you'll find options
for that as well.

If you want to generate XML (for example to write a modified version of
$config back out as XML), check out C<XMLout()>.

If your needs are not so simple, this may not be the module for you.  In that
case, you might want to read L<"WHERE TO FROM HERE?">.

=head1 DESCRIPTION

The XML::Simple module provides a simple API layer on top of an underlying XML
parsing module (either XML::Parser or one of the SAX2 parser modules).  Two
functions are exported: C<XMLin()> and C<XMLout()>.  Note: you can explicitly
request the lower case versions of the function names: C<xml_in()> and
C<xml_out()>.

The simplest approach is to call these two functions directly, but an
optional object oriented interface (see L<"OPTIONAL OO INTERFACE"> below)
allows them to be called as methods of an B<XML::Simple> object.  The object
interface can also be used at either end of a SAX pipeline.

=head2 XMLin()

Parses XML formatted data and returns a reference to a data structure which
contains the same information in a more readily accessible form.  (Skip
down to L<"EXAMPLES"> below, for more sample code).

C<XMLin()> accepts an optional XML specifier followed by zero or more 'name =>
value' option pairs.  The XML specifier can be one of the following:

=over 4

=item A filename

If the filename contains no directory components C<XMLin()> will look for the
file in each directory in the SearchPath (see L<"OPTIONS"> below) or in the
current directory if the SearchPath option is not defined.  eg:

  $ref = XMLin('/etc/params.xml');

Note, the filename '-' can be used to parse from STDIN.

=item undef

If there is no XML specifier, C<XMLin()> will check the script directory and
each of the SearchPath directories for a file with the same name as the script
but with the extension '.xml'.  Note: if you wish to specify options, you
must specify the value 'undef'.  eg:

  $ref = XMLin(undef, ForceArray => 1);

=item A string of XML

A string containing XML (recognised by the presence of '<' and '>' characters)
will be parsed directly.  eg:

  $ref = XMLin('<opt username="bob" password="flurp" />');

=item An IO::Handle object

An IO::Handle object will be read to EOF and its contents parsed. eg:

  $fh = IO::File->new('/etc/params.xml');
  $ref = XMLin($fh);

=back

=head2 XMLout()

Takes a data structure (generally a hashref) and returns an XML encoding of
that structure.  If the resulting XML is parsed using C<XMLin()>, it should
return a data structure equivalent to the original (see caveats below).

The C<XMLout()> function can also be used to output the XML as SAX events
see the C<Handler> option and L<"SAX SUPPORT"> for more details).

When translating hashes to XML, hash keys which have a leading '-' will be
silently skipped.  This is the approved method for marking elements of a
data structure which should be ignored by C<XMLout>.  (Note: If these items
were not skipped the key names would be emitted as element or attribute names
with a leading '-' which would not be valid XML).

=head2 Caveats

Some care is required in creating data structures which will be passed to
C<XMLout()>.  Hash keys from the data structure will be encoded as either XML
element names or attribute names.  Therefore, you should use hash key names
which conform to the relatively strict XML naming rules:

Names in XML must begin with a letter.  The remaining characters may be
letters, digits, hyphens (-), underscores (_) or full stops (.).  It is also
allowable to include one colon (:) in an element name but this should only be
used when working with namespaces (B<XML::Simple> can only usefully work with
namespaces when teamed with a SAX Parser).

You can use other punctuation characters in hash values (just not in hash
keys) however B<XML::Simple> does not support dumping binary data.

If you break these rules, the current implementation of C<XMLout()> will
simply emit non-compliant XML which will be rejected if you try to read it
back in.  (A later version of B<XML::Simple> might take a more proactive
approach).

Note also that although you can nest hashes and arrays to arbitrary levels,
circular data structures are not supported and will cause C<XMLout()> to die.

If you wish to 'round-trip' arbitrary data structures from Perl to XML and back
to Perl, then you should probably disable array folding (using the KeyAttr
option) both with C<XMLout()> and with C<XMLin()>.  If you still don't get the
expected results, you may prefer to use L<XML::Dumper> which is designed for
exactly that purpose.

Refer to L<"WHERE TO FROM HERE?"> if C<XMLout()> is too simple for your needs.


=head1 OPTIONS

B<XML::Simple> supports a number of options (in fact as each release of
B<XML::Simple> adds more options, the module's claim to the name 'Simple'
becomes increasingly tenuous).  If you find yourself repeatedly having to
specify the same options, you might like to investigate L<"OPTIONAL OO
INTERFACE"> below.

If you can't be bothered reading the documentation, refer to
L<"STRICT MODE"> to automatically catch common mistakes.

Because there are so many options, it's hard for new users to know which ones
are important, so here are the two you really need to know about:

=over 4

=item *

check out C<ForceArray> because you'll almost certainly want to turn it on

=item *

make sure you know what the C<KeyAttr> option does and what its default value is
because it may surprise you otherwise (note in particular that 'KeyAttr'
affects both C<XMLin> and C<XMLout>)

=back

The option name headings below have a trailing 'comment' - a hash followed by
two pieces of metadata:

=over 4

=item *

Options are marked with 'I<in>' if they are recognised by C<XMLin()> and
'I<out>' if they are recognised by C<XMLout()>.

=item *

Each option is also flagged to indicate whether it is:

 'important'   - don't use the module until you understand this one
 'handy'       - you can skip this on the first time through
 'advanced'    - you can skip this on the second time through
 'SAX only'    - don't worry about this unless you're using SAX (or
                 alternatively if you need this, you also need SAX)
 'seldom used' - you'll probably never use this unless you were the
                 person that requested the feature

=back

The options are listed alphabetically:

Note: option names are no longer case sensitive so you can use the mixed case
versions shown here; all lower case as required by versions 2.03 and earlier;
or you can add underscores between the words (eg: key_attr).


=head2 AttrIndent => 1 I<# out - handy>

When you are using C<XMLout()>, enable this option to have attributes printed
one-per-line with sensible indentation rather than all on one line.

=head2 Cache => [ cache schemes ] I<# in - advanced>

Because loading the B<XML::Parser> module and parsing an XML file can consume a
significant number of CPU cycles, it is often desirable to cache the output of
C<XMLin()> for later reuse.

When parsing from a named file, B<XML::Simple> supports a number of caching
schemes.  The 'Cache' option may be used to specify one or more schemes (using
an anonymous array).  Each scheme will be tried in turn in the hope of finding
a cached pre-parsed representation of the XML file.  If no cached copy is
found, the file will be parsed and the first cache scheme in the list will be
used to save a copy of the results.  The following cache schemes have been
implemented:

=over 4

=item storable

Utilises B<Storable.pm> to read/write a cache file with the same name as the
XML file but with the extension .stor

=item memshare

When a file is first parsed, a copy of the resulting data structure is retained
in memory in the B<XML::Simple> module's namespace.  Subsequent calls to parse
the same file will return a reference to this structure.  This cached version
will persist only for the life of the Perl interpreter (which in the case of
mod_perl for example, may be some significant time).

Because each caller receives a reference to the same data structure, a change
made by one caller will be visible to all.  For this reason, the reference
returned should be treated as read-only.

=item memcopy

This scheme works identically to 'memshare' (above) except that each caller
receives a reference to a new data structure which is a copy of the cached
version.  Copying the data structure will add a little processing overhead,
therefore this scheme should only be used where the caller intends to modify
the data structure (or wishes to protect itself from others who might).  This
scheme uses B<Storable.pm> to perform the copy.

=back

Warning! The memory-based caching schemes compare the timestamp on the file to
the time when it was last parsed.  If the file is stored on an NFS filesystem
(or other network share) and the clock on the file server is not exactly
synchronised with the clock where your script is run, updates to the source XML
file may appear to be ignored.

=head2 ContentKey => 'keyname' I<# in+out - seldom used>

When text content is parsed to a hash value, this option lets you specify a
name for the hash key to override the default 'content'.  So for example:

  XMLin('<opt one="1">Text</opt>', ContentKey => 'text')

will parse to:

  { 'one' => 1, 'text' => 'Text' }

instead of:

  { 'one' => 1, 'content' => 'Text' }

C<XMLout()> will also honour the value of this option when converting a hashref
to XML.

You can also prefix your selected key name with a '-' character to have
C<XMLin()> try a little harder to eliminate unnecessary 'content' keys after
array folding.  For example:

  XMLin(
    '<opt><item name="one">First</item><item name="two">Second</item></opt>',
    KeyAttr => {item => 'name'},
    ForceArray => [ 'item' ],
    ContentKey => '-content'
  )

will parse to:

  {
    'item' => {
      'one' =>  'First'
      'two' =>  'Second'
    }
  }

rather than this (without the '-'):

  {
    'item' => {
      'one' => { 'content' => 'First' }
      'two' => { 'content' => 'Second' }
    }
  }

=head2 DataHandler => code_ref I<# in - SAX only>

When you use an B<XML::Simple> object as a SAX handler, it will return a
'simple tree' data structure in the same format as C<XMLin()> would return.  If
this option is set (to a subroutine reference), then when the tree is built the
subroutine will be called and passed two arguments: a reference to the
B<XML::Simple> object and a reference to the data tree.  The return value from
the subroutine will be returned to the SAX driver.  (See L<"SAX SUPPORT"> for
more details).

=head2 ForceArray => 1 I<# in - important>

This option should be set to '1' to force nested elements to be represented
as arrays even when there is only one.  Eg, with ForceArray enabled, this
XML:

    <opt>
      <name>value</name>
    </opt>

would parse to this:

    {
      'name' => [
                  'value'
                ]
    }

instead of this (the default):

    {
      'name' => 'value'
    }

This option is especially useful if the data structure is likely to be written
back out as XML and the default behaviour of rolling single nested elements up
into attributes is not desirable.

If you are using the array folding feature, you should almost certainly enable
this option.  If you do not, single nested elements will not be parsed to
arrays and therefore will not be candidates for folding to a hash.  (Given that
the default value of 'KeyAttr' enables array folding, the default value of this
option should probably also have been enabled too - sorry).

=head2 ForceArray => [ names ] I<# in - important>

This alternative (and preferred) form of the 'ForceArray' option allows you to
specify a list of element names which should always be forced into an array
representation, rather than the 'all or nothing' approach above.

It is also possible (since version 2.05) to include compiled regular
expressions in the list - any element names which match the pattern will be
forced to arrays.  If the list contains only a single regex, then it is not
necessary to enclose it in an arrayref.  Eg:

  ForceArray => qr/_list$/

=head2 ForceContent => 1 I<# in - seldom used>

When C<XMLin()> parses elements which have text content as well as attributes,
the text content must be represented as a hash value rather than a simple
scalar.  This option allows you to force text content to always parse to
a hash value even when there are no attributes.  So for example:

  XMLin('<opt><x>text1</x><y a="2">text2</y></opt>', ForceContent => 1)

will parse to:

  {
    'x' => {           'content' => 'text1' },
    'y' => { 'a' => 2, 'content' => 'text2' }
  }

instead of:

  {
    'x' => 'text1',
    'y' => { 'a' => 2, 'content' => 'text2' }
  }

=head2 GroupTags => { grouping tag => grouped tag } I<# in+out - handy>

You can use this option to eliminate extra levels of indirection in your Perl
data structure.  For example this XML:

  <opt>
   <searchpath>
     <dir>/usr/bin</dir>
     <dir>/usr/local/bin</dir>
     <dir>/usr/X11/bin</dir>
   </searchpath>
 </opt>

Would normally be read into a structure like this:

  {
    searchpath => {
                    dir => [ '/usr/bin', '/usr/local/bin', '/usr/X11/bin' ]
                  }
  }

But when read in with the appropriate value for 'GroupTags':

  my $opt = XMLin($xml, GroupTags => { searchpath => 'dir' });

It will return this simpler structure:

  {
    searchpath => [ '/usr/bin', '/usr/local/bin', '/usr/X11/bin' ]
  }

The grouping element (C<< <searchpath> >> in the example) must not contain any
attributes or elements other than the grouped element.

You can specify multiple 'grouping element' to 'grouped element' mappings in
the same hashref.  If this option is combined with C<KeyAttr>, the array
folding will occur first and then the grouped element names will be eliminated.

C<XMLout> will also use the grouptag mappings to re-introduce the tags around
the grouped elements.  Beware though that this will occur in all places that
the 'grouping tag' name occurs - you probably don't want to use the same name
for elements as well as attributes.

=head2 Handler => object_ref I<# out - SAX only>

Use the 'Handler' option to have C<XMLout()> generate SAX events rather than
returning a string of XML.  For more details see L<"SAX SUPPORT"> below.

Note: the current implementation of this option generates a string of XML
and uses a SAX parser to translate it into SAX events.  The normal encoding
rules apply here - your data must be UTF8 encoded unless you specify an
alternative encoding via the 'XMLDecl' option; and by the time the data reaches
the handler object, it will be in UTF8 form regardless of the encoding you
supply.  A future implementation of this option may generate the events
directly.

=head2 KeepRoot => 1 I<# in+out - handy>

In its attempt to return a data structure free of superfluous detail and
unnecessary levels of indirection, C<XMLin()> normally discards the root
element name.  Setting the 'KeepRoot' option to '1' will cause the root element
name to be retained.  So after executing this code:

  $config = XMLin('<config tempdir="/tmp" />', KeepRoot => 1)

You'll be able to reference the tempdir as
C<$config-E<gt>{config}-E<gt>{tempdir}> instead of the default
C<$config-E<gt>{tempdir}>.

Similarly, setting the 'KeepRoot' option to '1' will tell C<XMLout()> that the
data structure already contains a root element name and it is not necessary to
add another.

=head2 KeyAttr => [ list ] I<# in+out - important>

This option controls the 'array folding' feature which translates nested
elements from an array to a hash.  It also controls the 'unfolding' of hashes
to arrays.

For example, this XML:

    <opt>
      <user login="grep" fullname="Gary R Epstein" />
      <user login="stty" fullname="Simon T Tyson" />
    </opt>

would, by default, parse to this:

    {
      'user' => [
                  {
                    'login' => 'grep',
                    'fullname' => 'Gary R Epstein'
                  },
                  {
                    'login' => 'stty',
                    'fullname' => 'Simon T Tyson'
                  }
                ]
    }

If the option 'KeyAttr => "login"' were used to specify that the 'login'
attribute is a key, the same XML would parse to:

    {
      'user' => {
                  'stty' => {
                              'fullname' => 'Simon T Tyson'
                            },
                  'grep' => {
                              'fullname' => 'Gary R Epstein'
                            }
                }
    }

The key attribute names should be supplied in an arrayref if there is more
than one.  C<XMLin()> will attempt to match attribute names in the order
supplied.  C<XMLout()> will use the first attribute name supplied when
'unfolding' a hash into an array.

Note 1: The default value for 'KeyAttr' is ['name', 'key', 'id'].  If you do
not want folding on input or unfolding on output you must set this option
to an empty list to disable the feature.

Note 2: If you wish to use this option, you should also enable the
C<ForceArray> option.  Without 'ForceArray', a single nested element will be
rolled up into a scalar rather than an array and therefore will not be folded
(since only arrays get folded).

=head2 KeyAttr => { list } I<# in+out - important>

This alternative (and preferred) method of specifying the key attributes
allows more fine grained control over which elements are folded and on which
attributes.  For example the option 'KeyAttr => { package => 'id' } will cause
any package elements to be folded on the 'id' attribute.  No other elements
which have an 'id' attribute will be folded at all.

Note: C<XMLin()> will generate a warning (or a fatal error in L<"STRICT MODE">)
if this syntax is used and an element which does not have the specified key
attribute is encountered (eg: a 'package' element without an 'id' attribute, to
use the example above).  Warnings can be suppressed with the lexical
C<no warnings;> pragma or C<no warnings 'XML::Simple';>.

Two further variations are made possible by prefixing a '+' or a '-' character
to the attribute name:

The option 'KeyAttr => { user => "+login" }' will cause this XML:

    <opt>
      <user login="grep" fullname="Gary R Epstein" />
      <user login="stty" fullname="Simon T Tyson" />
    </opt>

to parse to this data structure:

    {
      'user' => {
                  'stty' => {
                              'fullname' => 'Simon T Tyson',
                              'login'    => 'stty'
                            },
                  'grep' => {
                              'fullname' => 'Gary R Epstein',
                              'login'    => 'grep'
                            }
                }
    }

The '+' indicates that the value of the key attribute should be copied rather
than moved to the folded hash key.

A '-' prefix would produce this result:

    {
      'user' => {
                  'stty' => {
                              'fullname' => 'Simon T Tyson',
                              '-login'    => 'stty'
                            },
                  'grep' => {
                              'fullname' => 'Gary R Epstein',
                              '-login'    => 'grep'
                            }
                }
    }

As described earlier, C<XMLout> will ignore hash keys starting with a '-'.

=head2 NoAttr => 1 I<# in+out - handy>

When used with C<XMLout()>, the generated XML will contain no attributes.
All hash key/values will be represented as nested elements instead.

When used with C<XMLin()>, any attributes in the XML will be ignored.

=head2 NoEscape => 1 I<# out - seldom used>

By default, C<XMLout()> will translate the characters 'E<lt>', 'E<gt>', '&' and
'"' to '&lt;', '&gt;', '&amp;' and '&quot' respectively.  Use this option to
suppress escaping (presumably because you've already escaped the data in some
more sophisticated manner).

=head2 NoIndent => 1 I<# out - seldom used>

Set this option to 1 to disable C<XMLout()>'s default 'pretty printing' mode.
With this option enabled, the XML output will all be on one line (unless there
are newlines in the data) - this may be easier for downstream processing.

=head2 NoSort => 1 I<# out - seldom used>

Newer versions of XML::Simple sort elements and attributes alphabetically (*),
by default.  Enable this option to suppress the sorting - possibly for
backwards compatibility.

* Actually, sorting is alphabetical but 'key' attribute or element names (as in
'KeyAttr') sort first.  Also, when a hash of hashes is 'unfolded', the elements
are sorted alphabetically by the value of the key field.

=head2 NormaliseSpace => 0 | 1 | 2 I<# in - handy>

This option controls how whitespace in text content is handled.  Recognised
values for the option are:

=over 4

=item *

0 = (default) whitespace is passed through unaltered (except of course for the
normalisation of whitespace in attribute values which is mandated by the XML
recommendation)

=item *

1 = whitespace is normalised in any value used as a hash key (normalising means
removing leading and trailing whitespace and collapsing sequences of whitespace
characters to a single space)

=item *

2 = whitespace is normalised in all text content

=back

Note: you can spell this option with a 'z' if that is more natural for you.

=head2 NSExpand => 1 I<# in+out handy - SAX only>

This option controls namespace expansion - the translation of element and
attribute names of the form 'prefix:name' to '{uri}name'.  For example the
element name 'xsl:template' might be expanded to:
'{http://www.w3.org/1999/XSL/Transform}template'.

By default, C<XMLin()> will return element names and attribute names exactly as
they appear in the XML.  Setting this option to 1 will cause all element and
attribute names to be expanded to include their namespace prefix.

I<Note: You must be using a SAX parser for this option to work (ie: it does not
work with XML::Parser)>.

This option also controls whether C<XMLout()> performs the reverse translation
from '{uri}name' back to 'prefix:name'.  The default is no translation.  If
your data contains expanded names, you should set this option to 1 otherwise
C<XMLout> will emit XML which is not well formed.

I<Note: You must have the XML::NamespaceSupport module installed if you want
C<XMLout()> to translate URIs back to prefixes>.

=head2 NumericEscape => 0 | 1 | 2 I<# out - handy>

Use this option to have 'high' (non-ASCII) characters in your Perl data
structure converted to numeric entities (eg: &#8364;) in the XML output.  Three
levels are possible:

0 - default: no numeric escaping (OK if you're writing out UTF8)

1 - only characters above 0xFF are escaped (ie: characters in the 0x80-FF range are not escaped), possibly useful with ISO8859-1 output

2 - all characters above 0x7F are escaped (good for plain ASCII output)

=head2 OutputFile => <file specifier> I<# out - handy>

The default behaviour of C<XMLout()> is to return the XML as a string.  If you
wish to write the XML to a file, simply supply the filename using the
'OutputFile' option.

This option also accepts an IO handle object - especially useful in Perl 5.8.0
and later for output using an encoding other than UTF-8, eg:

  open my $fh, '>:encoding(iso-8859-1)', $path or die "open($path): $!";
  XMLout($ref, OutputFile => $fh);

Note, XML::Simple does not require that the object you pass in to the
OutputFile option inherits from L<IO::Handle> - it simply assumes the object
supports a C<print> method.

=head2 ParserOpts => [ XML::Parser Options ] I<# in - don't use this>

I<Note: This option is now officially deprecated.  If you find it useful, email
the author with an example of what you use it for.  Do not use this option to
set the ProtocolEncoding, that's just plain wrong - fix the XML>.

This option allows you to pass parameters to the constructor of the underlying
XML::Parser object (which of course assumes you're not using SAX).

=head2 RootName => 'string' I<# out - handy>

By default, when C<XMLout()> generates XML, the root element will be named
'opt'.  This option allows you to specify an alternative name.

Specifying either undef or the empty string for the RootName option will
produce XML with no root elements.  In most cases the resulting XML fragment
will not be 'well formed' and therefore could not be read back in by C<XMLin()>.
Nevertheless, the option has been found to be useful in certain circumstances.

=head2 SearchPath => [ list ] I<# in - handy>

If you pass C<XMLin()> a filename, but the filename include no directory
component, you can use this option to specify which directories should be
searched to locate the file.  You might use this option to search first in the
user's home directory, then in a global directory such as /etc.

If a filename is provided to C<XMLin()> but SearchPath is not defined, the
file is assumed to be in the current directory.

If the first parameter to C<XMLin()> is undefined, the default SearchPath
will contain only the directory in which the script itself is located.
Otherwise the default SearchPath will be empty.

=head2 StrictMode => 1 | 0  I<# in+out seldom used>

This option allows you to turn L<STRICT MODE> on or off for a particular call,
regardless of whether it was enabled at the time XML::Simple was loaded.

=head2 SuppressEmpty => 1 | '' | undef I<# in+out - handy>

This option controls what C<XMLin()> should do with empty elements (no
attributes and no content).  The default behaviour is to represent them as
empty hashes.  Setting this option to a true value (eg: 1) will cause empty
elements to be skipped altogether.  Setting the option to 'undef' or the empty
string will cause empty elements to be represented as the undefined value or
the empty string respectively.  The latter two alternatives are a little
easier to test for in your code than a hash with no keys.

The option also controls what C<XMLout()> does with undefined values.  Setting
the option to undef causes undefined values to be output as empty elements
(rather than empty attributes), it also suppresses the generation of warnings
about undefined values.  Setting the option to a true value (eg: 1) causes
undefined values to be skipped altogether on output.

=head2 ValueAttr => [ names ] I<# in - handy>

Use this option to deal elements which always have a single attribute and no
content.  Eg:

  <opt>
    <colour value="red" />
    <size   value="XXL" />
  </opt>

Setting C<< ValueAttr => [ 'value' ] >> will cause the above XML to parse to:

  {
    colour => 'red',
    size   => 'XXL'
  }

instead of this (the default):

  {
    colour => { value => 'red' },
    size   => { value => 'XXL' }
  }

Note: This form of the ValueAttr option is not compatible with C<XMLout()> -
since the attribute name is discarded at parse time, the original XML cannot be
reconstructed.

=head2 ValueAttr => { element => attribute, ... } I<# in+out - handy>

This (preferred) form of the ValueAttr option requires you to specify both
the element and the attribute names.  This is not only safer, it also allows
the original XML to be reconstructed by C<XMLout()>.

Note: You probably don't want to use this option and the NoAttr option at the
same time.

=head2 Variables => { name => value } I<# in - handy>

This option allows variables in the XML to be expanded when the file is read.
(there is no facility for putting the variable names back if you regenerate
XML using C<XMLout>).

A 'variable' is any text of the form C<${name}> which occurs in an attribute
value or in the text content of an element.  If 'name' matches a key in the
supplied hashref, C<${name}> will be replaced with the corresponding value from
the hashref.  If no matching key is found, the variable will not be replaced.
Names must match the regex: C<[\w.]+> (ie: only 'word' characters and dots are
allowed).

=head2 VarAttr => 'attr_name' I<# in - handy>

In addition to the variables defined using C<Variables>, this option allows
variables to be defined in the XML.  A variable definition consists of an
element with an attribute called 'attr_name' (the value of the C<VarAttr>
option).  The value of the attribute will be used as the variable name and the
text content of the element will be used as the value.  A variable defined in
this way will override a variable defined using the C<Variables> option.  For
example:

  XMLin( '<opt>
            <dir name="prefix">/usr/local/apache</dir>
            <dir name="exec_prefix">${prefix}</dir>
            <dir name="bindir">${exec_prefix}/bin</dir>
          </opt>',
         VarAttr => 'name', ContentKey => '-content'
        );

produces the following data structure:

  {
    dir => {
             prefix      => '/usr/local/apache',
             exec_prefix => '/usr/local/apache',
             bindir      => '/usr/local/apache/bin',
           }
  }

=head2 XMLDecl => 1  or  XMLDecl => 'string'  I<# out - handy>

If you want the output from C<XMLout()> to start with the optional XML
declaration, simply set the option to '1'.  The default XML declaration is:

        <?xml version='1.0' standalone='yes'?>

If you want some other string (for example to declare an encoding value), set
the value of this option to the complete string you require.


=head1 OPTIONAL OO INTERFACE

The procedural interface is both simple and convenient however there are a
couple of reasons why you might prefer to use the object oriented (OO)
interface:

=over 4

=item *

to define a set of default values which should be used on all subsequent calls
to C<XMLin()> or C<XMLout()>

=item *

to override methods in B<XML::Simple> to provide customised behaviour

=back

The default values for the options described above are unlikely to suit
everyone.  The OO interface allows you to effectively override B<XML::Simple>'s
defaults with your preferred values.  It works like this:

First create an XML::Simple parser object with your preferred defaults:

  my $xs = XML::Simple->new(ForceArray => 1, KeepRoot => 1);

then call C<XMLin()> or C<XMLout()> as a method of that object:

  my $ref = $xs->XMLin($xml);
  my $xml = $xs->XMLout($ref);

You can also specify options when you make the method calls and these values
will be merged with the values specified when the object was created.  Values
specified in a method call take precedence.

Note: when called as methods, the C<XMLin()> and C<XMLout()> routines may be
called as C<xml_in()> or C<xml_out()>.  The method names are aliased so the
only difference is the aesthetics.

=head2 Parsing Methods

You can explicitly call one of the following methods rather than rely on the
C<xml_in()> method automatically determining whether the target to be parsed is
a string, a file or a filehandle:

=over 4

=item parse_string(text)

Works exactly like the C<xml_in()> method but assumes the first argument is
a string of XML (or a reference to a scalar containing a string of XML).

=item parse_file(filename)

Works exactly like the C<xml_in()> method but assumes the first argument is
the name of a file containing XML.

=item parse_fh(file_handle)

Works exactly like the C<xml_in()> method but assumes the first argument is
a filehandle which can be read to get XML.

=back

=head2 Hook Methods

You can make your own class which inherits from XML::Simple and overrides
certain behaviours.  The following methods may provide useful 'hooks' upon
which to hang your modified behaviour.  You may find other undocumented methods
by examining the source, but those may be subject to change in future releases.

=over 4

=item new_xml_parser()

This method will be called when a new XML::Parser object must be constructed
(either because XML::SAX is not installed or XML::Parser is preferred).

=item handle_options(direction, name => value ...)

This method will be called when one of the parsing methods or the C<XMLout()>
method is called.  The initial argument will be a string (either 'in' or 'out')
and the remaining arguments will be name value pairs.

=item default_config_file()

Calculates and returns the name of the file which should be parsed if no
filename is passed to C<XMLin()> (default: C<$0.xml>).

=item build_simple_tree(filename, string)

Called from C<XMLin()> or any of the parsing methods.  Takes either a file name
as the first argument or C<undef> followed by a 'string' as the second
argument.  Returns a simple tree data structure.  You could override this
method to apply your own transformations before the data structure is returned
to the caller.

=item new_hashref()

When the 'simple tree' data structure is being built, this method will be
called to create any required anonymous hashrefs.

=item sorted_keys(name, hashref)

Called when C<XMLout()> is translating a hashref to XML.  This routine returns
a list of hash keys in the order that the corresponding attributes/elements
should appear in the output.

=item escape_value(string)

Called from C<XMLout()>, takes a string and returns a copy of the string with
XML character escaping rules applied.

=item escape_attr(string)

Called from C<XMLout()>, to handle attribute values.  By default, just calls
C<escape_value()>, but you can override this method if you want attributes
escaped differently than text content.

=item numeric_escape(string)

Called from C<escape_value()>, to handle non-ASCII characters (depending on the
value of the NumericEscape option).

=item copy_hash(hashref, extra_key => value, ...)

Called from C<XMLout()>, when 'unfolding' a hash of hashes into an array of
hashes.  You might wish to override this method if you're using tied hashes and
don't want them to get untied.

=back

=head2 Cache Methods

XML::Simple implements three caching schemes ('storable', 'memshare' and
'memcopy').  You can implement a custom caching scheme by implementing
two methods - one for reading from the cache and one for writing to it.

For example, you might implement a new 'dbm' scheme that stores cached data
structures using the L<MLDBM> module.  First, you would add a
C<cache_read_dbm()> method which accepted a filename for use as a lookup key
and returned a data structure on success, or undef on failure.  Then, you would
implement a C<cache_read_dbm()> method which accepted a data structure and a
filename.

You would use this caching scheme by specifying the option:

  Cache => [ 'dbm' ]

=head1 STRICT MODE

If you import the B<XML::Simple> routines like this:

  use XML::Simple qw(:strict);

the following common mistakes will be detected and treated as fatal errors

=over 4

=item *

Failing to explicitly set the C<KeyAttr> option - if you can't be bothered
reading about this option, turn it off with: KeyAttr => [ ]

=item *

Failing to explicitly set the C<ForceArray> option - if you can't be bothered
reading about this option, set it to the safest mode with: ForceArray => 1

=item *

Setting ForceArray to an array, but failing to list all the elements from the
KeyAttr hash.

=item *

Data error - KeyAttr is set to say { part => 'partnum' } but the XML contains
one or more E<lt>partE<gt> elements without a 'partnum' attribute (or nested
element).  Note: if strict mode is not set but C<use warnings;> is in force,
this condition triggers a warning.

=item *

Data error - as above, but non-unique values are present in the key attribute
(eg: more than one E<lt>partE<gt> element with the same partnum).  This will
also trigger a warning if strict mode is not enabled.

=item *

Data error - as above, but value of key attribute (eg: partnum) is not a
scalar string (due to nested elements etc).  This will also trigger a warning
if strict mode is not enabled.

=back

=head1 SAX SUPPORT

From version 1.08_01, B<XML::Simple> includes support for SAX (the Simple API
for XML) - specifically SAX2.

In a typical SAX application, an XML parser (or SAX 'driver') module generates
SAX events (start of element, character data, end of element, etc) as it parses
an XML document and a 'handler' module processes the events to extract the
required data.  This simple model allows for some interesting and powerful
possibilities:

=over 4

=item *

Applications written to the SAX API can extract data from huge XML documents
without the memory overheads of a DOM or tree API.

=item *

The SAX API allows for plug and play interchange of parser modules without
having to change your code to fit a new module's API.  A number of SAX parsers
are available with capabilities ranging from extreme portability to blazing
performance.

=item *

A SAX 'filter' module can implement both a handler interface for receiving
data and a generator interface for passing modified data on to a downstream
handler.  Filters can be chained together in 'pipelines'.

=item *

One filter module might split a data stream to direct data to two or more
downstream handlers.

=item *

Generating SAX events is not the exclusive preserve of XML parsing modules.
For example, a module might extract data from a relational database using DBI
and pass it on to a SAX pipeline for filtering and formatting.

=back

B<XML::Simple> can operate at either end of a SAX pipeline.  For example,
you can take a data structure in the form of a hashref and pass it into a
SAX pipeline using the 'Handler' option on C<XMLout()>:

  use XML::Simple;
  use Some::SAX::Filter;
  use XML::SAX::Writer;

  my $ref = {
               ....   # your data here
            };

  my $writer = XML::SAX::Writer->new();
  my $filter = Some::SAX::Filter->new(Handler => $writer);
  my $simple = XML::Simple->new(Handler => $filter);
  $simple->XMLout($ref);

You can also put B<XML::Simple> at the opposite end of the pipeline to take
advantage of the simple 'tree' data structure once the relevant data has been
isolated through filtering:

  use XML::SAX;
  use Some::SAX::Filter;
  use XML::Simple;

  my $simple = XML::Simple->new(ForceArray => 1, KeyAttr => ['partnum']);
  my $filter = Some::SAX::Filter->new(Handler => $simple);
  my $parser = XML::SAX::ParserFactory->parser(Handler => $filter);

  my $ref = $parser->parse_uri('some_huge_file.xml');

  print $ref->{part}->{'555-1234'};

You can build a filter by using an XML::Simple object as a handler and setting
its DataHandler option to point to a routine which takes the resulting tree,
modifies it and sends it off as SAX events to a downstream handler:

  my $writer = XML::SAX::Writer->new();
  my $filter = XML::Simple->new(
                 DataHandler => sub {
                                  my $simple = shift;
                                  my $data = shift;

                                  # Modify $data here

                                  $simple->XMLout($data, Handler => $writer);
                                }
               );
  my $parser = XML::SAX::ParserFactory->parser(Handler => $filter);

  $parser->parse_uri($filename);

I<Note: In this last example, the 'Handler' option was specified in the call to
C<XMLout()> but it could also have been specified in the constructor>.

=head1 ENVIRONMENT

If you don't care which parser module B<XML::Simple> uses then skip this
section entirely (it looks more complicated than it really is).

B<XML::Simple> will default to using a B<SAX> parser if one is available or
B<XML::Parser> if SAX is not available.

You can dictate which parser module is used by setting either the environment
variable 'XML_SIMPLE_PREFERRED_PARSER' or the package variable
$XML::Simple::PREFERRED_PARSER to contain the module name.  The following rules
are used:

=over 4

=item *

The package variable takes precedence over the environment variable if both are defined.  To force B<XML::Simple> to ignore the environment settings and use
its default rules, you can set the package variable to an empty string.

=item *

If the 'preferred parser' is set to the string 'XML::Parser', then
L<XML::Parser> will be used (or C<XMLin()> will die if L<XML::Parser> is not
installed).

=item *

If the 'preferred parser' is set to some other value, then it is assumed to be
the name of a SAX parser module and is passed to L<XML::SAX::ParserFactory>.
If L<XML::SAX> is not installed, or the requested parser module is not
installed, then C<XMLin()> will die.

=item *

If the 'preferred parser' is not defined at all (the normal default
state), an attempt will be made to load L<XML::SAX>.  If L<XML::SAX> is
installed, then a parser module will be selected according to
L<XML::SAX::ParserFactory>'s normal rules (which typically means the last SAX
parser installed).

=item *

if the 'preferred parser' is not defined and B<XML::SAX> is not
installed, then B<XML::Parser> will be used.  C<XMLin()> will die if
L<XML::Parser> is not installed.

=back

Note: The B<XML::SAX> distribution includes an XML parser written entirely in
Perl.  It is very portable but it is not very fast.  You should consider
installing L<XML::LibXML> or L<XML::SAX::Expat> if they are available for your
platform.

=head1 ERROR HANDLING

The XML standard is very clear on the issue of non-compliant documents.  An
error in parsing any single element (for example a missing end tag) must cause
the whole document to be rejected.  B<XML::Simple> will die with an appropriate
message if it encounters a parsing error.

If dying is not appropriate for your application, you should arrange to call
C<XMLin()> in an eval block and look for errors in $@.  eg:

    my $config = eval { XMLin() };
    PopUpMessage($@) if($@);

Note, there is a common misconception that use of B<eval> will significantly
slow down a script.  While that may be true when the code being eval'd is in a
string, it is not true of code like the sample above.

=head1 EXAMPLES

When C<XMLin()> reads the following very simple piece of XML:

    <opt username="testuser" password="frodo"></opt>

it returns the following data structure:

    {
      'username' => 'testuser',
      'password' => 'frodo'
    }

The identical result could have been produced with this alternative XML:

    <opt username="testuser" password="frodo" />

Or this (although see 'ForceArray' option for variations):

    <opt>
      <username>testuser</username>
      <password>frodo</password>
    </opt>

Repeated nested elements are represented as anonymous arrays:

    <opt>
      <person firstname="Joe" lastname="Smith">
        <email>joe@smith.com</email>
        <email>jsmith@yahoo.com</email>
      </person>
      <person firstname="Bob" lastname="Smith">
        <email>bob@smith.com</email>
      </person>
    </opt>

    {
      'person' => [
                    {
                      'email' => [
                                   'joe@smith.com',
                                   'jsmith@yahoo.com'
                                 ],
                      'firstname' => 'Joe',
                      'lastname' => 'Smith'
                    },
                    {
                      'email' => 'bob@smith.com',
                      'firstname' => 'Bob',
                      'lastname' => 'Smith'
                    }
                  ]
    }

Nested elements with a recognised key attribute are transformed (folded) from
an array into a hash keyed on the value of that attribute (see the C<KeyAttr>
option):

    <opt>
      <person key="jsmith" firstname="Joe" lastname="Smith" />
      <person key="tsmith" firstname="Tom" lastname="Smith" />
      <person key="jbloggs" firstname="Joe" lastname="Bloggs" />
    </opt>

    {
      'person' => {
                    'jbloggs' => {
                                   'firstname' => 'Joe',
                                   'lastname' => 'Bloggs'
                                 },
                    'tsmith' => {
                                  'firstname' => 'Tom',
                                  'lastname' => 'Smith'
                                },
                    'jsmith' => {
                                  'firstname' => 'Joe',
                                  'lastname' => 'Smith'
                                }
                  }
    }


The <anon> tag can be used to form anonymous arrays:

    <opt>
      <head><anon>Col 1</anon><anon>Col 2</anon><anon>Col 3</anon></head>
      <data><anon>R1C1</anon><anon>R1C2</anon><anon>R1C3</anon></data>
      <data><anon>R2C1</anon><anon>R2C2</anon><anon>R2C3</anon></data>
      <data><anon>R3C1</anon><anon>R3C2</anon><anon>R3C3</anon></data>
    </opt>

    {
      'head' => [
                  [ 'Col 1', 'Col 2', 'Col 3' ]
                ],
      'data' => [
                  [ 'R1C1', 'R1C2', 'R1C3' ],
                  [ 'R2C1', 'R2C2', 'R2C3' ],
                  [ 'R3C1', 'R3C2', 'R3C3' ]
                ]
    }

Anonymous arrays can be nested to arbitrary levels and as a special case, if
the surrounding tags for an XML document contain only an anonymous array the
arrayref will be returned directly rather than the usual hashref:

    <opt>
      <anon><anon>Col 1</anon><anon>Col 2</anon></anon>
      <anon><anon>R1C1</anon><anon>R1C2</anon></anon>
      <anon><anon>R2C1</anon><anon>R2C2</anon></anon>
    </opt>

    [
      [ 'Col 1', 'Col 2' ],
      [ 'R1C1', 'R1C2' ],
      [ 'R2C1', 'R2C2' ]
    ]

Elements which only contain text content will simply be represented as a
scalar.  Where an element has both attributes and text content, the element
will be represented as a hashref with the text content in the 'content' key
(see the C<ContentKey> option):

  <opt>
    <one>first</one>
    <two attr="value">second</two>
  </opt>

  {
    'one' => 'first',
    'two' => { 'attr' => 'value', 'content' => 'second' }
  }

Mixed content (elements which contain both text content and nested elements)
will be not be represented in a useful way - element order and significant
whitespace will be lost.  If you need to work with mixed content, then
XML::Simple is not the right tool for your job - check out the next section.

=head1 WHERE TO FROM HERE?

B<XML::Simple> is able to present a simple API because it makes some
assumptions on your behalf.  These include:

=over 4

=item *

You're not interested in text content consisting only of whitespace

=item *

You don't mind that when things get slurped into a hash the order is lost

=item *

You don't want fine-grained control of the formatting of generated XML

=item *

You would never use a hash key that was not a legal XML element name

=item *

You don't need help converting between different encodings

=back

In a serious XML project, you'll probably outgrow these assumptions fairly
quickly.  This section of the document used to offer some advice on choosing a
more powerful option.  That advice has now grown into the 'Perl-XML FAQ'
document which you can find at: L<http://perl-xml.sourceforge.net/faq/>

The advice in the FAQ boils down to a quick explanation of tree versus
event based parsers and then recommends:

For event based parsing, use SAX (do not set out to write any new code for
XML::Parser's handler API - it is obsolete).

For tree-based parsing, you could choose between the 'Perlish' approach of
L<XML::Twig> and more standards based DOM implementations - preferably one with
XPath support such as L<XML::LibXML>.


=head1 SEE ALSO

B<XML::Simple> requires either L<XML::Parser> or L<XML::SAX>.

To generate documents with namespaces, L<XML::NamespaceSupport> is required.

The optional caching functions require L<Storable>.

Answers to Frequently Asked Questions about XML::Simple are bundled with this
distribution as: L<XML::Simple::FAQ>

=head1 COPYRIGHT

Copyright 1999-2004 Grant McLean E<lt>grantm@cpan.orgE<gt>

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut


