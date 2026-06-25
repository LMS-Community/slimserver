######################################################################
# Limit.pm -- 2003, Mike Schilli <m@perlmeister.com>
######################################################################
# Special composite appender limiting the number of messages relayed
# to its appender(s).
######################################################################

###########################################
package Log::Log4perl::Appender::Limit;
###########################################

use strict;
use warnings;
use Storable;

our @ISA = qw(Log::Log4perl::Appender);

our $VERSION    = '1.53';

###########################################
sub new {
###########################################
    my($class, %options) = @_;

    my $self = {
        max_until_flushed   => undef,
        max_until_discarded => undef,
        appender_method_on_flush 
                            => undef,
        appender            => undef,
        accumulate          => 1,
        persistent          => undef,
        block_period        => 3600,
        buffer              => [],
        %options,
    };

        # Pass back the appender to be limited as a dependency
        # to the configuration file parser
    push @{$options{l4p_depends_on}}, $self->{appender};

        # Run our post_init method in the configurator after
        # all appenders have been defined to make sure the
        # appenders we're connecting to really exist.
    push @{$options{l4p_post_config_subs}}, sub { $self->post_init() };

    bless $self, $class;

    if(defined $self->{persistent}) {
        $self->restore();
    }

    return $self;
}

###########################################
sub log {
###########################################
    my($self, %params) = @_;
    
    local $Log::Log4perl::caller_depth =
        $Log::Log4perl::caller_depth + 2;

        # Check if message needs to be discarded
    my $discard = 0;
    if(defined $self->{max_until_discarded} and
       scalar @{$self->{buffer}} >= $self->{max_until_discarded} - 1) {
        $discard = 1;
    }

        # Check if we need to flush
    my $flush = 0;
    if(defined $self->{max_until_flushed} and
       scalar @{$self->{buffer}} >= $self->{max_until_flushed} - 1) {
        $flush = 1;
    }

    if(!$flush and
       (exists $self->{sent_last} and
        $self->{sent_last} + $self->{block_period} > time()
       )
      ) {
            # Message needs to be blocked for now.
        return if $discard;

            # Ask the appender to save a cached message in $cache
        $self->{app}->SUPER::log(\%params,
                             $params{log4p_category},
                             $params{log4p_level}, \my $cache);

            # Save message and other parameters
        push @{$self->{buffer}}, $cache if $self->{accumulate};

        $self->save() if $self->{persistent};

        return;
    }

    # Relay all messages we got to the SUPER class, which needs to render the
    # messages according to the appender's layout, first.

        # Log pending messages if we have any
    $self->flush();

        # Log current message as well
    $self->{app}->SUPER::log(\%params,
                             $params{log4p_category},
                             $params{log4p_level});

    $self->{sent_last} = time();

        # We need to store the timestamp persistently, if requested
    $self->save() if $self->{persistent};
}

###########################################
sub post_init {
###########################################
    my($self) = @_;

    if(! exists $self->{appender}) {
       die "No appender defined for " . __PACKAGE__;
    }

    my $appenders = Log::Log4perl->appenders();
    my $appender = Log::Log4perl->appenders()->{$self->{appender}};

    if(! defined $appender) {
       die "Appender $self->{appender} not defined (yet) when " .
           __PACKAGE__ . " needed it";
    }

    $self->{app} = $appender;
}

###########################################
sub save {
###########################################
    my($self) = @_;

    my $pdata = [$self->{buffer}, $self->{sent_last}];

        # Save the buffer if we're in persistent mode
    store $pdata, $self->{persistent} or
        die "Cannot save messages in $self->{persistent} ($!)";
}

###########################################
sub restore {
###########################################
    my($self) = @_;

    if(-f $self->{persistent}) {
        my $pdata = retrieve $self->{persistent} or
            die "Cannot retrieve messages from $self->{persistent} ($!)";
        ($self->{buffer}, $self->{sent_last}) = @$pdata;
    }
}

###########################################
sub flush {
###########################################
    my($self) = @_;

        # Log pending messages if we have any
    for(@{$self->{buffer}}) {
        $self->{app}->SUPER::log_cached($_);
    }

      # call flush() on the attached appender if so desired.
    if( $self->{appender_method_on_flush} ) {
        no strict 'refs';
        my $method = $self->{appender_method_on_flush};
        $self->{app}->$method();
    }

        # Empty buffer
    $self->{buffer} = [];
}

