#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#ifdef XS_VERSION
#undef XS_VERSION
#endif
#define XS_VERSION "1.102"

#define BASE 36
#define TMIN 1
#define TMAX 26
#define SKEW 38
#define DAMP 700
#define INITIAL_BIAS 72
#define INITIAL_N 128

#define isBASE(x) UTF8_IS_INVARIANT((unsigned char)x)
#define DELIM '-'

#define TMIN_MAX(t)  (((t) < TMIN) ? (TMIN) : ((t) > TMAX) ? (TMAX) : (t))

#ifndef utf8_to_uvchr_buf
#define utf8_to_uvchr_buf(in_p,in_e,u8) utf8_to_uvchr(in_p,u8);
#endif

static char enc_digit[BASE] = {
  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
  'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
};

static IV dec_digit[0x80] = {
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 00..0F */
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 10..1F */
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 20..2F */
  26, 27, 28, 29, 30, 31, 32, 33, 34, 35, -1, -1, -1, -1, -1, -1, /* 30..3F */
  -1,  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, /* 40..4F */
  15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, -1, -1, -1, -1, -1, /* 50..5F */
  -1,  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, /* 60..6F */
  15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, -1, -1, -1, -1, -1, /* 70..7F */
};

static int adapt(int delta, int numpoints, int first) {
  int k;

  delta /= first ? DAMP : 2;
  delta += delta/numpoints;

  for(k=0; delta > ((BASE-TMIN) * TMAX)/2; k += BASE)
    delta /= BASE-TMIN;

  return k + (((BASE-TMIN+1) * delta) / (delta+SKEW));
};

static void
grow_string(SV *const sv, char **start, char **current, char **end, STRLEN add)
{
  STRLEN len;

  if(*current + add <= *end)
    return;

  len = (*current - *start);
  *start = SvGROW(sv, (len + add + 15) & ~15);
  *current = *start + len;
  *end = *start + SvLEN(sv);
}

MODULE = Net::IDN::Punycode PACKAGE = Net::IDN::Punycode

SV*
encode_punycode(input)
		SV * input
	PREINIT:
		UV c, m, n = INITIAL_N;
		int k, q, t;
		int bias = INITIAL_BIAS;
		int delta = 0, skip_delta;

		const char *in_s, *in_p, *in_e, *skip_p;
 		char *re_s, *re_p, *re_e;
		int first = 1;
		STRLEN length_guess, len, h, u8;

	CODE:
		in_s = in_p = SvPVutf8(input, len);
		in_e = in_s + len;

		length_guess = len;
		if(length_guess < 64) length_guess = 64;	/* optimise for maximum length of domain names */
		length_guess += 2;				/* plus DELIM + '\0' */

		RETVAL = NEWSV('P',length_guess);
		SvPOK_only(RETVAL);
		re_s = re_p = SvPV_nolen(RETVAL);
		re_e = re_s + SvLEN(RETVAL);
		h = 0;

		/* copy basic code points */
		while(in_p < in_e) {
		  if( isBASE(*in_p) )  {
                    grow_string(RETVAL, &re_s, &re_p, &re_e, sizeof(char));
		    *re_p++ = *in_p;
		    h++;
		  }
		  in_p++;
		}

		/* add DELIM if needed */
		if(h) {
                  grow_string(RETVAL, &re_s, &re_p, &re_e, sizeof(char));
		  *re_p++ = DELIM;
		}

		for(;;) {
		  /* find smallest code point not yet handled */
		  m = UV_MAX;
		  q = skip_delta = 0;

		  for(in_p = skip_p = in_s; in_p < in_e;) {
		    c = utf8_to_uvchr_buf((U8*)in_p, (U8*)in_e, &u8);
		    c = NATIVE_TO_UNI(c);

		    if(c >= n && c < m) {
 		      m = c;
		      skip_p = in_p;
		      skip_delta = q;
		    }
		    if(c < n)
		      ++q;
		    in_p += u8;
		  }
		  if(m == UV_MAX)
		    break;

		  /* increase delta to the state corresponding to
		     the m code point at the beginning of the string */
		  delta += (m-n) * (h+1);
		  n = m;

		  /* now find the chars to be encoded in this round */

		  delta += skip_delta;
		  for(in_p = skip_p; in_p < in_e;) {
		    c = utf8_to_uvchr_buf((U8*)in_p, (U8*)in_e, &u8);
		    c = NATIVE_TO_UNI(c);

		    if(c < n) {
		      ++delta;
                    } else if( c == n ) {
		      q = delta;

		      for(k = BASE;; k += BASE) {
			t = TMIN_MAX(k - bias);
			if(q < t) break;
		        grow_string(RETVAL, &re_s, &re_p, &re_e, sizeof(char));
			*re_p++ = enc_digit[t + ((q-t) % (BASE-t))];
		        q = (q-t) / (BASE-t);
  		      }
		      if(q > BASE) croak("input exceeds punycode limit");
		      grow_string(RETVAL, &re_s, &re_p, &re_e, sizeof(char));
	              *re_p++ = enc_digit[q];
		      bias = adapt(delta, h+1, first);
                      delta = first = 0;
		      ++h;
                    }
		    in_p += u8;
		  }
		  ++delta;
		  ++n;
		}
		grow_string(RETVAL, &re_s, &re_p, &re_e, sizeof(char));
		*re_p = 0;
		SvCUR_set(RETVAL, re_p - re_s);
	OUTPUT:
		RETVAL

