package Log::Log4perl::Config::DOMConfigurator;
use Log::Log4perl::Config::BaseConfigurator;

our @ISA = qw(Log::Log4perl::Config::BaseConfigurator);

#todo
# DONE(param-text) some params not attrs but values, like <sql>...</sql>
# DONE see DEBUG!!!  below
# NO, (really is only used for AsyncAppender) appender-ref in <appender>
# DONE check multiple appenders in a category
# DONE in Config.pm re URL loading, steal from XML::DOM
# DONE, OK see PropConfigurator re importing unlog4j, eval_if_perl
# NO (is specified in DTD) - need to handle 0/1, true/false?
# DONE see Config, need to check version of XML::DOM
# OK user defined levels? see parse_level
# OK make sure 2nd test is using log4perl constructs, not log4j
# OK handle new filter stuff
# make sure sample code actually works
# try removing namespace prefixes in the xml

use XML::DOM;
use Log::Log4perl::Level;
use strict;

use constant _INTERNAL_DEBUG => 0;

our $VERSION = 0.03;

our $APPENDER_TAG = qr/^((log4j|log4perl):)?appender$/;

our $FILTER_TAG = qr/^(log4perl:)?filter$/;
our $FILTER_REF_TAG = qr/^(log4perl:)?filter-ref$/;

#can't use ValParser here because we're using namespaces? 
#doesn't seem to work - kg 3/2003 
our $PARSER_CLASS = 'XML::DOM::Parser';

our $LOG4J_PREFIX = 'log4j';
our $LOG4PERL_PREFIX = 'log4perl';
    

#poor man's export
*eval_if_perl = \&Log::Log4perl::Config::eval_if_perl;
*unlog4j      = \&Log::Log4perl::Config::unlog4j;


###################################################
sub parse {
###################################################
    my($self, $newtext) = @_;

    $self->text($newtext) if defined $newtext;
    my $text = $self->{text};

    my $parser = $PARSER_CLASS->new;
    my $doc = $parser->parse (join('',@$text));


    my $l4p_tree = {};
    
    my $config = $doc->getElementsByTagName("$LOG4J_PREFIX:configuration")->item(0)||
                 $doc->getElementsByTagName("$LOG4PERL_PREFIX:configuration")->item(0);

    my $threshold = uc(subst($config->getAttribute('threshold')));
    if ($threshold) {
        $l4p_tree->{threshold}{value} = $threshold;
    }

    if (subst($config->getAttribute('oneMessagePerAppender')) eq 'true') {
        $l4p_tree->{oneMessagePerAppender}{value} = 1;
    }

    for my $kid ($config->getChildNodes){

        next unless $kid->getNodeType == ELEMENT_NODE;

        my $tag_name = $kid->getTagName;

        if ($tag_name =~ $APPENDER_TAG) {
            &parse_appender($l4p_tree, $kid);

        }elsif ($tag_name eq 'category' || $tag_name eq 'logger'){
            &parse_category($l4p_tree, $kid);
            #Treating them the same is not entirely accurate, 
            #the dtd says 'logger' doesn't accept
            #a 'class' attribute while 'category' does.
            #But that's ok, log4perl doesn't do anything with that attribute

        }elsif ($tag_name eq 'root'){
            &parse_root($l4p_tree, $kid);

        }elsif ($tag_name =~ $FILTER_TAG){
            #parse log4perl's chainable boolean filters
            &parse_l4p_filter($l4p_tree, $kid);

        }elsif ($tag_name eq 'renderer'){
            warn "Log4perl: ignoring renderer tag in config, unimplemented";
            #"log4j will render the content of the log message according to 
            # user specified criteria. For example, if you frequently need 
            # to log Oranges, an object type used in your current project, 
            # then you can register an OrangeRenderer that will be invoked 
            # whenever an orange needs to be logged. "
         
        }elsif ($tag_name eq 'PatternLayout'){#log4perl only
            &parse_patternlayout($l4p_tree, $kid);
        }
    }
    $doc->dispose;

    return $l4p_tree;
}

