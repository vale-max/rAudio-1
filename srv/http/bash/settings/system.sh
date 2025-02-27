#!/bin/bash

. /srv/http/bash/common.sh
fileconfig=/boot/config.txt
filemodule=/etc/modules-load.d/raspberrypi.conf

# convert each line to each args
readarray -t args <<< "$1"

pushReboot() {
	pushRefresh
	pushstreamNotify "${1//\"/\\\"}" 'Reboot required.' $2 5000
	echo $1 >> $dirshm/reboot
}
pushRefresh() {
	data=$( $dirbash/settings/system-data.sh )
	pushstream refresh "$data"
}
I2Cset() {
	# parse finalized settings
	grep -q 'waveshare\|tft35a' $fileconfig && lcd=1
	[[ -e $dirsystem/lcdchar ]] && grep -q inf=i2c $dirsystem/lcdchar.conf && I2Clcdchar=1
	if [[ -e $dirsystem/mpdoled ]]; then
		chip=$( grep mpd_oled /etc/systemd/system/mpd_oled.service | cut -d' ' -f3 )
		if [[ $chip != 1 && $chip != 7 ]]; then
			I2Cmpdoled=1
			[[ ! $baud ]] && baud=$( grep dtparam=i2c_arm_baudrate $fileconfig | cut -d= -f3 )
		else
			SPImpdoled=1
		fi
	fi

	# reset
	sed -i '/dtparam=i2c_arm=on\|dtparam=spi=on\|dtparam=i2c_arm_baudrate/ d' $fileconfig
	sed -i '/i2c-bcm2708\|i2c-dev\|^\s*$/ d' $filemodule
	[[ -s $filemodule ]] || rm -f $filemodule

	# dtparam=i2c_arm=on
	[[ $lcd || $I2Clcdchar || $I2Cmpdoled ]] && echo dtparam=i2c_arm=on >> $fileconfig
	# dtparam=spi=on
	[[ $lcd || $SPImpdoled ]] && echo dtparam=spi=on >> $fileconfig
	# dtparam=i2c_arm_baudrate=$baud
	[[ $I2Cmpdoled ]] && echo dtparam=i2c_arm_baudrate=$baud >> $fileconfig
	# i2c-dev
	[[ $lcd || $I2Clcdchar || $I2Cmpdoled ]] && echo i2c-dev >> $filemodule
	# i2c-bcm2708
	[[ $lcd || $I2Clcdchar ]] && echo i2c-bcm2708 >> $filemodule
}
soundProfile() {
	if [[ $1 == reset ]]; then
		swappiness=60
		mtu=1500
		txqueuelen=1000
		rm -f $dirsystem/soundprofile
	else
		. $dirsystem/soundprofile.conf
		touch $dirsystem/soundprofile
	fi
	sysctl vm.swappiness=$swappiness
	if ifconfig | grep -q eth0; then
		ip link set eth0 mtu $mtu
		ip link set eth0 txqueuelen $txqueuelen
	fi
}

case ${args[0]} in

bluetooth )
	sleep 3
	[[ -e $dirsystem/btdiscoverable ]] && yesno=yes || yesno=no
	bluetoothctl discoverable $yesno &
	bluetoothctl discoverable-timeout 0 &
	bluetoothctl pairable yes &
	;;
bluetoothdisable )
	systemctl disable --now bluetooth
	pkill bluetooth
	rm -f $dirshm/{btdevice,btreceiver,btsender}
	grep -q 'device.*bluealsa' /etc/mpd.conf && $dirbash/settings/player-conf.sh
	pushRefresh
	;;
bluetoothstatus )
	echo "\
<bll># bluetoothctl show</bll>

$( bluetoothctl show )"
	;;
bluetoothset )
	btdiscoverable=${args[1]}
	btformat=${args[2]}
	if [[ $btdiscoverable == true ]]; then
		yesno=yes
		touch $dirsystem/btdiscoverable
	else
		yesno=no
		rm $dirsystem/btdiscoverable
	fi
	! systemctl -q is-active bluetooth && systemctl enable --now bluetooth
	bluetoothctl discoverable $yesno &
	[[ -e $dirsystem/btformat  ]] && prevbtformat=true || prevbtformat=false
	[[ $btformat == true ]] && touch $dirsystem/btformat || rm $dirsystem/btformat
	[[ $mpdrestart || $btformat != $prevbtformat ]] && $dirbash/settings/player-conf.sh bton
	pushRefresh
	;;
