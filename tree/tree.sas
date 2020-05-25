/*  (c) Karol Przanowski   */
/*    kprzan@sgh.waw.pl    */




libname t (wyj);
%let kat_tree=%sysfunc(pathname(wyj));
%put &kat_tree;

/**/
/*proc sql noprint;*/
/*	select upcase(zmienna) */
/*	into :zmienne_int_ord separated by ' '*/
/*	from &em_data_variableset */
/*	where typ in ('ord','int');*/
/*quit;*/
/*%let il_zm=&sqlobs;*/
/**/
/**/
/*%put ***&il_zm***&zmienne_int_ord;*/


data _null_;
	set &zb(obs=1 keep=&tar) nobs=il;
	min_il=int(&min_percent*il/100); /*minimalny % obserwacji w lisciu to 5%*/
	call symput('min_il',trim(put(min_il,best12.-L)));
run;
%put &min_il;
/*%let min_il=2000;*/
/*kyterium albo h albo g;*/
%let crit=h;



%macro zrob_podz(zm);
	/*obcinanie skrajnych*/
	%let cent=1;
	%let dop=%eval(100-&cent);

	data zzm;
		set &zb(keep=&tar &zm);
	run;

	proc means data=zzm nway noprint;
		var &zm;
		output out=cen p&cent=p1 p&dop=p99;
	run;
	data _null_;
		set cen;
		call symput("p1",put(p1,best12.));
		call symput("p99",put(p99,best12.));
	run;
	%put ***&p1***&p99***;

	proc means data=zzm nway noprint;
		class &zm;
		var &tar;
		output out=t.stat(drop= _freq_ _type_) sum()=sum n()=n;
	run;

	/*Tu w tym zbiorze bed� li�cie*/
	data t.warunki;
		length g_l g_p war $300 zmienna $32;
		g_l='low'; g_p='high'; criterion=0; dzielic=1;nrobs=1;glebokosc=1;
		length  il_jed_at il_at 8;
		war="not missing(&zm)";
		zmienna="&zm";
	run;

