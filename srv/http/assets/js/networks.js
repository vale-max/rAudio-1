$( function() { // document ready start >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

var accesspoint = $( '#accesspoint' ).length;
var timeoutscan;
$( '.back' ).click( function() {
	clearTimeout( timeoutscan );
	$( '#divinterface, #divaccesspoint' ).removeClass( 'hide' );
	$( '#divbluetooth, #divwifi, #divwebui' ).addClass( 'hide' );
	$( '#listwlscan, #listbtscan' ).empty();
	refreshData();
} );
$( '#btscan' ).click( function() {
	$( '#divinterface, #divwebui, #divaccesspoint' ).addClass( 'hide' );
	$( '#divbluetooth' ).removeClass( 'hide' );
	btScan();
} );
$( '#listbtscan' ).on( 'click', 'li', function() {
	var i = $( this ).index( '.btscan' );
	var list = G.listbtscan[ i ];
	if ( !list.connected ) {
		notify( 'Bluetooth', 'Pair ...', 'bluetooth' );
		bash( [ 'btpair', list.mac ], function( data ) {
			bannerHide();
			if ( data != -1 ) {
				$( '.back' ).click();
			} else {
				info( {
					  icon      : 'bluetooth'
					, title     : 'Bluetooth'
					, message   : 'Pair <wh>'+ list.name +'</wh> failed'
				} );
			}
		} );
	}
} );
$( '#wladd' ).click( function() {
	'ssid' in G ? infoAccesspoint() : editWiFi( 'add' );
} );
$( '#wlscan' ).click( function() {
	'ssid' in G ? infoAccesspoint() : wlanStatus();
} );
$( '#listbt, #listlan, #listwl' ).on( 'click', 'li', function() {
	G.li = $( this );
	G.list = G.li.parent().prop( 'id' );
	var active = $( this ).hasClass( 'active' );
	$( 'li' ).removeClass( 'active' );
	G.li.addClass( 'active' );
	var $menu = $( '#menu' );
	if ( !$menu.hasClass( 'hide' ) ) {
		$menu.addClass( 'hide' );
		if ( active ) return
	}
	
	if ( G.list === 'listbt' ) {
		$( '#menu a' ).addClass( 'hide' );
		$( '#menu .disconnect' ).toggleClass( 'hide', !G.li.data( 'connected' ) );
		$( '#menu .forget' ).removeClass( 'hide' );
	} else if ( G.list === 'listlan' ) {
		$( '#menu a' ).addClass( 'hide' );
		$( '#menu .edit' ).removeClass( 'hide' );
	} else {
		var connected = G.li.data( 'offline' ) != 1;
		$( '#menu a' ).removeClass( 'hide' );
		$( '#menu .connect' ).toggleClass( 'hide', connected );
		$( '#menu .disconnect' ).toggleClass( 'hide', !connected );
	}
	var menutop = ( G.li.position().top + 48 ) +'px';
	var menuH = $menu.height();
	$menu
		.removeClass( 'hide' )
		.css( 'top', menutop );
	var targetB = $menu.offset().top + menuH;
	var wH = window.innerHeight;
	if ( targetB > wH - 40 + $( window ).scrollTop() ) $( 'html, body' ).animate( { scrollTop: targetB - wH + 42 } );
} );
$( 'body' ).click( function( e ) {
	if ( !$( e.target ).parents( '#listbt, #listlan, #listwl' ).length ) {
		$( '#menu' ).addClass( 'hide' );
		$( 'li' ).removeClass( 'active' );
	}
} );
$( '.connect' ).click( function() {
	clearTimeout( timeoutscan );
	var ssid = wlanList().ssid;
	notify( ssid, 'Connect ...', 'wifi' );
	bash( [ 'profileconnect', ssid ] )
} );
$( '.disconnect' ).click( function() {
	if ( G.list === 'listbt' ) {
		var i = G.li.index( '.bt' );
		var list = G.listbt[ i ]
		var name = list.name;
		var icon = 'bluetooth';
	} else {
		var name = wlanList().ssid;
		var icon = 'wifi';
	}
	info( {
		  icon    : icon
		, title   : name
		, message : 'Disconnect?'
		, oklabel : '<i class="fa fa-times"></i>OK'
		, okcolor : orange
		, ok      : function() {
			clearTimeout( timeoutscan );
			notify( name, 'Disconnect ...', icon );
			bash( [ icon === 'wifi' ? 'disconnect' : 'btdisconnect' ] )
		}
	} );
} );
$( '.edit' ).click( function() {
	G.list === 'listwl' ? editWiFi() : editLAN();
} );
$( '.forget' ).click( function() {
	if ( G.list === 'listbt' ) {
		var i = G.li.index( '.bt' );
		var list = G.listbt[ i ]
		var name = list.name;
		var mac = list.mac;
		var icon = 'bluetooth';
	} else {
		var name = wlanList().ssid;
		var icon = 'wifi';
	}
	info( {
		  icon    : icon
		, title   : name
		, message : 'Forget?'
		, oklabel : '<i class="fa fa-minus-circle"></i>OK'
		, okcolor : red
		, ok      : function() {
			clearTimeout( timeoutscan );
			notify( name, 'Forget ...', icon );
			icon === 'wifi' ? bash( [ 'profileremove', name ] ) : bash( "/srv/http/bash/networks.sh btremove$'\n'"+ mac );
		}
	} );
} );
$( '#listwlscan' ).on( 'click', 'li', function() {
	var i = $( this ).index( '.wlscan' );
	var list = G.listwlscan[ i ];
	var ssid = list.ssid;
	var wpa = list.wpa || 'wep';
	var data = {
		  ESSID     : ssid
		, IP        : 'dhcp'
	}
	if ( !list.profile ) {
		if ( list.encrypt ) {
			info( {
				  icon          : 'wifi'
				, title         : ssid
				, passwordlabel : 'Password'
				, oklabel       : 'Connect'
				, ok            : function() {
					data.Security = wpa;
					data.Key      = infoVal();
					connectWiFi( data );
				}
			} );
		} else {
			connectWiFi( data );
		}
	} else {
		var ip = list.ip;
		info( {
			  icon    : 'wifi'
			, title   : ssid
			, message : ip ? 'Disconnect?' : 'Connect?'
			, oklabel : ip ? '<i class="fa fa-times"></i>OK' : '<i class="fa fa-check"></i>OK'
			, okcolor : ip ? orange : ''
			, ok      : function() {
				clearTimeout( timeoutscan );
				notify( ssid, ip ? 'Disconnect ...' : 'Connect ...', 'wifi' );
				if ( ip ) {
					bash( [ 'disconnect' ] );
				} else {
					bash( [ 'profileconnect', ssid ] );
				}
			}
		} );
	}
} );
$( '#setting-accesspoint' ).click( function() {
	location.href = 'settings.php?p=features&set=setting-hostapd';
} );

} );