databackup )
	dirconfig=$dirdata/config
	backupfile=$dirdata/tmp/backup.gz
	rm -f $backupfile
	alsactl store
	files=(
/boot/cmdline.txt
/boot/config.txt
/boot/shutdown.sh
/boot/startup.sh
/etc/conf.d/wireless-regdom
/etc/default/snapclient
/etc/hostapd/hostapd.conf
/etc/samba/smb.conf
/etc/systemd/network/eth.network
/etc/systemd/timesyncd.conf
/etc/X11/xorg.conf.d/99-calibration.conf
/etc/X11/xorg.conf.d/99-raspi-rotate.conf
/etc/fstab
/etc/mpd.conf
/etc/mpdscribble.conf
/etc/upmpdcli.conf
/var/lib/alsa/asound.state
)
	for file in ${files[@]}; do
		if [[ -e $file ]]; then
			mkdir -p $dirconfig/$( dirname $file )
			cp {,$dirconfig}$file
		fi
	done
	hostname > $dirsystem/hostname
	timedatectl | awk '/zone:/ {print $3}' > $dirsystem/timezone
	readarray -t profiles <<< $( ls -p /etc/netctl | grep -v / )
	if [[ $profiles ]]; then
		cp -r /etc/netctl $dirconfig/etc
		for profile in "${profiles[@]}"; do
			if [[ $( netctl is-enabled "$profile" ) == enabled ]]; then
				echo $profile > $dirsystem/netctlprofile
				break
			fi
		done
	fi
	mkdir -p $dirconfig/var/lib
	cp -r /var/lib/bluetooth $dirconfig/var/lib &> /dev/null
	
	services='bluetooth hostapd localbrowser mpdscribble@mpd powerbutton shairport-sync smb snapclient snapserver spotifyd upmpdcli'
	for service in $services; do
		systemctl -q is-active $service && enable+=" $service" || disable+=" $service"
	done
	[[ $enable ]] && echo $enable > $dirsystem/enable
	[[ $disable ]] && echo $disable > $dirsystem/disable
	
	bsdtar \
		--exclude './addons' \
		--exclude './embedded' \
		--exclude './shm' \
		--exclude './system/version' \
		--exclude './tmp' \
		-czf $backupfile \
		-C /srv/http \
		data \
		2> /dev/null && echo 1
	
	rm -rf $dirdata/{config,disable,enable}
	;;
