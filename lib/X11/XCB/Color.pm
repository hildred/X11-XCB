package X11::XCB::Color;

use Moose;
use Moose::Util::TypeConstraints;

coerce 'X11::XCB::Color'
    => from 'Str'
    => via { X11::XCB::Color->new(hexcode => $_) };

has 'hexcode' => (is => 'ro', isa => 'Str', required => 1);
has 'pixel' => (is => 'ro', isa => 'Int', lazy_build => 1);
has '_conn' => (is => 'ro', default => sub { X11::XCB::Connection->instance });

=head2 pixel

Returns the colorpixel (think of an ID) of this color. Works with TrueColor
displays only at the moment.

=cut
sub _build_pixel {
    my $self = shift;
    my $hex = $self->hexcode;

    # Strip optional leading # from hex code
    $hex =~ s/^#//;

    return hex($hex);
}

1
# vim:ts=4:sw=4:expandtab
