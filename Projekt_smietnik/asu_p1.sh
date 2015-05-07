#!/bin/bash

mkdir Folder1

touch Folder1/nowy1.txt
touch pliczek.dat

tar -cf ArchiwumFolder1.tar Folder1
tar -cf ArchiwumPlik.tar pliczek.dat

./tbin.sh -d Folder1 -f -
./tbin.sh -d ArchiwumFolder1.tar -f -
./tbin.sh -d ArchiwumPlik.tar -f $HOME/mojlog.log
./tbin.sh -d pliczek.dat -f $HOME/mojlog.log
