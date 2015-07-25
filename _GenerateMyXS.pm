#!/usr/bin/env perl
# vim:ts=4:sw=4:expandtab

# Known bugs:
# - Does not support _checked or _unchecked variants of function calls
# - Allows Lua to underflow and (maybe) crash C, when it should lua_error instead (so pcall can catch it)
# - ChangeProperty is limited to the 8-bit datatype

# Known warts:
# - Should get string lengths (and other lengths) from Lua, instead of requiring the length to be passed from the script

package _GenerateMyXS;

use strict; use warnings; use v5.10;
use autodie;
use Data::Dump;
use List::Util qw(first);
use ExtUtils::PkgConfig;

use XML::Simple qw(:strict);

use XML::Descent;
my $parser;

# forward declarations of utility functions:
sub on; sub walk;    # parser
sub slurp; sub spit; # file reading/writing
# name mangeling:
sub decamelize($); sub xcb_name($); sub xcb_type($); sub perl_name($); sub cname($);

sub indent (&$@); # templating
our $indent_level = 1;

my $prefix = 'xcb_';
my %const;

# The tmpl_* function push their generated code onto those arrays,
# &generate in turn writes and empties them.
my (@struct, @request);

# XXX currently unused:
# In contrary to %xcbtype, which only holds basic data types like 'int', 'char'
# and so on, the %exacttype hash holds the real type name, like INT16 or CARD32
# for any type which has been specified in the XML definition. For example,
# type KEYCODE is an alias for CARD32. This is necessary later on to correctly
# typecast our intArray type.
my %exacttype = ();

my %xcbtype = (
    BOOL   => 'int',
    BYTE   => 'uint8_t',
    CARD8  => 'uint8_t',
    CARD16 => 'uint16_t',
    CARD32 => 'uint32_t',
    INT8   => 'uint8_t',
    INT16  => 'uint16_t',
    INT32  => 'uint32_t',

    char   => 'char',
    void   => 'void',     # Hack, to partly support ChangeProperty, until we can reverse 'op'.
    float  => 'double',
    double => 'double',
);

sub tmpl_struct {
    my ($name, $params, $types) = @_;

    my $constructor = 'new';
    my $cname = $name;
    $cname =~ s/_/::/g;

    my $param = join ',', @$params;
    my $param_decl = indent { "$types->{$_} $_" } "\n", @$params;
    my $set_struct = indent { 'buf->' . cname($_) . " = $_;" } "\n", @$params;

    push @struct, << "__"
MODULE = X11::XCB PACKAGE = $name
$name *
$constructor(self,$param)
    SV* self
$param_decl
  PREINIT:
    $name *buf;
  CODE:
    if(SvOK(self)) Perl_croak(aTHX_ "%s: self is not ok", "$cname");
    New(0, buf, 1, $name);
$set_struct
    RETVAL = buf;
  OUTPUT:
    RETVAL

__
}

sub tmpl_struct_getter {
    my ($pkg, $name, $type) = @_;
    my $cname = cname($name);

    push @struct, << "__"
MODULE = X11::XCB PACKAGE = ${pkg}Ptr

$type
$name(self)
    $pkg * self
  CODE:
    RETVAL = self->$cname;
  OUTPUT:
    RETVAL

__
}

