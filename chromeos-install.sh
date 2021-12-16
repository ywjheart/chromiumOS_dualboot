#!/bin/bash
if ( ! test -z {,} ); then echo "Must be ran with \"bash\""; exit 1; fi
if [ -z $(which cgpt) ]; then echo "cgpt needs to be installed first"; exit 1; fi
if [ -z $(which pv) ]; then echo "pv needs to be installed first"; exit 1; fi
if [ $(whoami) != "root" ]; then echo "Please run with this script with sudo"; exit 1; fi

efi_size=33554432
roota_size=4294967296
setting_file=settings.cfg

if [ ! -f $setting_file ]; then
   echo "Setting file $setting_file not found."
   exit 1
fi

source $setting_file
export kernel
export kernel_ver
export kernel_file
export kernel_tar

usage()
{
	echo ""
	echo "Brunch installer: install ChromeOS on device or create disk image from the brunch framework."
	echo "Usage: chromeos_install.sh [-s X] [-l] -src chromeos_recovery_image_path -dst destination"
	echo "-src (source), --source (source)			ChromeOS recovery image"
	echo "-dst (destination), --destination (destination)	Device (e.g. /dev/sda) or Disk image file (e.g. chromeos.img)"
	echo "-s (disk image size), --size (disk image size)	Disk image output only: final image size in GB (default=7)"
	echo "-h, --help					Display this menu"
}

blocksize() {
  local path="$1"
  if [ -b "${path}" ]; then
    local dev="${path##*/}"
    local sys="/sys/block/${dev}/queue/logical_block_size"
    if [ -e "${sys}" ]; then
      cat "${sys}"
    else
      local part="${path##*/}"
      local block
      block="$(get_block_dev_from_partition_dev "${path}")"
      block="${block##*/}"
      cat "/sys/block/${block}/${part}/queue/logical_block_size"
    fi
  else
    echo 512
  fi
}

numsectors() {
  local block_size
  local sectors
  local path="$1"

  if [ -b "${path}" ]; then
    local dev="${path##*/}"
    block_size="$(blocksize "${path}")"

    if [ -e "/sys/block/${dev}/size" ]; then
      sectors="$(cat "/sys/block/${dev}/size")"
    else
      part="${path##*/}"
      block="$(get_block_dev_from_partition_dev "${path}")"
      block="${block##*/}"
      sectors="$(cat "/sys/block/${block}/${part}/size")"
    fi
  else
    local bytes
    bytes="$(stat -c%s "${path}")"
    local rem=$(( bytes % 512 ))
    block_size=512
    sectors=$(( bytes / 512 ))
    if [ "${rem}" -ne 0 ]; then
      sectors=$(( sectors + 1 ))
    fi
  fi

  echo $(( sectors * 512 / block_size ))
}

write_base_table() {
  local target="$1"
  local blocks
  block_size=$(blocksize "${target}")
  numsecs=$(numsectors "${target}")
  local curr=32768
  if [ $(( 0 & (block_size - 1) )) -gt 0 ]; then
    echo "Primary Entry Array padding is not block aligned." >&2
    exit 1
  fi
  cgpt create -p $(( 0 / block_size )) "${target}"
  blocks=$(( ${efi_size} / block_size ))
  if [ $(( ${efi_size} % block_size )) -gt 0 ]; then
     : $(( blocks += 1 ))
  fi
  cgpt add -i 12 -b $(( curr / block_size )) -s ${blocks} -t efi     -l "EFI-SYSTEM" "${target}"
  : $(( curr += blocks * block_size ))
  if [ $(( curr % 4096 )) -gt 0 ]; then
    : $(( curr += 4096 - curr % 4096 ))
  fi
  blocks=$(( ${roota_size} / block_size ))
  if [ $(( ${roota_size} % block_size )) -gt 0 ]; then
     : $(( blocks += 1 ))
  fi
  cgpt add -i 3 -b $(( curr / block_size )) -s ${blocks} -t rootfs     -l "ROOT-A" "${target}"
  : $(( curr += blocks * block_size ))
  if [ $(( curr % 4096 )) -gt 0 ]; then
    : $(( curr += 4096 - curr % 4096 ))
  fi
  blocks=$(( numsecs - (curr + 24576) / block_size ))
  cgpt add -i 1 -b $(( curr / block_size )) -s ${blocks} -t data     -l "STATE" "${target}"
  cgpt boot -p -i 12 "${target}"
  cgpt add -i 12 -B 0 "${target}"
  cgpt show "${target}"
}

