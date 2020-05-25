/*algorytm tree tworzenia kategoryzacji zmiennych ci¹g³ych wzglêdem zmiennej*/
/*(c) Karol Przanowski*/
/*kprzan@sgh.waw.pl*/

options compress=yes;

%let dir=C:\Users\arybak002\Desktop\sas projekt\SAS_projekt\Projekt_final\tree\;
%let dir_projekt=C:\Users\arybak002\Desktop\sas projekt\SAS_projekt\Projekt_final\dane\;

libname wej "&dir_projekt" compress=yes;
libname wyj "&dir.wyj" compress=yes;

%let zb=wyj.vin;
%let tar=vin3;

%let zmienne_int_ord = &nazwy_zmiennych;/*przekazujemy zmienne numeryczne*/
%let il_zm= &liczba_zmiennych;/*liczba zmiennych numerycznych*/

%put ***&il_zm***&zmienne_int_ord;

/*stworzenie zbioru do analiz*/
data vin0;
set wej.Transactions;
seniority=intck('month',input(fin_period,yymmn6.),input(period,yymmn6.));
vin3=(due_installments>=&due);/*do wyboru: mozliwe wartosci due = 1, 2, 3*/
output;
if status in ('B','C') and period<='200812' then do;
	n_steps=intck('month',input(period,yymmn6.),input('200812',yymmn6.));
	do i=1 to n_steps;
		period=put(intnx('month',input(period,yymmn6.),1,'end'),yymmn6.);
		seniority=intck('month',input(fin_period,yymmn6.),input(period,yymmn6.));
		output;
	end;
end;
where product=&produkt;/*do wyboru produkt: css, ins albo razem*/
keep vin3 seniority aid;
run;
data vin12_sample(drop=seniority);
set vin0;
where seniority=12;
run;
proc sort data=vin12_sample nodupkey;
by aid;
run;
proc sort data=wej.Production(keep=aid &zmienne_int_ord) out=prod nodupkey;
by aid;
run;
data &zb;
merge vin12_sample(in=z) prod;
by aid;
if z;
run;
/*stworzenie zbioru do analiz*/

/*maksymalna liczba podzia³ów minus 1, 
decyzja na maksymalnie 3 kategorie zmiennej numerycznej*/
%let max_il_podz=2;
/*minimalna liczba obserwacji w liœciu, minimalnie 5% */
%let min_percent=5;
%include "&dir.tree.sas" / source2;

/*analizowaæ zbiór wynikowy:*/
/*wyj.Podzialy_int_niem*/