#this is just for toplevel log4perl.PatternLayout tags
#holding the custom cspecs
sub parse_patternlayout {
    my ($l4p_tree, $node) = @_;

    my $l4p_branch = {};

    for my $child ($node->getChildNodes) {
        next unless $child->getNodeType == ELEMENT_NODE;

        my $name = subst($child->getAttribute('name'));
        my $value;

        foreach my $grandkid ($child->getChildNodes){
            if ($grandkid->getNodeType == TEXT_NODE) {
                $value .= $grandkid->getData;
            }
        }
        $value =~ s/^ +//;  #just to make the unit tests pass
        $value =~ s/ +$//;
        $l4p_branch->{$name}{value} = subst($value);
    }
    $l4p_tree->{PatternLayout}{cspec} = $l4p_branch;
}


#for parsing the root logger, if any
sub parse_root {
    my ($l4p_tree, $node) = @_;

    my $l4p_branch = {};

    &parse_children_of_logger_element($l4p_branch, $node);

    $l4p_tree->{category}{value} = $l4p_branch->{value};

}


#this parses a custom log4perl-specific filter set up under
#the root element, as opposed to children of the appenders
sub parse_l4p_filter {
    my ($l4p_tree, $node) = @_;

    my $l4p_branch = {};

    my $name = subst($node->getAttribute('name'));

    my $class = subst($node->getAttribute('class'));
    my $value = subst($node->getAttribute('value'));

    if ($class && $value) {
        die "Log4perl: only one of class or value allowed, not both, "
            ."in XMLConfig filter '$name'";
    }elsif ($class || $value){
        $l4p_branch->{value} = ($value || $class);

    }

    for my $child ($node->getChildNodes) {

        if ($child->getNodeType == ELEMENT_NODE){

            my $tag_name = $child->getTagName();

            if ($tag_name =~ /^(param|param-nested|param-text)$/) {
                &parse_any_param($l4p_branch, $child);
            }
        }elsif ($child->getNodeType == TEXT_NODE){
            my $text = $child->getData;
            next unless $text =~ /\S/;
            if ($class && $value) {
                die "Log4perl: only one of class, value or PCDATA allowed, "
                    ."in XMLConfig filter '$name'";
            }
            $l4p_branch->{value} .= subst($text); 
        }
    }

    $l4p_tree->{filter}{$name} = $l4p_branch;
}

   
#for parsing a category/logger element
sub parse_category {
    my ($l4p_tree, $node) = @_;

    my $name = subst($node->getAttribute('name'));

    $l4p_tree->{category} ||= {};
 
    my $ptr = $l4p_tree->{category};

    for my $part (split /\.|::/, $name) {
        $ptr->{$part} = {} unless exists $ptr->{$part};
        $ptr = $ptr->{$part};
    }

    my $l4p_branch = $ptr;

    my $class = subst($node->getAttribute('class'));
    $class                       && 
       $class ne 'Log::Log4perl' &&
       $class ne 'org.apache.log4j.Logger' &&
       warn "setting category $name to class $class ignored, only Log::Log4perl implemented";

    #this is kind of funky, additivity has its own spot in the tree
    my $additivity = subst(subst($node->getAttribute('additivity')));
    if (length $additivity > 0) {
        $l4p_tree->{additivity} ||= {};
        my $add_ptr = $l4p_tree->{additivity};

        for my $part (split /\.|::/, $name) {
            $add_ptr->{$part} = {} unless exists $add_ptr->{$part};
            $add_ptr = $add_ptr->{$part};
        }
        $add_ptr->{value} = &parse_boolean($additivity);
    }

    &parse_children_of_logger_element($l4p_branch, $node);
}