###########################################
sub DESTROY {
###########################################
    my($self) = @_;

}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Appender::Limit - Limit message delivery via block period

=head1 SYNOPSIS

    use Log::Log4perl qw(:easy);

    my $conf = qq(
      log4perl.category = WARN, Limiter
    
          # Email appender
      log4perl.appender.Mailer          = Log::Dispatch::Email::MailSend
      log4perl.appender.Mailer.to       = drone\@pageme.com
      log4perl.appender.Mailer.subject  = Something's broken!
      log4perl.appender.Mailer.buffered = 0
      log4perl.appender.Mailer.layout   = PatternLayout
      log4perl.appender.Mailer.layout.ConversionPattern=%d %m %n

          # Limiting appender, using the email appender above
      log4perl.appender.Limiter              = Log::Log4perl::Appender::Limit
      log4perl.appender.Limiter.appender     = Mailer
      log4perl.appender.Limiter.block_period = 3600
    );

    Log::Log4perl->init(\$conf);
    WARN("This message will be sent immediately.");
    WARN("This message will be delayed by one hour.");
    sleep(3601);
    WARN("This message plus the last one will be sent now, seperately.");

=head1 DESCRIPTION

=over 4

=item C<appender>

Specifies the name of the appender used by the limiter. The
appender specified must be defined somewhere in the configuration file,
not necessarily before the definition of 
C<Log::Log4perl::Appender::Limit>.

=item C<block_period>

Period in seconds between delivery of messages. If messages arrive in between,
they will be either saved (if C<accumulate> is set to a true value) or
discarded (if C<accumulate> isn't set).

=item C<persistent>

File name in which C<Log::Log4perl::Appender::Limit> persistently stores 
delivery times. If omitted, the appender will have no recollection of what
happened when the program restarts.

=item C<max_until_flushed>

Maximum number of accumulated messages. If exceeded, the appender flushes 
all messages, regardless if the interval set in C<block_period> 
has passed or not. Don't mix with C<max_until_discarded>.

=item C<max_until_discarded>

Maximum number of accumulated messages. If exceeded, the appender will
simply discard additional messages, waiting for C<block_period> to expire
to flush all accumulated messages. Don't mix with C<max_until_flushed>.

=item C<appender_method_on_flush>

Optional method name to be called on the appender attached to the
limiter when messages are flushed. For example, to have the sample code 
in the SYNOPSIS section bundle buffered emails into one, change the 
mailer's C<buffered> parameter to C<1> and set the limiters 
C<appender_method_on_flush> value to the string C<"flush">:

      log4perl.category = WARN, Limiter
    
          # Email appender
      log4perl.appender.Mailer          = Log::Dispatch::Email::MailSend
      log4perl.appender.Mailer.to       = drone\@pageme.com
      log4perl.appender.Mailer.subject  = Something's broken!
      log4perl.appender.Mailer.buffered = 1
      log4perl.appender.Mailer.layout   = PatternLayout
      log4perl.appender.Mailer.layout.ConversionPattern=%d %m %n

          # Limiting appender, using the email appender above
      log4perl.appender.Limiter              = Log::Log4perl::Appender::Limit
      log4perl.appender.Limiter.appender     = Mailer
      log4perl.appender.Limiter.block_period = 3600
      log4perl.appender.Limiter.appender_method_on_flush = flush

This will cause the mailer to buffer messages and wait for C<flush()>
to send out the whole batch. The limiter will then call the appender's
C<flush()> method when it's own buffer gets flushed out.

=back

If the appender attached to C<Limit> uses C<PatternLayout> with a timestamp
specifier, you will notice that the message timestamps are reflecting the
original log event, not the time of the message rendering in the
attached appender. Major trickery has been applied to accomplish 
this (Cough!).

=head1 DEVELOPMENT NOTES

C<Log::Log4perl::Appender::Limit> is a I<composite> appender.
Unlike other appenders, it doesn't log any messages, it just
passes them on to its attached sub-appender.
For this reason, it doesn't need a layout (contrary to regular appenders).
If it defines none, messages are passed on unaltered.

Custom filters are also applied to the composite appender only.
They are I<not> applied to the sub-appender. Same applies to appender
thresholds. This behaviour might change in the future.

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

