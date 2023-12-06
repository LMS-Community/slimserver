##################################################
package Log::Log4perl::MDC;
##################################################

use 5.006;
use strict;
use warnings;

our %MDC_HASH = ();

###########################################
sub get {
###########################################
    my($class, $key) = @_;

    if($class ne __PACKAGE__) {
        # Somebody called us with Log::Log4perl::MDC::get($key)
        $key = $class;
    }

    if(exists $MDC_HASH{$key}) {
        return $MDC_HASH{$key};
    } else {
        return undef;
    }
}

###########################################
sub put {
###########################################
    my($class, $key, $value) = @_;

    if($class ne __PACKAGE__) {
        # Somebody called us with Log::Log4perl::MDC::put($key, $value)
        $value = $key;
        $key   = $class;
    }

    $MDC_HASH{$key} = $value;
}

###########################################
sub remove {
###########################################
    %MDC_HASH = ();

    1;
}

###########################################
sub get_context {
###########################################
    return \%MDC_HASH;
}

1;

__END__

=head1 NAME

Log::Log4perl::MDC - Mapped Diagnostic Context

=head1 DESCRIPTION

Log::Log4perl allows loggers to maintain global thread-specific data, 
called the Nested Diagnostic Context (NDC) and 
Mapped Diagnostic Context (MDC).

The MDC is a simple thread-specific hash table, in which the application
can stuff values under certain keys and retrieve them later
via the C<"%X{key}"> placeholder in 
C<Log::Log4perl::Layout::PatternLayout>s.

=over 4

=item Log::Log4perl::MDC->put($key, $value);

Store a value C<$value> under key C<$key> in the map.

=item my $value = Log::Log4perl::MDC->get($key);

Retrieve the content of the map under the specified key.
Typically done by C<%X{key}> in
C<Log::Log4perl::Layout::PatternLayout>.
If no value exists to the given key, C<undef> is returned.

=item my $text = Log::Log4perl::MDC->remove();

Delete all entries from the map.

=item Log::Log4perl::MDC->get_context();

Returns a reference to the hash table.

=back

Please note that all of the methods above are class methods, there's no
instances of this class. Since the thread model in perl 5.8.0 is
"no shared data unless explicetly requested" the data structures
used are just global (and therefore thread-specific).

=head1 AUTHOR

Mike Schilli, E<lt>log4perl@perlmeister.comE<gt>

=cut
