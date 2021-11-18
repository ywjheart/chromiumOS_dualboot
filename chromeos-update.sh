#!/bin/bash
if ( ! test -z {,} ); then echo "Must be ran with \"bash\""; exit 1; fi
if [ -z $(which cgpt) ]; then echo "cgpt needs to be installed first"; exit 1; fi
if [ -z $(which pv) ]; then echo "pv needs to be installed first"; exit 1; fi
if [ $(whoami) != "root" ]; then echo "Please run with this script with sudo"; exit 1; fi

setting_file=settings.cfg

if [ ! -f $setting_file ]; then
   echo "Setting file $setting_file not found."
   exit 1
fi

source $setting_file

usage()
{
	echo ""
	echo "Brunch installer: update ChromeOS on device or disk image from the brunch framework."
	echo "Usage: chromeos_install.sh [-s X] [-l] -src chromeos_recovery_image_path -dst destination"
	echo "-src (source), --source (source)			ChromeOS recovery image"
	echo "-dst (destination), --destination (destination)	Device (e.g. /dev/sda) or Disk image file (e.g. chromeos.img)"
	echo "-h, --help					Display this menu"
}

patch_roota() {
  local target="$1"
  if [ -d /roota ]; then
    rm -rf /roota /rootc
  fi
  mkdir -p /roota /rootc
  ln -s $(pwd)/packages /rootc/packages
  ln -s $(pwd)/patches /rootc/patches
	
# reset ROOT-A partition	
  printf '\000' | dd of=$target seek=$((0x464 + 3)) conv=notrunc count=1 bs=1 status=none
  e2fsck -f -y $target
  resize2fs -f $target
  mount $target /roota

# copy kernel and modules
  rm -r /roota/lib/modules/*
  rm /roota/kernel*
  tar zxf packages/$kernel_tar -C /roota
  cp -v $kernel_file /roota
  ln -s $kernel_file /roota/kernel
  cp -v initramfs-direct.img /roota/initramfs.img
  cp -v $setting_file /roota/settings.cfg  

# apply patches
  chmod 755 /rootc/patches/*.sh
  for patch in /rootc/patches/*.sh
  do
	echo "brunch: invoke $patch"
	"$patch" "$options"
	ret="$?"
	if [ "$ret" -eq 0 ]; then
		echo "brunch: $patch success"
	else
		echo "brunch: $patch failed with ret=$ret"
	fi
  done

  umount /roota
}

while [ $# -gt 0 ]; do
	case "$1" in
		-src | --source)
		shift
		if [ ! -f "$1" ]; then echo "ChromeOS recovery image $1 not found"; exit 1; fi
		if [ ! $(dd if="$1" bs=1 count=4 status=none | od -A n -t x1 | sed 's/ //g') == '33c0fa8e' ] || [ $(cgpt show -i 12 -b "$1") -eq 0 ] || [ $(cgpt show -i 13 -b "$1") -gt 0 ] || [ ! $(cgpt show -i 3 -l "$1") == 'ROOT-A' ]; then
			echo "$1 is not a valid ChromeOS recovey image (have you unzipped it ?)"
			exit 1
		fi
		source="$1"
		;;
		-dst | --destination)
		shift
		if [ -z "${1##/dev/*}" ]; then device=1; fi
		destination="$1"
		;;
		-s | --size)
		shift
		;;
		-h | --help)
		usage
		 ;;
		*)
		echo "$1 argument is not valid"
		usage
		exit 1
	esac
	shift
done
if [ -z "$source" ]  || [ -z "$destination" ]; then
	echo "At least the input and output parameters should be provided."
	usage
	exit 1
fi

if [[ $device = 1 ]]; then
	if [ ! -b "$destination" ] || [ ! -d /sys/block/"${destination#/dev/}" ]; then echo "$destination is not a valid disk name"; exit 1; fi
	if [ $(blockdev --getsz "$destination") -lt 16360128 ]; then echo "Not enough space on device $destination"; exit 1; fi
	read -rp "All data on device $destination will be lost, are you sure ? (type yes to continue) " confirm
	if [ -z $confirm ] || [ ! $confirm == "yes" ]; then
		echo "Invalid answer $confirm, exiting"
		exit 0
	fi
	umount "$destination"*
	if [ -f /sys/block/"${destination#/dev/}"/device/rescan ]; then echo 1 > /sys/block/"${destination#/dev/}"/device/rescan; fi
	partx -u "$destination"
	sleep 5
	if (expr match "$destination" ".*[0-9]$" >/dev/null); then
		partition="$destination"p
	else
		partition="$destination"
	fi
	loopdevice=$(losetup --show -fP "$source")
	partx -u "$loopdevice"
	sleep 5
	for i in {3,12}; do
		echo "Writing partition $i"
		case $i in
			3)
			# ROOT-A
			# source is p3 dst3/dst5 are sharing p3
			pv "$loopdevice"p3 > "$partition"3
			patch_roota "$partition"3
			;;
			12)
			# EFI
			#mkfs.msdos -n "EFI" "$partition"12
			#write_efi "$partition"12 efi-system
			;;
		esac
	done
	losetup -d "$loopdevice"
	echo "ChromeOS updated."
else
	if [ -e /dev/loop-control ]; then
		destloop=$(losetup --show -fP "$destination")
		loopdevice=$(losetup --show -fP "$source")
		partx -u "$loopdevice"
		partx -u "$destloop"
		sleep 5
		for i in {3,12}; do
			echo "Writing partition $i"
			case $i in
				3)
				dd if="$loopdevice"p3 ibs=1M status=none | pv | dd of="$destloop"p3 obs=1M status=none
				patch_roota "$destloop"p3
				;;
				12)
				#mkfs.msdos -n "EFI" "$destloop"p12
				#write_efi "$destloop"p12 efi-image
				;;
			esac
		done

		losetup -d "$loopdevice"
		losetup -d "$destloop"
	fi
	echo -e "\n ChromeOS disk image updated.\n"
fi
