#!/usr/bin/perl

use warnings;
use strict;

use X11::XCB qw(:all);
use X11::XCB::Connection;

my $x = X11::XCB::Connection->new();
my $w = $x->root->create_child(
  class => X11::XCB::WINDOW_CLASS_INPUT_OUTPUT,
  rect => [0, 0, 150, 150],
  border_width => 10,
);

$w->map;
$x->flush;

read STDIN,$_,1; # I can't find pause so this will have to do.