# parses the children of a category element
sub parse_children_of_logger_element {
    my ($l4p_branch, $node) = @_;

    my (@appenders, $priority);

    for my $child ($node->getChildNodes) {
        next unless $child->getNodeType == ELEMENT_NODE;
            
        my $tag_name = $child->getTagName();

        if ($tag_name eq 'param') {
            my $name = subst($child->getAttribute('name'));
            my $value = subst($child->getAttribute('value'));
            if ($value =~ /^(all|debug|info|warn|error|fatal|off|null)^/) {
                $value = uc $value;
            }
            $l4p_branch->{$name} = {value => $value};
        
        }elsif ($tag_name eq 'appender-ref'){
            push @appenders, subst($child->getAttribute('ref'));
            
        }elsif ($tag_name eq 'level' || $tag_name eq 'priority'){
            $priority = &parse_level($child);
        }
    }
    $l4p_branch->{value} = $priority.', '.join(',', @appenders);
    
    return;
}


sub parse_level {
    my $node = shift;

    my $level = uc (subst($node->getAttribute('value')));

    die "Log4perl: invalid level in config: $level"
        unless Log::Log4perl::Level::is_valid($level);

    return $level;
}



sub parse_appender {
    my ($l4p_tree, $node) = @_;

    my $name = subst($node->getAttribute("name"));

    my $l4p_branch = {};

    my $class = subst($node->getAttribute("class"));

    $l4p_branch->{value} = $class;

    print "looking at $name----------------------\n"  if _INTERNAL_DEBUG;

    for my $child ($node->getChildNodes) {
        next unless $child->getNodeType == ELEMENT_NODE;

        my $tag_name = $child->getTagName();

        my $name = unlog4j(subst($child->getAttribute('name')));

        if ($tag_name =~ /^(param|param-nested|param-text)$/) {

            &parse_any_param($l4p_branch, $child);

            my $value;

        }elsif ($tag_name =~ /($LOG4PERL_PREFIX:)?layout/){
            $l4p_branch->{layout} = parse_layout($child);

        }elsif ($tag_name =~  $FILTER_TAG){
            $l4p_branch->{Filter} = parse_filter($child);

        }elsif ($tag_name =~ $FILTER_REF_TAG){
            $l4p_branch->{Filter} = parse_filter_ref($child);

        }elsif ($tag_name eq 'errorHandler'){
            die "errorHandlers not supported yet";

        }elsif ($tag_name eq 'appender-ref'){
            #dtd: Appenders may also reference (or include) other appenders. 
            #This feature in log4j is only for appenders who implement the 
            #AppenderAttachable interface, and the only one that does that
            #is the AsyncAppender, which writes logs in a separate thread.
            #I don't see the need to support this on the perl side any 
            #time soon.  --kg 3/2003
            die "Log4perl: in config file, <appender-ref> tag is unsupported in <appender>";
        }else{
            die "Log4perl: in config file, <$tag_name> is unsupported\n";
        }
    }
    $l4p_tree->{appender}{$name} = $l4p_branch;
}

sub parse_any_param {
    my ($l4p_branch, $child) = @_;

    my $tag_name = $child->getTagName();
    my $name = subst($child->getAttribute('name'));
    my $value;

    print "parse_any_param: <$tag_name name=$name\n" if _INTERNAL_DEBUG;

    #<param-nested>
    #note we don't set it to { value => $value }
    #and we don't test for multiple values
    if ($tag_name eq 'param-nested'){
        
        if ($l4p_branch->{$name}){
            die "Log4perl: in config file, multiple param-nested tags for $name not supported";
        }
        $l4p_branch->{$name} = &parse_param_nested($child); 

        return;

    #<param>
    }elsif ($tag_name eq 'param') {

         $value = subst($child->getAttribute('value'));

         print "parse_param_nested: got param $name = $value\n"  
             if _INTERNAL_DEBUG;
        
         if ($value =~ /^(all|debug|info|warn|error|fatal|off|null)$/) {
             $value = uc $value;
         }

         if ($name !~ /warp_message|filter/ &&
            $child->getParentNode->getAttribute('name') ne 'cspec') {
            $value = eval_if_perl($value);
         }
    #<param-text>
    }elsif ($tag_name eq 'param-text'){

        foreach my $grandkid ($child->getChildNodes){
            if ($grandkid->getNodeType == TEXT_NODE) {
                $value .= $grandkid->getData;
            }
        }
        if ($name !~ /warp_message|filter/ &&
            $child->getParentNode->getAttribute('name') ne 'cspec') {
            $value = eval_if_perl($value);
        }
    }

    $value = subst($value);

     #multiple values for the same param name
     if (defined $l4p_branch->{$name}{value} ) {
         if (ref $l4p_branch->{$name}{value} ne 'ARRAY'){
             my $temp = $l4p_branch->{$name}{value};
             $l4p_branch->{$name}{value} = [$temp];
         }
         push @{$l4p_branch->{$name}{value}}, $value;
     }else{
         $l4p_branch->{$name} = {value => $value};
     }
}