function btScan() {
	bash( '/srv/http/bash/networks-scanbt.sh', function( data ) {
		if ( data ) {
			G.listbtscan = data;
			var htmlbt = '';
			data.forEach( function( list ) {
				htmlbt += '<li class="btscan"><i class="fa fa-bluetooth"></i>';
				if ( list.connected ) htmlbt += '<grn>&bull;&ensp;</grn>';
				htmlbt += '<a class="liname wh">'+ list.name +'</a>';
				if ( list.paired ) htmlbt += '&ensp;<i class="fa fa-save-circle wh"></i>';
				htmlbt += '</li>';
			} );
			$( '#listbtscan' ).html( htmlbt );
		}
		timeoutscan = setTimeout( btScan, 12000 );
	}, 'json' );
}
function connectWiFi( data ) { // { ssid:..., wpa:..., password:..., hidden:..., ip:..., gw:... }
	clearTimeout( timeoutscan );
	var ssid = data.ESSID;
	var ip = data.Address;
	if ( ip ) {
		if ( $( '#listlan li' ).length ) {
			notify( ssid, 'Change ...', 'wifi' );
		} else {
			loader();
			location.href = 'http://'+ ip +'/settings.php?p=networks';
			notify( ssid, 'Change URL to '+ ip, 'wifi' );
		}
	} else {
		notify( ssid, $( '#listwl li' ).length ? 'Change ...' : 'Connect ...', 'wifi' );
	}
	bash( [ 'connect', JSON.stringify( data ) ], function( std ) {
		if ( std == -1 ) {
			G.wlconnected =  '';
			info( {
				  icon      : 'wifi'
				, title     : 'Wi-Fi'
				, message   : 'Connect to <wh>'+ ssid +'</wh> failed.'
			} );
		} else {
			$( '.back' ).click();
		}
	} );
}
function editLAN() {
	var static = G.listeth.static;
	var ip = G.listeth.ip;
	var gw = G.listeth.gateway;
	info( {
		  icon         : 'lan'
		, title        : 'LAN'
		, textlabel    : [ ( static ? '<gr>Static</gr> IP' : '<gr>DHCP</gr> IP' ), 'Gateway' ]
		, values       : [ ip, gw ]
		, checkchanged : 1
		, checkblank   : 1
		, beforeshow   : function() {
			if ( !static ) {
				$( '#infoContent input:eq( 0 )' ).on( 'keyup paste cut', function() {
					$( '#infoContent gr' ).text( $( this ).val() === ip ? 'DHCP' : 'Static' );
				} );
			}
		}
		, buttonlabel  : ( static ? '<i class="fa fa-undo"></i>DHCP' : '' )
		, button       : ( static ? function() {
			notify( 'LAN IP Address', 'Change URL to '+ G.hostname +'.local ...', 'lan' );
			loader();
			location.href = 'http://'+ G.hostname +'.local/settings.php?p=networks';
			bash( [ 'editlan' ] );
		} : '' )
		, ok           : function() {
			var values = infoVal();
			var ip = values[ 0 ];
			var gateway = values[ 1 ];
			notify( 'LAN IP Address', 'Change ip to '+ ip, 'lan' );
			bash( [ 'editlan', ip, gateway ], function( used ) {
				if ( used == -1 ) {
					info( {
						  icon    : 'lan'
						, title   : 'Duplicate IP'
						, message : 'IP <wh>'+ ip +'</wh> already in use.'
						, ok      : function() {
							editLAN();
						}
					} );
				}
				bannerHide();
			} );
		}
	} );
}
function editWiFi( add ) {
	if ( add ) {
		var values = [ '', '', '', '', false, false, false ]
	} else {
		var list = wlanList();
		var values = [];
		[ 'ssid', 'ip', 'gateway', 'password', 'static', 'hidden', 'wep' ].forEach( function( k ) {
			values.push( list[ k ] );
		} );
	}
	info( {
		  icon          : 'wifi'
		, title         : add ? 'New Wi-Fi Connection' : 'Edit Saved Connection'
		, textlabel     : [ 'SSID', 'IP', 'Gateway' ]
		, boxwidth      : 180
		, checkbox      : [ 'Static IP', 'Hidden SSID', 'WEP' ]
		, passwordlabel : 'Password'
		, values        : values
		, checkchanged  : add ? 0 : 1
		, checkblank    : add ? 0 : 1
		, beforeshow    : function() {
			var $static = $( '#infoContent' ).find( 'tr:eq( 1 ), tr:eq( 2 )' );
			$static.toggleClass( 'hide', !values[ 4 ] );
			$( '#infoContent input:checkbox:eq( 0 )' ).change( function() {
				$static.toggleClass( 'hide', !$( this ).prop( 'checked' ) );
			} );
		}
		, ok            : function() {
			var k =[ 'ESSID', 'Address', 'Gateway', 'Key', 'IP', 'Hidden', 'Security' ];
			var v = infoVal();
			var data = {}
			$.each( v, function( i, v ) {
				if ( i === 4 ) {
					v = v ? 'static' : 'dhcp';
				} else if ( i === 6 ) {
					v = v ? 'wep' : 'wpa';
				}
				data[ k[ i ] ] = v;
			} );
			if ( data.IP === 'dhcp' ) {
				connectWiFi( data );
			} else {
				bash( 'ping -c 1 -w 1 '+ data.Address +' &> /dev/null && echo -1', function( std ) {
					if ( std == -1 ) {
						info( {
							  icon    : 'wifi'
							, title   : 'Duplicate IP'
							, message : 'IP <wh>'+ data.Address +'</wh> already in use.'
							, ok      : function() {
								editWiFi();
							}
						} );
					} else {
						connectWiFi( data );
					}
				} );
			}
		}
	} );
}
function infoAccesspoint() {
	info( {
		  icon    : 'wifi'
		, title   : 'Wi-Fi'
		, message : 'Access Point must be disabled.'
	} );
}
function renderPage( list ) {
	if ( typeof list === 'string' ) { // on load, try catching any errors
		var list2G = list2JSON( list );
		if ( !list2G ) return
	} else {
		G = list;
	}
	var htmlbt = '';
	var htmlwl = '';
	if ( G.listbt ) {
		G.listbt.forEach( function( list ) {
			htmlbt += '<li class="bt"><i class="fa fa-bluetooth"></i>';
			htmlbt += list.connected ? '<grn>&bull;</grn>&ensp;' : '<gr>&bull;</gr>&ensp;'
			htmlbt += list.name +'</li>';
		} );
		$( '#listbt' ).html( htmlbt );
		$( '#ifconfig' ).next().find( 'code' ).text( 'ifconfig; bluetoothctl show' );
	}
	if ( G.listwl ) {
		var list = G.listwl;
		var signal = list.dbm > -60 ? '' : ( list.dbm < -67 ? 1 : 2 );
		htmlwl += '<li class="wl"><i class="fa fa-wifi'+ signal +'"></i><grn>&bull;</grn>&ensp;';
		if ( !G.hostapd ) {
			htmlwl += list.ssid +'<gr>&ensp;&bull;&ensp;</gr>'+ list.ip +'<gr>&ensp;&raquo;&ensp;'+ list.gateway +'</gr></li>';
		} else {
			htmlwl += '<gr>Access point&ensp;&laquo;&ensp;</gr>'+ G.hostapd.hostapdip +'</li>';
		}
	}
	if ( G.listwlnc ) {
		G.listwlnc.forEach( function( list ) {
			htmlwl += '<li class="wl" data-offline="1"><i class="fa fa-wifi"></i><gr>&bull;&ensp;</gr>'+ list.ssid +'</li>';
		} );
	}
	if ( G.listeth ) {
		var htmllan = '<li><i class="fa fa-lan"></i><grn>&bull;</grn>&ensp;'+ G.listeth.ip +'</li>';
	}
	if ( G.activebt ) {
		var active = $( '#listbt grn' ).length > 0;
		$( '#headbt' )
			.toggleClass( 'noline', htmlbt !== '' )
			.toggleClass( 'status', active );
		$( '#headbt' ).data( 'status', active ? 'bt' : '' );
		$( '#headbt .fa-status' ).toggleClass( 'hide', !active );
		$( '#divbt' ).removeClass( 'hide' );
	} else {
		$( '#divbt' ).addClass( 'hide' );
	}
	if ( G.activewlan ) {
		$( '#listwl' ).html( htmlwl );
		$( '#headwl' ).toggleClass( 'noline', htmlwl !== '' );
		$( '#divwl' ).removeClass( 'hide' );
	} else {
		$( '#divwl' ).addClass( 'hide' );
	}
	if ( G.activeeth ) {
		$( '#listlan' ).html( htmllan );
		$( '#headlan' ).toggleClass( 'noline', htmllan !== '' );
		$( '#lanadd' ).toggleClass( 'hide', htmllan !== '' );
		$( '#divlan' ).removeClass( 'hide' );
	} else {
		$( '#divlan' ).addClass( 'hide' );
	}
	$( '#divaccesspoint' ).toggleClass( 'hide', !G.hostapd );
	if ( $( '#divinterface' ).hasClass( 'hide' ) ) return
	
	renderQR();
	bannerHide();
	[ 'bluetooth', 'lan', 'wlan' ].forEach( function( id ) {
		codeToggle( id, 'status' );
	} );
	showContent();
}
function qr( msg ) {
	return new QRCode( {
		  msg : msg
		, dim : 130
		, pad : 0
	} );
}
function renderQR() {
	var $el = $( '#listlan li' ).length ? $( '#listlan li' ) : $( '#listwl li' );
	var ip = $el.data( 'ip' );
	if ( ip && ip !== G.hostapd.hostapdip ) {
		var hostname = $el.data( 'hostname' );
		$( '#qrwebui' ).html( qr( 'http://'+ ip ) );
		if( hostname ) ip += '<br><gr>http://</gr>'+ hostname;
		$( '#ipwebui' ).html( ip );
		$( '#divwebui' ).removeClass( 'hide' );
	} else {
		$( '#divwebui' ).addClass( 'hide' );
	}
	if ( G.hostapd ) {
		$( '#ipwebuiap' ).html( '<gr>Web User Interface<br>http://</gr>'+ G.hostapd.hostapdip );
		$( '#ssid' ).text( G.hostapd.ssid );
		$( '#passphrase' ).text( G.hostapd.passphrase )
		$( '#qraccesspoint' ).html( qr( 'WIFI:S:'+ G.ssid +';T:WPA;P:'+ G.passphrase +';' ) );
		$( '#qrwebuiap' ).html( qr( 'http://'+ G.hostapdip ) );
		$( '#boxqr' ).removeClass( 'hide' );
	} else {
		$( '#ipwebuiap, #ssid, #passphrase, #qraccesspoint, #qrwebuiap' ).empty();
		$( '#boxqr' ).addClass( 'hide' );
	}
}
function wlanList() {
	var i = G.li.index( '.wl' );
	return i === 0 ? G.listwl : G.listwlnc[ i - 1 ];
}
function wlanScan() {
	bash( '/srv/http/bash/networks-scanwlan.sh', function( data ) {
		if ( data ) {
			G.listwlscan = data;
			var htmlwl = '';
			G.listwlscan.forEach( function( list ) {
				var signal = list.dbm > -60 ? '' : ( list.dbm < -67 ? 1 : 2 );
				htmlwl += '<li class="wlscan"><i class="fa fa-wifi'+ signal +'"></i>';
				if ( list.connected ) htmlwl += '<grn>&bull;</grn>&ensp;';
				htmlwl += list.dbm < -67 ? '<gr>'+ list.ssid +'</gr>' : list.ssid;
				if ( list.encrypt === 'on') htmlwl += ' <i class="fa fa-lock"></i>';
				htmlwl += '<gr>'+ list.dbm +' dBm</gr>';
				if ( list.profile && !list.connected ) htmlwl += '&ensp;<i class="fa fa-save-circle wh"></i>';
				htmlwl += '</li>';
			} );
		} else {
			var htmlwl = '<li><i class="fa fa-lock"></i><gr>(no accesspoints found)</gr></li>';
		}
		$( '#listwlscan' ).html( htmlwl );
		timeoutscan = setTimeout( wlanScan, 12000 );
	}, 'json' );
}
function wlanStatus() {
	$( '#divinterface, #divwebui, #divaccesspoint' ).addClass( 'hide' );
	$( '#divwifi' ).removeClass( 'hide' );
	wlanScan();
}
