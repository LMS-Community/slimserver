package Slim::Player::Protocols::Buffered;

use strict;
use base qw(Slim::Player::Protocols::HTTPS);

use File::Temp;

use Slim::Utils::Errno;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log = logger('player.streaming.remote');
my $prefs = preferences('server');

sub canDirectStream { 0 }

sub new {
	my $class  = shift;
	my ($args) = @_;

	main::INFOLOG && $log->info("Using Buffered HTTP(S) service for $args->{url}");
	my $self = $class->SUPER::new(@_);
	
	# don't buffer if we don't have content-length
	return $self unless ${*$self}{'contentLength'};

	# HTTP headers have now been acquired in a blocking way by the above, we can 
	# now enable fast download of body to a file from which we'll read further data
	# but the switch of socket handler can only be done within _sysread otherwise
	# we will timeout when there is a pipeline with a callback 
	${*$self}{'_fh'} = File::Temp->new( DIR => Slim::Utils::Misc::getTempDir );
	open ${*$self}{'_rfh'}, '<', ${*$self}{'_fh'}->filename;
	binmode(${*$self}{'_rfh'});
	
	return $self;
}

sub close {
	my $self = shift;

	# clean buffer file and all handlers
	Slim::Networking::Select::removeRead($self);	
	${*$self}{'_rfh'}->close if ${*$self}{'_rfh'};
	delete ${*$self}{'_fh'};
	
	$self->SUPER::close(@_);
}

# we need that call structure to make sure that SUPER calls the
# object's parent, not the package's parent
# see http://modernperlbooks.com/mt/2009/09/when-super-isnt.html
sub _sysread {
	my $self  = $_[0];
	my $rfh = ${*$self}{'_rfh'};
	
	# we are not ready to read body yet, read socket directly
	return $self->SUPER::_sysread($_[1], $_[2], $_[3]) unless $rfh;

	# try to read from buffer file, first *always* reset read pointer
	$rfh->seek(0, 1);						
	my $readLength = read($rfh, $_[1], $_[2], $_[3]);
	return $readLength if $readLength;
	
	# assume that close() will be called for cleanup
	return 0 if ${*$self}{_done};
	
	# empty file but not done yet, try to read directly
	$readLength = $self->SUPER::_sysread($_[1], $_[2], $_[3]);

	# if we now have data pending, likely we have been removed from the reading loop
	# so we have to re-insert ourselves (no need to store fresh data in buffer)
	if ($readLength) {
		Slim::Networking::Select::addRead($self, \&saveStream);
		return $readLength;
	}
		
	# use EINTR because EWOULDBLOCK (although faster) may overwrite our addRead()
	$! = EINTR;
	return undef;
}

sub saveStream {
    my $self = shift;
	
	my $bytes = $self->SUPER::_sysread(my $data, 32768);
	return unless defined $bytes;
	
	if ($bytes) {
		${*$self}{'_fh'}->write($data);
	} else {
		Slim::Networking::Select::removeRead($self);	
		${*$self}{_done} = 1;		
	}
}	