datarestore )
	backupfile=$dirdata/tmp/backup.gz
	dirconfig=$dirdata/config
	systemctl stop mpd
	# remove all flags
	rm -f $dirsystem/{autoplay,login*}                          # features
	rm -f $dirsystem/{crossfade*,custom*,dop*,mixertype*,soxr*} # mpd
	rm -f $dirsystem/{updating,listing}                         # updating_db
	rm -f $dirsystem/{color,relays,soundprofile}                # system
	
	bsdtar -xpf $backupfile -C /srv/http
	
	uuid1=$( head -1 /etc/fstab | cut -d' ' -f1 )
	uuid2=${uuid1:0:-1}2
	sed -i "s/root=.* rw/root=$uuid2 rw/; s/elevator=noop //" $dirconfig/boot/cmdline.txt
	sed -i "s/^PARTUUID=.*-01  /$uuid1  /; s/^PARTUUID=.*-02  /$uuid2  /" $dirconfig/etc/fstab
	
	rm -f $dirconfig/etc/{shairport-sync,spotifyd}.conf # temp: for ealier version
	cp -rf $dirconfig/* /
	[[ -e $dirsystem/enable ]] && systemctl -q enable $( cat $dirsystem/enable )
	[[ -e $dirsystem/disable ]] && systemctl -q disable $( cat $dirsystem/disable )
	if systemctl -q is-enabled camilladsp; then
		modprobe snd-aloop
		echo snd-aloop > /etc/modules-load.d/loopback.conf
	fi
	hostnamectl set-hostname $( cat $dirsystem/hostname )
	if [[ -e $dirsystem/mirror ]]; then
		mirror=$( cat $dirsystem/mirror )
		sed -i "0,/^Server/ s|//.*mirror|//$mirror.mirror|" /etc/pacman.d/mirrorlist
	fi
	[[ -e $dirsystem/netctlprofile ]] && netctl enable "$( cat $dirsystem/netctlprofile )"
	timedatectl set-timezone $( cat $dirsystem/timezone )
	rm -rf $backupfile $dirconfig $dirsystem/{enable,disable,hostname,netctlprofile,timezone}
	[[ -e $dirsystem/crossfade ]] && mpc crossfade $( cat $dirsystem/crossfade.conf )
	rmdir /mnt/MPD/NAS/* &> /dev/null
	chown -R http:http /srv/http
	chown mpd:audio $dirdata/mpd/mpd* &> /dev/null
	readarray -t mountpoints <<< $( grep /mnt/MPD/NAS /etc/fstab | awk '{print $2}' | sed 's/\\040/ /g' )
	if [[ $mountpoints ]]; then
		for mountpoint in $mountpoints; do
			mkdir -p "$mountpoint"
		done
	fi
	mountpoint=/srv/http/shareddata
	if grep -q $mountpoint /etc/fstab; then
		mkdir -p $mountpoint
		chown http:http $mountpoint
		chmod 777 $mountpoint
		std=$( mount $mountpoint )
		if [[ $? == 0 ]]; then
			for dir in audiocd bookmarks lyrics mpd playlists webradios webradiosimg; do
				rm -rf $dirdata/$dir
				ln -s $mountpoint/$dir $dirdata
			done
		fi
	fi
	
	# temp 20220312 ###
	readarray -t plfiles <<< $( ls -I '*.*' $dirplaylists )
	if [[ $plfiles ]]; then
		echo -e "\n\e[38;5;6m\e[48;5;6m . \e[0m Convert saved playlists ..."
		for name in "${plfiles[@]}"; do
			echo $name
			plfile="$dirplaylists/$name"
			list=$( grep '"file":' "$plfile" | sed 's/^\s*"file": "//; s/",$//; s/\\//g' )
			if grep -q '^\s*"Range": ' "$plfile"; then
				readarray -t file_track <<< $( grep -B1 -A5 '"Range":' "$plfile" \
												| grep '"file":\|"Track":' \
												| sed 's/^\s*"file": "\|^\s*"Track": //; s/",$\|,$//; s/\\//g' )
				iL=${#file_track[@]}
				for (( i=0; i < iL; i++ )); do
					track=000${file_track[$(( i + 1 ))]}
					file=${file_track[i]}
					filecue="${file%.*}.cue/track${track: -4}"
					list=$( sed "s|$file|$filecue|" <<< "$list" )
					(( i++ ))
				done
			fi
			echo "$list" > "$plfile.m3u"
		    rm "$plfile"
		done
	fi
	# temp 20220312 ###
	
	chown -R http:http /srv/http/{assets,bash,settings}
	chmod 755 /srv/http/* $dirbash/* /srv/http/settings/*
	[[ -e $dirsystem/color ]] && $dirbash/cmd.sh color
	$dirbash/cmd.sh power$'\n'reboot
	;;
fstabget )
	echo -e "\
<bll># cat /etc/fstab</bll>
$( cat /etc/fstab )

<bll># mount | grep ^/dev</bll>
$( mount | grep ^/dev | sort )"
	;;
hddspindown )
	duration=${args[1]}
	dev=${args[2]}
	grep -q 'APM.*not supported' <<< $( hdparm -B $dev ) && echo -1 && exit
	
	if [[ $duration == 0 ]]; then
		apm=128
		rm -f $dirsystem/hddspindown
	else
		apm=127
		echo "$duration" > $dirsystem/hddspindown
	fi
	hdparm -q -B $apm $dev
	hdparm -q -S $duration $dev
	pushRefresh
	;;
hostname )
	hostname=${args[1]}
	hostnamectl set-hostname $hostname
	sed -i "s/^\(ssid=\).*/\1${args[1]}/" /etc/hostapd/hostapd.conf
	sed -i '/^\tname =/ s/".*"/"'$hostname'"/' /etc/shairport-sync.conf
	sed -i "s/^\(friendlyname = \).*/\1${args[1]}/" /etc/upmpdcli.conf
	rm -f /root/.config/chromium/SingletonLock 	# 7" display might need to rm: SingletonCookie SingletonSocket
	systemctl try-restart avahi-daemon bluetooth hostapd localbrowser mpd smb shairport-sync shairport-meta spotifyd upmpdcli
	pushRefresh
	;;
