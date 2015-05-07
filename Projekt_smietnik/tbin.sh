#!/bin/bash

# time in seconds when files in trashbin expire
# 48-hours
#expireTime=172800

#debug
expireTime=120

# default path for trashbin
binPath="$HOME/.smietnik"

# help
stringHelp="
 _______________________________________________
|						|
| 	      Miniprojekt : Smietnik 		|
|_______________________________________________|
|						|
| 		Autor: Kamil Gajowy		|
|_______________________________________________|
|						|					|
| Sposob wywolania:				|
|						|
| ./tbin.sh -d file [-options]			|
|						|
|	-d file 				|
|	-delete file				|
|		to plik do usuniecia		|
|	-f [nazwa/-]				|
|	-file [nazwa/-]				|
|		\"-\" to sciezka domyslna	|
|		dodanie dzialania do logu	|
|	--h					|
|	--help					|
|		wyswietla ten komunikat		|
|						|
|_______________________________________________|
"
saveToCustomLog=0
saveToLog=0
logFilename=""
deleteFilename=""

while [ "$1" != "" ]; do
	case $1 in
		-f | --file )	shift
				saveToLog=1
				logFilename="$1"
				;;
		-d | --delete ) shift
				deleteFilename="$1"
				;;
		--h | --help )	echo "$stringHelp"
				exit
				;;
		* )		echo "$stringHelp"
				exit 1
	esac
	shift	
done;

# care with log file
if [ "$saveToLog" -eq 1 ]
then
	if [ "$logFilename" == "-" -o "$logFilename" == "" ]
	then
		logFilename="$HOME/trashbin.log"
	fi
fi

# check if there is a file to delete
if [ "$deleteFilename" == "" ]
then
	echo "$stringHelp"
	exit 1
fi

# create bin if needed with file/dir check
if [[ -e "$binPath" && -d "$binPath" ]]
then
	echo "Using $binPath as a trashbin"
else
	if [ -f "$binPath" ]
	then
		rm $binPath
	fi
	mkdir -p "$binPath"
	echo "@Trashbin created."
fi

if [ "$saveToLog" -eq 0 ]; then
	echo "@ Deleting old files ... "
else
	echo "" >> $logFilename
	echo `date` >> $logFilename
	echo "@ Deleting old files ... " >> $logFilename
fi

currDate=`date +%s`
for i in "$binPath"/*
do
	fileDate=`date -r "$i" +%s`
	diff=$((currDate-fileDate))
	if [ $diff -ge $expireTime ]
	then
		if [ "$saveToLog" -eq 0 ]; then
			echo "	@ deleting $i"
		else
			echo "	@ deleting $i" >> $logFilename
		fi
		#rm $i
	fi
done;

if [ ! -e $deleteFilename ] ; then
	echo "@ File does not exist! Quitting..."
	exit 1
fi

filename=$(basename $deleteFilename)
# check if already packed and 
# retreive name for it
fnameInBin=""
if [ -f $deleteFilename ]
then
	extension=${filename##*.}
else
	extension=""
fi
filename=${filename%.*}‭
fnameInBin="$filename.$extension.$currDate"

# pack file
echo "$extension"
tar="tar"


if [ "$extension" = "tar" ]
then
	mv -T $deleteFilename $binPath/$filename.$currDate
fi

if [ "$extension" != "tar" ]
then
	tar -cf $binPath/$fnameInBin.tar $deleteFilename
	# remove file
	if [ -f $deleteFilename ]
	then
		rm $deleteFilename
	else
		rm -r $deleteFilename
	fi
fi



if [ "$saveToLog" -eq 0 ]; then
	echo "@ file $deleteFilename moved to trashbin."
else
	echo "@ file $deleteFilename moved to trashbin.">> $logFilename
fi