write_efi() {
  local target="$1"
  local install_type="$2"
  mkdir -p /var/efi
  mount $target /var/efi
  
  cp -rv $install_type/* /var/efi/
    
  umount /var/efi
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

expand_state() {
  local target="$1"
#  printf '\000' | dd of=$target seek=$((0x464 + 3)) conv=notrunc count=1 bs=1 status=none
  e2fsck -f -y $target
  resize2fs -f $target
}

image_size=7
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
		if [ ! -z "${1##*[!0-9]*}" ] ; then
			if [ $1 -lt $image_size ] ; then
				echo "Disk image size cannot be lower than $image_size GB"
				exit 1
			fi
		else
			echo "Provided disk image size is not numeric: $1"
			exit 1
		fi
		image_size=$1
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
	write_base_table "$destination"
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
	for i in {1,3,12}; do
		echo "Writing partition $i"
		case $i in
			1)
			# STATE
			#pv "$loopdevice"1 > "$partition"1
			#expand_state "$partition"1
			mkfs.ext4 -F -b 4096 -L "H-STATE" "$partition"1
			;;
			3)
			# ROOT-A
			# source is p3 dst3/dst5 are sharing p3
			pv "$loopdevice"p3 > "$partition"3
			patch_roota "$partition"3
			;;
			12)
			# EFI
			mkfs.msdos -n "EFI" "$partition"12
			#write_efi "$partition"12 efi-system
			;;
		esac
	done
	losetup -d "$loopdevice"
	echo "ChromeOS installed."
else
	if [ -e /dev/loop-control ]; then
		if [ -f "$destination" ]; then rm "$destination"; fi
		if [[ ! $destination == *"/"* ]]; then path="."; else path="$(dirname $(realpath "$destination"))"; fi
		if [ $(( ($(df -k --output=avail "$path" | sed 1d) / 1024 / 1024) - $image_size )) -lt 0 ]; then echo "Not enough space to create image file, available space is $(( ($(df -k --output=avail $path | sed 1d) / 1024 / 1024) )) GB. If you think that this is incorrect, verify that you have correctly mounted the destination partition or if the partition is in ext4 format that there is no reserved space (cf. https://odzangba.wordpress.com/2010/02/20/how-to-free-reserved-space-on-ext4-partitions)"; exit 1; fi
		echo "Creating image file"
		dd if=/dev/zero of="$destination" bs=1G seek=$image_size count=0
		if [ ! "$?" -eq 0 ]; then echo "Could not write image here, try with sudo ?"; rm "$destination"; exit 1; fi
		write_base_table "$destination"
		sleep 5
		destloop=$(losetup --show -fP "$destination")
		loopdevice=$(losetup --show -fP "$source")
		partx -u "$loopdevice"
		partx -u "$destloop"
		sleep 5
		for i in {1,3,12}; do
			echo "Writing partition $i"
			case $i in
				1)
				#dd if="$loopdevice"p1 ibs=1M status=none | pv | dd of="$destloop"p1 obs=1M status=none
				#expand_state "$destloop"p1
				mkfs.ext4 -F -b 4096 -L "STATE" "$destloop"p1
				;;
				3)
				dd if="$loopdevice"p3 ibs=1M status=none | pv | dd of="$destloop"p3 obs=1M status=none
				patch_roota "$destloop"p3
				;;
				12)
				mkfs.msdos -n "EFI" "$destloop"p12
				#write_efi "$destloop"p12 efi-image
				;;
			esac
		done

		losetup -d "$loopdevice"
		losetup -d "$destloop"
	fi
	echo -e "\n ChromeOS disk image created.\n"
	grep -qi 'Microsoft' /proc/version || cat <<GRUB | tee "$destination".grub.txt
To boot directly from this image file, add the lines between stars to either:
- A brunch usb flashdrive grub config file (then boot from usb and choose boot from disk image in the menu),
- Or your hard disk grub install if you have one (refer to you distro's online resources).
********************************************************************************
menuentry "ChromeOS" --class "brunch" {
	rmmod tpm
	img_part=$(df "$destination" --output=source | sed 1d)
	img_path=$(if [ $(findmnt -n -o TARGET -T "$destination") == "/" ]; then echo $(realpath "$destination"); else echo $(realpath "$destination") | sed "s#$(findmnt -n -o TARGET -T "$destination")##g"; fi)
	search --no-floppy --set=disk --file \$img_path
	loopback loop (\$disk)\$img_path
	source (loop,3)/settings.cfg
	if [ -z \$verbose ] -o [ \$verbose -eq 0 ]; then
		linux (loop,3)\$kernel boot=local noresume noswap loglevel=7 \$cmdline_params \\
			cros_secure cros_debug loop.max_part=16 img_part=\$img_part img_path=\$img_path \\
			console= vt.global_cursor_default=0 quiet
	else
		linux (loop,3)\$kernel boot=local noresume noswap loglevel=7 \$cmdline_params \\
			cros_secure cros_debug loop.max_part=16 img_part=\$img_part img_path=\$img_path
	fi
	initrd (loop,3)/lib/firmware/amd-ucode.img (loop,3)/lib/firmware/intel-ucode.img (loop,3)/initramfs.img
}
********************************************************************************
GRUB
	echo -e "\n"
	if [ -f /etc/lsb-release ]; then
		grep -qi 'Microsoft' /proc/version || ! (grep -qi 'Ubuntu' /etc/lsb-release || grep -qi 'LinuxMint' /etc/lsb-release) || cat <<AUTOGRUB
If you have Ubuntu or Linux Mint installed, you can create the grub config automatically by running the below command:
********************************************************************************
echo -e '#!/bin/sh\nexec tail -n +3 \$0\n\n\n\n'"\$(sed '1,4d;\$d' \$(realpath "$destination").grub.txt)" | sudo tee /etc/grub.d/99_brunch && sudo chmod 0755 /etc/grub.d/99_brunch && sudo update-grub
********************************************************************************
AUTOGRUB
	fi
fi
