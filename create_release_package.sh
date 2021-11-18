#!/bin/bash
if ( ! test -z {,} ); then echo "Must be ran with \"bash\""; exit 1; fi
if [ $(whoami) != "root" ]; then echo "Please run with this script with sudo"; exit 1; fi
if [ ! -f ./rootc.img ]; then echo "put latest rootc.img to this directory first"; exit 1; fi

build_package() {
  local target="$1"
  if [ -d /var/rootc ]; then
    rm -rf /var/rootc ./out
  fi
  mkdir -p /var/rootc ./out/packages ./out/patches

  mount $target /var/rootc

  # pick selected packages
  FILES="alsa-ucm-conf.tar.gz broadcom-wl.tar.gz kernel-5.10.57-brunch-sebanc.tar.gz firmware_amd_intel.tar.gz  kernel-5.4.139-brunch-sebanc.tar.gz firmwares.tar.gz"
  for i in $FILES
  do
    cp -r /var/rootc/packages/$i ./out/packages/
  done
  
  # pack cpu microcode
  cp -r /var/rootc/lib/firmware ./out
  cd ./out
  tar -czvf ./packages/firmware_amd_intel.tar.gz firmware  --owner=0 --group=0
  cd ..
  
  # adjust initramfs
  cd ./out
  mkdir -p ./initramfs && cd ./initramfs && gzip -cd /var/rootc/initramfs.img | cpio -i
  cp ../../initramfs_init ./init
  # adjust bootsplash
  mkdir ./bootsplash
  if [ -f ../../bootsplash/main.png ]; then
    cp ../../bootsplash/main.png ./bootsplash/
  else
    cp ./bootsplashes/default/main.png ./bootsplash/
  fi
  if [ -f ../../bootsplash/incompatible.png ]; then
    cp ../../bootsplash/incompatible.png ./bootsplash/
  else
    cp ./bootsplashes/default/incompatible.png ./bootsplash/
  fi
  rm -rf ./bootsplashes
  # re-pack initramfs
  find . | cpio -o -H newc | gzip > ../initramfs-direct.img
  cd ../..  
  
  # use selected patches
  cp -r ./patches ./out
  
  # copy files in root directory
  FILES="kernel-5.4 kernel-5.10"
  for i in $FILES
  do
    cp /var/rootc/$i ./out/
  done  

  FILES2="chromeos-install.sh chromeos-update.sh settings.cfg readme.md samples.sh create_release_package.sh"
  for i in $FILES2
  do
    cp ./$i ./out/
  done 

  # pack everything
  cd ./out
  tar -czvf chromium-dualboot.tar.gz packages patches $FILES $FILES2 initramfs-direct.img --owner=0 --group=0
  cd ..

  umount /var/rootc
}

main() {
  loopdevice=$(losetup --show -fP ./rootc.img)
  build_package $loopdevice
  losetup -d "$loopdevice"
}

main
