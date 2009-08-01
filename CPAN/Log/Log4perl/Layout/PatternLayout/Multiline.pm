#!/usr/bin/perl

package Log::Log4perl::Layout::PatternLayout::Multiline;
use base qw(Log::Log4perl::Layout::PatternLayout);

###########################################
sub render {
###########################################
    my($self, $message, $category, $priority, $caller_level) = @_;

    my @messages = split /\r?\n/, $message;

    $caller_level = 0 unless defined $caller_level;

    my $result;

    for my $msg ( @messages ) {
        $result .= $self->SUPER::render(
            $msg, $category, $priority, $caller_level + 1
        );
    }
    return $result;
}

1;

__END__

=head1 NAME

    Log::Log4perl::Layout::PatternLayout::Multiline

=head1 SYNOPSIS

    use Log::Log4perl::Layout::PatternLayout::Multiline;

    my $layout = Log::Log4perl::Layout::PatternLayout::Multiline->new(
        "%d (%F:%L)> %m");

=head1 DESCRIPTION

C<Log::Log4perl::Layout::PatternLayout::Multiline> is a subclass
of Log4perl's PatternLayout and is helpful if you send multiline
messages to your appenders which appear as

    2007/04/04 23:59:01 This is
    a message with
    multiple lines

and you want them to appear as 

    2007/04/04 23:59:01 This is
    2007/04/04 23:59:01 a message with
    2007/04/04 23:59:01 multiple lines

instead. This layout class simply splits up the incoming message into
several chunks split by line breaks and renders them with PatternLayout
just as if it had arrived in separate chunks in the first place.

=head1 AUTHOR

2007, Cory Bennett, Mike Schilli <cpan@perlmeister.com>
