#!/bin/bash
#sprawdzenie czy użytkownik to root
if [ `id -u` -ne 0 ]
  then echo WŁĄCZ TEN SKRYPT JAKO ROOT LUB UŻYJ SUDO!!!
else


#parametry domyślne
defaultLifetime=1
defaultTimeout=1
defaultDirectory="/home"
defaultBackupDirectory="/backup"
defaultCompleteCopyInterval=1


#odczyt z pliku konfiguracyjnego
timeout=$(sed -n -e 's/.*://' -e '2p' backup.conf) #co ile minut wykonuje sie backup
lifetime=$(sed -n -e 's/.*://' -e '3p' backup.conf) #ile dni przechowywane są kopie
directory=$(sed -n -e 's/.*://' -e '4p' backup.conf | sed 's/\/$//') #katalog śledzdony
backupDirectory=$(sed -n -e 's/.*://' -e '5p' backup.conf | sed 's/\/$//') #katalog do przechowywania
completeCopyInterval=$(sed -n -e 's/.*://' -e '6p' backup.conf) #co ile wykonuje się kopia pełna

#sprawdzenie czy wartości są większe od parametrów domyślnych 
if [[ ($timeout == "") || ($timeout -lt $defaultTimeout) ]]
	then timeout=$defaultTimeout
		echo "PARAMETR TIMEOUT USTAWIONY NIEPOPRAWNIE, POWINIEN PRZYJMOWAĆ WARTOŚCI WIĘKSZE NIŻ 0, WCZYTANO WARTOŚĆ DOMYŚLNĄ $defaultTimeout"
fi

if [[ ($lifetime == "") || ($lifetime -lt $defaultLifetime) ]]
	then lifetime=$defaultLifetime
		echo "PARAMETR MAX_BACKUP_LIFETIME USTAWIONY NIEPOPRAWNIE, POWINIEN PRZYJMOWAĆ WARTOŚCI CAŁKOWITE WIĘKSZE NIŻ 0, WCZYTANO WARTOŚĆ DOMYŚLNĄ $defaultLifetime"
fi

if [[ "$directory" == "" ]]
	then directory=$defaultDirectory
		echo "PARAMETR DIRECTORY USTAWIONY NIEPOPRAWNIE, WCZYTANO WARTOŚĆ DOMYŚLNĄ $defaultDirectory"
fi

if [[ "$backupDirectory" == "" ]]
	then backupDirectory=$defaultBackupDirectory
		echo "PARAMETR BACKUP_DIRECTORY ZOSTAŁ USTAWIONY NIEPOPRAWNIE, WCZYTANO WARTOŚĆ DOMYŚLNĄ $defaultBackupDirectory"
fi

if [[ ($completeCopyInterval == "") || ($completeCopyInterval -lt $defaultCopmpleteCopyInterval) ]]
	then completeCopyInterval=$defaultCompleteCopyInterval
		echo "PARAMETR COMPLETE_COPY_INTERVAL ZOSTAŁ USTAWIONY NIEPOPRAWNIE, WCZYTANO WARTOŚĆ DOMYŚLNĄ $defaultCompleteCopyInterval"
fi




timeout=$(expr "$timeout" \* "60") #zmian minut na sekundy bo sleep przyjmuje parametr w sekundach
	
#sprawdzenie czy folder backup istnieje, jeśli nie to zostanie utworzony
if [ ! -d "$backupDirectory" ] 
then #folder nie istnieje
	echo "UTWOŻONO FOLDER $backupDirectory"
	mkdir -p "$backupDirectory"
fi
	

#przy uruchomieniu programu od razu jest tworzona kopia pełna (mi się to wydaje logiczne)
actualBackup="$backupDirectory/$(date +'%Y-%m-%d-%H-%M')"


tail -n +2 backup_serv_list.conf | xargs -I {} systemctl stop {}
cp -aR "$directory"/ "$actualBackup"
tail -n +2 backup_serv_list.conf | xargs -I {} systemctl start {}

#nieskończona pętla co X miut

counter=1

while :
do
sleep "$timeout"

#zatrzymanie serwisów z listy
tail -n +2 backup_serv_list.conf | xargs -I {} systemctl stop {}


#kopia całkowita co X minut
newestBackup=$(ls -tu1d "$backupDirectory"/*/ | head -1)
actualBackup="$backupDirectory/$(date +'%Y-%m-%d-%H-%M')"

if [ $counter -gt $completeCopyInterval ] 
	then cp -aR "$directory"/ "$actualBackup"
	counter=1
else
counter=$(expr "$counter" + "1")

#stworzenie drzewa katalogów takiego jakie ma aktualnie śledzony katalog
find "$directory" -type d | tail -n +2 | sed 's\.*'"$directory"'\\' | xargs -I {} mkdir -p "$actualBackup"/{}

#skopiowanie uprawnień
find "$directory" -type d | tail -n +2 | sed 's\.*'"$directory"'\\' | xargs -I {} chmod --reference="$directory"{} "$actualBackup"/{}


#sprawdzenie które pliki zostały nienaruszone (użytkownik nie usunął ani nie zmodyfikował) i stworzenie do nich hardlinków z poprzednim całkowitym backupem
	


	plikiDoSkopiowania=($(find $directory/ -type f | sed 's\.*'"$directory/"'\\' | xargs -I {} echo "$newestBackup{}"))
	plikiDocelowe=($(find $directory/ -type f | sed 's\.*'"$directory/"'\\' |xargs -I {} echo "$actualBackup/{}"))
	
	

	#towrzenie hardlinków
	for((i = 0; i < ${#plikiDocelowe[@]}; i++))
	do
	cp -al "${plikiDoSkopiowania[i]}" "${plikiDocelowe[i]}" 2>/dev/null
	done


#szukanie różnic i kopiowanie zedytowanych plików

zmienionePliki=($(diff -qr "$actualBackup" "$directory" | grep differ | sed 's/.* and //' | rev | sed 's/.* //' | rev))
katalogDocelowy=($(diff -qr "$actualBackup" "$directory" | grep differ | sed 's/.* and //' | rev | sed 's/.* //' | rev | sed 's#'"$directory"'##'))


for((i=0; i < ${#zmienionePliki[@]}; i++))
do
rm -fR "$actualBackup${katalogDocelowy[i]}"
cp -af "${zmienionePliki[i]}" "$actualBackup${katalogDocelowy[i]}"
done

#szukanie nowych plików i kopiowanie ich
nowePliki=$(diff <(find "$actualBackup" -type f -printf "%P\n" | sort) <(find "$directory" -type f -printf "%P\n" | sort))

plikiDoSkopiowania=($(echo "$nowePliki" | grep '^>' | sed 's/^> //'))


for((i=0; i < ${#plikiDoSkopiowania[@]}; i++ ))
do
cp -af "$directory/${plikiDoSkopiowania[i]}" "$actualBackup/${plikiDoSkopiowania[i]}"
done



fi


#uruchomienie serwisów z listy
tail -n +2 backup_serv_list.conf | xargs -I {} systemctl start {}

#usunięcie plików starszych niż X dni
find "$backupDirectory"/  -maxdepth 1 -type d -mtime +"$lifetime" | tail -n +2 | xargs -I {} rm -Rf {}



done #koniec pętli
fi