i2smodule )
	aplayname=${args[1]}
	output=${args[2]}
	dtoverlay=$( grep 'dtparam=i2c_arm=on\|dtparam=krnbt=on\|dtparam=spi=on\|dtoverlay=gpio\|dtoverlay=sdtweak,poll_once\|waveshare\|tft35a\|hdmi_force_hotplug=1' $fileconfig )
	if [[ $aplayname != onboard ]]; then
		dtoverlay+="
dtparam=i2s=on
dtoverlay=$aplayname"
		[[ $output == 'Pimoroni Audio DAC SHIM' ]] && dtoverlay+="
gpio=25=op,dh"
		[[ $aplayname == rpi-cirrus-wm5102 ]] && echo softdep arizona-spi pre: arizona-ldo1 > /etc/modprobe.d/cirrus.conf
		! grep -q gpio-shutdown $fileconfig && systemctl disable --now powerbutton
	else
		dtoverlay+="
dtparam=audio=on"
		revision=$( awk '/Revision/ {print $NF}' /proc/cpuinfo )
		revision=${revision: -3:2}
		[[ $revision == 09 || $revision == 0c ]] && output='HDMI 1' || output=Headphones
		aplayname="bcm2835 $output"
		output="On-board - $output"
		rm -f $dirsystem/audio-* /etc/modprobe.d/cirrus.conf
	fi
	sed -i '/dtparam=\|dtoverlay=\|gpio=25=op,dh\|^$/ d' $fileconfig
	echo "$dtoverlay" | sed '/^$/ d' >> $fileconfig
	echo $aplayname > $dirsystem/audio-aplayname
	echo $output > $dirsystem/audio-output
	pushReboot 'Audio I&#178;S module' i2saudio
	;;
journalctl )
	filebootlog=/tmp/bootlog
	if [[ -e $filebootlog ]]; then
		journal=$( cat $filebootlog )
	else
		journal=$( journalctl -b | sed -n '1,/Startup finished.*kernel/ p' )
		if grep -q 'Startup finished.*kernel' <<< "$journal"; then
			echo "$journal" > $filebootlog
		else
			journal+='
(Starting ...)
'
		fi
	fi
	echo "\
<bll># journalctl -b</bll>
$journal
"
	;;
lcdcalibrate )
	degree=$( grep rotate $fileconfig | cut -d= -f3 )
	cp -f /etc/X11/{lcd$degree,xorg.conf.d/99-calibration.conf}
	systemctl stop localbrowser
	value=$( DISPLAY=:0 xinput_calibrator | grep Calibration | cut -d'"' -f4 )
	if [[ $value ]]; then
		sed -i "s/\(Calibration\"  \"\).*/\1$value\"/" /etc/X11/xorg.conf.d/99-calibration.conf
		systemctl start localbrowser
	fi
	;;
lcdchar )
	kill -9 $( pgrep lcdchar ) &> /dev/null
	$dirbash/lcdcharinit.py
	$dirbash/lcdchar.py ${args[1]}
	;;
lcdchardisable )
	rm $dirsystem/lcdchar
	I2Cset
	$dirbash/lcdchar.py clear
	pushRefresh
	;;
lcdcharset )
	# 0cols 1charmap 2inf 3i2caddress 4i2cchip 5pin_rs 6pin_rw 7pin_e 8pins_data 9backlight
	conf="\
[var]
cols=${args[1]}
charmap=${args[2]}"
	if [[ ${args[3]} == i2c ]]; then
		conf+="
inf=i2c
address=${args[4]}
chip=${args[5]}"
		! ls /dev/i2c* &> /dev/null && reboot=1
	else
		conf+="
inf=gpio
pin_rs=${args[6]}
pin_rw=${args[7]}
pin_e=${args[8]}
pins_data=[$( echo ${args[@]:9:4} | tr ' ' , )]"
	fi
	conf+="
backlight=${args[13]^}"
	echo "$conf" > $dirsystem/lcdchar.conf
	touch $dirsystem/lcdchar
	I2Cset
	if [[ $reboot ]]; then
		pushReboot 'Character LCD' lcdchar
	else
		$dirbash/lcdchar.py logo
		pushRefresh
	fi
	;;
