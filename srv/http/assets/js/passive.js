$( window ).on( 'resize', () => { // portrait / landscape
	displayBars();
	if ( G.wH > G.wW === window.innerHeight > window.innerWidth ) return
	
	G.wH = window.innerHeight;
	G.wW = window.innerWidth;
	displayBars();
	if ( G.playback ) {
		displayPlayback();
		setTimeout( renderPlayback, 50 );
		setButtonControl();
	} else if ( G.library ) {
		if ( G.librarylist ) {
			setTimeout( () => {
				if ( $( '.licover' ).length ) {
					$( '#lib-list p' ).css( 'min-height', ( $( '#bar-top' ).is( ':visible' ) ? 40 : 0 ) );
					$( '.liinfo' ).css( 'width', ( document.body.clientWidth - $( '.licoverimg img' ).width() - 50 ) );
				} else {
					$( '#lib-list p' ).css( 'min-height', G.wH - ( $( '#bar-top' ).is( ':visible' ) ? 130 : 90 ));
				}
			}, 0 );
		}
	} else {
		if ( G.playlist && !G.savedlist && !G.savedplaylist ) {
			setTimeout( () => {
				setPlaylistInfoWidth();
				setPlaylistScroll()
				$( '#pl-list p' ).css( 'min-height', G.wH - ( $( '#bar-top' ).is( ':visible' ) ? 277 : 237 ) );
			}, 0 );
		}
	}
} );
// active / inactive window /////////
var active = 1;
connect = () => {
	if ( !active && !G.poweroff ) {
		active = 1;
		pushstream.connect();
	}
}
disconnect = () => {
	if ( active ) {
		active = 0;
		pushstream.disconnect();
	}
}
function bookmarkCover( url, path ) {
	var url = url.replace( '/srv/http', '' );
	var path = path.replace( '/srv/http/data/', '' );
	$( '.bookmark' ).each( function() {
		var $this = $( this );
		if ( $this.find( '.lipath' ).text() === path ) {
			var htmlbk = '<a class="lipath">'+ path +'</a>';
			if ( url.slice( -4 ) !== 'none' ) {
				htmlbk += '<img class="bkcoverart" src="'+ url +'">';
			} else {
				htmlbk += '<i class="fa fa-bookmark"></i>'
						 +'<div class="divbklabel">'
						 +'<span class="bklabel label">'+ path.split( '/' ).pop() +'</span></div>'
			}
			$this.find( '.mode' ).html( htmlbk );
			return false
		}
	} );
}
function statusUpdate( data ) {
	$.each( data, function( key, value ) {
		G.status[ key ] = value;
	} );
	if ( !$( '#playback' ).hasClass( 'fa-'+ G.status.player ) ) displayBottom();
	setButtonControl();
	setButtonOptions();
	if ( G.display.snapclient ) bash( [ 'lcdcharrefresh', JSON.stringify( G.status ) ] );
}
function webradioIcon( srcnoext ) {
	var radiourl = decodeURIComponent( srcnoext )
					.split( '/' ).pop()
					.replace( /\|/g, '/' );
	return $( '#lib-list li' ).filter( function() {
		return $( this ).find( '.lipath' ).text() === radiourl;
	} ).find( '.lib-icon' );
}
document.addEventListener( 'visibilitychange', () => document.hidden ? disconnect() : connect() ); // invisible
window.onpagehide = window.onblur = disconnect; // invisible + visible but not active
window.onpageshow = window.onfocus = connect;
////////////////////////////////////
var pushstream = new PushStream( {
	  modes                                 : 'websocket'
	, timeout                               : 5000
	, reconnectOnChannelUnavailableInterval : 5000
} );
var streams = [ 'airplay', 'bookmark', 'btreceiver', 'coverart', 'display', 'equalizer', 'mpdplayer', 'mpdradio', 'mpdupdate',
	'notify', 'option', 'order', 'playlist', 'playlists', 'relays', 'reload', 'volume', 'webradio' ];
