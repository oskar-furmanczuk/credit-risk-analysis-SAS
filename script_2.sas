/*Spis treœci
*warstwa zbiorcza:
makro raportowanie
	makro predict (prognoza)
	makro maksimum wykresu

*warstwa zmienncyh
makro raportowanie
	makro najlepsze_zmienne - kategoryzacja
		makro oblicz wspó³zale¿noœæ - Cramer (potrzeba vin3)
			makro kategoryzacja zmiennych
				makro tree
	makro wynik 
		marko wykresy
			makro prognoza
			makro maksimum wykresu
		makro rysuj
makro zapisz*/

libname wej "C:\Projekt\dane\";
libname wyj "C:\Projekt\tree\wyj\";
libname kat "C:\Projekt\tree\wyj\";

/*KOD DLA WARSTWY ZBIORCZEJ*/
/*zmienna vintage (zero-jedynkowe) zale¿na jest od: 
					m_prod - miesi¹c w którym wszystkie kredyty uruchomiono 
					m - liczba miesiêcy po uruchomieniu
					due - min. liczba opóŸnionych rat ustalana przez nas na poziomie 1,2,3
		ostatecznie otrzymujemy 3 zmienne vin: vin1, vin2, vin3*/
/*ins - kredyt ratalny
css - kredyt gotowkowy*/

/*Makro dla produktu 'ins', 'css' lub razem, dla due(1,2,3)*/
%macro raportowanie(produkt, due);

/*OBLICZANIE VINTAGE*/

proc sql;
create table tabela_vintage as select 
p.app_loan_amount, t.product, t.period, t.fin_period, t.status, 
t.due_installments, t.paid_installments, t.leftn_installments, t.aid
from wej.Production p
join wej.Transactions t
on p.aid=t.aid;
quit;

	data vin;
	set tabela_vintage;
	seniority=intck('month',input(fin_period,yymmn6.),input(period,yymmn6.));
	vin3=(due_installments>=&due);
	kwota = vin3*app_loan_amount;/*zmienna do obliczenia vintage kwotowo*/
	output;
		if status in ('B','C') and period<='200812' then do;
		n_steps=intck('month',input(period,yymmn6.),input('200812',yymmn6.));
		do i=1 to n_steps;
		period=put(intnx('month',input(period,yymmn6.),1,'end'),yymmn6.);
		seniority=intck('month',input(fin_period,yymmn6.),input(period,yymmn6.));
		output;
		end;
	end;
	where product=&produkt;/*wybieramy produkt*/
	keep app_loan_amount aid fin_period vin3 seniority kwota;/*tylko potrzebne zmienne*/
	run;
	
		/*obliczenie vintage dla ca³ego portfela*/
		proc means data=vin noprint nway;
		class fin_period seniority;
		var vin3;
		output out=vintagr(drop=_freq_ _type_) n()=production mean()=vintage3 sum(kwota)=kwotowo;
		format vin3 nlpct12.2;
		run;

	/*produkcja dla ca³ego portfela - s³upki na wykresach*/
	proc means data=vin noprint nway;
	class fin_period;
	var vin3;
	output out=production(drop=_freq_ _type_) n()=production;
	where seniority = 0;
	run;
	
		/***VINTAGE ILOŒCIOWY***/

		/*dla ca³ego portfela*/
		proc transpose data=vintagr out=vintage(drop=_name_) prefix=months_after_;
		by fin_period;
		var vintage3;
		id seniority;
		run;

	/*tabela wejœciowa do predykcji*/
	proc sql;
	create table vin_pre as select *
	from work.vintage x
	join work.production y
	on x.fin_period=y.fin_period;
	quit;

		/***VINTAGE KWOTOWY***/
		
		/*dla ca³ego portfela*/
		proc transpose data=vintagr out=vintage_kwot(drop=_name_) prefix=months_after_;
		by fin_period;
		var kwotowo;
		id seniority;
		run;

	/*Tabela wejœciowa do predykcji*/
	proc sql;
	create table vin_pre_kwot as select *
	from work.vintage_kwot x
	join work.production y
	on x.fin_period=y.fin_period;
	quit;

/**Prognoza*/

%macro predict(tabela);

/*kolumna 'n' do póŸniejszego ³¹czenia tabel*/
data &tabela;
set &tabela;
liczba = _n_;
run;

