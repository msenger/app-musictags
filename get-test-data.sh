#!/bin/bash
#

DEFAULT_TARGETDIR=testdata
TARGETDIR=${1:-$DEFAULT_TARGETDIR}

mkdir -p $TARGETDIR

cp -R '/c/My Music/00_Various Artists/1975 - Pisne dlouhych cest'                 "$TARGETDIR/"
cp -R '/c/My Music/00_Various Artists/21 Viteznych pisni'                         "$TARGETDIR/"
cp -R '/c/My Music/00_Various Artists/30 let Ceske Country'                       "$TARGETDIR/"
cp -R '/c/My Music/00_Various Artists/Ceske hity 1961-1969, 1975/Hity 1964 vol.2' "$TARGETDIR/"

echo "$TARGETDIR/"
ls -l "$TARGETDIR/"