lcddisable )
	sed -i 's/ fbcon=map:10 fbcon=font:ProFont6x11//' /boot/cmdline.txt
	sed -i '/hdmi_force_hotplug\|rotate=/ d' $fileconfig
	sed -i '/incognito/ i\	--disable-software-rasterizer \\' $dirbash/xinitrc
	sed -i 's/fb1/fb0/' /etc/X11/xorg.conf.d/99-fbturbo.conf
	I2Cset
	pushRefresh
	;;
lcdset )
	model=${args[1]}
	if [[ $model != tft35a ]]; then
		echo $model > $dirsystem/lcdmodel
	else
		rm $dirsystem/lcdmodel
	fi
	sed -i '1 s/$/ fbcon=map:10 fbcon=font:ProFont6x11/' /boot/cmdline.txt
	sed -i '/hdmi_force_hotplug\|rotate=/ d' $fileconfig
	echo "\
hdmi_force_hotplug=1
dtoverlay=$model:rotate=0" >> $fileconfig
	cp -f /etc/X11/{lcd0,xorg.conf.d/99-calibration.conf}
	sed -i '/disable-software-rasterizer/ d' $dirbash/xinitrc
	sed -i 's/fb0/fb1/' /etc/X11/xorg.conf.d/99-fbturbo.conf
	I2Cset
	if [[ $( uname -m ) == armv7l ]] && ! grep -q no-xshm /srv/http/bash/xinitrc; then
		sed -i '/^chromium/ a\	--no-xshm \\' /srv/http/bash/xinitrc
	fi
	systemctl enable localbrowser
	pushReboot 'TFT 3.5" LCD' lcd
	;;
mirrorlist )
	file=/etc/pacman.d/mirrorlist
	current=$( grep ^Server $file \
				| head -1 \
				| sed 's|\.*mirror.*||; s|.*//||' )
	[[ ! $current ]] && current=0
	if ! grep -q '^###' $file; then
		pushstreamNotifyBlink 'Mirror List' 'Get ...' globe
		curl -skL https://github.com/archlinuxarm/PKGBUILDs/raw/master/core/pacman-mirrorlist/mirrorlist -o $file
	fi
	readarray -t lines <<< $( awk NF $file \
								| sed -n '/### A/,$ p' \
								| sed 's/ (not Austria\!)//; s/.mirror.*//; s|.*//||' )
	clist='"Auto (by Geo-IP)"'
	codelist=0
	for line in "${lines[@]}"; do
		if [[ ${line:0:4} == '### ' ]];then
			city=
			country=${line:4}
		elif [[ ${line:0:3} == '## ' ]];then
			city=${line:3}
		else
			[[ $city ]] && cc="$country - $city" || cc=$country
			clist+=',"'$cc'"'
			codelist+=',"'$line'"'
		fi
	done
	echo '{
  "country" : [ '$clist' ]
, "current" : "'$current'"
, "code"    : [ '$codelist' ]
}'
	;;
mount )
	protocol=${args[1]}
	mountpoint="/mnt/MPD/NAS/${args[2]}"
	ip=${args[3]}
	directory=${args[4]}
	user=${args[5]}
	password=${args[6]}
	extraoptions=${args[7]}
	update=${args[8]}

	! ping -c 1 -w 1 $ip &> /dev/null && echo "IP <code>$ip</code> not found." && exit

	if [[ -e $mountpoint ]]; then
		find "$mountpoint" -mindepth 1 | read && echo "Mount name <code>$mountpoint</code> not empty." && exit
	else
		mkdir "$mountpoint"
	fi
	chown mpd:audio "$mountpoint"
	if [[ $protocol == cifs ]]; then
		source="//$ip/$directory"
		options=noauto
		if [[ ! $user ]]; then
			options+=,username=guest
		else
			options+=",username=$user,password=$password"
		fi
		options+=,uid=$( id -u mpd ),gid=$( id -g mpd ),iocharset=utf8
	else
		source="$ip:$directory"
		options=defaults,noauto,bg,soft,timeo=5
	fi
	[[ $extraoptions ]] && options+=,$extraoptions
	echo "${source// /\\040}  ${mountpoint// /\\040}  $protocol  ${options// /\\040}  0  0" >> /etc/fstab
	std=$( mount "$mountpoint" 2>&1 )
	if [[ $? == 0 ]]; then
		[[ $update == true ]] && $dirbash/cmd.sh mpcupdate$'\n'"${mountpoint:9}"  # /mnt/MPD/NAS/... > NAS/...
		for i in {1..5}; do
			sleep 1
			mount | grep -q "$mountpoint" && break
		done
		pushRefresh
	else
		echo "Mount <code>$source</code> failed:<br>"$( echo "$std" | head -1 | sed 's/.*: //' )
		sed -i "\|${mountpoint// /\\040}| d" /etc/fstab
		rmdir "$mountpoint"
	fi
	;;