/*oszacowanie vintage dla ca³ego portfela*/
proc arima data = &tabela;
identify var=months_after_12 crosscorr=production noprint;
estimate p=(4) q=(3) input=production noprint maxiter=200;
forecast lead=12 id=liczba out=oszacowanie noprint;/*lead - liczba oszacowanych obserwacji*/
run;
quit;

	data oszacowanie;
	set oszacowanie;
	if _n_ < 24 then predykcja = .;
	else if _n_ = 24 then predykcja = months_after_12;
	else if _n_ > 24 then predykcja = FORECAST;
	format predykcja nlpct12.2;
	keep liczba predykcja;
	run;

proc sql;
create table vin_f_&tabela as select *
from work.&tabela x
join work.oszacowanie y
on x.liczba=y.liczba;
quit;

%mend;

%predict(vin_pre);
%predict(vin_pre_kwot);

	/***TWORZENIE WYKRESU***/

	/*makro wyliczaj¹ce maksimum dla osi pionowej wykresu*/
	%macro maksimum_wykresu;

	proc means data=vin_f_vin_pre noprint;
	var production;
	output out=maksimum max=maksimum;
	run;

	data _null_;
	set maksimum;
	call symput("maks",maksimum);
	run;

	%let maks=%eval(&maks+100);

	%mend;

	%maksimum_wykresu;

/*ustawienia osi wykresu*/
axis1 order=(0 to &maks by 100) offset=(0) label=(a=90 h=11pt 'Liczba kredytów (produkcja)');
axis2 offset=(2) label=('Okres');
axis3 label=(a=90 h=11pt 'Vintage');

/*ustawienia dla s³upków*/
symbol1 bwidth=1.6 color=cream interpol=needle value=none w=12;
/*ustawienia dla krzywych*/
symbol2 color=red interpol=join value=dot line=1;
symbol3 color=blue interpol=join value=dot line=1;
symbol4 color=green interpol=join value=dot line=1;
symbol5 color=black interpol=join value=dot line=1;
symbol6 color=brown interpol=join value=dot line=2;/*dla predykcji*/

options nodate nonumber;

ods noresults;
ods pdf	file="C:\Projekt\wykresy\produkt_&produkt._due_&due..pdf";
	
	/***WYKRESY ILOŒCIOWE***/

	title "Vintage iloœciowy produktu &produkt dla due &due";

	proc gplot data=vin_f_vin_pre;
	plot  production*fin_period / overlay vaxis = axis1 haxis = axis2;
	plot2 months_after_3*fin_period 
		  months_after_6*fin_period
		  months_after_9*fin_period
		  months_after_12*fin_period
		  predykcja*fin_period / overlay vaxis = axis3;
	run;
	quit;

	/***WYKRESY KWOTOWE***/

	title "Vintage kwotowy produktu &produkt dla due &due";

	proc gplot data=vin_f_vin_pre_kwot;
	plot  production*fin_period / overlay vaxis = axis1 haxis = axis2;
	plot2 months_after_3*fin_period 
		  months_after_6*fin_period
		  months_after_9*fin_period
		  months_after_12*fin_period
		  predykcja*fin_period / overlay vaxis = axis3;
	run;
	quit;

ods pdf close;
ods results;

%mend;


%raportowanie('ins', 1);
%raportowanie('ins', 2);
%raportowanie('ins', 3);

%raportowanie('css', 1);
%raportowanie('css', 2);
%raportowanie('css', 3);

%raportowanie('ins' OR 'css', 1);
%raportowanie('ins' OR 'css', 2);
%raportowanie('ins' OR 'css', 3);


/*zmiana opcji - zapis do logu*/
proc printto;
run;

/*VINTAGE w zaleznosci od zmiennych*/

/*KATEGORYZACJA ZMIENNYCH*/

/*W pierwszym kroku kategoryzacja zmiennych: zmienne numeryczne skategoryzowane na podstawie algorytmu drzewa deycyzyjnego
wzgledem zmiennej vin w zaleznosci od prodkutu - 'ins', 'css' albo 'ins'&'css' oraz ze wzgledu na due (1,2,3)*/

