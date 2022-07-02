#!/bin/bash

# file mode
# initial page load / refresh > status.sh
# changes:
#    - mpdidle.sh > status-push.sh
#    - radioparadize / radiofrance - no stream update - status-radio.sh

. /srv/http/bash/common.sh

date=$( date +%s )

elapsedGet() {
	elapsed=$( printf '%.0f' $( { echo status; sleep 0.05; } \
								| telnet 127.0.0.1 6600 2> /dev/null \
								| awk '/^elapsed/ {print $NF}' ) )
}
outputStatus() {
	[[ ! $snapclient ]] && data2json "$status" || echo "$status" # - no braces
	[[ $1 != noexit ]] && exit
}

if [[ $1 == snapclient ]]; then # snapclient
	snapclient=1
	player=mpd
else
	btreceiver=$( exists $dirshm/btreceiver )
	consume=$( mpc | grep -q 'consume: on' && echo true )
	counts=$( cat $dirdata/mpd/counts 2> /dev/null )
	librandom=$( exists $dirsystem/librandom )
	player=$( cat $dirshm/player )
	[[ ! $player ]] && player=mpd && echo mpd > $dirshm/player
	[[ $player != mpd ]] && icon=$player
	relays=$( exists $dirsystem/relays )
	relayson=$( exists $dirshm/relayson )
	stoptimer=$( exists $dirshm/stoptimer )
	updateaddons=$( exists $dirdata/addons/update )
	if [[ -e $dirmpd/updating ]]; then 
		updating_db=true
		if ! mpc | grep -q ^Updating; then
			path=$( cat $dirmpd/updating )
			[[ $path == rescan ]] && mpc -q rescan || mpc -q update "$path"
		fi
	fi
	if [[ -e $dirshm/nosound && ! $btreceiver ]]; then
		volume=false
	else
		ccv=$( $dirbash/cmd.sh volumecontrolget )
		card=${ccv/^*}
		control=$( echo $ccv | cut -d^ -f2 ) # keep trailing space if any
		volume=${ccv/*^}
	fi
	scrobble=$( exists $dirsystem/scrobble )
	volumemute=$( cat $dirsystem/volumemute 2> /dev/null || echo 0 )

########
	status='
  "player"       : "'$player'"
, "btreceiver"   : '$btreceiver'
, "card"         : '$card'
, "consume"      : '$consume'
, "control"      : "'$control'"
, "counts"       : '$counts'
, "file"         : ""
, "icon"         : "'$icon'"
, "librandom"    : '$librandom'
, "relays"       : '$relays'
, "relayson"     : '$relayson'
, "scrobble"     : '$scrobble'
, "stoptimer"    : '$stoptimer'
, "stream"       : false
, "updateaddons" : '$updateaddons'
, "updating_db"  : '$updating_db'
, "volume"       : '$volume'
, "volumemute"   : '$volumemute'
, "webradio"     : false'
fi
if [[ $1 == withdisplay ]]; then
	if [[ -e $dirshm/nosound ]]; then
		volumenone=true
	else
		[[ ! -e $dirshm/mixernone || -e $dirshm/btreceiver || -e $dirshm/snapclientactive ]] && volumenone=false || volumenone=true
	fi
	display=$( head -n -1 $dirsystem/display )
	display+='
, "audiocd"          : '$( exists $dirshm/audiocd )'
, "camilladsp"       : '$( exists $dirsystem/camilladsp )'
, "color"            : "'$( cat $dirsystem/color 2> /dev/null )'"
, "equalizer"        : '$( exists $dirsystem/equalizer )'
, "lock"             : '$( exists $dirsystem/login )'
, "multiraudio"      : '$( exists $dirsystem/multiraudio )'
, "order"            : '$( cat $dirsystem/order 2> /dev/null )'
, "relays"           : '$( exists $dirsystem/relays )'
, "screenoff"        : '$( ! grep -q screenoff=0 $dirsystem/localbrowser.conf 2> /dev/null && echo true )'
, "snapclient"       : '$( exists $dirsystem/snapclient )'
, "snapclientactive" : '$( exists $dirshm/snapclientactive )'
, "volumenone"       : '$volumenone'
}'
	status+='
, "display"          : '$display
fi

if [[ $player != mpd && $player != upnp ]]; then
	case $player in

	airplay )
		dirairplay=$dirshm/airplay
		state=$( cat $dirairplay/state 2> /dev/null )
		Time=$( cat $dirairplay/Time 2> /dev/null )
		timestamp=$( date +%s%3N )
		if [[ $state == pause ]]; then
			elapsedms=$( cat $dirairplay/elapsed 2> /dev/null )
		else
			start=$( cat $dirairplay/start 2> /dev/null )
			elapsedms=$(( timestamp - start ))
		fi
		elapsed=$(( ( elapsedms + 1500 ) / 1000 )) # roundup + 1s
########
		status+='
, "Album"     : "'$( cat $dirairplay/Album 2> /dev/null )'"
, "Artist"    : "'$( cat $dirairplay/Artist 2> /dev/null )'"
, "Title"     : "'$( cat $dirairplay/Title 2> /dev/null )'"
, "coverart"  : "/data/shm/airplay/coverart.'$date'.jpg"
, "elapsed"   : '$elapsed'
, "sampling"  : "16 bit 44.1 kHz 1.41 Mbit/s • AirPlay"
, "state"     : "'$state'"
, "Time"      : '$Time'
, "timestamp" : '$timestamp
		;;
	bluetooth )
########
		status+="
$( $dirbash/status-bluetooth.sh )"
		;;
	snapcast )
		serverip=$( cat $dirshm/serverip )
########
		status+="
$( sshCommand $serverip $dirbash/status.sh snapclient \
	| sed -e 's|^\(, "stationcover" *: "\)\(.\+"\)|\1http://'$serverip'\2|
		' -e 's|^\(, "coverart" *: "\)\(.\+"\)|\1http://'$serverip'\2|
		' -e 's|^, *"icon".*|, "icon" : "snapcast"|' )"
		;;
	spotify )
		. $dirshm/spotify/state
		[[ $state == play ]] && elapsed=$(( $( date +%s ) - start + 1 )) # 1s delayed
########
		status+="
$( cat $dirshm/spotify/status )"
	status+='
, "elapsed"   : '$elapsed'
, "timestamp" : '$( date +%s%3N )
		;;
		
	esac
# >>>>>>>>>>
	outputStatus
fi

(( $( grep '"cover".*true\|"vumeter".*false' $dirsystem/display | wc -l ) == 2 )) && displaycover=1

filter='^Album|^AlbumArtist|^Artist|^audio|^bitrate|^duration|^file|^Name|^song:|^state|^Time|^Title'
[[ ! $snapclient ]] && filter+='|^playlistlength|^random|^repeat|^single'
mpdStatus() {
	mpdtelnet=$( { echo clearerror; echo status; echo $1; sleep 0.05; } \
		| telnet 127.0.0.1 6600 2> /dev/null \
		| grep -E "$filter" )
}
mpdStatus currentsong
# 'file:' missing / blank
#   - when playlist is empty, add song without play
#     - 'currentsong' has no data
#     - use 'playlistinfo 0' instead
#   - webradio start - blank 'file:' (in case 1 sec delay from cmd.sh not enough)
! grep -q '^file: .\+' <<< "$mpdtelnet" && mpdStatus 'playlistinfo 0'
# 'state:' - missing on webradio track change
grep -q '^state' <<< "$mpdtelnet" || mpdStatus currentsong

readarray -t lines <<< "$mpdtelnet"
for line in "${lines[@]}"; do
	key=${line/:*}
	val=${line#*: }
	case $key in
		audio )
			data=( ${val//:/ } )
			samplerate=${data[0]}
			bitdepth=${data[1]}
			;;
		bitrate )
			bitrate=$(( val * 1000 ));;
		# true/false
		random | repeat | single )
			[[ $val == 1 ]] && tf=true || tf=false
########
			status+='
, "'$key'" : '$tf
			;;
		# number
		duration | playlistlength | song | Time )
			printf -v $key '%s' $val;; # value of $key as "var name" - value of $val as "var value"
		# string - escaped name
		Album | AlbumArtist | Artist | Name | Title )
			printf -v $key '%s' "${val//\"/\\\"}";; # escape " for json
		file )
			file0=$val           # no escape " for coverart and ffprobe
			[[ $file0 == *".cue/track"* ]] && file0=$( dirname "$file0" )
			file=${val//\"/\\\"};; # escape " for json
		# string
		* ) # state | updating_db
			[[ $key ]] && printf -v $key '%s' "$val";;
	esac
done

[[ ! $pllength ]] && pllength=$( mpc playlist | wc -l )
status=$( echo "$status" | grep -v '^, "file"' )
########
status+='
, "file"      : "'$file'"
, "pllength"  : '$pllength'
, "song"      : '$song'
, "state"     : "'$state'"
, "timestamp" : '$( date +%s%3N )
if (( $pllength  == 0 )); then
	ip=$( ifconfig | grep inet.*broadcast | head -1 | awk '{print $2}' )
	[[ $ip ]] && hostname=$( avahi-resolve -a4 $ip | awk '{print $NF}' )
########
	status+='
, "coverart" : ""
, "hostname" : "'$hostname'"
, "ip"       : "'$ip'"'
# >>>>>>>>>>
	outputStatus
fi
fileheader=${file:0:4}
if [[ 'http rtmp rtp: rtsp' =~ ${fileheader,,} ]]; then
	stream=1
########
	status+='
, "stream" : true'
fi
if [[ $fileheader == cdda ]]; then
	ext=CD
	icon=audiocd
	discid=$( cat $dirshm/audiocd 2> /dev/null )
	if [[ $discid && -e $dirdata/audiocd/$discid ]]; then
		track=${file/*\/}
		readarray -t audiocd <<< $( sed -n ${track}p $dirdata/audiocd/$discid | tr ^ '\n' )
		Artist=${audiocd[0]}
		Album=${audiocd[1]}
		Title=${audiocd[2]}
		Time=${audiocd[3]}
		if [[ $displaycover ]]; then
			coverfile=$( ls $dirdata/audiocd/$discid.* 2> /dev/null | head -1 )
			[[ $coverfile ]] && coverart=/data/audiocd/$discid.$( date +%s ).${coverfile/*.}
		fi
	else
		[[ $state == stop ]] && Time=0
	fi
########
		status+='
, "Album"  : "'$Album'"
, "Artist" : "'$Artist'"
, "discid" : "'$discid'"
, "Time"   : '$Time'
, "Title"  : "'$Title'"'
elif [[ $stream ]]; then
	if [[ $player == upnp ]]; then # internal ip
		ext=UPnP
		[[ $duration ]] && duration=$( printf '%.0f\n' $duration )
########
		status+='
, "Album"  : "'$Album'"
, "Artist" : "'$Artist'"
, "Time"   : "'$duration'"
, "Title"  : "'$Title'"'
		# fetched coverart
		if [[ $displaycover ]]; then
			covername=$( echo $Artist$Album | tr -d ' "`?/#&'"'" )
			onlinefile=$( ls $dirshm/online/$covername.* 2> /dev/null | head -1 )
			[[ $onlinefile ]] && coverart=${onlinefile:9}
		fi
	else
		ext=Radio
		icon=webradio
		# before webradios play: no 'Name:' - use station name from file instead
		url=${file/\#charset*}
		urlname=${url//\//|}
		radiofile=$dirdata/webradios/$urlname
		[[ ! -e $radiofile  ]] && radiofile=$( find $dirdata/webradios -name "$urlname" )
		if [[ -e $radiofile ]]; then
			readarray -t radiodata < "$radiofile"
			station=${radiodata[0]}
			radiosampling=${radiodata[1]}
		fi
		[[ $file == *icecast.radiofrance.fr* ]] && icon=radiofrance
		[[ $file == *stream.radioparadise.com* ]] && icon=radioparadise
		[[ $file == *$(hostname -f)* ]] && tipo=DAB
		if [[ $state != play ]]; then
			state=stop
			Title=
		else
			if [[ $icon == radiofrance || $icon == radioparadise ]]; then # triggered once on start - subsequently by status-push.sh
				id=$( basename ${file/-*} )
				[[ ${id:0:13} == francemusique ]] && id=${id:13}
				[[ ! $id ]] && id=francemusique
				stationname=${station/* - }
				if [[ ! -e $dirshm/radio ]] || ! systemctl -q is-active radio; then
					echo "\
$file
$stationname
$id
$radiosampling" > $dirshm/radio
					systemctl start radio
				else
					. <( grep -E '^Artist|^Album|^Title|^coverart|^station' $dirshm/status )
					[[ ! $displaycover ]] && coverart=
				fi
			elif [[ $tipo == DAB ]]; then
				id=DAB
				stationname=${station/* - }
				if [[ ! -e $dirshm/radio ]] || ! systemctl -q is-active radio; then
                                        echo "\
$file
$stationname
$id
$radiosampling" > $dirshm/radio
                                        systemctl start radio
                                else
                                        . <( grep -E '^Artist|^Album|^Title|^coverart|^station' $dirshm/status )
                                        [[ ! $displaycover ]] && coverart=
                                fi

			
			
			
			elif [[ $Title && $displaycover ]]; then
				# split Artist - Title: Artist - Title (extra tag) or Artist: Title (extra tag)
				readarray -t radioname <<< $( echo $Title | sed 's/ - \|: /\n/' )
				Artist=${radioname[0]}
				Title=${radioname[1]}
				# fetched coverart
				covername=$( echo "$Artist${Title/ (*}" | tr -d ' "`?/#&'"'" ) # remove ' (extra tag)'
				coverfile=$( ls $dirshm/webradio/$covername.* 2> /dev/null | head -1 )
				if [[ $coverfile ]]; then
					coverart=${coverfile:9}
					Album=$( cat $dirshm/webradio/$covername 2> /dev/null )
				fi
			fi
		fi
		if [[ $displaycover ]]; then
			filenoext=/data/webradiosimg/$urlname
			pathnoext=/srv/http$filenoext
			if [[ -e $pathnoext.gif ]]; then
				stationcover=$filenoext.$date.gif
			elif [[ -e $pathnoext.jpg ]]; then
				stationcover=$filenoext.$date.jpg
			fi
		fi
		status=$( grep -v '^, *"state"\|^, *"webradio"' <<< "$status" )
########
		status+='
, "Album"        : "'$Album'"
, "Artist"       : "'$Artist'"
, "stationcover" : "'${stationcover/\#/%23}'"
, "Name"         : "'$Name'"
, "state"        : "'$state'"
, "station"      : "'$station'"
, "Time"         : false
, "Title"        : "'$Title'"
, "webradio"     : true'
	if [[ $id ]]; then
		sampling="$(( song + 1 ))/$pllength &bull; $radiosampling"
		elapsedGet
########
		status+='
, "coverart"     : "'$coverart'"
, "elapsed"      : '$elapsed'
, "ext"          : "Radio"
, "icon"         : "'$icon'"
, "sampling"     : "'$sampling'"
, "song"         : '$song
# >>>>>>>>>>
		outputStatus
	fi
	
	fi
else
	ext=${file/*.}
	if [[ ${ext:0:9} == cue/track ]]; then
		cuefile=$( dirname "$file" )
		cuesrc=$( grep ^FILE "/mnt/MPD/$cuefile" | head -1 | cut -d'"' -f2 )
		ext=${cuesrc/*.}
	fi
	ext=${ext^^}
	# missing id3tags
	[[ ! $Album ]] && Album=
	[[ ! $AlbumArtist ]] && AlbumArtist=$Artist
	[[ ! $Artist ]] && Artist=$AlbumArtist
	[[ ! $Artist ]] && dirname=${file%\/*} && Artist=${dirname/*\/}
	[[ ! $Title ]] && filename=${file/*\/} && Title=${filename%.*}
########
	status+='
, "Album"  : "'$Album'"
, "Artist" : "'$Artist'"
, "Time"   : '$Time'
, "Title"  : "'$Title'"'
fi

samplingfile=$dirshm/sampling/$( echo $file | tr -d ' "`?/#&'"'_.\-" )
samplingSave() {
	if [[ $player != upnp ]]; then
		echo $sampling > $samplingfile
		files=$( ls -1t $dirshm/sampling 2> /dev/null )
		(( $( echo "$files" | wc -l ) > 20 )) && rm -f "$( echo "$files" | tail -1 )"
	fi
}
samplingLine() {
	bitdepth=$1
	samplerate=$2
	bitrate=$3
	ext=$4
	[[ $bitrate -eq 0 || ! $bitrate ]] && bitrate=$(( bitdepth * samplerate * 2 ))
	if (( $bitrate < 1000000 )); then
		rate="$(( bitrate / 1000 )) kbit/s"
	else
		[[ $bitdepth == dsd ]] && bitrate=$(( bitrate / 2 ))
		rate="$( awk "BEGIN { printf \"%.2f\n\", $bitrate / 1000000 }" ) Mbit/s"
#		rate=$( echo "print $bitrate / 1000000" | perl )' Mbit/s'
	fi
	
	if [[ $bitdepth == dsd ]]; then
		sampling="${samplerate^^} &bull; $rate"
	else
		[[ $bitdepth == 'N/A' && ( $ext == WAV || $ext == AIFF ) ]] && bitdepth=$(( bitrate / samplerate / 2 ))
		sample="$( awk "BEGIN { printf \"%.1f\n\", $samplerate / 1000 }" ) kHz"
#		sample=$( echo "print $samplerate / 1000" | perl )' kHz'
		if [[ $bitdepth && $ext != Radio && $ext != MP3 && $ext != AAC ]]; then
			sampling="$bitdepth bit $sample $rate"
		else # lossy has no bitdepth
			sampling="$sample $rate"
		fi
	fi
	[[ $ext != Radio ]] && sampling+=" &bull; $ext"
}

if [[ $ext == CD ]]; then
	sampling='16 bit 44.1 kHz 1.41 Mbit/s &bull; CD'
elif [[ $state != stop ]]; then
	if [[ $ext == DSF || $ext == DFF ]]; then
		bitdepth=dsd
		[[ $state == pause ]] && bitrate=$(( ${samplerate/dsd} * 2 * 44100 ))
	fi
	if [[ $ext != Radio ]]; then
		samplingLine $bitdepth $samplerate $bitrate $ext
	else
		if [[ $bitrate && $bitrate != 0 ]]; then
			samplingLine $bitdepth $samplerate $bitrate $ext
			[[ -e $radiofile ]] && sed -i "2 s|.*|$sampling|" $radiofile # update sampling on each play
		else
			sampling=$radiosampling
		fi
	fi
	samplingSave &
else
	if [[ $ext == Radio ]]; then
		sampling="$radiosampling"
	else
		if [[ -e $samplingfile ]]; then
			sampling=$( cat $samplingfile )
		else
			if [[ $ext == DSF || $ext == DFF ]]; then
				# DSF: byte# 56+4 ? DSF: byte# 60+4
				[[ $ext == DSF ]] && byte=56 || byte=60;
				[[ $cuesrc ]] && file="$( dirname "$cuefile" )/$cuesrc"
				hex=( $( hexdump -x -s$byte -n4 "/mnt/MPD/$file" | head -1 | tr -s ' ' ) )
				dsd=$(( ${hex[1]} / 1100 * 64 )) # hex byte#57-58 - @1100:dsd64
				bitrate=$( awk "BEGIN { printf \"%.2f\n\", $dsd * 44100 / 1000000 }" )
#				bitrate=$( echo "print $dsd * 44100 / 1000000" | perl )
				sampling="DSD$dsd • $bitrate Mbit/s &bull; $ext"
			else
				data=( $( ffprobe -v quiet -select_streams a:0 \
					-show_entries stream=bits_per_raw_sample,sample_rate \
					-show_entries format=bit_rate \
					-of default=noprint_wrappers=1:nokey=1 \
					"/mnt/MPD/$file0" ) )
				samplerate=${data[0]}
				bitdepth=${data[1]}
				bitrate=${data[2]}
				samplingLine $bitdepth $samplerate $bitrate $ext
			fi
		fi
		samplingSave &
	fi
fi

########
pos="$(( song + 1 ))/$pllength"
sampling="$pos &bull; $sampling"
status+='
, "ext"      : "'$ext'"
, "coverart" : "'$coverart'"
, "icon"     : "'$icon'"
, "sampling" : "'$sampling'"'

if [[ $coverart || ! $displaycover ]]; then # webradio $coverart exists
	elapsedGet
# >>>>>>>>>>
	status+='
, "elapsed"  : '$elapsed
	outputStatus
fi

if [[ $ext != CD && ! $stream ]]; then
	getcover=1
	coverart=$( $dirbash/status-coverart.sh "\
$AlbumArtist
$Album
$file0" )
fi
elapsedGet
########
	status+='
, "elapsed"  : '$elapsed'
, "coverart" : "'$coverart'"'
# >>>>>>>>>>
outputStatus $( [[ ! $getcover && $Artist ]] && echo noexit )

[[ $getcover || ! $Artist ]] && exit

if [[ $stream && $state == play && $Title ]]; then
	[[ $ext == Radio ]] && Title=${Title/ (*} # remove ' (extra tag)'
	args="\
$Artist
$Title
webradio"
elif [[ $Album ]]; then
	args="\
$Artist
$Album"
fi
if [[ $args ]]; then
	kill -9 $( pgrep status-coverartonline ) &> /dev/null
	$dirbash/status-coverartonline.sh "$args" &> /dev/null &
fi
