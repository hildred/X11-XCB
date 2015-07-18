#!/usr/bin/perl

use warnings;
use strict;

use X11::XCB qw(:all);
use X11::XCB::Connection;

my $x = X11::XCB::Connection->new;

my $foreground=$x->generate_id();
X11::XCB::create_gc($x, $foreground, $x->root->{id}, GC_FOREGROUND | GC_GRAPHICS_EXPOSURES, $x->get_black(),0);
my $background=$x->generate_id();
X11::XCB::create_gc($x, $background, $x->root->{id}, GC_BACKGROUND | GC_GRAPHICS_EXPOSURES, $x->get_white(),0);

my $w = $x->root->create_child(
  class => X11::XCB::WINDOW_CLASS_INPUT_OUTPUT,
  rect => [0, 0, 150, 150],
  background_color => '#ffffff',
  event_mask => [qw(EXPOSURE KEY_PRESS)],
);

$w->map;
$x->flush;
while(my $e=$x->wait_for_event){
	my ($type,$sequence)=@{$e}{qw(response_type sequence)};
	if(X11::XCB::EXPOSE==$type){
		X11::XCB::poly_rectangle($x, $w->{id}, $foreground, [40,40,20,20]);
		X11::XCB::image_text_8 ($x, $w->{id}, $background, 20, 20, "Hello, XCB!");
		$x->flush;
	}elsif(X11::XCB::KEY_PRESS==$type){
		last;
	}
};