/*Makro ze wzgledu na produkt 'ins', 'css' oraz due(1,2,3)*/
%macro raportowanie(produkt, due);

	/*Makro dla grup zmiennych app_, act_, ags, agr*/
	%macro najlepsze_zmienne(grupa);

	/*Zmienne numeryczne danej grupy, dokonanie ich kategoryzacji za pomoca drzewa decyzyjnego*/
	proc sql noprint;
	select name into :nazwy_zmiennych separated by ' '
	from dictionary.columns
	where libname='WEJ' and memname='PRODUCTION' and type='num' and name like ("&grupa" || '%');
	quit;

	/*Wyznaczona liczba zmiennych numerycznych, do kodu 'kategoryzacja_zmiennych'*/
	%let liczba_zmiennych=&sqlobs;

	/*kod do kategoryzacji
	Zmienne zostana podzielone ma maksymalnie 3 kategorie. 
	Zalozenia do drzewa deycyzjnego: minimalny udzial obserwacji w danym lisciu zostal ustalony na poziomie 5% */
	%include "C:\Projekt\tree\kategoryzacja_zmiennych.sas" / source2;

	/*Nieposortowana lista zmiennych z kategoriami*/
	proc sort data=wyj.podzialy_int_niem out=kategorie;
	by zmienna;
	run;
	
	/*Posortowana lista zmiennych z kategoriami ze wzgledu na zmienne*/
	proc transpose data=kategorie out=kategorie_f (drop=_name_);
	by zmienna;
	var war;
	run;

		/*Makro - obliczenia V-Cramera*/
		%macro oblicz_wspolzaleznosc;

		%do i=1 %to &liczba_zmiennych;

			data _null_;
			set kategorie_f (firstobs=&i obs=&i);
			call symput("zmienna",trim(zmienna));
			if missing(col2) then
				do;
					call symput("klasa1",trim(col1));
					call symput("klasa2",0);
					call symput("klasa3",0);
				end;
			else if missing(col3) then
				do;
					call symput("klasa1",trim(col1));
					call symput("klasa2",trim(col2));
					call symput("klasa3",0);
				end;
			else 
				do;
					call symput("klasa1",trim(col1));
					call symput("klasa2",trim(col2));
					call symput("klasa3",trim(col3));
				end;
			run;

			/*Tabela robocza przed przypisaniem kategorii*/
			proc sql;
			create table cramer1 as select x.&zmienna, y.vin3 
			from wej.production x
			join work.vin12_sample y
			on x.aid=y.aid;
			quit;

			/*Tabela z kategoriami, do obliczenia V-Cramera,
			gdy zmienna przyjmuje wartosc z 1 kategorii, wtedy 'A', gdy z 2 -'B', gdy z 3-'C'*/
			proc sql;		
			create table cramer2 as select *,
			case when &klasa1 then 'A'
				 when &klasa2 then 'B'
				 when &klasa3 then 'C'
				 else 'D' end 
			as klasa from cramer1;
			quit;
			
			/*obliczenie statystyki V-Cramera za pomoca procedury freq*/
			proc freq data=cramer2 noprint;
			tables vin3*klasa / chisq;
			output out=cramer cramv;
			run;
			
			/*Zapis obliczonej statystyki V-Cramera do makrozmiennej 'v'*/
			data _null_;
			set cramer;
			call symput("cramer",_cramv_);
			run;

			/*Wygenerowanie listy zmiennych z kategoriami (max 3) i statystykami V-Cramera*/
			data kategorie_f;
			set kategorie_f;
			if _n_=&i then cramer=&cramer;
			run;

		%end;

		/*Zapis danych */
		data wyj.&grupa._all;
		set kategorie_f;
		run;
		
		/*Sortowanie wedlug V-Cramera malejaco - im wyzsza statystyka, tym wyzsza zaleznosc z vin3*/
		proc sort data=wyj.&grupa._all;
		by descending cramer;
		run;
		
		/*Wybor i zapis 5 zmiennych o najwiekszej wspolzaleznosci z vin3*/
		data wyj.&grupa.5;
		set wyj.&grupa._all(obs=5);
		run;
		
		%mend;

	%oblicz_wspolzaleznosc;

%mend;

%najlepsze_zmienne(act_);
%najlepsze_zmienne(app_);
%najlepsze_zmienne(agr);
%najlepsze_zmienne(ags);


