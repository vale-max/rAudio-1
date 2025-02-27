#!/bin/bash

. /srv/http/bash/common.sh
spotifyredirect=https://rern.github.io/raudio/spotify

dirscrobble=$dirsystem/scrobble.conf
for key in airplay bluetooth spotify upnp notify; do
	scrobbleconf+=$( [[ -e $dirscrobble/$key ]] && echo true, || echo false, )
done
scrobbleconf+='"'$( cat $dirscrobble/user 2> /dev/null )'", ""'

data+='
  "page"             : "features"
, "autoplay"         : '$( ls $dirsystem/autoplay* &> /dev/null && echo true )'
, "autoplayconf"     : [ '$( exists $dirsystem/autoplaybt )', '$( exists $dirsystem/autoplaycd )', '$( exists $dirsystem/autoplay )' ]
, "bluetoothsink"    : '$( cut -d' ' -f2 $dirshm/btconnected 2> /dev/null | grep -q Sink && echo true )'
, "camilladsp"       : '$( exists $dirsystem/camilladsp )'
, "camillarefresh"   : '$( grep 'status_update_interval' /srv/http/settings/camillagui/config/gui-config.yml | cut -d' ' -f2 )'
, "equalizer"        : '$( exists $dirsystem/equalizer )'
, "hostname"         : "'$( hostname )'"
, "latest"           : '$( exists $dirsystem/latest )'
, "lcd"              : '$( grep -q 'waveshare\|tft35a' /boot/config.txt 2> /dev/null && echo true )'
, "login"            : '$( exists $dirsystem/login )'
, "lyricsembedded"   : '$( [[ -e $dirsystem/lyricsembedded ]] && echo true )'
, "multiraudio"      : '$( exists $dirsystem/multiraudio )'
, "multiraudioconf"  : [ '$( sed 's/^/"/; s/$/", /' $dirsystem/multiraudio.conf 2> /dev/null | sed '$ s/,//' )' ]
, "nosound"          : '$( exists $dirshm/nosound )'
, "scrobble"         : '$( [[ -e $dirsystem/scrobble ]] && echo true )'
, "scrobbleconf"     : ['$scrobbleconf']
, "scrobblekey"      : '$( [[ -e $dirsystem/scrobble.conf/key ]] && echo true )'
, "stoptimer"        : '$( [[ -e $dirshm/stoptimer ]] && echo true )'
, "stoptimerconf"    : '$( cat $dirshm/stoptimer 2> /dev/null || echo [ false, false ] )'
, "streaming"        : '$( grep -q 'type.*"httpd"' /etc/mpd.conf && echo true )
[[ -e /usr/bin/hostapd ]] && data+='
, "hostapd"          : '$( systemctl -q is-active hostapd && echo true )'
, "hostapdconf"      : '$( $dirbash/settings/features.sh hostapdget )'
, "ssid"             : "'$( awk -F'=' '/^ssid/ {print $2}' /etc/hostapd/hostapd.conf | sed 's/"/\\"/g' )'"
, "wlanconnected"    : '$( ip r | grep -q "^default.*wlan0" && echo true )
[[ -e /usr/bin/shairport-sync ]] && data+='
, "shairport-sync"   : '$( systemctl -q is-active shairport-sync && echo true )'
, "shairportactive"  : '$( [[ $( cat $dirshm/player ) == airplay ]] && echo true )
[[ -e /usr/bin/snapserver ]] && data+='
, "snapserver"       : '$( systemctl -q is-active snapserver && echo true )'
, "snapserveractive" : '$( [[ -e $dirshm/clientip || -e $dirshm/snapclientactive ]] && echo true )'
, "snapclient"       : '$( exists $dirsystem/snapclient )'
, "snapclientactive" : '$( systemctl -q is-active snapclient && echo true )'
, "snapcastconf"     : '$( grep -q latency /etc/default/snapclient && grep latency /etc/default/snapclient | tr -d -c 0-9 || echo 800 )
[[ -e /usr/bin/spotifyd ]] && data+='
, "spotifyd"         : '$( systemctl -q is-active spotifyd && echo true )'
, "spotifydactive"   : '$( [[ $( cat $dirshm/player ) == spotify ]] && echo true )'
, "spotifyredirect"  : "'$spotifyredirect'"
, "spotifytoken"     : '$( grep -q refreshtoken $dirsystem/spotify 2> /dev/null && echo true )
[[ -e /usr/bin/upmpdcli ]] && data+='
, "upmpdcli"         : '$( systemctl -q is-active upmpdcli && echo true )'
, "upmpdcliactive"   : '$( [[ $( cat $dirshm/player ) == upnp ]] && echo true )'
, "upmpdcliownqueue" : '$( grep -q 'ownqueue = 1' /etc/upmpdcli.conf && echo true )
if [[ -e /etc/X11/xinit/xinitrc ]]; then
	brightnessfile=/sys/class/backlight/rpi_backlight/brightness
	[[ -e $brightnessfile ]] && brightness=$( cat $brightnessfile )
	if [[ -e $dirsystem/localbrowser.conf ]]; then
		conf=$( awk NF $dirsystem/localbrowser.conf \
				| sed 's/^/,"/; s/=/":/' \
				| sed 's/\(.*rotate.*:\)\(.*\)/\1"\2"/' )
		conf+=', "brightness" : '$brightness
		localbrowserconf="{${conf:1}}"
	else
		localbrowserconf='{ "rotate": "NORMAL", "zoom": 100, "screenoff": 0, "playon": false, "cursor": false, "brightness": '$brightness' }'
	fi
	data+='
, "localbrowser"     : '$( systemctl -q is-active localbrowser && echo true )'
, "localbrowserconf" : '$localbrowserconf
fi
if [[ -e /usr/bin/smbd ]]; then
	grep -A1 /mnt/MPD/SD /etc/samba/smb.conf | grep -q 'read only = no' && writesd=true || writesd=false
	grep -A1 /mnt/MPD/USB /etc/samba/smb.conf | grep -q 'read only = no' && writeusb=true || writeusb=false
	smbconf="[ $writesd, $writeusb ]"
	data+='
, "smb"              : '$( systemctl -q is-active smb && echo true )'
, "smbconf"          : '$smbconf
fi

data2json "$data"
