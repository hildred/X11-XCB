#!/usr/bin/perl

use strict; use warnings;

# Automated testing of this module makes little sense: It requires libXau,
# libXdmcp, python2.6 and xsltproc which are typically not installed on CPAN
# smokers.
exit 0 if $ENV{AUTOMATED_TESTING};

my (@configure_req);
BEGIN{
  @configure_req = qw/
    Module::Install
    Module::Install::AuthorRequires
    Module::Install::XSUtil
    ExtUtils::Depends
    XS::Object::Magic
  /;
  my %ok;

  die << '__' . (join "\n", grep { not $ok{$_} } keys %ok) . << '__'
You're running me in author mode.
Your fellow developer left a message to inform you
to please install the following packages manually:

__


Afterwards you can use your CPAN client to install the remaining dependencies,
build this module and install it (eg. `cpanm .`).
__
    if -e '.git'
       and @configure_req
           != grep { $ok{$_} = eval "require $_; 1" } @configure_req;
}

use inc::Module::Install;

name 'X11-XCB';
all_from 'lib/X11/XCB.pm';

repository 'git://code.stapelberg.de/X11-XCB';

requires 'Mouse';
requires 'MouseX::NativeTraits';
requires 'Try::Tiny';

# These are build-time requirements, but there is no way to express this (that
# I know of):
requires 'XML::Simple';
requires 'XML::Descent';
requires 'Data::Dump';

test_requires 'Test::More';
test_requires 'Test::Deep';
test_requires 'Test::Exception';

configure_requires $_ for grep !/Module::Install/, @configure_req;

use_ppport;

# -Wunused-value generates too much output to use it unconditionally
cc_warnings if 1||$ENV{X11_XCB_CC_WARNINGS};

require ExtUtils::PkgConfig;
require ExtUtils::Depends;

ExtUtils::PkgConfig->atleast_version('xcb', '1.2')
  or die "You need at least libxcb version 1.2\n";

my @xcb_libs = qw/xcb xcb-util xcb-xinerama xcb-icccm xcb-randr/;
@xcb_libs == grep { eval { ExtUtils::PkgConfig->find($_); 1 } } @xcb_libs
  or die "Perhaps you haven't installed the development versions?\n";

cc_libs @xcb_libs;

my $pkg = ExtUtils::Depends
    ->new('X11::XCB', 'XS::Object::Magic');
#$pkg->add_c('ucs2_conversion.c');
#$pkg->add_c('listarray.c');
WriteMakefile(
	depend		=> {
		'XCB.c'	=> 'XCB_xs.inc XCB_util.inc XCB.inc XCB.h',
		#'ucs2_conversion.c'	=> 'EXTERN.h perl.h',
	},
	$pkg->get_makefile_vars
);

postamble <<'END_OF_MAKEFILE';

listarray.c: gen2.pl
	./gen2.pl c > listarray.c

XCB.h: gen2.pl
	./gen2.pl h > XCB.h

XCB_xs.inc: _GenerateMyXS.pm
	$(PERL) -M_GenerateMyXS -E '_GenerateMyXS::generate()'

END_OF_MAKEFILE

# vim:sw=2:sts=2:et