/***OBLICZANIE VINTAGE***/

%macro wynik(grupa_zmiennych);

/*zliczenie liczby zmiennych skategoryzowanych*/
data _null_;
set kat.&grupa_zmiennych nobs=n;
call symputx('nrows',trim(n));
run;

%do i=1 %to &nrows;

	data _null_;
	set kat.&grupa_zmiennych (firstobs=&i obs=&i);
	call symput("zmienna",trim(zmienna));
	if missing(col2) then
		do;
			n=1;
			call symput("klasa1",trim(col1));
			call symput("klasa2",0);
			call symput("klasa3",0);
		end;
	else if missing(col3) then
		do;
			n=2;
			call symput("klasa1",trim(col1));
			call symput("klasa2",trim(col2));
			call symput("klasa3",0);
		end;
	else do;
			n=3;
			call symput("klasa1",trim(col1));
			call symput("klasa2",trim(col2));
			call symput("klasa3",trim(col3));
		end;
	call symputx("n",trim(n));
	run;

proc sql;
create table polaczenie as select 
p.&zmienna, p.app_loan_amount, t.product, t.period, t.fin_period, t.status, 
t.due_installments, t.paid_installments, t.leftn_installments, t.aid
from wej.Production p
join wej.Transactions t
on p.aid=t.aid;
quit;

proc sql;	
create table tabela_vintage as select *,
case 	when &klasa1 then 'A'
		when &klasa2 then 'B'
		when &klasa3 then 'C'
		else 'D'
		end 
		as klasa from polaczenie;
quit;

	%macro wykresy(klasa_zmiennej,name);

	data vin;
	set tabela_vintage;
	seniority=intck('month',input(fin_period,yymmn6.),input(period,yymmn6.));
	vin3=(due_installments>=&due);
	kwota = vin3*app_loan_amount;/*zmienna do obliczenia vintage kwotowo*/
	output;
		if status in ('B','C') and period<='200812' then do;
		n_steps=intck('month',input(period,yymmn6.),input('200812',yymmn6.));
		do i=1 to n_steps;
		period=put(intnx('month',input(period,yymmn6.),1,'end'),yymmn6.);
		seniority=intck('month',input(fin_period,yymmn6.),input(period,yymmn6.));
		output;
		end;
	end;
	where product=&produkt;/*wybieramy produkt*/
	keep &zmienna app_loan_amount klasa aid fin_period vin3 seniority kwota;/*tylko potrzebne zmienne*/
	run;
	
		/*obliczenie vintage dla ca³ego portfela*/
		proc means data=vin noprint nway;
		class fin_period seniority;
		var vin3;
		output out=vintagr(drop=_freq_ _type_) n()=production mean()=vintage3 sum(kwota)=kwotowo;
		format vin3 nlpct12.2;
		run;
		
		/*obliczenie vintage dla kategorii*/
		proc means data=vin noprint nway;
		class fin_period seniority;
		var vin3;
		output out=vintagr_klasa(drop=_freq_ _type_) n()=production mean()=vintage3 sum(kwota)=kwotowo;
		format vin3 nlpct12.2;
		where klasa = &klasa_zmiennej;
		run;

	/*produkcja dla danej kategorii - s³upki na wykresach*/
	proc means data=vin noprint nway;
	class fin_period;
	var vin3;
	output out=production(drop=_freq_ _type_) n()=production;
	where seniority = 0 and klasa = &klasa_zmiennej;
	run;
	
/*Vintage iloœciowy*/

		/*transpozycja vintage iloœciowego dla ca³ego portfela*/
		proc transpose data=vintagr out=vintage(drop=_name_) prefix=months_after_;
		by fin_period;
		var vintage3;
		id seniority;
		run;

		/*transpozycja vintage iloœciowego dla danej klasy*/
		proc transpose data=vintagr_klasa out=vintage_klasa(drop=_name_) prefix=klasa_months_after_;
		by fin_period;
		var vintage3;
		id seniority;
		run;
		
		/*zbiór tylko ze zmiennymi dla 3 6 9 i 12 miesiêcy*/
		data vintage_klasa;
		set vintage_klasa;
		keep fin_period klasa_months_after_3 klasa_months_after_6 klasa_months_after_9 klasa_months_after_12;
		run;

			/*tabela wejœciowa do predykcji - po³¹czenie tabel vintage, production i vintage_klasa*/
			proc sql;
			create table vin_pre as 
			select *
			from work.vintage x
			join work.production y
			on x.fin_period=y.fin_period
			join work.vintage_klasa z
			on x.fin_period=z.fin_period;
			quit;