%macro krok(nr_war);
	proc sql noprint;
		select war,criterion 
		into :war,:c 
		from t.warunki(obs=&nr_war firstobs=&nr_war);

		%let zb_krok=t.stat(where=(&war));

		select 
			sum(n) as il,
			sum(sum) as il_jed, 
			calculated il - calculated il_jed
		into :il,:il_jed,:il_zer
		from &zb_krok;
	quit;
	%put &il;
	%put &war;
	%global jest;
	%let jest=.;
	data krok;
		retain il_zer &il_zer il_jed &il_jed il &il;
		retain max_h max_g -10;
		retain max_h_v max_g_v;
		retain max_g_poww max_g_pon max_h_poww max_h_pon;
		retain 
		opt_g_il_jed_poww 
		opt_g_il_jed_pon  
		opt_g_il_poww     
		opt_g_il_pon      

		opt_h_il_jed_poww 
		opt_h_il_jed_pon  
		opt_h_il_poww     
		opt_h_il_pon
		;

		set &zb_krok end=e;

		cum_sum+sum;
		cum_n+n;
		il_jed_poww=cum_sum;
		il_jed_pon=il_jed-cum_sum;
		il_zer_poww=cum_n-cum_sum;
		il_zer_pon=il_zer-il_zer_poww;
		il_poww=cum_n;
		il_pon=il-cum_n;

		g_poww=(1-((il_jed_poww/il_poww)**2+(il_zer_poww/il_poww)**2));
		g_pon=(1-((il_jed_pon/il_pon)**2+(il_zer_pon/il_pon)**2));
		g=1-((il_jed/il)**2+(il_zer/il)**2)
		-g_poww*il_poww/il
		-g_pon*il_pon/il;

		h_poww=-((il_jed_poww/il_poww)*log2(il_jed_poww/il_poww)+(il_zer_poww/il_poww)*log2(il_zer_poww/il_poww));
		h_pon=-((il_jed_pon/il_pon)*log2(il_jed_pon/il_pon)+(il_zer_pon/il_pon)*log2(il_zer_pon/il_pon));
		h=-((il_jed/il)*log2(il_jed/il)+(il_zer/il)*log2(il_zer/il))     
		-h_poww*il_poww/il
		-h_pon*il_pon/il;


		if il_poww<&min_il or il_pon<&min_il then do;
			h=.;
			g=.;
		end;


		if h>max_h and h ne . then do;
			max_h=h;
			max_h_v=&zm;
			max_h_poww=h_poww;
			max_h_pon=h_pon;

			opt_h_il_jed_poww =il_jed_poww ;
			opt_h_il_jed_pon  =il_jed_pon  ;
			opt_h_il_poww     =il_poww     ;
			opt_h_il_pon      =il_pon      ;

		end;

		if g>max_g and g ne . then do;
			max_g=g;
			max_g_v=&zm;
			max_g_poww=g_poww;
			max_g_pon=g_pon;

			opt_g_il_jed_poww =il_jed_poww ;
			opt_g_il_jed_pon  =il_jed_pon  ;
			opt_g_il_poww     =il_poww     ;
			opt_g_il_pon      =il_pon      ;

		end;

		if _error_=1 then _error_=0;

		if e;

		if max_&crit._v eq . then call symput('jest','.');
		else do;
			if max_&crit._poww>=&c or max_&crit._pon>=&c then call symput('jest','ok');
			else call symput('jest','.');
		end;
		keep max_h_v max_g_v max_g_poww max_g_pon max_h_poww max_h_pon
		opt_g_il_jed_poww 
		opt_g_il_jed_pon  
		opt_g_il_poww     
		opt_g_il_pon      

		opt_h_il_jed_poww 
		opt_h_il_jed_pon  
		opt_h_il_poww     
		opt_h_il_pon
		;
	run;
	%put jest***&jest;

	%if "&jest" ne "." %then %do; 
	/*%if "&jest" ne ".           " %then %do; */

	data t.warunki;
		length prawy $300;
		obs=&nr_war;
		modify t.warunki point=obs;
		prawy=g_p;
		set krok;
		g_p=put(max_&crit._v,best12.-L);
		criterion=max_&crit._poww;
		if g_l ne 'low' then war=trim(g_l)||" < &zm <= "||trim(g_p);
		else war="not missing(&zm) and &zm <= "||trim(g_p);
		dzielic=1;
		glebokosc=glebokosc/2;

		il_jed_at=opt_&crit._il_jed_poww;
		il_at=opt_&crit._il_poww;

		replace;
		g_l=put(max_&crit._v,best12.-L);
		g_p=trim(prawy);
		criterion=max_&crit._pon;
		if g_p ne 'high' then war=trim(g_l)||" < &zm <= "||trim(g_p);
		else war=trim(g_l)||" < &zm ";
		dzielic=1;
		nrobs=nrobs+0.5;

		il_jed_at=opt_&crit._il_jed_pon;
		il_at=opt_&crit._il_pon;

		output;
		stop;
	run;

	proc sort data=t.warunki;
		by nrobs;
	run;

	data t.warunki;
		modify t.warunki;
		nrobs=_n_;
		replace;
	run;

	%end; %else %do;
	data t.warunki;
	obs=&nr_war;
	modify t.warunki point=obs;
	dzielic=0;
	replace;
	stop;
	run;
	%end;

%mend krok;

%macro podzialy;
	%do i=1 %to &max_il_podz;

		%let nr_war=pusty;
		proc sql noprint;
			select nrobs 
			into :nr_war
			from t.warunki
			where dzielic=1
			order by glebokosc desc, criterion;
		quit;
		%if "&nr_war" ne "pusty" %then %do;
			%krok(&nr_war);
		%end;

	%end;
%mend podzialy;
%podzialy;
%mend;


%macro dla_wszystkich_zm;


data t.podzialy;
length g_l g_p war $300 zmienna $32;
g_l='low'; g_p='high'; criterion=0; dzielic=1;nrobs=1;glebokosc=1;
length  il_jed_at il_at 8;
delete;
run;

/*%do nr_zm=1 %to 1;*/
%do nr_zm=1 %to &il_zm;


%zrob_podz(%upcase(%scan(&zmienne_int_ord,&nr_zm,%str( ))));

proc append base=t.podzialy data=t.warunki;
run;
%end;

%mend;



%dla_wszystkich_zm;



data t.podzialy_int_niem;
set t.podzialy;
keep zmienna war nrobs;
rename nrobs=grp;
run;
