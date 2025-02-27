#!/bin/bash

. /srv/http/bash/common.sh

systemctl stop camilladsp

dirconfigs=$dirdata/camilladsp/configs
camilladspyml=$dirconfigs/camilladsp.yml
card=$( cat $dirsystem/asoundcard )
sed -i "/playback:/,/device:/ s/\(device: hw:\).*/\1$card,0/" $camilladspyml

camilladsp $camilladspyml &> /dev/null &
sleep 1
if pgrep -x camilladsp &> /dev/null; then
	pkill -x camilladsp
	formatok=1
else
	lineformat=$( sed -n '/playback:/,/format:/=' $camilladspyml | tail -1 )
	for format in FLOAT64LE FLOAT32LE S32LE S24LE3 S24LE S16LE; do
		sed -i "$lineformat s/\(format: \).*/\1$format/" $camilladspyml
		camilladsp $camilladspyml &> /dev/null &
		sleep 1
		if pgrep -x camilladsp &> /dev/null; then
			pkill -x camilladsp
			formatok=1
			break
		fi
	done
fi
if [[ $formatok ]]; then
	if [[ $format ]]; then
		pushstreamNotify CamillaDSP "Playback format: <wh>$format</wh>" camilladsp
		defaultyml=$dirconfigs/default_config.yml
		lineformat=$( sed -n '/playback:/,/format:/=' $defaultyml | tail -1 )
		sed -i "$lineformat s/\(format: \).*/\1$format/" $defaultyml
	fi
	sleep 1
	systemctl start camilladsp
	$dirbash/settings/camilladsp-gain.py set
else
	pushstreamNotify CamillaDSP "Playback format: <wh>Setting required</wh>" camilladsp 10000
fi