/*Vintage kwotowy*/
		
		/*transpozycja vintage kwotowego dla ca³ego portfela*/
		proc transpose data=vintagr out=vintage_kwot(drop=_name_) prefix=months_after_;
		by fin_period;
		var kwotowo;
		id seniority;
		run;

		/*transpozycja vintage kwotowego dla danej klasy*/
		proc transpose data=vintagr_klasa out=vintage_klasa_kwot(drop=_name_) prefix=klasa_months_after_;
		by fin_period;
		var kwotowo;
		id seniority;
		run;

		/*zbiór tylko ze zmiennymi dla 3 6 9 i 12 miesiêcy*/
		data vintage_klasa_kwot;
		set vintage_klasa_kwot;
		keep fin_period klasa_months_after_3 klasa_months_after_6 klasa_months_after_9 klasa_months_after_12;
		run;

			/*tabela wejœciowa do predykcji - po³¹czenie tabel vintage_kwot, production i vintage_klasa_kwot*/
			proc sql;
			create table vin_pre_kwot as 
			select *
			from work.vintage_kwot x
			join work.production y
			on x.fin_period=y.fin_period
			join work.vintage_klasa_kwot z
			on x.fin_period=z.fin_period;
			quit;

/*Prognoza*/

%macro prognoza(dane_pre);

			/*dodanie kolumny z liczb¹ porz¹dkow¹ umo¿liwiaj¹c¹ ³¹czenie tabel z oszacowaniami*/
			data &dane_pre;
			set &dane_pre;
			liczba=_n_;
			run;

	/*prognoza wartoœci vintage dla ca³ego portfela*/
	proc arima data=&dane_pre;
	identify var=months_after_12 crosscorr=production noprint;/*corsscorr - wspó³czynik autokorelacji*/
	estimate p=(4) q=(3) input=production noprint maxiter=200;/*maksymalna liczba iteracji*/
	forecast lead=12 id=liczba out=prognoza noprint;/*lead - liczba oszacowanych obserwacji*/
	run;
	quit;

			/*zbiór prognoza - po³¹czenie danych z oszacowaniami*/
			data prognoza;
			set prognoza;
			if _n_ < 24 then wart_prognozy = .;
			else if _n_ = 24 then wart_prognozy = months_after_12;
			else if _n_ > 24 then wart_prognozy = FORECAST;
			format wart_prognozy nlpct12.2;
			keep liczba wart_prognozy;
			run;

	/*prognoza wartoœci vintage dla danej kategorii*/
	proc arima data=&dane_pre;
	identify var=klasa_months_after_12 crosscorr=production noprint;
	estimate p=(4) q=(3) input=production noprint maxiter=200;
	forecast lead=12 id=liczba out=prognoza_2 noprint;
	run;
	quit;

			/*zbiór prognoza dla kategorii - po³¹czenie danych z oszacowaniami*/
			data prognoza_2;
			set prognoza_2;
			if _n_ < 24 then wart_prognozy_2 = .;
			else if _n_ = 24 then wart_prognozy_2 = klasa_months_after_12;
			else if _n_ > 24 then wart_prognozy_2 = FORECAST;
			format wart_prognozy_2 nlpct12.2;
			keep liczba wart_prognozy_2;
			run;

				/*dane do wykresów*/
				proc sql;
				create table vin_f_&dane_pre as select *
				from work.&dane_pre x
				join work.prognoza y
				on x.liczba=y.liczba
				join work.prognoza_2 z
				on x.liczba=z.liczba;
				quit;

%mend prognoza;

