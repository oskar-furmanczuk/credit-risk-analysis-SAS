/*Spis treœci*/
/*- Stworzenie tabeli ze zmiennymi z transactions i dodatkowo kwot¹ raty*/
/*- Ustalenie statystyki vin3 (zero-jedynkowej) i zmiennej kwota do obliczenia vintage kwotowego*/
/*- Obliczenie vintage3 i production dla ca³ego portfela*/
/*- Transpozycja vintage iloœciowego i kwotowego*/
/*- Predykcja*/
/*- Tworzenie wykresów*/
/*- Okreœlenie makrozmiennych*/

libname wej "C:\Users\arybak002\Desktop\sas projekt\zipek 2\SAS_projekt\Projekt_final";

/*makro dla produktu 'ins', 'css' lub razem, dla due(1,2,3)*/
%macro raportowanie(produkt, due);

/***OBLICZANIE VINTAGE***/

/*Stworzenie tabeli ze zmiennymi z transactions i dodatkowo kwot¹ raty */
proc sql;
create table tabela_vintage as select 
p.app_loan_amount, t.product, t.period, t.fin_period, t.status, 
t.due_installments, t.paid_installments, t.leftn_installments, t.aid
from wej.Production p
join wej.Transactions t
on p.aid=t.aid;
quit;

	/*Ustalenie statystyki vin3 (zero-jedynkowej) i zmiennej kwota do obliczenia vintage kwotowego*/
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
	
		/*obliczenie vintage dla ca³ego portfela - linie na wykresach przedstawiaj¹ce odsetek kredytów z niesp³acanymi ratami*/
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
	
		/*Vintage iloœciowy*/

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

		/*Vintage kwotowy*/
		
		/*dla ca³ego portfela*/
		proc transpose data=vintagr out=vintage_kwot(drop=_name_) prefix=months_after_;
		by fin_period;
		var kwotowo;
		id seniority;
		run;

	/*tabela wejœciowa do predykcji*/
	proc sql;
	create table vin_pre_kwot as select *
	from work.vintage_kwot x
	join work.production y
	on x.fin_period=y.fin_period;
	quit;

/*PREDYKCJA*/

%macro predykcja(tabela_pre);

			/*dodanie kolumny z liczb¹ porz¹dkow¹ umo¿liwiaj¹c¹ ³¹czenie tabel z oszacowaniami*/
			data &tabela_pre;
			set &tabela_pre;
			liczba = _n_;
			run;

	/*prognoza wartoœci vintage dla ca³ego portfela*/
	proc arima data=&tabela_pre;
	identify var=months_after_12 crosscorr=production noprint; /*corsscorr - wspó³czynik autokorelacji*/
	estimate p=(4) q=(3) input=production noprint maxiter=200; /*maksymalna liczba iteracji*/
	forecast lead=12 id=liczba out=oszacowanie noprint;/*lead - liczba oszacowanych obserwacji*/
	run;
	quit;

	/*zbiór prognoza - po³¹czenie danych z oszacowaniami*/
	data oszacowanie;
	set oszacowanie;
	if _n_ < 24 then predykcja = .;
	else if _n_ = 24 then predykcja = months_after_12;
	else if _n_ > 24 then predykcja = FORECAST;
	format predykcja nlpct12.2;
	keep liczba predykcja;
	run;

			/*dane do wykresów*/
			proc sql;
			create table vin_f_&tabela_pre as select *
			from work.&tabela_pre x
			join work.oszacowanie y
			on x.liczba=y.liczba;
			quit;

%mend predykcja;

%predykcja(vin_pre);
%predykcja(vin_pre_kwot);

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
ods pdf	file="C:\Users\arybak002\Desktop\sas projekt\zipek 2\SAS_projekt\Projekt_final\Wykresiki by Marta";
	
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
