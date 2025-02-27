<?php
if ( file_exists( '/srv/http/data/system/login' ) ) {
	session_start();
	if ( !isset( $_SESSION[ 'login' ] ) ) header( 'Location: /' );
}
$time = time();
$localhost = in_array( $_SERVER[ 'REMOTE_ADDR' ], ['127.0.0.1', '::1'] );
$page = $_GET[ 'p' ];
$sudo = '/usr/bin/sudo /usr/bin';
?>
<!DOCTYPE html>
<html>
<head>
	<meta charset="utf-8">
	<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no, viewport-fit=cover">
	<meta name="apple-mobile-web-app-capable" content="yes">
	<meta name="apple-mobile-web-app-status-bar-style" content="black">
	<meta http-equiv="X-UA-Compatible" content="IE=edge">
	<meta name="msapplication-tap-highlight" content="no">
	<link rel="icon" href="/assets/img/icon.<?=$time?>.png">
	<link rel="stylesheet" href="/assets/css/colors.<?=$time?>.css">
	<link rel="stylesheet" href="/assets/css/common.<?=$time?>.css">
	<link rel="stylesheet" href="/assets/css/info.<?=$time?>.css">
	<link rel="stylesheet" href="/assets/css/settings.<?=$time?>.css">
</head>
<body>
<i id="button-data"></i>
<pre id="data" class="hide"></pre>
<div class="head hide">
	<?php $pagehead = $page !== 'relays' ? $page : 'system';?>
	<i class="page-icon fa fa-<?=$pagehead?>"></i><span class='title'><?=( strtoupper( $pagehead ) )?></span>
	<i id="close" class="fa fa-times"></i><i id="help" class="fa fa-help"></i>