%prognoza(vin_pre);
%prognoza(vin_pre_kwot);


	/***TWORZENIE WYKRESU***/

	/*makro wyliczaj¹ce maksimum dla osi pionowej wykresu*/
	%macro maksimum_wykresu;

	proc means data=vin_f_vin_pre noprint;
	var production;
	output out=maksimum max=maksimum;
	run;

	data _null_;
	set maksimum;
	call symput("maks",maksimum);
	run;

	%let maks=%eval(&maks+50);

	%mend;

	%maksimum_wykresu;

		/***ALGORYTM WYBORU ISTOTNYCH WYNIKÓW***/

		proc means data=vin_f_vin_pre nway noprint;
		var klasa_months_after_3 months_after_3
			klasa_months_after_6 months_after_6
			klasa_months_after_9 months_after_9
			klasa_months_after_12 months_after_12;
			output out=stat;
		run;

		data stat;
		set stat;
		if  klasa_months_after_3 > months_after_3 and
			klasa_months_after_6 > months_after_6 and
			klasa_months_after_9 > months_after_9 and
			klasa_months_after_12 > months_after_12 and
			&maks >= 1000
		then indicator = 1;
		else indicator = 0;
		where _STAT_ = 'MEAN';
		call symputx("indicator",indicator);
		run;

		proc means data=vin_f_vin_pre_kwot nway noprint;
		var klasa_months_after_3 months_after_3
			klasa_months_after_6 months_after_6
			klasa_months_after_9 months_after_9
			klasa_months_after_12 months_after_12;
			output out=stat2;
		run;

		data stat2;
		set stat2;
		if  klasa_months_after_3 > months_after_3 and
			klasa_months_after_6 > months_after_6 and
			klasa_months_after_9 > months_after_9 and
			klasa_months_after_12 > months_after_12 and
			&maks >= 1000
		then indicator2 = 1;
		else indicator2 = 0;
		where _STAT_ = 'MEAN';
		call symputx("indicator2",indicator2);
		run;

/*ustawienia osi wykresu*/
axis1 order=(0 to &maks by 20) offset=(0) label=(a=90 h=11pt 'Liczba kredytów (produkcja)');
axis2 offset=(2) label=('Okres');
axis3 label=(a=90 h=11pt 'Vintage');

/*ustawienia dla s³upków*/
symbol1 bwidth=1.6 color=cream interpol=needle value=none w=12;
/*ustawienia dla krzywych*/
symbol2 color=red interpol=join value=dot line=1;
symbol3 color=blue interpol=join value=dot line=1;
symbol4 color=green interpol=join value=dot line=1;
symbol5 color=black interpol=join value=dot line=1;
symbol6 color=brown interpol=join value=dot line=2;/*dla predykcji*/
symbol7 color=red interpol=join value=dot line=3;
symbol8 color=blue interpol=join value=dot line=3;
symbol9 color=green interpol=join value=dot line=3;
symbol10 color=black interpol=join value=dot line=3;
symbol11 color=brown interpol=join value=dot line=5;/*dla predykcji*/

%let nazwapliku='&indicator._&indicator2._&zmienna._&klasa_zmiennej._&produkt._&due';

options nodate nonumber;

