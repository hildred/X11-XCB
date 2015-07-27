X11-XCB version 0.14
====================

X11::XCB is a wrapper around lib xcb the X c language bindings which was
intinded to be a replacement for xlib. As such this is mostly just a
straight wrap but with a slightly more perlish flavor.

INSTALLATION

To install this module type the following:

   perl Makefile.PL
   make
   make test
   make install

DEPENDENCIES

This module requires these other modules and libraries:

Firstly you need libxcb (and its development package if not installing
from source). You probably also want most of the optional extension
libraries and the corresponding development packages starting with
Xinemra which is currently required for the tests to pass. We also use
the following modules from cpan:

- Module::Install
- Module::Install::AuthorRequires
- Module::Install::XSUtil
- ExtUtils::Depends
- XS::Object::Magic
- Mouse
- MouseX::NativeTraits
- Try::Tiny
- XML::Simple
- XML::Descent
- Data::Dump
- Test::More
- Test::Deep
- Test::Exception

COPYRIGHT AND LICENCE

Copyright (C) 2009 by Michael Stapelberg  
Copyright (C) 2015 by Ben Hildred

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.


