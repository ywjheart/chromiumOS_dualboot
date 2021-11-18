This project is meant to boot different chromiumOS based distros, tested with Cloudready, FydeOS, Wayne OS. Suggest to use Brunch project to boot your system if your system satisfies its system requirements, try this project only if:
1. You have a nVidia GPU, you want to dual boot with cloudready, wayneOS.
2. You want to try other ChromiumsOS based distros, other than ChromeOS.

Comparing to Brunch project, this project doesn't use ROOTC for extra logic, instead, this project carries out all modifications during installation. so NO ROOTC(save 1GB), no ROOTB(save 3GB). 
Required to use chromeos-update.sh to update an existing installation.

Usages:
1. Shrink your current partition to make space for ChromiumOS. You can use Disk Management in Windows. or gparted in Linux.

2. Boot from Ubuntu LiveUSB, or your linux installation.
Install required packages before start.

sudo apt-get update
sudo apt-get install pv -y
sudo apt-get install cgpt -y

3. Create a new partition with your preferred disk tools, can use gparted or Disks tools in Ubuntu.
Please mount it after creating.

4. Adjust settings.cfg to switch between 5.4 and 5.10, 5.4 is fine in most case. Other Brunch kernels have been removed, because both chromebook and macbook are supported by Brunch project, you should use Brunch if you are using macbook or chromebook. Of course, you can copies files from Brunch.
You may need to add broadcom_wl to option if you are using a broadcom wireless network adapter.

5. Use following commands to start a new installation, either same distro or different distro.
sudo bash chromeos-install.sh -src cloudready-free-92.4.45-64bit.bin -dst /media/ubuntu/Cloudready/cloudready.img -s 24 # in GB

replace cloudready-free-92.4.45-64bit.bin to your downloaded image file
replace /media/ubuntu/Cloudready/cloudready.img to your desired installation path.
replace 24 to your desired image size, the unit is gigabytes.

Add a boot entry to your grub, or grub4win according the info on the screen.

6. Use following commands to update an existing installation. Suggest to use it only for reinstalling or updating the same chromiumsOS distro. You may be unable to boot if update across different ChromiumOS distros, say, change from cloudready to wayneOS, or to fydeOS.

sudo bash chromeos-update.sh -src cloudready-free-92.4.45-64bit.bin -dst /media/ubuntu/Cloudready/cloudready.img

Notes:
1. The files in the packages directory are from Brunch project v93. you can always replace them. 
The files in the patches directory are from Brunch project v93, most of them have been removed in order to remove ChromeOS compatibility (Brunch project is preferred). You may add back but require code view to make sure they are working (pay attention to /proc/version, /proc/cmdline).
You can use create_release_package.sh and latest rootc.img from Brunch project to create a latest package.

2. Report issues here if you have problem on scripts provided by this project.
Send feedback to Brunch project only if your hardware is not supported by current kernels, either 5.4 or 5.10.

3. Refer to samples.sh

Project Brunch: 
https://github.com/sebanc/brunch

Cloudready OS:
https://www.neverware.com/freedownload#home-edition-overview
https://davrt8itj6cgg.cloudfront.net/cloudready-free-92.4.45-64bit/cloudready-free-92.4.45-64bit.zip

FydeOS:
https://fydeos.io/download/pc/
https://fydeos.io/download/pc/intel-hd
https://download.fydeos.io/FydeOS_for_PC_v13.0-SP2-stable.img.xz

Wayne OS:
https://wayne-os.com/category/release/
https://storage.googleapis.com/bucket-release-20200923/wayne-os-dev-installation-3q21-r1.7z

