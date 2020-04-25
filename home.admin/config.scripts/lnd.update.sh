#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "Interim optional LND updates between RaspiBlitz releases."
 echo "lnd.update.sh [info|secure|reckless]"
 echo "info -> get actual state and possible actions"
 echo "secure -> only do recommended updates by RaspiBlitz team"
 echo "  binary will be checked by signature and checksum"
 echo "reckless -> if you just want to update to the latest release"
 echo "  published on LND GitHub releases (RC or final) without any"
 echo "  testing or security checks."
 exit 1
fi

# 1. parameter [info|secure|reckless]
mode="$1"

# RECOMMENDED UPDATE BY RASPIBLITZ TEAM

lndUpdateVersion="0.10.0-beta"
lndUpdateComment="Some optional apps might not work with this update. You will not be able to downgrade after LND database migration."

# check who signed the release in https://github.com/lightningnetwork/lnd/releases
# olaoluwa
lndUpdatePGPpkeys="https://keybase.io/roasbeef/pgp_keys.asc"
lndUpdatePGPcheck="9769140D255C759B1EB77B46A96387A57CAAE94D"

#joostjager
# lndUpdatePGPpkeys="https://keybase.io/joostjager/pgp_keys.asc"
# lndUpdatePGPcheck="D146D0F68939436268FA9A130E26BB61B76C4D3A"

# bitconner 
# lndUpdatePGPpkeys="https://keybase.io/bitconner/pgp_keys.asc"
# lndUpdatePGPcheck="9C8D61868A7C492003B2744EE7D737B67FA592C7"

# wpaulino
# lndUpdatePGPpkeys="https://keybase.io/wpaulino/pgp_keys.asc"
# lndUpdatePGPcheck="729E9D9D92C75A5FBFEEE057B5DD717BEF7CA5B1"

# GATHER DATA

# setting download directory
downloadDir="/home/admin/download"

# detect CPU architecture & fitting download link
cpuArchitecture=""
if [ $(uname -m | grep -c 'arm') -eq 1 ] ; then
  cpuArchitecture="armv7"
fi
if [ $(uname -m | grep -c 'aarch64') -eq 1 ] ; then
  cpuArchitecture="arm64"
fi
if [ $(uname -m | grep -c 'x86_64') -eq 1 ] ; then
  cpuArchitecture="amd64"
fi
if [ $(uname -m | grep -c 'i386\|i486\|i586\|i686\|i786') -eq 1 ] ; then
  cpuArchitecture="386"
fi

# installed LND version
lndInstalledVersion=$(sudo -u bitcoin lncli --network=mainnet --chain=bitcoin  getinfo | jq -r ".version" | cut -d " " -f1)
lndInstalledVersionMajor=$(echo "${lndInstalledVersion}" | cut -d "-" -f1 | cut -d "." -f1)
lndInstalledVersionMain=$(echo "${lndInstalledVersion}" | cut -d "-" -f1 | cut -d "." -f2)
lndInstalledVersionMinor=$(echo "${lndInstalledVersion}" | cut -d "-" -f1 | cut -d "." -f3)

# test if the installed version already the secure/recommended update version
lndUpdateInstalled=$(echo "${lndInstalledVersion}" | grep -c "lndUpdateVersion")

# get latest release from LND GitHub releases
gitHubLatestReleaseJSON="$(curl -s https://api.github.com/repos/lightningnetwork/lnd/releases | jq '.[0]')"
lndLatestVersion=$(echo "${gitHubLatestReleaseJSON}" | jq -r '.tag_name')
lndLatestDownload=$(echo "${gitHubLatestReleaseJSON}" | grep "browser_download_url" | grep "linux-${cpuArchitecture}" | cut -d '"' -f4)

# INFO
if [ "${mode}" = "info" ]; then

  echo "# basic data"
  echo "cpuArchitecture='${cpuArchitecture}'"
  echo "lndInstalledVersion='${lndInstalledVersion}'"
  echo "lndInstalledVersionMajor='${lndInstalledVersionMajor}'"
  echo "lndInstalledVersionMain='${lndInstalledVersionMain}'"
  echo "lndInstalledVersionMinor='${lndInstalledVersionMinor}'"

  echo "# the secure/recommended update option"
  echo "lndUpdateInstalled='${lndUpdateInstalled}'"
  echo "lndUpdateVersion='${lndUpdateVersion}'"
  echo "lndUpdateComment='${lndUpdateComment}'"

  echo "# reckless update option (latest LND release from GitHub)"
  echo "lndLatestVersion='${lndLatestVersion}'"
  echo "lndLatestDownload='${lndLatestDownload}'"

  exit 1
fi