#handles an appender's <param-nested> elements
sub parse_param_nested {
    my ($node) = shift;

    my $l4p_branch = {};

    for my $child ($node->getChildNodes) {
        next unless $child->getNodeType == ELEMENT_NODE;

        my $tag_name = $child->getTagName();

        if ($tag_name =~ /^param|param-nested|param-text$/) {
            &parse_any_param($l4p_branch, $child);
        }
    }

    return $l4p_branch;
}

#this handles filters that are children of appenders, as opposed
#to the custom filters that go under the root element
sub parse_filter {
    my $node = shift;

    my $filter_tree = {};

    my $class_name = subst($node->getAttribute('class'));

    $filter_tree->{value} = $class_name;

    print "\tparsing filter on class $class_name\n"  if _INTERNAL_DEBUG;  

    for my $child ($node->getChildNodes) {
        next unless $child->getNodeType == ELEMENT_NODE;

        my $tag_name = $child->getTagName();

        if ($tag_name =~ 'param|param-nested|param-text') {
            &parse_any_param($filter_tree, $child);
        
        }else{
            die "Log4perl: don't know what to do with a ".$child->getTagName()
                ."inside a filter element";
        }
    }
    return $filter_tree;
}

sub parse_filter_ref {
    my $node = shift;

    my $filter_tree = {};

    my $filter_id = subst($node->getAttribute('id'));

    $filter_tree->{value} = $filter_id;

    return $filter_tree;
}



sub parse_layout {
    my $node = shift;

    my $layout_tree = {};

    my $class_name = subst($node->getAttribute('class'));
    
    $layout_tree->{value} = $class_name;
    #
    print "\tparsing layout $class_name\n"  if _INTERNAL_DEBUG;  
    for my $child ($node->getChildNodes) {
        next unless $child->getNodeType == ELEMENT_NODE;
        if ($child->getTagName() eq 'param') {
            my $name = subst($child->getAttribute('name'));
            my $value = subst($child->getAttribute('value'));
            if ($value =~ /^(all|debug|info|warn|error|fatal|off|null)$/) {
                $value = uc $value;
            }
            print "\tparse_layout: got param $name = $value\n"
                if _INTERNAL_DEBUG;
            $layout_tree->{$name}{value} = $value;  

        }elsif ($child->getTagName() eq 'cspec') {
            my $name = subst($child->getAttribute('name'));
            my $value;
            foreach my $grandkid ($child->getChildNodes){
                if ($grandkid->getNodeType == TEXT_NODE) {
                    $value .= $grandkid->getData;
                }
            }
            $value =~ s/^ +//;
            $value =~ s/ +$//;
            $layout_tree->{cspec}{$name}{value} = subst($value);  
        }
    }
    return $layout_tree;
}

sub parse_boolean {
    my $a = shift;

    if ($a eq '0' || lc $a eq 'false') {
        return '0';
    }elsif ($a eq '1' || lc $a eq 'true'){
        return '1';
    }else{
        return $a; #probably an error, punt
    }
}


