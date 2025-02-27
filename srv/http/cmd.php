<?php
$sudo = '/usr/bin/sudo ';
$sudobin = $sudo.'/usr/bin/';
$dirdata = '/srv/http/data/';
$dirbookmarks = $dirdata.'bookmarks/';
$dirsystem = $dirdata.'system/';
$coverartsize = '200x200';
$thumbsize = '80x80';
$unsharp = '0x.5';

switch( $_POST[ 'cmd' ] ) {

// multiple arguments passing to bash as array
//  - no each argument quote
//  - escape ["`] in mutiline once by php
//    js   -> php  - array
//    php  -> bash - array > multiline string ( escaped ["`] )
//    bash         - multiline string > arguments = array by line
//    bash -> php  - string / json literal
//    php  -> js   - string / array / json literal( response type 'json' )
//
case 'sh': // multiple commands / scripts: no pre-escaped characters - js > php > bash
	$sh = $_POST[ 'sh' ];                                // php array = js array
	$script = '/srv/http/bash/'.array_shift( $sh ).' "'; // script    = 1st element
	$script.= escape( implode( "\n", $sh ) ).'"';        // arguments = array > escaped multiline string
	echo rtrim( shell_exec( $sudo.$script ) );           // bash arguments = multiline string > array by line
	break;
case 'bash': // single / one-line command - return string
	$cmd = $_POST[ 'bash' ];
	if ( $cmd[ 0 ] === '/' ) {
		$cmd = $sudo.$cmd;
	} else if ( $cmd[ 0 ] !== '{' ) {
		$cmd = $sudobin.$cmd;
	}
	echo shell_exec( $cmd );
	break;
case 'exec': // single / one-line command - return array of lines to js
	$cmd = $_POST[ 'exec' ];
	exec( $sudobin.$cmd, $output, $std );
	echo json_encode( $output );
	break;
	
case 'bookmark':
	$name = $_POST[ 'name' ];
	if ( file_exists( $dirbookmarks.$name ) ) exit( '-1' );
	
	$path = $_POST[ 'path' ];
	$coverart = $_POST[ 'coverart' ] ?? '';
	$fileorder = $dirsystem.'order';
	$order = json_decode( file_get_contents( $fileorder ) );
	$order[] = $path;
	file_put_contents( $fileorder, json_encode( $order, JSON_PRETTY_PRINT ) );
	if ( $coverart ) {
		$content = $path."\n".$coverart;
		$icon = '<img class="bkcoverart" src="'.rawurlencode( $coverart ).'">';
	} else {
		$content = $path;
		$icon ='<i class="fa fa-bookmark"></i><div class="divbklabel"><span class="bklabel label" style="">'.$name.'</span></div>';
	}
	file_put_contents( $dirbookmarks.str_replace( '/', '|', $name ), $content );
	$data = [
		  'path' => $path
		, 'html' => '
			<div class="lib-mode bookmark">
				<div class="mode mode-bookmark">
				<a class="lipath">'.$path.'</a>
				'.$icon.'
			</div></div>'
		, 'order' => $order
	];
	pushstream( 'bookmark', $data );
	break;
case 'bookmarkremove':
	$path = $_POST[ 'path' ];
	$fileorder = $dirsystem.'order';
	$order = json_decode( file_get_contents( $fileorder ) );
	$name = str_replace( '/', '|', $_POST[ 'delete' ] );
	exec( 'rm "'.$dirbookmarks.escape( $name ).'"' );
	$index = array_search( $path, $order );
	array_splice( $order, $index, 1 ); // remove + reindex for json_encode
	file_put_contents( $fileorder, json_encode( $order, JSON_PRETTY_PRINT ) );
	pushstream( 'bookmark', [ 'type' => 'delete', 'path' => $path, 'order' => $order ] );
	break;
case 'bookmarkrename':
	$name = $_POST[ 'name' ];
	$rename = $_POST[ 'rename' ];
	rename( $dirbookmarks.str_replace( '/', '|', $name ), $dirbookmarks.str_replace( '/', '|', $rename ) );
	pushstream( 'bookmark', [ 'type' => 'rename', 'path' => $_POST[ 'path' ], 'name' => $rename ] );
	break;
case 'datarestore':
	if ( $_FILES[ 'file' ][ 'error' ] != UPLOAD_ERR_OK ) exit( '-1' );
	
	move_uploaded_file( $_FILES[ 'file' ][ 'tmp_name' ], $dirdata.'tmp/backup.gz' );
	exec( $sudo.'/srv/http/bash/settings/system.sh datarestore' );
	break;
case 'imagereplace':
	$imagefile = $_POST[ 'imagefile' ];
	$type = $_POST[ 'type' ];
	$covername = $_POST[ 'covername' ] ?? '';
	$base64 = $_POST[ 'base64' ] ?? '';
	$ext = $base64 ? '.jpg' : '.gif';
	if ( $type === 'audiocd' ) {
		$filenoext = substr( $imagefile, 0, -3 );
		exec( 'rm -f '.$filenoext.'*' );
		$content = $base64 ? base64_decode( $base64 ) : $_FILES[ 'file' ][ 'tmp_name' ];
		file_put_contents( $imagefile, $content );
		$coverfile = substr( $filenoext, 9 ).time().$ext; // remove /srv/http
		pushstream( 'coverart', json_decode( '{"url":"'.$coverfile.'","type":"coverart"}' ) );
	} else if ( $base64 ) { // jpg/png - album coverart(path /mnt/...) needs sudo
		$tmpfile = $dirdata.'shm/binary';
		file_put_contents( $tmpfile, base64_decode( $base64 ) );
		cmdsh( [ 'thumbjpg', $type, $tmpfile, $imagefile, $covername ] );
	} else { // gif passed as file
		$tmpfile = $_FILES[ 'file' ][ 'tmp_name' ];
		cmdsh( [ 'thumbgif', $type, $tmpfile, $imagefile, $covername ] );
	}
	if ( $type === 'bookmark' ) {
		$coverart = preg_replace( '#^/srv/http#', '', $imagefile ); // webradio
		$path = exec( 'head -1 "'.$dirbookmarks.$covername.'"' );
		if ( file_exists( $imagefile ) ) $path.= "\n".$coverart;
		file_put_contents( $dirbookmarks.$covername, $path );
	}
	break;
case 'login':
	$passwordfile = $dirsystem.'loginset';
	if ( file_exists( $passwordfile ) ) {
		$hash = file_get_contents( $passwordfile );
		if ( !password_verify( $_POST[ 'password' ], $hash ) ) die( -1 );
	}
	
	if ( isset( $_POST[ 'disable' ] ) ) {
		exec( $sudo.'/srv/http/bash/settings/features.sh logindisable' );
		exit();
	}
	
	$pwdnew = $_POST[ 'pwdnew' ] ?? '';
	if ( $pwdnew ) {
		$hash = password_hash( $pwdnew, PASSWORD_BCRYPT, [ 'cost' => 12 ] );
		echo file_put_contents( $passwordfile, $hash );
		exec( $sudo.'/srv/http/bash/settings/features.sh loginset' );
	} else {
		echo 1;
		session_start();
		$_SESSION[ 'login' ] = 1;
	}
	break;
case 'logout':
	session_start();
	session_destroy();
	break;
}

function cmdsh( $sh ) {
	$script = '/usr/bin/sudo /srv/http/bash/cmd.sh "';
	$script.= escape( implode( "\n", $sh ) ).'"';
	return shell_exec( $script );
}
function escape( $string ) {
	return preg_replace( '/(["`])/', '\\\\\1', $string );
}
function pushstream( $channel, $data ) {
	$ch = curl_init( 'http://localhost/pub?id='.$channel );
	curl_setopt( $ch, CURLOPT_HTTPHEADER, array( 'Content-Type:application/json' ) );
	curl_setopt( $ch, CURLOPT_POSTFIELDS, json_encode( $data, JSON_NUMERIC_CHECK ) );
	curl_exec( $ch );
	curl_close( $ch );
}