# SECURE
if [ "${mode}" = "secure" ]; then

  echo "# lnd.update.sh secure"

  # check for optional second parameter: forced update version
  # --> only does the secure update if its the given version
  # this is needed for recovery/update. 
  fixedUpdateVersion="$2"
  if [ ${#fixedUpdateVersion} -gt 0 ]; then
    echo "# checking for fixed version update: askedFor(${fixedUpdateVersion}) available(${lndUpdateVersion})"
    if [ "${fixedUpdateVersion}" != "${lndUpdateVersion}" ]; then
      echo "warn='required update version does not match'"
      echo "# this is normal when the recovery script of a new RaspiBlitz version checks for an old update - just ignore"
      exit 1
    else
      echo "# OK - update version is matching"
    fi
  fi

  # change into download directory
  cd "${downloadDir}"

  # extract the SHA256 hash from the manifest file for the corresponding platform
  sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndUpdateVersion}/manifest-v${lndUpdateVersion}.txt
  checkDownload=$(ls manifest-v${lndUpdateVersion}.txt 2>/dev/null | grep -c manifest-v${lndUpdateVersion}.txt)
  if [ ${checkDownload} -eq 0 ]; then
    echo "error='download manifest failed'"
    exit 1
  fi
  lndSHA256=$(grep -i "linux-${cpuArchitecture}" manifest-v$lndUpdateVersion.txt | cut -d " " -f1)
  echo "# SHA256 hash: $lndSHA256"

  # get LND binary
  binaryName="lnd-linux-${cpuArchitecture}-v${lndUpdateVersion}.tar.gz"
  sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndUpdateVersion}/${binaryName}
  checkDownload=$(ls ${binaryName} 2>/dev/null | grep -c ${binaryName})
  if [ ${checkDownload} -eq 0 ]; then
    echo "error='download binary failed'"
    exit 1
  fi

  # check binary was not manipulated (checksum test)
  sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndUpdateVersion}/manifest-v${lndUpdateVersion}.txt.sig
  sudo -u admin wget -N -O "${downloadDir}/pgp_keys.asc" ${lndUpdatePGPpkeys}
  binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
  if [ "${binaryChecksum}" != "${lndSHA256}" ]; then
    echo "error='checksum not matching'"
    exit 1
  fi

  # check gpg finger print
  gpg ./pgp_keys.asc
  fingerprint=$(sudo gpg "${downloadDir}/pgp_keys.asc" 2>/dev/null | grep "${lndUpdatePGPcheck}" -c)
  if [ ${fingerprint} -lt 1 ]; then
    echo "error='PGP author check failed'"
  fi
  gpg --import ./pgp_keys.asc
  sleep 3
  verifyResult=$(gpg --verify manifest-v${lndUpdateVersion}.txt.sig 2>&1)
  goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
  echo "# goodSignature(${goodSignature})"
  correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${lndUpdatePGPcheck}" -c)
  echo "# correctKey(${correctKey})"
  if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
    echo "error='PGP verify fail'"
    exit 1
  fi
  # note: install will be done the same as reckless further down
  
fi

# RECKLESS
# this mode is just for people running test and development nodes - its not recommended
# for production nodes. In a update/recovery scenario it will not install a fixed version
# it will always pick the latest release from the github
if [ "${mode}" = "reckless" ]; then

  echo "# lnd.update.sh reckless"

  # check that download link has a value
  if [ ${#lndLatestDownload} -eq 0 ]; then
    echo "error='no download link'"
    exit 1
  fi

  # change into download directory
  cd "${downloadDir}"

  # download binary
  echo "# downloading binary"
  binaryName=$(basename "${lndLatestDownload}")
  sudo -u admin wget -N ${lndLatestDownload}
  checkDownload=$(ls ${binaryName} 2>/dev/null | grep -c ${binaryName})
  if [ ${checkDownload} -eq 0 ]; then
    echo "error='download binary failed'"
    exit 1
  fi

  # prepare install
  lndUpdateVersion="reckless"
fi

# JOINED INSTALL (SECURE & RECKLESS)
if [ "${mode}" = "secure" ] || [ "${mode}" = "reckless" ]; then

  # install
  echo "# stopping LND"
  sudo systemctl stop lnd
  echo "# installing new LND binary"
  sudo -u admin tar -xzf ${binaryName}
  sudo install -m 0755 -o root -g root -t /usr/local/bin lnd-linux-${cpuArchitecture}-v${lndUpdateVersion}/*
  sleep 3
  installed=$(sudo -u admin lnd --version)
  if [ ${#installed} -eq 0 ]; then
    echo "error='install failed'"
    exit 1
  fi
  echo "# flag update in raspiblitz config"
  source /mnt/hdd/raspiblitz.conf
  if [ ${#lndInterimsUpdate} -eq 0 ]; then
    echo "lndInterimsUpdate='${lndUpdateVersion}'" >> /mnt/hdd/raspiblitz.conf
  else
    sudo sed -i "s/^lndInterimsUpdate=.*/lndInterimsUpdate='${lndUpdateVersion}'/g" /mnt/hdd/raspiblitz.conf
  fi
  echo "# restarting LND"
  sudo systemctl start lnd
  sleep 5
  echo ""

  echo "# OK LND Installed"
  exit 1

else

  echo "error='parameter not known'"
  exit 1

fi