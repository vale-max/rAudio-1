#!/bin/bash

# Radio Paradise metadata
dirsystem=/srv/http/data/system
dirtmp=/srv/http/data/shm
readarray -t stationdata < $dirtmp/radioparadise
file=${stationdata[0]}
station=${stationdata[1]}
id=${stationdata[2]}
case $id in
	flac )   id=0;;
	mellow ) id=1;;
	rock )   id=2;;
	world )  id=3;;
esac

metadataGet() { # run every 5s
	readarray -t metadata <<< $( curl -sL \
		https://api.radioparadise.com/api/now_playing?chan=$id \
		| jq -r .artist,.title,.album,.cover \
		| sed 's/^null$//' )
	datanew=${metadata[@]:0:3}
	dataprev=$( head -3 /srv/http/data/shm/status 2> /dev/null | tr -d '\n ' )
	if [[ ${datanew// } == $dataprev ]]; then
		sleep 5
		metadataGet
		return
	fi

	artist=${metadata[0]}
	title=${metadata[1]}
	album=${metadata[2]}
	coverurl=${metadata[3]}
	if [[ -n $coverurl && ! -e $dirsystem/vumeter ]]; then
		name=$( echo $artist$title | tr -d ' "`?/#&'"'" )
		coverfile=$dirtmp/webradio-$name.jpg
		curl -s $coverurl -o $coverfile
		[[ -e $coverfile ]] && coverart=/data/shm/webradio-$name.$( date +%s ).jpg
	fi

	echo "\
$artist
$title
$album
play
false
false
true
$station
$file
$coverart" > $dirtmp/status

	artist=${artist//\"/\\\"}
	title=${title//\"/\\\"}
	album=${album//\"/\\\"}
	station=${station//\"/\\\"}
	data='{
  "Artist"   : "'$artist'"
, "Title"    : "'$title'"
, "Album"    : "'$album'"
, "coverart" : "'$coverart'"
, "station"  : "'$station'"
, "file"     : "'$file'"
, "rprf"     : 1
, "webradio" : true
}'
	curl -s -X POST http://127.0.0.1/pub?id=mpdplayer -d "$data"
	if [[ -e $dirtmp/snapclientip ]]; then
		readarray -t clientip < $dirtmp/snapclientip
		for ip in "${clientip[@]}"; do
			[[ -n $ip ]] && curl -s -X POST http://$ip/pub?id=mpdplayer -d "$data"
		done
	fi
	if [[ -e $dirsystem/lcdchar ]]; then
		elapsed=$( { echo clearerror; echo status; sleep 0.05; } \
					| telnet 127.0.0.1 6600 2> /dev/null \
					| awk '/elapsed/ {print $NF}' )
		status=( "$artist" "$title" "$album" play false 0 $( date +%s%3N ) true "$station" "$file" )
		killall lcdchar.py &> /dev/null
		/srv/http/bash/lcdchar.py "${status[@]}" &
	fi
	/srv/http/bash/cmd.sh onlinefileslimit
	sleep 5
	metadataGet
}

metadataGet
