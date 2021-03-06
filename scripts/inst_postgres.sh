#!/bin/bash
#set -x
function writeln()
{
   tput cup $1 $2  # Cursor positionieren
   tput el         # Rest der Zeile löschen
   shift 2         # Parameter für die Koordinaten entfernen
   echo -n $*" "   # Rest der Parameterliste ausgeben
}

tput clear

#Als root anmelden
if [ `id -u` -gt 0 ]; then echo "Bitte als root anmelden"; exit 1; fi

writeln 1 1 PostgreSQL fuer Lx-Office vorbereiten
writeln 2 1 1. plpgsql.so suchen
PLPGSQL=""
#Datei plpgsql.so suchen

POSTGRESQL=`dpkg -l | grep -E "postgresql-[0-9]" | cut -d" " -f3 | sort -r | head -1 -`

#Mit Paketmanager (Apt) suchen
if [ "$POSTGRESQL#" == "#" ]; then
    writeln 1 1 $FEHLER
    writeln 2 1 Keine PostgreSQL mit Paketmanager installiert
    writeln 3 1 Datenbank bitte manuell einrichten.
    exit 0
else
   PLPGSQL=`dpkg -L $POSTGRESQL | grep plpgsql.so`
fi

#Mit Paketmanager (RPM) suchen ?
#PLPGSQL=`rpm -q --list postgres | grep plpgsql.so`

if [ "$PLPGSQL#" == "#" ]; then
	#Probleme mit Paketmanager, dann zunaechst mit locate, geht schneller
	updatedb
	writeln 3 3 --locate
	tmp=`locate plpgsql.so 2>/dev/null`
	PLPGSQL=`echo $tmp | cut -d " " -f 1`
fi
if [ "$PLPGSQL#" == "#" ]; then
	#noch nicht gefunden, also mit find suchen
	writeln 3 15 --find /usr/lib
	tmp=`find /usr/lib -name  plpgsql.so -type f`
	PLPGSQL=`echo $tmp | cut -d " " -f 1`
fi	
if [ "$PLPGSQL#" == "#" ]; then
	while :; do
		writeln 4 1 'plpgsql.so' nicht gefunden.
		tput bold
   		writeln 5 1 "Bitte den Pfad eingeben: "
		tput rmso
   		read PLPGSQL
   		[ "$PLPGSQL#" != "#" ] && [ -f $PLPGSQL ] && break
   		tput bel
	done
fi
writeln 6 1 ok. 'plpgsql.so' gefunden

#Kann der User postgres die db erreichen
cnt=`ps aux | grep postgres | wc -l`
if [ $cnt -eq 0 ]; then
	tput bel
	tput bold
	echo Die postgreSQL-Datebbank ist nicht gestartet!
	tput rmso
	exit 1
fi
v8=`su postgres -c "echo 'select version()' | psql template1 2>/dev/null | grep -E "[Ss][Qq][Ll][[:space:]]+8\.[2-9]\.[0-9]" | wc -l"`
if [ $v8 -eq 0 ]; then 
	tput bel
	tput bold
	echo User postgres konnte die Datenbank 8.2.x -  8.9.x nicht ansprechen
	tput rmso
	exit 1; 
else
	tput clear
	writeln 1 1 Datenbank Version 8.2.x - 8.9.x konnte erreicht werden.
fi

echo "CREATE FUNCTION plpgsql_call_handler() RETURNS language_handler" > lxdbinst.sql
echo "AS '$PLPGSQL', 'plpgsql_call_handler'" >> lxdbinst.sql
echo "LANGUAGE c;" >> lxdbinst.sql
echo "CREATE PROCEDURAL LANGUAGE plpgsql HANDLER plpgsql_call_handler;" >> lxdbinst.sql

writeln 2 1 Datenbankbenutzer einrichten
tput bold
writeln 3 1 "Bitte den Datenbank-Benutzernamen (Kleinbuchstaben) eingeben [lxoffice]: "
tput rmso
read LXOUSER
if [ "$LXOUSER#" == "#" ]; then LXOUSER="lxoffice"; fi
while :; do
	tput bold
	writeln 4 1 "Bitte ein Kennwort eingeben : "
	tput rmso
	read USRPWD
	if ! [ "$USRPWD#" == "#" ]; then break; fi
	tput bel
done;

echo "CREATE USER $LXOUSER with CREATEDB ;" >> lxdbinst.sql
echo "ALTER USER $LXOUSER PASSWORD '$USRPWD';" >> lxdbinst.sql
echo "UPDATE pg_language SET lanpltrusted = true WHERE lanname = 'plpgsql';" >> lxdbinst.sql

su postgres -c "psql template1 < lxdbinst.sql"

echo "Fehlermeldungen die 'already exists' enthalten koennen ignoriert werden"

writeln 11 1 Datenbank fuer Lx-Office vorbereitet

writeln 12 1 Datenbankberechtigung einrichten
#wo ist die pg_hba.conf
writeln 13 3 --find erst /etc dann /var/lib
tmp=`find /etc/postgresql -name pg_hba.conf -type f`
[ "$tmp#" == "#" ] && tmp=`find /var/lib -name  pg_hba.conf -type f`
PGHBA=`echo $tmp | cut -d " " -f 1`

if [ "$PGHBA#" == "#" ]; then
	while :; do
		writeln 14 1 'pg_hba.conf' nicht gefunden.
		tput bold
   		writeln 15 1 "Bitte den Pfad eingeben: "
		tput rmso
   		read PGHBA
   		[ "$PGHBA#" != "#" ] && [ -f $PGHBA ] && break
   		tput bel
	done
fi
writeln 16 1 ok. 'pg_hba.conf' gefunden

cnt=`grep $LXOUSER $PGHBA | wc -l `

if [ $cnt -eq 0 ]; then 
	mv $PGHBA  $PGHBA.org
	echo "local   all         $LXOUSER                                           password" > $PGHBA
	echo "host    all         $LXOUSER      127.0.0.1         255.255.255.255    password" >> $PGHBA
	cat $PGHBA.org >> $PGHBA
fi 

#CONFDIR=`dirname $PGHBA`

#postgresql.conf anpassen, liegt vermutlich im gleichen Verzeichnis wie pg_hba.conf
#if ! [ -f $CONFDIR/postgresql.conf ]; then
#	#doch nicht da, dann fragen
#        while :; do
#		writeln 13 1 'postgresql.conf' nicht gefunden.
#		tput bold
#                writeln 14 1 "Bitte den Pfad eingeben: "
#		tput rmso
#                read PGCONF
#                [ "$PGCONF#" != "#" ] && [ -f $PGCONF ] && break
#                tput bel
#        done
#	CONFDIR=`dirname $PGCONF`
#fi

#mv $CONFDIR/postgresql.conf $CONFDIR/postgresql.conf.org
#Bei der V8.x OID einschalten.
#sed 's/^.*default_with_oids.*/default_with_oids = true/i' $CONFDIR/postgresql.conf.org > $CONFDIR/postgresql.conf
#cnt=`grep default_with_oids $CONFDIR/postgresql.conf | wc -l`
#if [ $cnt -eq 0 ]; then
#	cp $CONFDIR/postgresql.conf.org $CONFDIR/postgresql.conf
#	echo "default_with_oids = true" >> $CONFDIR/postgresql.conf
#fi
 
tmp=`ls -r1 /etc/init.d/postgres*`
PGSQL=`echo $tmp | cut -d " " -f 1`

writeln 18 1 Datenbank neu starten
$PGSQL restart

tput bold
tput smso
writeln 20 12 ok. Das sollte es gewesen sein.
tput rmso
tput rmso
echo 