SV*
decode_punycode(input)
		SV * input
	PREINIT:
		UV c, n = INITIAL_N;
		IV dc;
		int i = 0, oldi, j, k, t, w;

		int bias = INITIAL_BIAS;
		int delta = 0, skip_delta;

		const char *in_s, *in_p, *in_e, *skip_p;
		char *re_s, *re_p, *re_e;
		int first = 1;
		STRLEN length_guess, len, h, u8;

	CODE:
		in_s = in_p = SvPV_nolen(input);
		in_e = SvEND(input);

		length_guess = SvCUR(input) * 2;
		if(length_guess < 256) length_guess = 256;

		RETVAL = NEWSV('D',length_guess);
		SvPOK_only(RETVAL);
		re_s = re_p = SvPV_nolen(RETVAL);
		re_e = re_s + SvLEN(RETVAL);

		skip_p = NULL;
		for(in_p = in_s; in_p < in_e; in_p++) {
		  c = *in_p;					/* we don't care whether it's UTF-8 */
		  if(!isBASE(c)) croak("non-base character in input for decode_punycode");
		  if(c == DELIM) skip_p = in_p;
		  grow_string(RETVAL, &re_s, &re_p, &re_e, 1);
		  *re_p++ = c;					/* copy it */
		}

		if(skip_p) {
		  h = skip_p - in_s;				/* base chars handled */
		  re_p = re_s + h;				/* points to end of base chars */
		  skip_p++;					/* skip over DELIM */
                } else {
		  h = 0;					/* no base chars */
		  re_p = re_s;
		  skip_p = in_s;				/* read everything */
		}

		for(in_p = skip_p; in_p < in_e; i++) {
		  oldi = i;
		  w = 1;

	          for(k = BASE;; k+= BASE) {
		    if(!(in_p < in_e)) croak("incomplete encoded code point in decode_punycode");
		    dc = dec_digit[*in_p++];			/* we already know it's in 0..127 */
		    if(dc < 0) croak("invalid digit in input for decode_punycode");
		    c = (UV)dc;
		    i += c * w;
		    t = TMIN_MAX(k - bias);
		    if(c < t) break;
		    w *= BASE-t;
		  }
		  h++;
		  bias = adapt(i-oldi, h, first);
		  first = 0;
		  n += i / h;					/* code point n to insert */
	          i = i % h;					/* at position i */

		  u8 = UNISKIP(n);				/* how many bytes we need */

		  j = i;
		  for(skip_p = re_s; j > 0; j--) 		/* find position in UTF-8 */
		    skip_p+=UTF8SKIP(skip_p);

		  grow_string(RETVAL, &re_s, &re_p, &re_e, u8);
		  if(skip_p < re_p)				/* move succeeding chars */
		    Move(skip_p, skip_p + u8, re_p - skip_p, char);
		  re_p += u8;
		  uvuni_to_utf8_flags((U8*)skip_p, n, UNICODE_ALLOW_ANY);
		}

		if(!first) SvUTF8_on(RETVAL);			/* UTF-8 chars have been inserted */
		grow_string(RETVAL, &re_s, &re_p, &re_e, 1);
		*re_p = 0;
		SvCUR_set(RETVAL, re_p - re_s);
	OUTPUT:
		RETVAL