#this handles variable substitution
sub subst {
    my $val = shift;

    $val =~ s/\$\{(.*?)}/
                      Log::Log4perl::Config::var_subst($1, {})/gex;
    return $val;
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Config::DOMConfigurator - reads xml config files

=head1 SYNOPSIS

    --------------------------
    --using the log4j DTD--
    --------------------------

    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE log4j:configuration SYSTEM "log4j.dtd">

    <log4j:configuration xmlns:log4j="http://jakarta.apache.org/log4j/">

    <appender name="FileAppndr1" class="org.apache.log4j.FileAppender">
        <layout class="Log::Log4perl::Layout::PatternLayout">
                <param name="ConversionPattern"
                       value="%d %4r [%t] %-5p %c %t - %m%n"/>
        </layout>
        <param name="File" value="t/tmp/DOMtest"/>
        <param name="Append" value="false"/>
    </appender>

    <category name="a.b.c.d" additivity="false">
        <level value="warn"/>  <!-- note lowercase! -->
        <appender-ref ref="FileAppndr1"/>
    </category>

   <root>
        <priority value="warn"/>
        <appender-ref ref="FileAppndr1"/>
   </root>

   </log4j:configuration>
   
   
   
   --------------------------
   --using the log4perl DTD--
   --------------------------
   
   <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE log4perl:configuration SYSTEM "log4perl.dtd">

    <log4perl:configuration xmlns:log4perl="http://log4perl.sourceforge.net/"
        threshold="debug" oneMessagePerAppender="true">

    <log4perl:appender name="jabbender" class="Log::Dispatch::Jabber">

            <param-nested name="login">
                   <param name="hostname" value="a.jabber.server"/>
                   <param name="password" value="12345"/>
                   <param name="port"     value="5222"/>
                   <param name="resource" value="logger"/>
                   <param name="username" value="bobjones"/>
            </param-nested>

            <param name="to" value="bob@a.jabber.server"/>

            <param-text name="to">
                  mary@another.jabber.server
            </param-text>

            <log4perl:layout class="org.apache.log4j.PatternLayout">
                <param name="ConversionPattern" value = "%K xx %G %U"/>
                <cspec name="K">
                    sub { return sprintf "%1x", $$}
                </cspec>
                <cspec name="G">
                    sub {return 'thisistheGcspec'}
                </cspec>
            </log4perl:layout>
    </log4perl:appender>

    <log4perl:appender name="DBAppndr2" class="Log::Log4perl::Appender::DBI">
              <param name="warp_message" value="0"/>
              <param name="datasource" value="DBI:CSV:f_dir=t/tmp"/>
              <param name="bufferSize" value="2"/>
              <param name="password" value="sub { $ENV{PWD} }"/>
              <param name="username" value="bobjones"/>

              <param-text name="sql">
                  INSERT INTO log4perltest
                            (loglevel, message, shortcaller, thingid,
                            category, pkg, runtime1, runtime2)
                  VALUES
                             (?,?,?,?,?,?,?,?)
              </param-text>

               <param-nested name="params">
                    <param name="1" value="%p"/>
                    <param name="3" value="%5.5l"/>
                    <param name="5" value="%c"/>
                    <param name="6" value="%C"/>
               </param-nested>

               <layout class="Log::Log4perl::Layout::NoopLayout"/>
    </log4perl:appender>

    <category name="animal.dog">
               <priority value="info"/>
               <appender-ref ref="jabbender"/>
               <appender-ref ref="DBAppndr2"/>
    </category>

    <category name="plant">
            <priority value="debug"/>
            <appender-ref ref="DBAppndr2"/>
    </category>

    <PatternLayout>
        <cspec name="U"><![CDATA[
            sub {
                return "UID $< GID $(";
            }
        ]]></cspec>
    </PatternLayout>

    </log4perl:configuration>
    



=head1 DESCRIPTION

This module implements an XML config, complementing the properties-style
config described elsewhere.

=head1 WHY

"Why would I want my config in XML?" you ask.  Well, there are a couple
reasons you might want to.  Maybe you have a personal preference
for XML.  Maybe you manage your config with other tools that have an
affinity for XML, like XML-aware editors or automated config
generators.  Or maybe (and this is the big one) you don't like
having to run your application just to check the syntax of your
config file.

By using an XML config and referencing a DTD, you can use a namespace-aware
validating parser to see if your XML config at least follows the rules set 
in the DTD. 

=head1 HOW

To reference a DTD, drop this in after the <?xml...> declaration
in your config file:

    <!DOCTYPE log4perl:configuration SYSTEM "log4perl.dtd">

That tells the parser to validate your config against the DTD in
"log4perl.dtd", which is available in the xml/ directory of
the log4perl distribution.  Note that you'll also need to grab
the log4j-1.2.dtd from there as well, since the it's included
by log4perl.dtd.

Namespace-aware validating parsers are not the norm in Perl.  
But the Xerces project 
(http://xml.apache.org/xerces-c/index.html --lots of binaries available, 
even rpm's)  does provide just such a parser
that you can use like this:

    StdInParse -ns -v < my-log4perl-config.xml

This module itself does not use a validating parser, the obvious
one XML::DOM::ValParser doesn't seem to handle namespaces.

=head1 WHY TWO DTDs

The log4j DTD is from the log4j project, they designed it to 
handle their needs.  log4perl has added some extensions to the 
original log4j functionality which needed some extensions to the
log4j DTD.  If you aren't using these features then you can validate
your config against the log4j dtd and know that you're using
unadulterated log4j config tags.   

The features added by the log4perl dtd are:

=over 4

=item 1 oneMessagePerAppender global setting

    log4perl.oneMessagePerAppender=1

=item 2 globally defined user conversion specifiers

    log4perl.PatternLayout.cspec.G=sub { return "UID $< GID $("; }

=item 3 appender-local custom conversion specifiers

     log4j.appender.appndr1.layout.cspec.K = sub {return sprintf "%1x", $$ }

=item 4 nested options

     log4j.appender.jabbender          = Log::Dispatch::Jabber
     #(note how these are nested under 'login')
     log4j.appender.jabbender.login.hostname = a.jabber.server
     log4j.appender.jabbender.login.port     = 5222
     log4j.appender.jabbender.login.username = bobjones

=item 5 the log4perl-specific filters, see L<Log::Log4perl::Filter>,
lots of examples in t/044XML-Filter.t, here's a short one:


  <?xml version="1.0" encoding="UTF-8"?> 
  <!DOCTYPE log4perl:configuration SYSTEM "log4perl.dtd">

  <log4perl:configuration xmlns:log4perl="http://log4perl.sourceforge.net/">
   
  <appender name="A1" class="Log::Log4perl::Appender::TestBuffer">
        <layout class="Log::Log4perl::Layout::SimpleLayout"/>
        <filter class="Log::Log4perl::Filter::Boolean">
            <param name="logic" value="!Match3 &amp;&amp; (Match1 || Match2)"/> 
        </filter>
  </appender>   
  
  <appender name="A2" class="Log::Log4perl::Appender::TestBuffer">
        <layout class="Log::Log4perl::Layout::SimpleLayout"/>
        <filter-ref id="Match1"/>
  </appender>   
  
  <log4perl:filter name="Match1" value="sub { /let this through/ }" />
  
  <log4perl:filter name="Match2">
        sub { 
            /and that, too/ 
        }
   </log4perl:filter>
  
  <log4perl:filter name="Match3" class="Log::Log4perl::Filter::StringMatch">
    <param name="StringToMatch" value="suppress"/>
    <param name="AcceptOnMatch" value="true"/>
  </log4perl:filter>
  
  <log4perl:filter name="MyBoolean" class="Log::Log4perl::Filter::Boolean">
    <param name="logic" value="!Match3 &amp;&amp; (Match1 || Match2)"/>
  </log4perl:filter>
  
   
   <root>
           <priority value="info"/>
           <appender-ref ref="A1"/>
   </root>
   
   </log4perl:configuration>


=back


So we needed to extend the log4j dtd to cover these additions.
Now I could have just taken a 'steal this code' approach and mixed
parts of the log4j dtd into a log4perl dtd, but that would be
cut-n-paste programming.  So I've used namespaces and

=over 4

=item * 

replaced three elements:

=over 4

=item <log4perl:configuration>

handles #1) and accepts <PatternLayout>

=item <log4perl:appender> 

accepts <param-nested> and <param-text>

=item <log4perl:layout> 

accepts custom cspecs for #3)

=back

=item * 

added a <param-nested> element (complementing the <param> element)
    to handle #4)

=item * 

added a root <PatternLayout> element to handle #2)

=item * 

added <param-text> which lets you put things like perl code
    into escaped CDATA between the tags, so you don't have to worry
    about escaping characters and quotes

=item * 

added <cspec>

=back

See the examples up in the L<"SYNOPSIS"> for how all that gets used.

=head1 WHY NAMESPACES

I liked the idea of using the log4j DTD I<in situ>, so I used namespaces
to extend it.  If you really don't like having to type <log4perl:appender>
instead of just <appender>, you can make your own DTD combining
the two DTDs and getting rid of the namespace prefixes.  Then you can
validate against that, and log4perl should accept it just fine.

=head1 VARIABLE SUBSTITUTION

This supports variable substitution like C<${foobar}> in text and in 
attribute values except for appender-ref.  If an environment variable is defined
for that name, its value is substituted. So you can do stuff like

        <param name="${hostname}" value="${hostnameval}.foo.com"/>
        <param-text name="to">${currentsysadmin}@foo.com</param-text>


=head1 REQUIRES

To use this module you need XML::DOM installed.  

To use the log4perl.dtd, you'll have to reference it in your XML config,
and you'll also need to note that log4perl.dtd references the 
log4j dtd as "log4j-1.2.dtd", so your validator needs to be able
to find that file as well.  If you don't like having to schlep two
files around, feel free
to dump the contents of "log4j-1.2.dtd" into your "log4perl.dtd" file.

=head1 CAVEATS

You can't mix a multiple param-nesteds with the same name, I'm going to
leave that for now, there's presently no need for a list of structs
in the config.

=head1 CHANGES

0.03 2/26/2003 Added support for log4perl extensions to the log4j dtd

=head1 SEE ALSO

t/038XML-DOM1.t, t/039XML-DOM2.t for examples

xml/log4perl.dtd, xml/log4j-1.2.dtd

Log::Log4perl::Config

Log::Log4perl::Config::PropertyConfigurator

Log::Log4perl::Config::LDAPConfigurator (coming soon!)

The code is brazenly modeled on log4j's DOMConfigurator class, (by 
Christopher Taylor, Ceki Gülcü, and Anders Kristensen) and any
perceived similarity is not coincidental.

=head1 LICENSE

Copyright 2002-2013 by Mike Schilli E<lt>m@perlmeister.comE<gt> 
and Kevin Goess E<lt>cpan@goess.orgE<gt>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=head1 AUTHOR

Please contribute patches to the project on Github:

    http://github.com/mschilli/log4perl

Send bug reports or requests for enhancements to the authors via our

MAILING LIST (questions, bug reports, suggestions/patches): 
log4perl-devel@lists.sourceforge.net

Authors (please contact them via the list above, not directly):
Mike Schilli <m@perlmeister.com>,
Kevin Goess <cpan@goess.org>

Contributors (in alphabetical order):
Ateeq Altaf, Cory Bennett, Jens Berthold, Jeremy Bopp, Hutton
Davidson, Chris R. Donnelly, Matisse Enzer, Hugh Esco, Anthony
Foiani, James FitzGibbon, Carl Franks, Dennis Gregorovic, Andy
Grundman, Paul Harrington, Alexander Hartmaier  David Hull, 
Robert Jacobson, Jason Kohles, Jeff Macdonald, Markus Peter, 
Brett Rann, Peter Rabbitson, Erik Selberg, Aaron Straup Cope, 
Lars Thegler, David Viner, Mac Yang.

