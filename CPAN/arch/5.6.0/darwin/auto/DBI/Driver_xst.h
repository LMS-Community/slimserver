/*
#  $Id: Driver_xst.h,v 1.2 2004/12/11 23:51:01 vidur Exp $
#  Copyright (c) 2002  Tim Bunce  Ireland
#
#  You may distribute under the terms of either the GNU General Public
#  License or the Artistic License, as specified in the Perl README file.
*/

static SV *
dbixst_bounce_method(char *methname, int params)
{
    /* XXX this 'magic' undoes the dMARK embedded in the dXSARGS of our caller	*/
    /* so that the dXSARGS below can set things up as they were for our caller	*/
    void *xxx = PL_markstack_ptr++;
    dXSARGS; /* declares sp, ax, mark, items */
    int i;
    SV *sv;
    int debug = 0;
    D_imp_xxh(ST(0));
    if (debug >= 3) {
	PerlIO_printf(DBIc_LOGPIO(imp_xxh),
	    "    -> %s (trampoline call with %d (%ld) params)\n", methname, params, (long)items);
	xxx = xxx; /* avoid unused var warning */
    }
    EXTEND(SP, params);
    PUSHMARK(SP);
    for (i=0; i < params; ++i) {
	sv = (i >= items) ? &sv_undef : ST(i);
        PUSHs(sv);
    }
    PUTBACK;
    i = perl_call_method(methname, G_SCALAR);
    SPAGAIN;
    sv = (i) ? POPs : &sv_undef;
    PUTBACK;
    if (debug >= 3)
	PerlIO_printf(DBIc_LOGPIO(imp_xxh),
	    "    <- %s= %s (trampoline call return)\n", methname, neatsvpv(sv,0));
    return sv;
}


static int
dbdxst_bind_params(SV *sth, imp_sth_t *imp_sth, I32 items, I32 ax)
{
    /* Handle binding supplied values to placeholders.		*/
    /* items = one greater than the number of params		*/
    /* ax = ax from calling sub, maybe adjusted to match items	*/
    int i;
    SV *idx;
    if (items-1 != DBIc_NUM_PARAMS(imp_sth)
	&& DBIc_NUM_PARAMS(imp_sth) != DBIc_NUM_PARAMS_AT_EXECUTE
    ) {
	char errmsg[99];
	sprintf(errmsg,"called with %d bind variables when %d are needed",
		(int)items-1, DBIc_NUM_PARAMS(imp_sth));
	sv_setpv(DBIc_ERRSTR(imp_sth), errmsg);
	sv_setiv(DBIc_ERR(imp_sth), (IV)-1);
	return 0;
    }
    idx = sv_2mortal(newSViv(0));
    for(i=1; i < items ; ++i) {
	SV* value = ST(i);
	if (SvGMAGICAL(value))
	    mg_get(value);	/* trigger magic to FETCH the value     */
	sv_setiv(idx, i);
	if (!dbd_bind_ph(sth, imp_sth, idx, value, 0, Nullsv, FALSE, 0)) {
	    return 0;	/* dbd_bind_ph already registered error	*/
	}
    }
    return 1;
}

#ifndef dbd_fetchall_arrayref
static SV *
dbdxst_fetchall_arrayref(SV *sth, SV *slice, SV *batch_row_count)
{
    D_imp_sth(sth);
    SV *rows_rvav;
    if (SvOK(slice)) {  /* should never get here */
	char errmsg[99];
	sprintf(errmsg,"slice param not supported by XS version of fetchall_arrayref");
	sv_setpv(DBIc_ERRSTR(imp_sth), errmsg);
	sv_setiv(DBIc_ERR(imp_sth), (IV)-1);
	return &sv_undef;
    }
    else {
	IV maxrows = SvOK(batch_row_count) ? SvIV(batch_row_count) : -1;
	AV *fetched_av;
	AV *rows_av = newAV();
	if ( !DBIc_ACTIVE(imp_sth) && maxrows>0 ) {
	    /* to simplify application logic we return undef without an error	*/
	    /* if we've fetched all the rows and called with a batch_row_count	*/
	    return &sv_undef;
	}
	av_extend(rows_av, (maxrows>0) ? maxrows : 31);
	while ( (maxrows < 0 || maxrows-- > 0)
	    && (fetched_av = dbd_st_fetch(sth, imp_sth))
	) {
	    AV *copy_row_av = av_make(AvFILL(fetched_av)+1, AvARRAY(fetched_av));
	    av_push(rows_av, newRV_noinc((SV*)copy_row_av));
	}
	rows_rvav = sv_2mortal(newRV_noinc((SV *)rows_av));
    }
    return rows_rvav;
}
#endif