if ( !G.localhost ) streams.push( 'vumeter' );
streams.forEach( stream => {
	pushstream.addChannel( stream );
} );
pushstream.connect();
pushstream.onstatuschange = status => { // 0 - disconnected; 1 - reconnect; 2 - connected
	if ( status === 2 && G.disconnected ) { // suppress on 1st load
		getPlaybackStatus( 'withdisplay' );
		if ( O.title === 'Equalizer' ) {
			bash( [ 'equalizerget' ], function( data ) {
				psEqualizer( data );
			}, 'json' );
		}
	} else if ( status === 0 ) {
		G.disconnected = 1;
		clearIntervalAll();
		hideGuide();
		if ( $( '#infoIcon' ).hasClass( 'fa-relays' ) ) $( '#infoX' ).click();
	}
}
pushstream.onmessage = ( data, id, channel ) => {
	switch( channel ) {
		case 'airplay':    psAirplay( data );    break;
		case 'bookmark':   psBookmark( data );   break;
		case 'btreceiver': psBtReceiver( data ); break;
		case 'coverart':   psCoverart( data );   break;
		case 'display':    psDisplay( data );    break;
		case 'equalizer':  psEqualizer( data );  break;
		case 'relays':     psRelays( data );     break;
		case 'mpdplayer':  psMpdPlayer( data );  break;
		case 'mpdradio':   psMpdRadio( data );   break;
		case 'mpdupdate':  psMpdUpdate( data );  break;
		case 'notify':     psNotify( data );     break;
		case 'option':     psOption( data );     break;
		case 'order':      psOrder( data );      break;
		case 'playlist':   psPlaylist( data );   break;
		case 'playlists':  psPlaylists( data );  break;
		case 'reload':     location.href = '/';  break;
		case 'restore':    psRestore( data );    break;
		case 'volume':     psVolume( data );     break;
		case 'vumeter':    psVUmeter( data );    break;
		case 'webradio':   psWebradio( data );   break;
	}
}
function psAirplay( data ) {
	statusUpdate( data );
	if ( G.playback ) renderPlayback();
}
function psBtReceiver( connected ) {
	var prefix = $( '#time-knob' ).is( ':visible' ) ? 'ti' : 'i';
	$( '#'+ prefix +'-btsender' ).toggleClass( 'hide', !connected );
}
function psBookmark( data ) {
	if ( 'html' in data ) {
		$( '#lib-mode-list' ).append( data.html );
	} else {
		var $bookmark = $( '.lib-mode' ).filter( function() {
			return $( this ).find( '.lipath' ) === data.path;
		} );
		if ( data.type === 'delete' ) {
			$bookmark.remove();
		} else {
			$bookmark.find( '.bklabel' ).text( data.name );
		}
	}
	$( '.mode-bookmark, .bklabel' ).removeAttr( 'style' );
	if ( 'order' in data ) {
		G.display.order = data.order;
		orderLibrary();
	}
}
function psCoverart( data ) {
	clearTimeout( G.timeoutCover );
	var src = data.url;
	var url = decodeURIComponent( data.url );
	var path = getDirectory( url ).replace( '/mnt/MPD/', '' );
	switch( data.type ) {
		case 'bookmark':
			bookmarkCover( url, path );
			break;
		case 'coverart':
			$( '.coveredit, .bkedit' ).remove();
			$( '#coverart, #liimg' ).css( 'opacity', '' );
			if ( G.playback ) {
				G.status.coverart = url;
				setCoverart();
				if ( 'Album' in data ) { // with webradio
					G.status.Album = data.Album;
					setInfo();
				}
			} else if ( G.library ) {
				if ( path === '/data/audiocd' ) return
				
				if ( $( '.licover' ).length ) {
					var covername = url.split( '/' ).pop().slice( 0, -4 );
					var artistalbum = $( '.liinfo .liartist' ).text() + $( '.liinfo .lialbum' ).text();
					artistalbum = artistalbum.replace( /[ '"`?/#&]/g, '' );
					if ( covername === artistalbum ) {
						$( '#liimg' ).attr( 'src', url );
						$( '.licover .coveredit' ).remove();
						$( '.licoverimg ' )
							.css( 'opacity', '' )
							.append( icoversave );
					}
				} else {
					$( '#lib-list li' ).each( function() {
						if ( $( this ).find( '.lipath' ).text() === path ) {
							$( this ).find( '.lib-icon' ).replaceWith( '<img class="iconthumb lib-icon" src="'+ url +'" data-target="#menu-folder">' );
							return false
						}
					} );
				}
			} else {
				if ( path === '/data/shm' || !$( '#pl-index' ).hasClass( 'hide' ) ) return
				
				if ( path === '/data/audiocd' ) {
					$( '#pl-list li' ).each( function() {
						if ( $( this ).find( '.lipath' ).text().slice( 0, 4 ) === 'cdda' ) {
							$( this ).find( '.pl-icon' ).replaceWith( '<img class="iconthumb pl-icon" src="'+ url +'">' );
						}
					} );
					return // skip .bookmark
				}
				
				var $li = G.savedplaylist ? $( '#pl-savedlist li' ) : $( '#pl-list li' );
				$li.each( function() {
					var lipath = $( this ).find( '.lipath' ).text()
					if ( getDirectory( lipath ) === path ) {
						if ( url.slice( -4 ) !== 'none' ) {
							$( this ).find( '.pl-icon' ).replaceWith( '<img class="iconthumb pl-icon" src="'+ url +'">' );
						} else {
							$( this ).find( '.pl-icon' ).replaceWith( '<i class="fa fa-music pl-icon" data-target="#menu-filesavedpl"></i>' );
						}
					}
				} );
			}
			bookmarkCover( url, path );
			break;
		case 'webradio':
			G.status.stationcover = src;
			if ( G.playback ) {
				$( '#vu' ).addClass( 'hide' );
				$( '#coverart' )
					.attr( 'src', src )
					.css( 'opacity', '' )
					.removeClass( 'hide' );
			} else if ( G.playlist ) {
				$( '#playlist' ).click();
			} else if ( G.librarylist && G.mode === 'webradio' ) {
				psWebradio( -1 );
			}
			break;
		case 'webradioreset':
			G.status.stationcover = '';
			if ( G.playback ) {
				if ( G.status.coverart === src ) coverartDefault();
			} else if ( G.playlist ) {
				$( '#playlist' ).click();
			} else if ( G.librarylist && G.mode === 'webradio' ) {
				psWebradio( -1 );
			}
			break;
	}
	bannerHide();
}
function psDisplay( data ) {
	console.log(data)
	if ( 'submenu' in data ) {
		G.display[ data.submenu ] = data.value;
		displaySubMenu();
		return
	}
	
	if ( 'updateaddons' in data ) {
		G.status.updateaddons = data.updateaddons ? true : false;
		setButtonUpdateAddons();
		return
	}
	
	$.each( data, function( key, val ) {
		G.display[ key ] = val;
	} );
	G.coverdefault = !G.display.covervu && !G.display.vumeter ? G.coverart : G.covervu;
	displayBars();
	if ( G.playback ) {
		setButtonControl();
		displayPlayback();
		renderPlayback();
	} else if ( G.library ) {
		if ( !G.librarylist ) {
			renderLibrary();
		} else if ( $( '.lib-icon' ).eq( 0 ).hasClass( 'fa-music' ) ) {
			if ( G.display.hidecover ) {
				$( '.licover' ).remove();
			} else {
				var query = G.query[ G.query.length - 1 ];
				list( query, function( data ) {
					data.path = query.path;
					data.modetitle = query.modetitle;
					renderLibraryList( data );
				}, 'json' );
			}
		}
		$( '#button-lib-back' ).toggleClass( 'back-left', G.display.backonleft );
	}
}
function psEqualizer( data ) {
	if ( !$( '#eqpreset' ).length ) return
	
	G.eq = data;
	infoEqualizer( 'update' );
}
function psMpdPlayer( data ) {
	clearTimeout( G.debounce );
	G.debounce = setTimeout( function() {
		if ( data.state === 'play' && !data.Title && [ 'radiofrance', 'radioparadise' ].includes( data.icon ) ) {
			bash( [ 'radiorestart' ] ); // fix slow wi-fi - on station changed
		}
		if ( !data.control && data.volume == -1 ) { // fix - upmpdcli missing values on stop/pause
			delete data.control;
			delete data.volume;
		}
		statusUpdate( data );
		if ( G.playback ) {
			displayPlayback();
			renderPlayback();
		} else if ( G.playlist ) {
			setPlaylistScroll();
		}
	}, G.debouncems );
}
function psMpdRadio( data ) {
	statusUpdate( data );
	setProgress( 0 );
	if ( G.playback ) {
		setInfo();
		setCoverart();
		if ( G.display.radioelapsed ) {
			$( '#progress' ).html( '<i class="fa fa-play"></i><span></span>' );
			setProgressElapsed();
		} else {
			setBlinkDot();
		}
	} else if ( G.playlist ) {
		setPlaylistScroll();
	}
}	
function psMpdUpdate( data ) {
	G.status.updating_db = data === 1;
	if ( G.status.updating_db ) {
		setButtonUpdating();
		return
	}
	
	clearTimeout( G.debounce );
	G.debounce = setTimeout( function() {
		G.status.counts = data;
		renderLibraryCounts();
		setButtonUpdating();
		banner( 'Library Update', 'Done', 'library' );
		if ( G.library ) {
			if ( !G.librarylist ) return
			
			if ( G.mode === 'webradio' ) {
				data.webradio ? $( '#mode-webradio' ).click() : $( '#button-library' ).click();
			} else {
				var query = G.query[ G.query.length - 1 ];
				if ( query ) {
					list( query, function( data ) {
						data.path = query.path;
						data.modetitle = query.modetitle;
						renderLibraryList( data );
					}, 'json' );
				}
			}
		} else if ( G.playlist && !G.savedlist ) {
			$( '#playlist' ).click();
		}
	}, 3000 );
}
function psNotify( data ) {
	if ( $( '#bannerMessage' ).text().includes( 'Reconnect again' ) && data.text !== 'Connect ...' ) return
	
	banner( data.title, data.text, data.icon, data.delay );
	if ( data.title === 'Power' ) {
		switchPage( 'playback' );
		loader();
		if ( data.text === 'Off ...' ) {
			$( '#loader' ).css( 'background', '#000000' );
			setTimeout( function() {
				$( '#loader .logo' ).css( 'animation', 'none' );
			}, 10000 );
			pushstream.disconnect();
			G.poweroff = 1;
		}
	} else if ( data.text === 'Change track ...' ) { // audiocd
		clearIntervalAll();
	} else if ( data.title === 'Latest' ) {
		G.status.counts.latest = 0;
		$( '#mode-latest gr' ).empty();
		if ( G.mode === 'latest' ) $( '#button-library' ).click();
	}
}
function psOption( data ) {
	if ( G.local ) return
	
	if ( 'addons' in data ) {
		setButtonUpdateAddons();
		return
	}
	
	var option = Object.keys( data )[ 0 ];
	G.status[ option ] = Object.values( data )[ 0 ];
	setButtonOptions();
}
function psOrder( data ) {
	if ( G.local ) return
	
	G.display.order = data;
	orderLibrary();
}
function psPlaylist( data ) {
	if ( G.local || G.plremove || G.sortable ) return
	
	clearTimeout( G.debounce );
	G.debounce = setTimeout( function() {
		if ( data == -1 ) {
			setPlaybackBlank();
			renderPlaylist( -1 );
			bannerHide();
		} else if ( 'autoplaycd' in data ) {
			G.autoplaycd = 1;
			setTimeout( function() { delete G.autoplaycd }, 5000 );
		} else if ( 'html' in data ) {
			if ( G.playlist && !G.plremove ) renderPlaylist( data );
		} else {
			var name = $( '#pl-path .lipath' ).text();
			if ( G.savedplaylist && data.playlist === name ) renderSavedPlaylist( name );
		}
		getPlaybackStatus();
	}, G.debouncems );
}
function psPlaylists( data ) {
	var count = data.count;
	G.status.counts.playlists = count;
	if ( G.savedlist ) {
		count ? renderPlaylistList( data ) : $( '#playlist' ).click();
	} else if ( G.savedplaylist ) {
		if ( 'delete' in data && $( '#pl-path .lipath' ).text() === data.delete ) $( '#playlist' ).click();
	}
	$( '#button-pl-playlists' ).toggleClass( 'disabled', count === 0 );
	$( '#mode-playlists gr' ).text( count || '' );
}
function psRelays( response ) {
	clearInterval( G.intRelaysTimer );
	if ( 'on' in response ) {
		$( '#device'+ response.on ).removeClass( 'gr' );
	} else if ( 'off' in response ) {
		$( '#device'+ response.off ).addClass( 'gr' );
	} else if ( 'done' in response ) {
		$( '#infoX' ).click();
	}
	if ( !( 'state' in response ) ) return
		
	var stopwatch = '<div class="msg-l"><object type="image/svg+xml" data="/assets/img/stopwatch.svg"></object></div>';
	var state = response.state;
	if ( state === 'RESET' ) {
		$( '#infoX' ).click();
	} else if ( state === 'IDLE' ) {
		info( {
			  icon        : 'relays'
			, title       : 'Relays Countdown'
			, message     : stopwatch
							+'<div class="msg-r wh">60</div>'
			, buttonlabel : '<i class="fa fa-relays"></i>Off'
			, buttoncolor : red
			, button      : function() {
				bash( '/srv/http/bash/settings/relays.sh' );
			}
			, oklabel     : '<i class="fa fa-set0"></i>Reset'
			, ok          : function() {
				bash( [ 'relaystimerreset' ] );
				banner( 'GPIO Relays', 'Reset idle timer to '+ response.timer +'m', 'relays' );
			}
		} );
		var delay = 59;
		G.intRelaysTimer = setInterval( function() {
			if ( delay ) {
				$( '.infomessage .wh' ).text( delay-- );
			} else {
				clearInterval( G.intRelaysTimer );
				$( '#relays' ).removeClass( 'on' );
				$( '#i-relays, #ti-relays' ).addClass( 'hide' );
			}
		}, 1000 );
	} else {
		if ( !state ) $( '#infoX' ).click();
		var devices = '';
		$.each( response.order, function( i, val ) {
			if ( i === 0 ) {
				var color = state ? '' : 'class="gr"';
			} else {
				var color = state ? 'class="gr"' : '';
			}
			devices += '<a id="device'+ ( i + 1 ) +'" '+ color +'>'+ val +'</a><br>';
		} );
		if ( $( '#infoOverlay' ).hasClass( 'hide' ) ) {
			info( {
				  icon       : 'relays'
				, title      : 'Relays '+ ( state ? 'ON' : 'OFF' )
				, message    : stopwatch
							  +'<div class="msg-r">'+ devices +'</div>'
				, okno       : 1
				, beforeshow : function() {
					$( '#infoX' ).addClass( 'hide' );
				}
			} );
		} else {
			$( '#infoTitle' ).text( 'GPIO Relays '+ ( state ? 'ON' : 'OFF' ) );
			$( '.infobtn' ).addClass( 'hide' );
			$( '.infofooter wh' ).html( devices );
		}
	}
}
function psRestore( data ) {
	if ( data.restore === 'done' ) {
		banner( 'Restore Settings', 'Done', 'sd' );
		setTimeout( function() {
			location.href = '/';
		}, 2000 );
	} else {
		loader();
		banner( 'Restore Settings', 'Restart '+ data.restore +' ...', 'sd blink', -1 );
	}
}
function psVolume( data ) {
	if ( data.type === 'disable' ) {
		$( '#volume-knob, #vol-group i' ).toggleClass( 'disabled', data.val );
		return
	} else if ( 'volumenone' in data ) {
		G.display.volumenone = data.volumenone;
		$( '#volume-knob' ).toggleClass( 'hide', data.volumenone )
		return
	}
	
	clearTimeout( G.debounce );
	G.debounce = setTimeout( function() {
		var vol = data.val;
		var mute = data.type === 'mute';
		if ( mute ) {
			G.status.volumemute = vol;
			vol = 0;
		} else {
			G.status.volumemute = 0;
		}
		$volumeRS.setValue( vol );
		mute ? volumeColorMute() : volumeColorUnmute();
		$( '#volume-bar' ).css( 'width',  vol +'%' )
		$( '#volume-text' )
			.text( mute ? data.val : vol )
			.toggleClass( 'bl', mute );
		if ( $( '#time-knob' ).is( ':hidden' ) ) {
			var prefix = $( '#time-knob' ).is( ':visible' ) ? 'ti' : 'i';
			$( '#'+ prefix +'-mute' ).toggleClass( 'hide', !mute );
		}
	}, G.debouncems );
}
function psVUmeter( data ) {
	$( '#vuneedle' ).css( 'transform', 'rotate( '+ data.val +'deg )' ); // 0-100 : 0-42 degree
}
function psWebradio( data ) {
	if ( data != -1 ) $( '#mode-webradio gr' ).text( data );
	if ( G.librarylist && G.mode === 'webradio' ) {
		var query = G.query[ G.query.length - 1 ];
		if ( query.path ) {
			list( query, function( data ) {
				data.path = query.path;
				data.modetitle = query.modetitle;
				renderLibraryList( data );
			}, 'json' );
		} else {
			$( '#mode-webradio gr' ).click();
		}
	} else if ( G.playlist && !G.local ) {
		getPlaylist();
	}
}

