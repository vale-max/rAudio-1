#!/bin/bash

. /srv/http/bash/addons.sh

warningWrite() {
	title "$warn Unable to create thumbnails."
	echo "Directory:  $( tcolor "$1" )"
	echo -e "Permission: $( ls -ld "$1" | cut -d' ' -f1 | sed 's/r-/r\\e[31m-\\e[0m/g' )\n"
}

title "$bar Update Album Thumbnails ..."

[[ ! -w "/mnt/MPD/$1" ]] && warningWrite "$1" && exit

SECONDS=0

albumfile=/srv/http/data/mpd/album

if [[ ! $1 ]]; then
	mpdpathlist=$( cat $albumfile | cut -d^ -f7 )
else
	mpdpathlist=$( find "/mnt/MPD/$1" -type d | cut -c10- )
fi
unsharp=0x.5

if [[ ! $mpdpathlist ]]; then
	echo "$padW No albums found in database."
	exit
fi

readarray -t lines <<< "$mpdpathlist"

count=${#lines[@]}
i=0
for mpdpath in "${lines[@]}"; do
	(( i++ ))
	percent=$(( $i * 100 / $count ))
	if (( $percent > 0 )); then
		sec=$SECONDS
		total=$(( $sec * 100 / $percent ))
	else
		sec=0
		total=0
	fi
	elapse=$( date -d@$sec -u +%H:%M:%S )
	total=$( date -d@$total -u +%H:%M:%S )
	echo $percent% $( tcolor $elapse/$total 8 )
	echo $i/$count $( tcolor "$mpdpath" )
	
	dir="/mnt/MPD/$mpdpath"
	if ls "$dir/coverart".* &> /dev/null; then
		echo "   $padW Thumbnail already exists."
		continue
	fi
	
	for name in cover folder front album; do # file
		for ext in jpg png gif; do
			coverfile="$dir/$name.$ext"
			[[ -e "$coverfile" ]] && break 2
			coverfile="$dir/${name^}.$ext" # capitalize
			[[ -e "$coverfile" ]] && break 2
		done
		coverfile=
	done
	if [[ ! $coverfile ]]; then # embedded
		files=$( mpc ls "$mpdpath" 2> /dev/null )
		readarray -t files <<<"$files"
		for file in "${files[@]}"; do
			file="/mnt/MPD/$file"
			if [[ -f "$file" ]]; then
				coverfile="$dir/cover.jpg"
				kid3-cli -c "select \"$file\"" -c "get picture:\"$coverfile\"" &> /dev/null
				[[ ! -e $coverfile ]] && coverfile=
				break
			fi
		done
	fi
	if [[ $coverfile ]]; then
		ext=${coverfile: -3}
		if [[ $ext == gif ]]; then
			[[ $( gifsicle -I "$coverfile" | awk 'NR==1 {print $NF}' ) == images ]] && echo "     Resize aninated GIF ..."
			gifsicle -O3 --resize-fit 200x200 "$coverfile" > "$dir/coverart.gif"
			gifsicle -O3 --resize-fit 80x80 "$coverfile" > "$dir/thumb.gif"
		else
			convert "$coverfile" -thumbnail 200x200\> -unsharp $unsharp "$dir/coverart.jpg"
			convert "$coverfile" -thumbnail 80x80\> -unsharp $unsharp "$dir/thumb.jpg"
		fi
		[[ ! -e "$dir/coverart.jpg" ]] && warningWrite "$dir" && exit
		
		(( thumb++ ))
		echo "   $padG #$thumb - Thumbnail created."
	else
		echo "   $padGr No coverart found."
	fi
done

echo Duration: $( date -d@$SECONDS -u +%H:%M:%S )

title -l '=' "$bar Done"
