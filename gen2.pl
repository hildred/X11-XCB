#!/usr/bin/perl

use strict; use warnings;

my @typenames=qw(XCBSegment XCBArc XCBRectangle XCBPoint XCBColoritem);
my %typegroup=(
	XCBSegment=>qname=>
	XCBRectangle=>pname=>
	XCBArc=>pname=>
	XCBPoint=>pname=>
	XCBColoritem=>cname=>
);
my %typesize=(
	XCBSegment=>4,
	XCBRectangle=>4,
	XCBArc=>6,
	XCBPoint=>2,
	XCBColoritem=>5,
);
my %typemem=(
	pname=>["x","y","width","height","angle1","angle2"],
	qname=>["x1","y1","x2","y2"],
	cname=>[qw(pixel red green blue flags)],
);
sub dimcheck{
	my($indent,$size,$type)=@_;
	#$type=~s/ \*$//;
	my @a;
	push @a, "#line ", __LINE__, ' "', __FILE__, "\"\n", << "__", $indent, qq/if(av_len((AV*)this_)!=/,($size-1), "){warn(\"%s: %s ";
${indent}//{warn("%s: %s count %d, line %d",lname,fname,(av_len((AV*)this_)),__LINE__);}
${indent}//{warn("%s: %s size %d, line %d",lname,fname,$size,__LINE__);}
__
	if('XCBArc'eq$type){		push @a, qq/arcs must have six/;
	}elsif('XCBRectangle'eq$type){	push @a, qq/rectangles must have four/;
	}elsif('XCBPoint'eq$type){	push @a, qq/points must have two/;
	}elsif('XCBSegment'eq$type){	push @a, qq/segments must have four/;
	}elsif('XCBColoritem'eq$type){	push @a, qq/colors must have five/;
	}else{die $type}
	push @a, " dimensions, line %d\",lname,fname,__LINE__);return 0;}\n";
	join '', @a;
}
sub structfill{
	my($indent,$size,$type)=@_;
	#$type=~s/ \*$//;
	my @a;
	push @a, "#line ", __LINE__, ' "', __FILE__, "\"\n", << "__";
${indent}//SvGETMAGIC(*that);
${indent}switch(j){
__
	if($typegroup{$type}){
		for(my $i=0;$i<$typesize{$type};$i++){
			push @a, "$indent	case $i: array[i].$typemem{$typegroup{$type}}[$i]=SvUV(*that);break;\n"
		}
	}else{
		die $type;
	}
	push @a, "#line ", (__LINE__ +1), ' "', __FILE__, "\"\n", << "__";
$indent	default: warn("this should not happen");break;
$indent}
__
	join '', @a;
}
sub decl{
	my($type)=@_;
	#$type=~s/ \*$//;
	return "$type* mk$type(pTHX_ int items, int count, U32* ix_ret, U32 ax, char* lname, char* fname)";
}
sub psub{
	my($type)=@_;
	#$type=~s/ \*$//;
	my @a;
	#my $b="bool st$type()";
	my $size=$typesize{$type};;
	my $array=$typegroup{$type};
	if($size){
	}elsif('XCBArc'eq$type){	$size=6;	$array='pname';
	}elsif('XCBPoint'eq$type){	$size=2;	$array='pname';
	}elsif('XCBColoritem'eq$type){	$size=5;	$array='cname';
	}else{		warn '$size needs set';
			die $type;
	}
	die $type unless $array;
	push @a, "#line ", (__LINE__ +1), ' "', __FILE__, "\"\n", decl(@_), << "__";
{
	$type* array=0;
	//{warn("%s: %s items %d, line %d",lname,fname,items,__LINE__);}
	//{warn("%s: %s count %d, line %d",lname,fname,count,__LINE__);}
	//{warn("%s: %s size %d, line %d",lname,fname,$size,__LINE__);}
	if(1>items-count){
		warn("%s: %s is empty",lname,fname);return 0;
	}else if(1!=items-count){
		// we have a list!
		*ix_ret = items-count;
		Newx(array, *ix_ret, $type);
    		if(0==array){warn("%s: %s Newx failed",lname,fname);return 0;}
		{U32 i;for(i=0;i<*ix_ret;i++){
			SV* this=ST(i+count);
			if(0==this){warn("%s: %s null pointer",lname,fname);return 0;}
			//SvGETMAGIC(this);
			if (!SvROK(this)){warn("%s: %s is missing",lname,fname);return 0;}
			if (SvTYPE(SvRV(this)) == SVt_PVAV){
				AV* this_ = (AV*)SvRV(this);
__
	push @a, dimcheck("\t"x4,$size,@_), "#line ", (__LINE__ +1), ' "', __FILE__, "\"\n", << "__";
				{U32 j;for(j=0;j<$size;j++){
					SV** that=av_fetch(this_,j,0);
					if(0==that){warn("%s: %s null pointer",lname,fname);return 0;}
__
	push @a, structfill("\t"x5,$size,@_), "#line ", (__LINE__ +1), ' "', __FILE__, "\"\n", << "__";
				}}
			}else if (SvTYPE(SvRV(this)) == SVt_PVHV){
				HV* this_ = (HV*)SvRV(this);
				{U32 j;for(j=0;j<$size;j++){
					SV** that=hv_fetch(this_,$array\[j],strlen($array\[j]),0);
					if(0==that){warn("%s: %s->%s is missing",lname,fname,$array\[j]);return 0;}
__
	push @a, structfill("\t"x5,$size,@_), "#line ", (__LINE__ +1), ' "', __FILE__, "\"\n", << "__";
				}}
			}else{
				warn("%s: %s is not an ARRAY or HASH reference",lname,fname);return 0;
			}
		}}
		if (!array){warn("%s: %s null array at %s, line %d.",lname,fname,__FILE__,__LINE__);return 0;}
		return array;
	}else{
		// single item, check for array and object
		//{warn("%s: %s count %d, line %d",lname,fname,count,__LINE__);}
		if (!SvROK(ST(count))){warn("%s: %s expecting more",lname,fname);return 0;}
		//{warn("%s: %s count %d, line %d",lname,fname,count,__LINE__);}
		if (SvTYPE(SvRV(ST(count))) == SVt_PVHV){
			//{warn("%s: %s count %d, line %d",lname,fname,count,__LINE__);}
			// at this point we can assume that we have a list one item long.
			*ix_ret = 1;
			Newx(array, *ix_ret, $type);
	    		if(0==array){warn("%s: %s Newx failed",lname,fname);return 0;}
			int i=0;
			HV* this_ = (HV*)SvRV(ST(count));
			{U32 j;for(j=0;j<$size;j++){
				SV** that=hv_fetch(this_,$array\[j],strlen($array\[j]),0);
				if(0==that){warn("%s: %s->%s is missing",lname,fname,$array\[j]);return 0;}
__
	push @a, structfill("\t"x4,$size,@_), "#line ", (__LINE__ +1), ' "', __FILE__, "\"\n", << "__";
			}}
			if (!array){warn("%s: %s null array at %s, line %d.",lname,fname,__FILE__,__LINE__);return 0;}
			return array;
		}else if (SvTYPE(SvRV(ST(count))) == SVt_PVAV){
			//{warn("%s: %s count %d, line %d",lname,fname,count,__LINE__);}
			// so is the array the only object in a list or does it have the list as it's children?
			AV* me = (AV*)SvRV(ST(count));
			*ix_ret = 1+av_len(me);
    			if(1>*ix_ret){warn("%s: %s is empty",lname,fname);return 0;} // easy out, we still don't know what we got but it is not useful.
			if($size==*ix_ret){
				//{warn("%s: %s count %d, line %d",lname,fname,count,__LINE__);}
				//{warn("%s: %s size %d, line %d",lname,fname,$size,__LINE__);}
				// a quandry: do we have an array object or a list that just happens to be that long?
				// if we have a list of one set *ix_ret to one and we need to handle it and return, otherwise fall thtough
				SV** this=av_fetch(me,0,0);
				if(0==this){warn("%s: %s null pointer",lname,fname);return 0;}
				SvGETMAGIC(*this);
				if(!SvROK(*this)){
					// not a refrence so our list is one handle it.
					*ix_ret = 1;
					Newx(array, *ix_ret, $type);
			    		if(0==array){warn("%s: %s Newx failed",lname,fname);return 0;}
					int i=0;
					{U32 j;for(j=0;j<$size;j++){
						SV** that=av_fetch(me,j,0);
						if(0==that){warn("%s: %s null pointer",lname,fname);return 0;}
__
	push @a, structfill("\t"x6,$size,@_), "#line ", (__LINE__ +1), ' "', __FILE__, "\"\n", << "__";
					}}
					if (!array){warn("%s: %s null array at %s, line %d.",lname,fname,__FILE__,__LINE__);return 0;}
					return array;
				// }else{ // commented becouse the body is all comments
					// refrence so fall through
				}
			//}else{ // this can be commented as we are going to fall through.
				// a list, definatly a list.
			}
			Newx(array, *ix_ret, $type); 
		    	if(0==array){warn("%s: %s Newx failed",lname,fname);return 0;}
    			{U32 i;for(i=0;i<*ix_ret;i++){
				SV** this=av_fetch(me,i,0);
				if(0==this){warn("%s: %s null pointer",lname,fname);return 0;}
				SvGETMAGIC(*this);
				if (!SvROK(*this)){warn("%s: %s is missing",lname,fname);return 0;}
				if (SvTYPE(SvRV(*this)) == SVt_PVAV){
					AV* this_ = (AV*)SvRV(*this);
__
	push @a, dimcheck("\t"x4,$size,@_), "#line ", (__LINE__ +1), ' "', __FILE__, "\"\n", << "__";
					{U32 j;for(j=0;j<$size;j++){
						SV** that=av_fetch(this_,j,0);
						if(0==that){warn("%s: %s null pointer",lname,fname);return 0;}
__
	push @a, structfill("\t"x6,$size,@_), "#line ", (__LINE__ +1), ' "', __FILE__, "\"\n", << "__";
					}}
				}else if (SvTYPE(SvRV(*this)) == SVt_PVHV){
					HV* this_ = (HV*)SvRV(*this);
					{U32 j;for(j=0;j<$size;j++){
						SV** that=hv_fetch(this_,$array\[j],strlen($array\[j]),0);
						if(0==that){warn("%s: %s->%s is missing",lname,fname,$array\[j]);return 0;}
__
	push @a, structfill("\t"x6,$size,@_), "#line ", (__LINE__ +1), ' "', __FILE__, "\"\n", << "__";
					}}
				}
			}}
			if (!array){warn("%s: %s null array at %s, line %d.",lname,fname,__FILE__,__LINE__);return 0;}
		}else{
			if (!array){warn("%s: %s null array at %s, line %d.",lname,fname,__FILE__,__LINE__);return 0;}
		}
		if (!array){warn("%s: %s null array at %s, line %d.",lname,fname,__FILE__,__LINE__);return 0;}
		return array;
	}
	if (!array){warn("%s: %s null array at %s, line %d.",lname,fname,__FILE__,__LINE__);return 0;}
	return array;
}
__
	return join '', @a;
}
sub narray{
	my($type)=@_;
	return "char *$type\[".scalar @{$typemem{$type}}."]={".join(', ', map {"\"$_\""} @{$typemem{$type}})."};\n";
}
sub c{
	print "#line ", (__LINE__ +1), ' "', __FILE__, "\"\n", << "__";
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <xcb/xcb.h>
#include <xcb/xinerama.h>

#include "ppport.h"

#include "typedefs.h"
#include "xs_object_magic.h"

#include "XCB.h"

__
	print map {narray($_)} sort keys %typemem;
	print map {psub($_)} @typenames;
}
sub h{
	print "#line ", (__LINE__ +1), ' "', __FILE__, "\"\n", << "__";
#pragma once
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <xcb/xcb.h>
#include <xcb/xinerama.h>

#include "ppport.h"

#include "typedefs.h"
#include "xs_object_magic.h"

/**
 * Converts the given string to UTF-8 from UCS-2 big endian and sticks it in
 * a SV. The return value must be freed after use.
 *
 */
SV *convert_ucs2_to_utf8(xcb_char2b_t *text, size_t num_glyphs);

/**
 * Converts the given string to UCS-2 big endian for use with
 * xcb_image_text_16(). The amount of real glyphs is stored in real_strlen,
 * a buffer containing the UCS-2 encoded string (16 bit per glyph) is
 * returned. It has to be freed when done.
 *
 */
xcb_char2b_t *convert_SV_to_ucs2(SV *input, size_t *real_strlen);

__
	print map {decl($_).";\n"} @typenames;
}
if('h'eq$ARGV[0]){h;}elsif('c'eq$ARGV[0]){c;}else{die $ARGV[0]}
