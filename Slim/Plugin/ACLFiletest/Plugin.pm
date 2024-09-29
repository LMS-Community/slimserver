package Slim::Plugin::ACLFiletest::Plugin;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use Slim::Utils::Log;

sub preinitPlugin {
	Slim::Utils::OSDetect::getOS->aclFiletest( sub {
		my $path = shift || return;

		{
			use filetest 'access';
			return (! -r $path) ? 0 : 1;
		}
	} );

	logError('Successfully initialized ACL filetests');
}

1;