mpdoleddisable )
	rm $dirsystem/mpdoled
	I2Cset
	$dirbash/settings/player-conf.sh
	pushRefresh
	;;
mpdoledset )
	chip=${args[1]}
	baud=${args[2]}
	if [[ $( grep mpd_oled /etc/systemd/system/mpd_oled.service | cut -d' ' -f3 ) != $chip ]]; then
		sed -i "s/-o ./-o $chip/" /etc/systemd/system/mpd_oled.service
		systemctl daemon-reload
	fi
	if [[ $chip != 1 && $chip != 7 ]]; then
		[[ $( grep dtparam=i2c_arm_baudrate $fileconfig | cut -d= -f3 ) != $baud ]] && reboot=1
		! ls /dev/i2c* &> /dev/null && reboot=1
	else
		! grep -q dtparam=spi=on $fileconfig && reboot=1
	fi
	touch $dirsystem/mpdoled
	I2Cset
	if [[ $reboot ]]; then
		pushReboot 'Spectrum OLED' mpdoled
	else
		pushRefresh
	fi
	;;
powerbuttondisable )
	systemctl disable --now powerbutton
	gpio -1 write $( grep led $dirsystem/powerbutton.conf | cut -d= -f2 ) 0
	sed -i '/gpio-shutdown/ d' $fileconfig
	pushRefresh
	;;
powerbuttonset )
	sw=${args[1]}
	led=${args[2]}
	reserved=${args[3]}
	echo "\
sw=$sw
led=$led
reserved=$reserved" > $dirsystem/powerbutton.conf
	prevreserved=$( grep gpio-shutdown $fileconfig | cut -d= -f3 )
	sed -i '/gpio-shutdown/ d' $fileconfig
	systemctl restart powerbutton
	systemctl enable powerbutton
	if [[ $sw == 5 ]]; then
		pushRefresh
	else
		sed -i "/disable_overscan/ a\dtoverlay=gpio-shutdown,gpio_pin=$reserved" $fileconfig
		[[ $reserved != $prevreserved ]] && pushReboot 'Power Button' power
	fi
	;;
relaysdisable )
	rm -f $dirsystem/relays
	pushRefresh
	pushstream display '{"submenu":"relays","value":false}'
	;;
remount )
	mountpoint=${args[1]}
	source=${args[2]}
	if [[ ${mountpoint:9:3} == NAS ]]; then
		mount "$mountpoint"
	else
		udevil mount "$source"
	fi
	pushRefresh
	;;
remove )
	mountpoint=${args[1]}
	umount -l "$mountpoint"
	rmdir "$mountpoint" &> /dev/null
	sed -i "\|${mountpoint// /\\\\040}| d" /etc/fstab
	$dirbash/cmd.sh mpcupdate$'\n'NAS
	pushRefresh
	;;
rotaryencoderdisable )
	systemctl disable --now rotaryencoder
	pushRefresh
	;;
rotaryencoderset )
	echo "\
pina=${args[1]}
pinb=${args[2]}
pins=${args[3]}
step=${args[4]}" > $dirsystem/rotaryencoder.conf
	systemctl restart rotaryencoder
	systemctl enable rotaryencoder
	pushRefresh
	;;
servers )
	ntp=${args[1]}
	mirror=${args[2]}
	file=/etc/systemd/timesyncd.conf
	prevntp=$( grep ^NTP $file | cut -d= -f2 )
	if [[ $ntp != $prevntp ]]; then
		sed -i "s/^\(NTP=\).*/\1$ntp/" $file
		ntpdate $ntp
	fi
	if [[ $mirror ]]; then
		file=/etc/pacman.d/mirrorlist
		prevmirror=$( grep ^Server $file \
						| head -1 \
						| sed 's|\.*mirror.*||; s|.*//||' )
		if [[ $mirror != $prevmirror ]]; then
			if [[ $mirror == 0 ]]; then
				mirror=
				rm $dirsystem/mirror
			else
				echo $mirror > $dirsystem/mirror
				mirror+=.
			fi
			sed -i "0,/^Server/ s|//.*mirror|//${mirror}mirror|" $file
		fi
	fi
	pushRefresh
	;;