ods noresults;
ods pdf	file="C:\Projekt\wykresy\&nazwapliku..pdf";
	
	/***WYKRESY ILOŒCIOWE***/

	title "Vintage iloœciowy &name i produktu &produkt - porównanie z ryzykiem ca³ego portfela";

	proc gplot data=vin_f_vin_pre;
	plot  production*fin_period / overlay vaxis = axis1 haxis = axis2;
	plot2 months_after_3*fin_period 
		  months_after_6*fin_period
		  months_after_9*fin_period
		  months_after_12*fin_period
		  wart_prognozy*fin_period 
		  klasa_months_after_3*fin_period
		  klasa_months_after_6*fin_period
		  klasa_months_after_9*fin_period
		  klasa_months_after_12*fin_period
		  wart_prognozy_2*fin_period / overlay vaxis = axis3;
	run;
	quit;

	title "Vintage iloœciowy &name i produktu &produkt";

	proc gplot data=vin_f_vin_pre;
	plot  production*fin_period / overlay vaxis = axis1 haxis = axis2;
	plot2 klasa_months_after_3*fin_period
		  klasa_months_after_6*fin_period
		  klasa_months_after_9*fin_period
		  klasa_months_after_12*fin_period
		  wart_prognozy_2*fin_period / overlay vaxis = axis3;
	run;
	quit;

	title "Statystyki - Vintage iloœciowy";

	proc means data=vin_f_vin_pre nway;
	var klasa_months_after_3 months_after_3
		klasa_months_after_6 months_after_6
		klasa_months_after_9 months_after_9
		klasa_months_after_12 months_after_12;
	run;

	ods startpage=no;

	proc print data=stat;
	run;

	/***WYKRESY KWOTOWE***/

	title "Vintage kwotowy &name i produktu &produkt - porównanie z ryzykiem ca³ego portfela";

	proc gplot data=vin_f_vin_pre_kwot;
	plot  production*fin_period / overlay vaxis = axis1 haxis = axis2;
	plot2 months_after_3*fin_period 
		  months_after_6*fin_period
		  months_after_9*fin_period
		  months_after_12*fin_period
		  wart_prognozy*fin_period 
		  klasa_months_after_3*fin_period
		  klasa_months_after_6*fin_period
		  klasa_months_after_9*fin_period
		  klasa_months_after_12*fin_period
		  wart_prognozy_2*fin_period / overlay vaxis = axis3;
	run;
	quit;

	title "Vintage kwotowy &name i produktu &produkt";

	proc gplot data=vin_f_vin_pre_kwot;
	plot  production*fin_period / overlay vaxis = axis1 haxis = axis2;
	plot2 klasa_months_after_3*fin_period
		  klasa_months_after_6*fin_period
		  klasa_months_after_9*fin_period
		  klasa_months_after_12*fin_period
		  wart_prognozy_2*fin_period / overlay vaxis = axis3;
	run;
	quit;

	title "Statystyki - Vintage kwotowy";

	proc means data=vin_f_vin_pre_kwot nway;
	var klasa_months_after_3 months_after_3
		klasa_months_after_6 months_after_6
		klasa_months_after_9 months_after_9
		klasa_months_after_12 months_after_12;
	run;

	ods startpage=no;

	proc print data=stat2;
	run;

ods pdf close;
ods results;

%mend;
	
		/*ograniczenia narzucone liczb¹ kategorii*/
		%macro rysuj(ile);

		%if &ile=1 %then %do;
			%wykresy('A', &klasa1);
			%end;
		%else %if &ile=2 %then %do;
			%wykresy('A', &klasa1);
			%wykresy('B', &klasa2);
			%end;
		%else %if &ile=3 %then %do;
			%wykresy('A', &klasa1);
			%wykresy('B', &klasa2);
			%wykresy('C', &klasa3);
			%end;

		%mend;

	%rysuj(&n);

%end;

%mend;

%wynik(act_5);
%wynik(app_5);
%wynik(ags5);
%wynik(agr5);

%mend;

/*zapis listy najlepszych zmiennych do pdf*/
%macro zapisz(tekst);

options nodate nonumber;

ods noresults;
ods html path="C:\Projekt\raporty" (url=none) file="Raport dla &tekst..html" style = theme;

	proc print data=wyj.act_5;
	title 'Zmienne z grupy act_ o najwiekszej wspolzaleznosci ze zmienna vin3';
	run;
	
	ods startpage=no;

	proc print data=wyj.agr5;
	title 'Zmienne z grupy agr_ o najwiekszej wspolzaleznosci ze zmienna vin3';
	run;
	
	ods startpage=yes;

	proc print data=wyj.ags5;
	title 'Zmienne z grupy ags o najwiekszej wspolzaleznosci ze zmienna vin3';
	run;

	ods startpage=no;

	proc print data=wyj.app_5;
	title 'Zmienne z grupy app o najwiekszej wspolzaleznosci ze zmienna vin3';
	run;

ods html close;
ods results;

%mend;


/*realizacja*/


%raportowanie('ins',1);
%zapisz('ins1');
%raportowanie('ins',2);
%zapisz('ins2');
%raportowanie('ins',3);
%zapisz('ins3');


%raportowanie('css',1);
%zapisz('css1');
%raportowanie('css',2);
%zapisz('css2');
%raportowanie('css',3);
%zapisz('css3');


%raportowanie('ins' OR 'css',1);
%zapisz('inscss1');
%raportowanie('ins' OR 'css',2);
%zapisz('inscss2');
%raportowanie('ins' OR 'css',3);
%zapisz('inscss3');


/*zmiana opcji - zapis do logu*/
proc printto;
run;
