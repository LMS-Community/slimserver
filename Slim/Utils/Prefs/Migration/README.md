IMPORTANT
=========

Whenever you add a new migration module (be it Vx.pm or ClientVx.pm), make sure you add it to the Windows build file [squeezecenter.perlsvc](https://github.com/Logitech/slimserver-platforms/blob/public/7.9/win32/squeezecenter.perlsvc). Otherwise the Windows build will not include it in the binary and fail to load.