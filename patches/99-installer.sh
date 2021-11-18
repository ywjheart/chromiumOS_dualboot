# This patch generates a script to install ChromeOS from a running ChromeOS environment

ret=0
cat >/roota/usr/sbin/chromeos-install <<INSTALL
#!/bin/bash

exit 1;

INSTALL
if [ ! "$?" -eq 0 ]; then ret=$((ret + (2 ** 0))); fi
chmod 0755 /roota/usr/sbin/chromeos-install
if [ ! "$?" -eq 0 ]; then ret=$((ret + (2 ** 1))); fi
exit $ret