shareddatadisable )
	copydata=${args[1]}
	mountpoint=/srv/http/shareddata
	ip=$( ifconfig | grep inet.*broadcast | head -1 | awk '{print $2}' )
	sed -i "/$ip/ d" $mountpoint/iplist
	[[ $( grep . $mountpoint/iplist | wc -l ) == 0 ]] && rm $mountpoint/iplist
	for dir in audiocd bookmarks lyrics mpd playlists webradios webradiosimg; do
		rm -rf $dirdata/$dir
		[[ $copydata == true ]] && cp -rf $mountpoint/$dir $dirdata || mkdir $dirdata/$dir
	done
	umount -l $mountpoint
	sed -i "\|$mountpoint| d" /etc/fstab
	rm -rf $mountpoint
	chown -R http:http $dirdata
	chown -R mpd:audio $dirdata/mpd
	pushRefresh
	if [[ $copydata == false ]]; then
		rm -f $dirmpd/{updating,listing}
		systemctl restart mpd
		$dirbash/cmd.sh mpcupdate
	fi
	;;
shareddata )
	protocol=${args[1]}
	ip=${args[2]}
	directory=${args[3]}
	user=${args[4]}
	password=${args[5]}
	extraoptions=${args[6]}
	copydata=${args[7]}
	
	! ping -c 1 -w 1 $ip &> /dev/null && echo "IP <code>$ip</code> not found." && exit
	
	if [[ $protocol == cifs ]]; then
		source="//$ip/$directory"
		options=noauto
		if [[ ! $user ]]; then
			options+=,username=guest
		else
			options+=",username=$user,password=$password"
		fi
		options+=,uid=$( id -u mpd ),gid=$( id -g mpd ),iocharset=utf8,file_mode=0777,dir_mode=0777
	else
		source="$ip:$directory"
		options=defaults,noauto,bg,soft,timeo=5
	fi
	[[ $extraoptions ]] && options+=,$extraoptions
	mountpoint=/srv/http/shareddata
	mkdir -p $mountpoint
	echo "${source// /\\040}  $mountpoint  $protocol  ${options// /\\040}  0  0" >> /etc/fstab
	std=$( mount $mountpoint )
	if [[ $? == 0 ]]; then
		for i in {1..5}; do
			sleep 1
			mount | grep -q "$mountpoint" && break
		done
		for dir in audiocd bookmarks lyrics mpd playlists webradios webradiosimg; do
			if [[ $copydata == true ]]; then
				rm -rf $mountpoint/$dir
				cp -rf $dirdata/$dir $mountpoint
			else
				mkdir -p $mountpoint/$dir
			fi
			rm -rf $dirdata/$dir
			ln -s $mountpoint/$dir $dirdata
		done
		ifconfig | grep inet.*broadcast | head -1 | awk '{print $2}' >> $mountpoint/iplist
		chown -h http:http $mountpoint/*/
		chown -h mpd:audio $mountpoint $mountpoint/{mpd,playlist}
		pushRefresh
		[[ $copydata == false ]] && systemctl restart mpd
	else
		echo "Mount <code>$source</code> failed:<br>"$( echo "$std" | head -1 | sed 's/.*: //' )
		sed -i "\|$mountpoint| d" /etc/fstab
		rm -rf $mountpoint
		exit
	fi
	;;
soundprofile )
	soundProfile
	;;
soundprofiledisable )
	soundProfile reset
	pushRefresh
	;;
soundprofileget )
	echo "\
<bll># sysctl vm.swappiness
# ifconfig eth0 | grep 'mtu\\|txq'</bll>

$( sysctl vm.swappiness )
$( ifconfig eth0 \
	| grep 'mtu\|txq' \
	| sed 's/.*\(mtu.*\)/\1/; s/.*\(txq.*\) (.*/\1/; s/ / = /' )"
	;;
