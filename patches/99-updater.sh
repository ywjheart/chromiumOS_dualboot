# This patch generates a script to manually update ChromeOS and/or brunch

ret=0
cat >/roota/usr/sbin/chromeos-update <<UPDATE
#!/bin/bash

exit 1;

UPDATE
if [ ! "$?" -eq 0 ]; then ret=$((ret + (2 ** 0))); fi
chmod 0755 /roota/usr/sbin/chromeos-update
if [ ! "$?" -eq 0 ]; then ret=$((ret + (2 ** 1))); fi
exit $ret
