#!/usr/bin/env bash

# Clone busybox, check out to desired tag, cherry-pick / apply patches for NDK, then run this script
[ ! -d busybox ] && exit 1

[ $1 = "--commit" ] && COMMIT=true || COMMIT==false

progress() {
  echo -e "\033[44m\n${1}\n\033[0m"
}

parse_kbuild() {
  for KBUILD in `find . -type f -name Kbuild`; do
    DIR=${KBUILD#./}
    DIR=${DIR%/*}
    cat $KBUILD | grep '^[^#].*\.o\b' | while read LINE; do
      FILE_LIST=${LINE#*+=}
      CONFIG=`echo ${LINE%+=*} | grep -o '$(.*)' | cut -d\( -f2 | cut -d\) -f1`
      eval [ -z \"$CONFIG\" -o \"\$$CONFIG\" = \"1\" ] && INCL=true || INCL=false
      if $INCL; then
        for FILE in `echo $FILE_LIST | grep -o '\b[a-zA-Z0-9_\-]*\.o\b'`; do
          echo $DIR/$FILE | sed 's/.o$/.c \\/g'
        done
      fi
    done
  done
}

cd busybox

# Copy config and make config
progress "Generating configuration files"
cp ../ndk_busybox.config .config
yes n | make oldconfig 2>/dev/null

# Generate headers
gcc applets/applet_tables.c -o applets/applet_tables
applets/applet_tables include/applet_tables.h include/NUM_APPLETS.h
gcc applets/usage.c -o applets/usage -Iinclude
applets/usage_compressed include/usage_compressed.h applets
scripts/mkconfigs include/bbconfigopts.h include/bbconfigopts_bz2.h
scripts/generate_BUFSIZ.sh include/common_bufsiz.h

progress "Generating Android_src.mk based on configs"

# Load config into shell variables
eval `grep -o 'CONFIG[_A-Z0-9]* 1' include/autoconf.h | sed 's/ 1/=1/g'`

# Process Kbuild files
echo "LOCAL_SRC_FILES := \\" > Android_src.mk
parse_kbuild | sort -u >> Android_src.mk

# Build Android.mk
echo 'LOCAL_PATH := $(call my-dir)' > Android.mk
cat Makefile | head -n 3 >> Android.mk
cat ../busybox.mk >> Android.mk

if $COMMIT; then
  progress "Commit headers and makefiles"
  git add -f include
  git add *.mk
  git commit -m "Add generated files for ndk-build" -m "Auto generated by ndk-busybox-kitchen"
fi

cd ..