soundprofileset )
	if [[ ${args[@]:1:4} == '60 1500 1000' ]]; then
		rm -f $dirsystem/soundprofile.conf
		soundProfile reset
	else
		echo -n "\
swappiness=${args[2]}
mtu=${args[3]}
txqueuelen=${args[4]}
" > $dirsystem/soundprofile.conf
		soundProfile
	fi
	pushRefresh
	;;
statusonboard )
	ifconfig
	if systemctl -q is-active bluetooth; then
		echo '<hr>'
		bluetoothctl show | sed 's/^\(Controller.*\)/bluetooth: \1/'
	fi
	;;
systemconfig )
	config="\
<bll># cat /boot/cmdline.txt</bll>
$( cat /boot/cmdline.txt )

<bll># cat /boot/config.txt</bll>
$( cat /boot/config.txt )"
	file=/etc/modules-load.d/raspberrypi.conf
	raspberrypiconf=$( cat $file )
	if [[ $raspberrypiconf ]]; then
		config+="

<bll># $file</bll>
$raspberrypiconf"
		dev=$( ls /dev/i2c* 2> /dev/null | cut -d- -f2 )
		[[ $dev ]] && config+="
		
<bll># i2cdetect -y $dev</bll>
$(  i2cdetect -y $dev )"
	fi
	echo "$config"
	;;
timedate )
	echo '<bll># timedatectl</bll>'
	timedatectl
	;;
timezone )
	timezone=${args[1]}
	timedatectl set-timezone $timezone
	pushRefresh
	;;
unmount )
	mountpoint=${args[1]}
	if [[ ${mountpoint:9:3} == NAS ]]; then
		umount -l "$mountpoint"
	else
		udevil umount -l "$mountpoint"
	fi
	pushRefresh
	;;
usbconnect|usbremove ) # for /etc/conf.d/devmon - devmon@http.service
	[[ -e $dirshm/audiocd ]] || ! systemctl -q is-active mpd && exit # is-active mpd - suppress on startup
	
	if [[ ${args[0]} == usbconnect ]]; then
		action=Ready
		name=$( lsblk -p -S -n -o VENDOR,MODEL | tail -1 )
		[[ ! $name ]] && name='USB Drive'
	else
		action=Removed
		name='USB Drive'
	fi
	pushstreamNotify "$name" $action usbdrive
	pushRefresh
	[[ -e $dirsystem/usbautoupdate ]] && $dirbash/cmd.sh mpcupdate$'\n'USB
	;;
usbautoupdate )
	[[ ${args[1]} == true ]] && touch $dirsystem/usbautoupdate || rm $dirsystem/usbautoupdate
	pushRefresh
	;;
vuleddisable )
	rm -f $dirsystem/vuled
	killall cava &> /dev/null
	p=$( cat $dirsystem/vuled.conf )
	for i in $p; do
		echo 0 > /sys/class/gpio/gpio$i/value
	done
	if [[ -e $dirsystem/vumeter ]]; then
		cava -p /etc/cava.conf | $dirbash/vu.sh &> /dev/null &
	else
		$dirbash/settings/player-conf.sh
	fi
	pushRefresh
	;;
vuledset )
	echo ${args[@]:1} > $dirsystem/vuled.conf
	touch $dirsystem/vuled
	! grep -q mpd.fifo /etc/mpd.conf && $dirbash/settings/player-conf.sh
	kill -9 $( pgrep cava ) &> /dev/null
	cava -p /etc/cava.conf | $dirbash/vu.sh &> /dev/null &
	pushRefresh
	;;
wlandisable )
	systemctl -q is-active hostapd && $dirbash/settings/features.sh hostapddisable
	rmmod brcmfmac &> /dev/null
	pushRefresh
	;;
wlanset )
	regdom=${args[1]}
	apauto=${args[2]}
	rfkill | grep -q wlan || modprobe brcmfmac
	echo wlan0 > $dirshm/wlan
	iw wlan0 set power_save off
	[[ $apauto == false ]] && touch $dirsystem/wlannoap || rm -f $dirsystem/wlannoap
	if ! grep -q $regdom /etc/conf.d/wireless-regdom; then
		sed -i 's/".*"/"'$regdom'"/' /etc/conf.d/wireless-regdom
		iw reg set $regdom
	fi
	pushRefresh
	;;
	
esac
