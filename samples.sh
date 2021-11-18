#!/bin/sh
sudo apt-get update
sudo apt-get install pv -y
sudo apt-get install cgpt -y

# if install cloudready
#sudo bash chromeos-install.sh -src cloudready-free-92.4.45-64bit.bin -dst /media/ubuntu/Cloudready/cloudready.img -s 24 # in GB

# if install fydeOS
#sudo bash chromeos-install.sh -src FydeOS_for_PC_v13.0-SP2-stable.img -dst /media/ubuntu/FYDEOS/fydeos.img -s 24 # in GB

# if install wayneOS
#sudo bash chromeos-install.sh -src wayne-os-dev-installation-3q21-r1.bin -dst /media/ubuntu/WayneOS/wayneos.img -s 24 # in GB


# if update cloudready
#sudo bash chromeos-update.sh -src cloudready-free-92.4.45-64bit.bin -dst /media/ubuntu/Cloudready/cloudready.img

# if update fydeOS
#sudo bash chromeos-update.sh -src FydeOS_for_PC_v13.0-SP2-stable.img -dst /media/ubuntu/FYDEOS/fydeos.img

# if update wayneOS
#sudo bash chromeos-update.sh -src wayne-os-dev-installation-3q21-r1.bin -dst /media/ubuntu/WayneOS/wayneos.img