sub parse_loop_{
	my($name,$type,$count)=@_;
	$type=~s/ \*$//;
	my $size;
	<< "__";
    $_=mk$type(aTHX_ items,$count,&${_}_len,ax,"X11::XCB::$name","$_");
    if(0==$_){Perl_croak(aTHX_ "%s: %s could not create array","X11::XCB::$name","${_}");}
__
}
sub parse_loop_simple{
	my($name,$type,$count)=@_;
	$type=~s/ \*$//;
	my @a;
	push @a, << "__";
    if(1>items-$count)croak("%s: %s is empty","X11::XCB::$name","$_");
    if(1!=items-$count){
	// we have a list!
	${_}_len = items-$count;
	Newx($_, ${_}_len, $type);
	if(0==$_){croak("%s: %s Newx failed","X11::XCB::$name","$_");}
        {int i;for(i=0;i<${_}_len;i++){
	    SV* this=ST(i+$count);
	    if(0==this){croak("%s: %s null pointer","X11::XCB::$name","$_");}
	    SvGETMAGIC(this);
	    ${_}[i]=SvUV(this);
	}}
    }else{
	if (!SvROK(ST($count))){croak("%s: %s expecting more","X11::XCB::$name","$_");}
	if (!SvTYPE(SvRV(ST($count))) == SVt_PVAV){croak("%s: %s not an array or array ref","X11::XCB::$name","$_");}
	AV* me = (AV*)SvRV(ST($count));
	${_}_len = 1+av_len(me);
	if(1>${_}_len){Perl_croak(aTHX_ "%s: %s is empty","X11::XCB::$name","${_}");}
	Newx(${_}, ${_}_len, $type);
	{int i;for(i=0;i<${_}_len;i++){
	    SV** this=av_fetch(me,i,0);
	    if(0==this){Perl_croak(aTHX_ "%s: %s null pointer","X11::XCB::$name","${_}");}
	    SvGETMAGIC(*this);
	    ${_}[i]=SvUV(*this);
	}}
    }
__
	join '',@a;
}

