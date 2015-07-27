#!/usr/bin/perl

use warnings;
use strict;

use X11::XCB qw(:all);
use X11::XCB::Connection;

my $x = X11::XCB::Connection->new(populate=>1);
my $screen=$x->{screen}[0];

print ("\n");
printf ("Informations of screen %d:\n", $screen->{root});
printf ("  width.........: %d\n", $screen->{width_in_pixels});
printf ("  height........: %d\n", $screen->{height_in_pixels});
printf ("  white pixel...: %d\n", $screen->{white_pixel});
printf ("  black pixel...: %d\n", $screen->{black_pixel});
print ("\n");
