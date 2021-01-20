#!/bin/bash
#
#	script qui envoie une image sur la matrice RGB Connectée
#	de ioodyme
#
FILENAME="$1"
MAXW=16
MAXH=32

convert "$FILENAME" -resize $MAXW"x"$MAXH^ "$FILENAME.tmp"
W=$(identify -format '%w' $FILENAME".tmp")
H=$(identify -format '%h' $FILENAME".tmp")
for i in `seq 0 1 $W`; do
  echo $i;
  for j in `seq 0 1 $H`; do
    COL=$(convert $FILENAME".tmp" -format '%[pixel:p{'$i','$j'}]' -colorspace RGB info:-)
    RGB=$(echo $COL |  grep -o -E '[0-9]+')
    R=$(echo "$RGB" | sed -n 1p)
    G=$(echo "$RGB" | sed -n 2p)
    B=$(echo "$RGB" | sed -n 3p)
    echo "PRIVMSG #ioodyme :!matrix $i $j $R $G $B" >> ircoutput
    sleep 2
  done
done