{
my %codemap=(
	'char *'	=>sub{my($name)=@_;"    $_ = SvPV(${_}_sv,${_}_len);".($name=~/^poly_text/?"\n    if(${_}_len>254) croak(\"string too long for type\");":'')},
	'XCBChar2b *'	=>sub{my($name)=@_;"    $_ = convert_SV_to_ucs2(${_}_sv,&${_}_len);".($name=~/^poly_text/?"\n    if(${_}_len>254) croak(\"string too long for type\");":'')},
	'XCBArc *'	=>*parse_loop_,
	'XCBRectangle *'=>*parse_loop_,
	'XCBPoint *'	=>*parse_loop_,
	'XCBColoritem *'=>*parse_loop_,
	'XCBSegment *'	=>*parse_loop_,
	'uint8_t *'	=>*parse_loop_simple,
	'intArray32 *'	=>*parse_loop_simple,
);
my %vmap=(
	'char *'=>[s=>0],
	'XCBChar2b *'=>[s=>0],
	'XCBArc *'=>[l=>1],
	'XCBRectangle *'=>[l=>1],
	'XCBColoritem *'=>[l=>1],
	'XCBSegment *'=>[l=>1],
	'XCBPoint *'=>[l=>1],
	'uint8_t *'=>[l=>1],
	'intArray32 *'=>[l=>1],
	#'void *'=>[a=>0],
);
sub redefinelentype($$$){
	my ($types,$key,$old)=@_;
	if(!defined $types->{$key.'_len'}){
		warn "_len, $key, $old"if defined$types->{$key};
	}elsif(!defined $types->{$key}){
		warn "unknown_len, $key, $old";
	}elsif(!$vmap{$types->{$key}}){
		warn "__len, $key, $old";
	}elsif('s'eq$vmap{$types->{$key}}[0]){
		$types->{$key.'_len'}='STRLEN';
	}elsif('l'eq$vmap{$types->{$key}}[0]){
		$types->{$key.'_len'}='U32';
	}else{
		warn "__len, $key, $old";
	}
}
sub redefinetype($$$$){
	my ($types,$key,$old,$new)=@_;
	if(defined($types->{$key})&& $types->{$key}eq$old){$types->{$key}=$new;}
}
sub tmpl_request {
    my $name=shift;
    my ($cookie, $params, $types, $xcb_cast, $cleanups) = @_;
    return if grep { defined $types->{$_} and $types->{$_} =~ /^void/} @$params; ### void types must be handled by hand.
    #return if grep { /^pixels$/} @$params; ### colors need work
    #return if $name=~/^poly_text/;  ### length abuse, need a plan

    #these are really arrays of bytes doubel bytes or quad bytes, so we want to map from intigers
    if(defined($types->{dashes})&&	'intArray8 *'	eq $types->{dashes}		){$xcb_cast->{dashes}='';}
    redefinetype $types, dashes=>	'intArray8 *'=>'uint8_t *';
    redefinetype $types, value_list=>	'intArray16 *'=>'intArray32 *';

    #these realy are strings, so lets treat them as such
    redefinetype $types, items_=>	'intArray8 *'=>'char *'	     if 'poly_text_8' eq$name;
    redefinetype $types, items_=>	'intArray8 *'=>'XCBChar2b *' if 'poly_text_16'eq$name;

    #these realy are data buffers, so lets treat them as strings
    redefinetype $types, map=>		'intArray8 *'=>'char *';
    redefinetype $types, data=>		'intArray8 *'=>'char *';
    redefinetype $types, address=>	'intArray8 *'=>'char *';

    #lengths will be auto mapped by c, except when passed by pointer and strings need as length type of STRLEN for thes SvPV family and U32 for newx.
    redefinelentype $types, map=>	'uint8_t';
    redefinelentype $types, name=>	'uint16_t';
    redefinelentype $types, string=>	'uint8_t';
    redefinelentype $types, pattern=>	'uint16_t';
    redefinelentype $types, address=>	'uint16_t';
    redefinelentype $types, data=>	'int';
    redefinelentype $types, arcs=>	'int';
    redefinelentype $types, string=>	'int';
    redefinelentype $types, items_=>	'int';
    redefinelentype $types, points=>	'int';
    redefinelentype $types, segments=>	'int';
    redefinelentype $types, rectangles=>'int';

    #let's get the length params ready for use
    my %param = map { my $a=$_;$a=~s/_len$//; $a,1} grep { /_len$/ } @$params;

    my $param = join ',', ('conn', map {
	    if($param{$_}){
		    if($vmap{$types->{$_}}){
			    $vmap{$types->{$_}}[0]eq'l'?'...':$_.'_'.$vmap{$types->{$_}}[0].'v'
		    }else{
			    $_
		    }
	    }else{$_}
    } grep { !/_len$/ } @$params);
    my @param = map {
        $a=$_;
	if($a=~s/_len$//){
	    $param{$_}?(
		    $vmap{$types->{$_}}?
			$_
		    :$a.'_len'
	    ):$_
	}else{
	    $_
	}
    } grep { $_ ne '...' } @$params;

    #   $types->{$_.'_svx'}='SV*' foreach (keys %param);
    $types->{$_.'_sv'}='SV*' foreach (keys %param);
    $types->{$_.'_av'}='AV*' foreach (keys %param);
    $types->{$_.'_hv'}='HV*' foreach (keys %param);
    my $param_decl = indent { $_?"$types->{$_} $_":() } "\n", map {
	    $param{$_}?(
		    $vmap{$types->{$_}}?
			$vmap{$types->{$_}}[0]eq'l'?():$vmap{$types->{$_}}?$_.'_'.$vmap{$types->{$_}}[0].'v':$_
		    :$a.'_len'
	    ):$_
    } grep { !/_len$/ } @param;
    my $len_decl   = indent {
	    $types->{$_}='dummy' unless defined $types->{$_};
	    if($types->{${_}.'_len'}){
		    "$types->{$_} $_;\n    $types->{${_}.'_len'} ${_}_len;"
	    }else{
		    "$types->{$_} $_;\n    size_t ${_}_len;"
	    }
    } "\n", grep {
	    $param{$_}?(
		$types->{$_}?(
		     $vmap{$types->{$_}}?1:0
		):1
	    ):1
    } keys %param;
    my $code_decl  = join "$_", map {($codemap{$types->{$_}}?$codemap{$types->{$_}}:sub{"//error map for $types->{$_} missing\n#error $_"})->($name,$types->{$_},scalar(@param)-1)} sort keys %param;

    # XXX should be "$prefix$name", but $name has already a prefix like xinerama_
    my $xcb_name = "xcb_$name";
    my $xcb_param = do {
        local $indent_level = 0;
        $xcb_cast->{conn} = '';
        indent { $xcb_cast->{$_} . $_ } ', ', ('conn', @param);
    };
    my $cleanup = indent { "free($_);" } "\n", @$cleanups;

    push @request, << "__"
HV *
$name($param)
    XCBConnection *conn
$param_decl
  PREINIT:
$len_decl
    HV * hash;
    $cookie cookie;
  CODE:
$code_decl
    cookie = $xcb_name($xcb_param);

    hash = newHV();
    hv_store(hash, "sequence", strlen("sequence"), newSViv(cookie.sequence), 0);
    RETVAL = hash;
$cleanup
  OUTPUT:
    RETVAL

__
}}

sub on_field {
    my ($fields, $types) = @_;

    on field => sub {
        my $name = $_->{name};
        push @$fields, $name;

        my $type = xcb_type($_->{type});
        # XXX why not XCB\u$1?
        $type =~ s/^xcb_/XCB/;
        $types->{$name} = $type;
    }
}

sub do_structs {
    my $x_name = $_->{name};
    my $xcb_type = xcb_type $x_name;
    my $perlname = perl_name $x_name;

    print OUTTD " typedef $xcb_type $perlname;\n";
    print OUTTM "$perlname * T_PTROBJ\n";

    my (@fields, %type);
    on_field(\@fields, \%type);

    my $dogetter = 1;

    my %nostatic = (    # These structs are used from the base protocol
        xcb_setup_t => 1,
    );

    # TODO: unimplemented
    on list => sub {
        $dogetter = 0;    # If it has a list, the get half shouldn't (can't?) be needed.
    };

    # TODO: unimplemented
    # on union => sub { on [ qw/field list/ ] => sub {} };

    walk;

    tmpl_struct($perlname, \@fields, \%type);

    if ($dogetter) {
        tmpl_struct_getter($perlname, $_, $type{$_}) for @fields;
    }

}

sub do_typedefs {
    my $e = shift;

    if ($e eq 'typedef') {
        $xcbtype{ $_->{newname} }      = $xcbtype{ $_->{oldname} };
        $exacttype{ $_->{newname} }    = $_->{oldname};
    }
    elsif ($e =~ /^(?:xidtype|xidunion)/) {
        $xcbtype{ $_->{name} }      = $xcbtype{CARD32};
    }
}

# items is already in use by XS, see perlapi
# <Variables created by "xsubpp" and "xsubpp" internal functions> for more
# XXX this is currently only used in do_request/on list
sub param_sanitize {
    $_[0] eq 'items' ? 'items_' : $_[0]
}

sub do_requests {
    my $x_name = $_->{name};
    my $xcb_name  = xcb_name $x_name;

    # XXX hack, to get eg. a xinerama_ prefix
    (my $ns = $prefix) =~ s/^xcb_//;

    my $name = $ns . decamelize $x_name;

    my (@param, %type, %xcb_cast, @cleanup);

    # Skip documentation blocks.
    on doc => sub {};

    on_field(\@param, \%type);

    # array length
    # TODO : rid _len from parameters, use XS to get the length of strings, etc
    on list => sub {
        my $param = param_sanitize($_->{name});
        my $x_type = $_->{type};

        my $push_len = 1;
        on [ qw/fieldref op value/ ] => sub { $push_len = 0 };
        walk;

        push @param, $param . '_len' if $push_len;
        push @param, $param;

        my $type = $xcbtype{$x_type} || perl_name $x_type;

	if ($type =~ /^uint8_t$/) {
	    $xcb_cast{$param} = " (const $type*)";
	    $type = 'intArray8'
	}elsif ($type =~ /^uint16_t$/) {
	    $xcb_cast{$param} = " (const $type*)";
	    $type = 'intArray16'
	}elsif ($type =~ /^uint32_t$/) {
	    $xcb_cast{$param} = " (const $type*)";
	    $type = 'intArray32'
	}

        # We use char* instead of void* to be able to use pack() in the perl part
	#$type = 'char' if $type eq 'void'; ## this breaks when we get real strings.

        $type{$param} = "$type *";
        $type{$param . '_len'} = 'int' if $push_len;

        push @cleanup, $param unless $type =~ /^(?:char|void)$/;
    };

    # bitmask -> list of value.
    # TODO: ideally this would be a hashref eg. C< { bitname => "value", … } >
    on valueparam => sub {
        my ($mask, $list, $type) = @{$_}{qw/value-mask-name value-list-name value-mask-type/};
        push @param, $mask
        # eg. ConfigureWindow already specifies the mask via <field />
            unless ($param[-1] || '') eq $mask;

        push @param, $list;
        push @param, '...';

        $type{$mask} = xcb_type $type;
	$type=~s/CARD([0-9]+)/intArray$1 */;
        $type{$list} = $type;
	#$type{$list} = 'intArray *';

        push @cleanup, $list;
    };

    my $cookie = 'xcb_void_cookie_t';
    on reply => sub { $cookie = $xcb_name . '_cookie_t'; 'do_reply(@_)' };
    walk;

    $xcb_cast{$_} ||= '' for @param;

    tmpl_request($name, $cookie, \@param, \%type, \%xcb_cast, \@cleanup);

}

sub do_events($) {
    my $xcb = shift;
    my %events;

    # TODO: events
}

sub do_replies($\%\%) {
    my ($xcb, $func, $collect) = @_;

    for my $req (@{ $xcb->{request} }) {
        my $rep = $req->{reply};
        next unless defined($rep);
        # request should return a cookie object, blessed into the right pkg
        # $perlname should be set fixed to 'reply'

        my $name     = xcb_name($req->{name}) . "_reply";
        my $reply    = xcb_name($req->{name}) . "_reply_t";
        my $perlname = $name;
        $perlname =~ s/^xcb_//g;
        my $cookie = xcb_name($req->{name}) . "_cookie_t";

        print OUT "HV *\n$perlname(conn,sequence)\n";
        print OUT "    XCBConnection *conn\n";
        print OUT "    int sequence\n";
        print OUT "  PREINIT:\n";
        print OUT "    HV * hash;\n";
        print OUT "    $cookie cookie;\n";
        print OUT "    $reply *reply;\n";
        print OUT "  CODE:\n";
        print OUT "    cookie.sequence = sequence;\n";
        print OUT "    reply = $name(conn, cookie, NULL);\n";
        # XXX use connection_has_error
        print OUT qq/    if (!reply) croak("Could not get reply for: $name"); /;
        print OUT "    hash = newHV();\n";

        # We ignore pad0 and response_type. Every reply has sequence and length
        print OUT "    hv_store(hash, \"sequence\", strlen(\"sequence\"), newSViv(reply->sequence), 0);\n";
        print OUT "    hv_store(hash, \"length\", strlen(\"length\"), newSViv(reply->length), 0);\n";
        for my $var (@{ $rep->[0]->{field} }) {
            my $type = xcb_type($var->{type});
            my $name = cname($var->{name});
            if ($type =~ /^(?:uint(?:8|16|32)_t|int)$/) {
                print OUT "    hv_store(hash, \"$name\", strlen(\"$name\"), newSViv(reply->$name), 0);\n";
            } else {
                print OUT "    /* TODO: type $type, name $var->{name} */\n";
            }
        }

        for my $list (@{ $rep->[0]->{list} }) {
            my $listname      = $list->{name};
            my $type          = xcb_name($list->{type}) . '_t';
            my $iterator      = xcb_name($list->{type}) . '_iterator_t';
            my $iterator_next = xcb_name($list->{type}) . '_next';
            my $pre           = xcb_name($req->{name});

            if ($list->{type} eq 'void') {

                # A byte-array. Provide it as SV.
		print OUT "    {\n";
		print OUT "    int _len;\n";
                print OUT "    _len = reply->value_len * (reply->format / 8);\n";
                print OUT "    if (_len > 0)\n";
                print OUT "        hv_store(hash, \"value\", strlen(\"value\"), newSVpvn((const char*)(reply + 1), _len), 0);\n";
		print OUT "    }\n";
                next;
            }

            # Get the type description of the list’s members
            my $struct = first { $_->{name} eq $list->{type} } @{ $xcb->{struct} };

            next unless defined($struct->{field}) && scalar(@{ $struct->{field} }) > 0;

            print OUT "    {\n";
	    print OUT "    AV * alist;\n";
            print OUT "    /* Handling list part of the reply */\n";
            print OUT "    alist = newAV();\n";
            print OUT "    $iterator iterator = $pre" . '_' . $listname . "_iterator(reply);\n";
            print OUT "    for (; iterator.rem > 0; $iterator_next(&iterator)) {\n";
	    print OUT "      HV * inner_hash;\n";
            print OUT "      $type *data = iterator.data;\n";
            print OUT "      inner_hash = newHV();\n";

            for my $field (@{ $struct->{field} }) {
                my $type = xcb_type($field->{type});
                my $name = cname($field->{name});

                if ($type =~ /^(?:uint(?:8|16|32)_t|int)$/) {
                    print OUT "      hv_store(inner_hash, \"$name\", strlen(\"$name\"), newSViv(data->$name), 0);\n";
                } else {
                    print OUT "      /* TODO: type $type, name $name */\n";
                }
            }
            print OUT "      av_push(alist, newRV((SV*)inner_hash));\n";

            print OUT "    }\n";
            print OUT "    hv_store(hash, \"" . $list->{name} . "\", strlen(\"" . $list->{name} . "\"), newRV((SV*)alist), 0);\n";

            print OUT "    }\n";
        }

        #print Dumper($rep);
        #if (defined($rep->{list})) {

        print OUT "    RETVAL = hash;\n";
        print OUT "  OUTPUT:\n    RETVAL\n\n";
    }
}

sub do_enums {
    my ($tag, $attr) = @_;

    my $name = uc decamelize $attr->{name};

    if ($tag eq 'enum') {
        on item => sub {
            my $tname = $name . "_" . uc decamelize $_->{name};
            $const{$tname} = "newSViv(XCB_$tname)";
        };
        walk;

    }
    elsif ($tag eq 'event') { # =~ /^(?:event|eventcopy|error|errorcopy)$/) {
        $const{$name} = "newSViv(XCB_$name)";
    }

}

sub generate {
    my $path = ExtUtils::PkgConfig->variable('xcb-proto', 'xcbincludedir');
    #my @xcb_xmls = qw/xproto.xml xinerama.xml randr.xml/;
    my @xcb_xmls = qw/xproto.xml xinerama.xml/;

    -d $path or die "$path: $!\n";

    # TODO: Handle all .xmls
    #opendir(DIR, '.');
    #@files = grep { /\.xml$/ } readdir(DIR);
    #closedir DIR;

    my @files = map {
        my $xml = "$path/$_";
        -r $xml or die "$xml: $!\n";
        $xml
    } @xcb_xmls;

    open(OUT,   ">XCB_xs.inc");
    open(OUTTM, ">typemap");
    open(OUTTD, ">typedefs.h");

    print OUTTM << '__';
XCBConnection *             T_PTROBJ_MG
intArray8 *                 T_ARRAY
intArray16 *                T_ARRAY
intArray32 *                T_ARRAY
XCBSegment *                T_ARRAY
intArray8                   T_U_CHAR
intArray16                  T_U_SHORT
intArray32                  T_UV
X11_XCB_ICCCM_WMHints *     T_PTROBJ
X11_XCB_ICCCM_SizeHints *   T_PTROBJ
uint8_t                     T_U_CHAR
uint16_t                    T_U_SHORT
uint32_t                    T_UV
__



    # Our own additions: EWMH constants
    $const{_NET_WM_STATE_ADD}    = 'newSViv(1)';
    $const{_NET_WM_STATE_REMOVE} = 'newSViv(0)';
    $const{_NET_WM_STATE_TOGGLE} = 'newSViv(2)';

    # ICCCM constants from xcb-util
    for my $const (qw(XCB_ICCCM_WM_STATE_WITHDRAWN XCB_ICCCM_WM_STATE_NORMAL XCB_ICCCM_WM_STATE_ICONIC)) {
        my ($name) = ($const =~ /XCB_(.*)/);
        $const{$name} = "newSViv($const)";
    }

    for my $path (@files) {
        say "Processing: $path";
	{
		my $inc=$path;
		$inc=~s!.*/([^/]+)\.xml!$1.h!;
		print OUTTD "#include <xcb/$inc>\n"
	}
        my $xcb = XMLin("$path", KeyAttr => undef, ForceArray => 1);

        $parser = XML::Descent->new({ Input => $path });

        on xcb => sub {
            my ($e, $attr) = @_;
            my $name = $attr->{header};

            $prefix = $name eq 'xproto' ? 'xcb_' : "xcb_${name}_";

            on [ qw/enum event eventcopy error errorcopy/ ] => \&do_enums;
            on [ qw/typedef xidtype xidunion/ ] => \&do_typedefs;
            on struct => \&do_structs;
            on request => \&do_requests;
            walk;
        };
        walk;

        print OUT @struct;
        undef @struct;

        do_events($xcb);

        print OUT "MODULE = X11::XCB PACKAGE = X11::XCB\n";
        print OUT @request;
        undef @request;

        &do_replies($xcb);


    }

    close OUT;
    close OUTTM;
    close OUTTD;

    my @const = sort keys %const;

    spit 'XCB.inc', << "__",
static void boot_constants(HV *stash, AV *tags_all) {
    av_extend(tags_all, ${\ scalar @const });
__
        (map { << "__" } @const),
    newCONSTSUB(stash, "$_", $const{$_});
    av_push(tags_all, newSVpvn("$_", ${\ length $_ }));
__
        "}\n";
}

# utility functions

sub on {
    my ($tag, $code) = @_;
    $parser->on($tag => sub { $code->(@_) for $_[1] });
}
sub walk { $parser->walk }

# reads in a whole file
sub slurp {
    open my $fh, '<', shift;
    local $/;
    <$fh>;
}

sub spit {
    my $file = shift;
    open my $fh, '>', $file;
    print $fh @_;
    say "Writing: $file";
    close $fh;
}

sub perl_name($) {
    my $x_name = shift;
    # XXX hack:
    # get potential extra ns like "xinerama"
    (my $ns = $prefix) =~ s/^xcb_//;

    return 'XCB' . ucfirst +($ns . decamelize($x_name));
}

sub xcb_name($) {
    my $x_name = shift;
    return $prefix . decamelize($x_name);
}

sub xcb_type($) {
    my $type = shift;
    # XXX shouldn't those be in %xcbtype anyway?
    return $xcbtype{$type} || xcb_name($type) . '_t';
}

sub decamelize($) {
    my ($camel) = @_;

    my %special = (qw(
        CHAR2B	1
        INT64	1
        FLOAT32	1
        FLOAT64	1
        BOOL32	1
        STRING8	1
        Family_DECnet	1
        DECnet	1
   ));

    return lc $camel if $special{$camel};

    # FIXME: eliminate this special case
    return $camel if $camel =~ /^CUT_BUFFER/;

    my $name = '';

    while (length($camel)) {
        my ($char, $next) = ($camel =~ /^(.)(.*)$/);

        $name .= lc($char);

        if (   $camel =~ /^[[:lower:]][[:upper:]]/
            || $camel =~ /^\d[[:alpha:]]/
            || $camel =~ /^[[:alpha:]]\d/
            || $camel =~ /^[[:upper:]][[:upper:]][[:lower:]]/)
        {
            $name .= '_';
        }

        $camel = $next;
    }

    return $name;
}

sub cname($) {
    my $name = shift;
    my %special = (qw(
	new	1
	delete	1
	class	1
	operator	1
   ));

    return "_$name" if $special{$name};
    return $name;
}

sub indent (&$@) {
    my ($code, $join, @input) = @_;
    my $indent = '    ' x ($indent_level);

    return join $join, map { $indent . $code->() } @input;
}

() = $0 =~ (__PACKAGE__ . '.pm') ? generate() : 1;

# Copyright (C) 2009 Michael Stapelberg <michael at stapelberg dot de>
# Copyright (C) 2007 Hummingbird Ltd. All Rights Reserved.
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated
# documentation files (the "Software"), to deal in the
# Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute,
# sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall
# be included in all copies or substantial portions of the
# Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
# KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
# PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
# BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
# Except as contained in this notice, the names of the authors
# or their institutions shall not be used in advertising or
# otherwise to promote the sale, use or other dealings in this
# Software without prior written authorization from the
# authors.