</div>
<div class="container hide">
<?php
/*
$head = [
	  'title'   => 'TITLE'                  // REQUIRED
	, 'subhead' => true                     // with no help icon
	, 'status'  => 'COMMAND'                // include status icon and status box
	, 'button'  => [ 'ID' => 'ICON', ... ]  // icon button
	, 'back'    => true                     // back button
	, 'nohelp'  => true
	, 'help'    => <<<html
HELP
html
];
$body = [
	[
		  'label'       => 'LABEL'      // REQUIRED
		, 'id'          => 'INPUT ID'   // REQUIRED
		, 'sublabel'    => 'SUB LABEL'
		, 'icon'        => 'ICON'
		, 'status'      => 'COMMAND'    // include status icon and status box
		, 'input'       => 'HTML'       // alternative - if not switch
		, 'setting'     => true         // true = common - setting before enable
		                                // 'self' = self trigger setting
		                                // 'none' = no setting - self trigger script
		, 'settingicon' => 'ICON'
		, 'disable'     => 'MESSAGE'    // set data-diabled
		, 'help'        => <<<html
HELP - PHP heredoc
html
		, 'exist'       => EXIST        // return blank if not EXIST
	]
	, [
		...
	]
];
htmlSection( $head, $body );
*/
function htmlHead( $data ) {
	if ( isset( $data[ 'exist' ] ) && !$data[ 'exist' ] ) return;
	
	$title = $data[ 'title' ];
	$subhead = $data[ 'subhead' ] ?? '';
	$status = $data[ 'status' ] ?? '';
	$button = $data[ 'button' ] ?? '';
	$help = $data[ 'help' ] ?? '';
	$class = $status ? 'status' : '';
	$class.= $subhead ? ' sub' : '';
	
	$html = $status ? '<heading data-status="'.$status.'"' : '<heading';
	$html.= $class ? ' class="'.$class.'">' : '>';
	$html.= '<span class="headtitle">'.$title.'</span>';
	if ( $button ) foreach( $button as $id => $icon ) $html.= '<i id="'.$id.'" class="fa fa-'.$icon.'"></i>';
	$html.= isset( $data[ 'nohelp' ] ) || $subhead ? '' : '<i class="help fa fa-help"></i>';
	$html.= isset( $data[ 'back' ] ) ? '<i class="fa fa-arrow-left back"></i>' : '';
	$html.= '</heading>';
	$html.= $help ? '<span class="help-block hide">'.$help.'</span>' : '';
	$html.= $status ? '<pre id="code'.$status.'" class="status hide"></pre>' : '';
	
	echo $html;
}
function htmlSetting( $data ) {
	if ( isset( $data[ 'exist' ] ) && !$data[ 'exist' ] ) return;
	// col-l
	$label = $data[ 'label' ];
	$icon = $data[ 'icon' ] ?? '';
	$sublabel = $data[ 'sublabel' ] ?? '';
	$status = $data[ 'status' ] ?? '';
	$id = $data[ 'id' ] ?? '';
	$input = $data[ 'input' ] ?? '';
	$setting = $data[ 'setting' ] ?? '';
	$settingicon = $data[ 'settingicon' ] ?? 'gear';
	$disabled = $data[ 'disabled' ] ?? '';
	$help = $data[ 'help' ] ?? '';
	$html = '<div id="div'.$id.'"><div class="col-l';
	$html.= $sublabel ? '' : ' single';
	$html.= $status ? ' status" data-status="'.$status.'">' : '">';
	if ( $sublabel ) {
		$html.= '<a>'.$label.'<gr>'.$sublabel;
		$html.= '</gr></a>';
	} else {
		$html.= $label;
	}
	$html.= $icon ? '<i class="fa fa-'.$icon.'"></i>' : '';
	$html.= '</div>';
	// col-r
	if ( !$icon ) {
		global $page;
		$icon = $page;
	}
	$html.= '<div class="col-r">';
	if ( !$input ) {
		$html.= '<input type="checkbox" id="'.$id.'"';
		$html.= $setting === 'self' || $setting === 'none' ? '' : ( $setting ? ' class="switch common"' : ' class="switch"' );
		$html.= $disabled ? ' data-disabled="'.$disabled.'"' : '';
		$html.= ' data-label="'.$label.'" data-icon="'.$icon.'"><div class="switchlabel" for="'.$id.'"></div>';
	} else {
		$html.= $input;
	}
	$html.= $setting && $setting !== 'none' ? '<i id="setting-'.$id.'" class="setting fa fa-'.$settingicon.'"></i>' : '';
	$html.= $help ? '<span class="help-block hide">'.$help.'</span>' : '';
	$html.= '</div>
			 <div style="clear:both"></div>
			 </div>';
	$html.= $status ? '<pre id="code'.$status.'" class="status hide"></pre>' : '';
	echo $html;
}
function htmlSection( $head, $body, $id = '' ) {
	$html = '<div';
	$html.= $id ? ' id="div'.$id.'"' : '';
	$html.= ' class="section">';
	echo $html;
	htmlHead( $head );
	foreach( $body as $data ) htmlSetting( $data );
	echo '</div>';
}

include "settings/$page.php";
$htmlbar = '';
foreach ( [ 'Features', 'Player', 'Networks', 'System' ] as $name ) {
	$id = strtolower( $name );
	$active = $id === $pagehead ? ' class="active"' : '';
	$htmlbar.= '<div id="'.$id.'"'.$active.'><i class="fa fa-'.$id.'"></i><a> '.$name.'</a></div>';
}
?>
</div>
<div id="bar-bottom">
	<?=$htmlbar?>
</div>

<script src="/assets/js/plugin/jquery-3.6.0.min.js"></script>
<script src="/assets/js/plugin/pushstream-20211210.min.js"></script>
<script src="/assets/js/info.<?=$time?>.js"></script>
<script src="/assets/js/<?=$page?>.<?=$time?>.js"></script>
	<?php if ( $page === 'relays' ) { ?>
<link rel="stylesheet" href="/assets/css/relays.<?=$time?>.css">
<script src="/assets/js/relays.<?=$time?>.js"></script>
	<?php } else if ( $page === 'networks' ) { ?>
<script src="/assets/js/plugin/qrcode.min.js"></script>
	<?php }
		  if ( $page !== 'networks' ) { ?>
<link rel="stylesheet" href="/assets/css/selectric.<?=$time?>.css">
<script src="/assets/js/plugin/jquery.selectric-1.13.1.min.js"></script>
	<?php }
		  if ( $localhost ) include 'keyboard.php';?>
<script src="/assets/js/settings.<?=$time?>.js"></script>
	
</body>
</html>
