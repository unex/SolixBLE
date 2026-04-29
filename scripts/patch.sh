#!/bin/bash
#
# Script name   : patch.sh
# Description   : Script for injecting Frida gadget into Anker Android app
# Author        : Harvey Lelliott (@flip-dots)
# Date          : 23/03/26
# Usage         : ./patch.sh [ADB device (e.g 192.168.1.1:1234)]
#
# License       : MIT
# Revision      : 1.0.0
#
set -euxo pipefail

# Use portable in-place sed for macOS (BSD sed) and Linux (GNU sed).
if sed --version >/dev/null 2>&1; then
  SED_INPLACE=(sed -i)
else
  SED_INPLACE=(sed -i '')
fi


#############
# Constants #
#############

FRIDA_VERSION="17.8.3"

UBER_APK_SIGNER_VERSION="1.3.0"


##################################
# Environment and arg validation #
##################################
echo "Checking environment/tools..."

# Validate arguments
if [ $# -lt 1 ]; then
  echo "Missing device argument (e.g 192.168.1.1:1234)!"
  exit 2
fi

# The device for use with ADB
DEVICE=$1

# Check tools
command -v wget >/dev/null 2>&1 || { echo >&2 "wget is required!"; exit 1; }
command -v adb >/dev/null 2>&1 || { echo >&2 "adb is required!"; exit 1; }
command -v apktool >/dev/null 2>&1 || { echo >&2 "apktool is required!"; exit 1; }
command -v java >/dev/null 2>&1 || { echo >&2 "java is required!"; exit 1; }
command -v frida >/dev/null 2>&1 || { echo >&2 "frida is required!"; exit 1; }


################
# Folder setup #
################
echo "Setting up folders..."

# The current folder
WORKING_FOLDER=$(pwd)

# Folder to put all data in
DATA_FOLDER="${WORKING_FOLDER}/data"
mkdir -p $DATA_FOLDER

# Folder to put source APK inside
APK_SOURCE_FOLDER="${DATA_FOLDER}/source_apks"
mkdir -p $APK_SOURCE_FOLDER

# Folder to put source APK inside
APK_DECOMPILED_FOLDER="${DATA_FOLDER}/base_apk_decompiled"
mkdir -p $APK_DECOMPILED_FOLDER

# Folder to put patched APKs inside
APK_PATCHED_FOLDER="${DATA_FOLDER}/patched"
mkdir -p $APK_PATCHED_FOLDER

# Folder to put signed APKs inside
APK_SIGNED_FOLDER="${DATA_FOLDER}/signed"
mkdir -p $APK_SIGNED_FOLDER

# Folder to put tools in
TOOLS_FOLDER="${WORKING_FOLDER}/tools"
mkdir -p $TOOLS_FOLDER

# Folder to put Frida gadgets in
FRIDA_FOLDER="${TOOLS_FOLDER}/frida"
mkdir -p $FRIDA_FOLDER


#######################
# Download deps/tools #
#######################
echo "Downloading dependencies/tools"

cd "$FRIDA_FOLDER"
if [ ! -f "undetected-frida-gadget-${FRIDA_VERSION}-android-arm.so" ]; then
  wget -O "undetected-frida-gadget-${FRIDA_VERSION}-android-arm.so.xz" "https://github.com/zer0def/undetected-frida/releases/download/${FRIDA_VERSION}/undetected-frida-gadget-${FRIDA_VERSION}-android-arm.so.xz"
  unxz -f "undetected-frida-gadget-${FRIDA_VERSION}-android-arm.so.xz"
fi

if [ ! -f "undetected-frida-gadget-${FRIDA_VERSION}-android-arm64.so" ]; then
  wget -O "undetected-frida-gadget-${FRIDA_VERSION}-android-arm64.so.xz" "https://github.com/zer0def/undetected-frida/releases/download/${FRIDA_VERSION}/undetected-frida-gadget-${FRIDA_VERSION}-android-arm64.so.xz"
  unxz -f "undetected-frida-gadget-${FRIDA_VERSION}-android-arm64.so.xz"
fi

if [ ! -f "${TOOLS_FOLDER}/uber-apk-signer-${UBER_APK_SIGNER_VERSION}.jar" ]; then
  cd "$TOOLS_FOLDER" && wget -O "uber-apk-signer-${UBER_APK_SIGNER_VERSION}.jar" "https://github.com/patrickfav/uber-apk-signer/releases/download/v${UBER_APK_SIGNER_VERSION}/uber-apk-signer-${UBER_APK_SIGNER_VERSION}.jar"
fi


########################
# Pull and extract APK #
########################

# Pull Anker APKs from Phone
echo "Extracting original APKs from phone..."
rm -f "${APK_SOURCE_FOLDER}"/*.apk
adb -s $DEVICE shell pm path com.anker.charging | sed 's/^package://' | tr -d '\r' | xargs -I {} adb -s $DEVICE pull {} $APK_SOURCE_FOLDER

# Decompile main APK
echo "Decompiling main APK..."
apktool d "${APK_SOURCE_FOLDER}/base.apk" -o $APK_DECOMPILED_FOLDER -f


################
# Inject Frida #
################
echo "Injecting Frida gadget into main APK..."

# Copy Frida gadget binaries
mkdir -p "${APK_DECOMPILED_FOLDER}/lib/armeabi"
mkdir -p "${APK_DECOMPILED_FOLDER}/lib/armeabi-v7a"
mkdir -p "${APK_DECOMPILED_FOLDER}/lib/arm64-v8a"
cp "${FRIDA_FOLDER}/undetected-frida-gadget-${FRIDA_VERSION}-android-arm.so" "${APK_DECOMPILED_FOLDER}/lib/armeabi/libnative-utils.so"
cp "${FRIDA_FOLDER}/undetected-frida-gadget-${FRIDA_VERSION}-android-arm.so" "${APK_DECOMPILED_FOLDER}/lib/armeabi-v7a/libnative-utils.so"
cp "${FRIDA_FOLDER}/undetected-frida-gadget-${FRIDA_VERSION}-android-arm64.so" "${APK_DECOMPILED_FOLDER}/lib/arm64-v8a/libnative-utils.so"

cp "${WORKING_FOLDER}/frida_config.json" "${APK_DECOMPILED_FOLDER}/lib/armeabi/libnative-utils.config.so"
cp "${WORKING_FOLDER}/frida_config.json" "${APK_DECOMPILED_FOLDER}/lib/armeabi-v7a/libnative-utils.config.so"
cp "${WORKING_FOLDER}/frida_config.json" "${APK_DECOMPILED_FOLDER}/lib/arm64-v8a/libnative-utils.config.so"

# Add Frida gadget to app startup
"${SED_INPLACE[@]}" '34c \
const-string v0, "native-utils"\
invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V\
' "${APK_DECOMPILED_FOLDER}/smali/s/h/e/l/l/A.smali"

# Modify manifest to enable Frida loading
"${SED_INPLACE[@]}" '/<application/,/>/ s/android:allowBackup="false"/android:allowBackup="true"/' "${APK_DECOMPILED_FOLDER}/AndroidManifest.xml"
"${SED_INPLACE[@]}" '/<application/,/>/ s/android:extractNativeLibs="false"/android:extractNativeLibs="true" android:debuggable="true"/' "${APK_DECOMPILED_FOLDER}/AndroidManifest.xml"


##########################
# Re-package and re-sign #
##########################
echo "Re-packaging and re-signing APK..."

# Re-package base/main APK
apktool b -o "${APK_PATCHED_FOLDER}/base.apk" ${APK_DECOMPILED_FOLDER}

# Re-sign APKs
mapfile -t SOURCE_SPLITS < <(find "$APK_SOURCE_FOLDER" -maxdepth 1 -type f -name 'split*.apk' | sort)

java -jar "${TOOLS_FOLDER}/uber-apk-signer-${UBER_APK_SIGNER_VERSION}.jar" -o "$APK_SIGNED_FOLDER" --allowResign --apks \
  "${APK_PATCHED_FOLDER}/base.apk" \
  "${SOURCE_SPLITS[@]}"

# Uninstall existing Anker app
adb -s $DEVICE uninstall com.anker.charging

# Install patched APKs
SIGNED_APKS=("${APK_SIGNED_FOLDER}/base-aligned-debugSigned.apk")
for split_apk in "${SOURCE_SPLITS[@]}"; do
  split_name="$(basename "${split_apk}" .apk)"
  SIGNED_APKS+=("${APK_SIGNED_FOLDER}/${split_name}-aligned-debugSigned.apk")
done

adb -s "$DEVICE" install-multiple "${SIGNED_APKS[@]}"
