namespace eval tmq {
	proc display {data} {
		set decoded {}

		foreach x [split $data ""] {
    	binary scan $x c d 
    	if {$d < 32 || $d > 126 }  {append decoded \\x[binary encode hex $x]} {append decoded $x}
		
	}
	return $decoded
	}
	proc send {name zmsg} {
		variable ${name}_socket
		set channel [set ${name}_socket]
		puts "Sending on $name zmq port ($channel)"

		# on the wire format is UTF-8
		set zmsg [lmap m $zmsg {encoding convertto utf-8 $m}]

		foreach msg [lrange $zmsg 0 end-1] {
			set length [string length $msg]
			if {$length > 255} {
				set format W
				set prefix \x03
			} else {
				set format c
				set prefix \x01	
			}
			set length_bytes [binary format $format $length]
			# puts [display [string range $prefix$length_bytes$msg 0 200]]
			pputs $channel $prefix$length_bytes$msg
			flush $channel
		}
		set msg [lindex $zmsg end]
		set length [string length $msg]
		if {$length > 255} {
			set format W
			set prefix \x02
		} else {
			set format c
			set prefix \x00	
		}
		set length_bytes [binary format $format $length]
		# puts [display [string range $prefix$length_bytes$msg 0 200]]
		pputs $channel $prefix$length_bytes$msg
		flush $channel
	}

	set greeting [binary decode hex [join [subst {
		ff00000000000000017f
		03
		00
		[binary encode hex NULL]
		[string repeat 00 16]
		00
		[string repeat 00 31]
	}] ""]]

	if {[string length $greeting] != 64} {
		error "Invalid greeting constant [string length $greeting] <> 64"
	}

	proc listen {name type address callback} {
		puts "Listening for $address ($name:$type)"
		socket -server [namespace code [list connection $name $type $address]] [dict get $address port]
	}

	proc connection {name type address s ip port} {
		puts "Incoming connection from $s ($ip:$port) on $address ($type) "
		dict with address {
			variable ${channel}_socket 
			set ${channel}_socket $s
		}
		set context $address


		coroutine ::tmq_$s handle $name $port [string toupper $type] $s
		fileevent $s readable ::tmq_$s
	}

	proc handle {name port type channel} {
	    variable greeting
	    variable ready
		fconfigure $channel -blocking 1 -encoding binary -translation binary
		yield
		puts "Incoming $type connection"
		# Negotiate version
		pputs $channel [string range $greeting 0 10]
		flush $channel
		set remote_greeting [read $channel 11]
		puts "Remote greeting [display $remote_greeting]"
	    # Send rest of greeting
		pputs $channel [string range $greeting 11 end]
		flush $channel
		append remote_greeting [read $channel [expr {64-11}]]


		# Send the ready command

		set msg \x05READY\x0bSocket-Type[len32 $type]$type
		if {$type eq "ROUTER"} {
			append msg \x08Identity[len32 ""]
		} 
		set zmsg [zlen $msg]$msg
		# puts ">>>> $name ($port:$type)\n[display $zmsg]"
		pputs $channel $zmsg
		flush $channel


		while {1} {
			# readable read the complete message
			set more 1
			set frames {}		
			while {$more} {
				yield
				set prefix [read $channel 1]
				if {[eof $channel]} {
					return -code error "ERROR: Channel $channel closed" 
				}

				switch -exact $prefix {
					\x00 {
						set zmsg_type msg
						set more 0
						set size short
					}	
					\x01 {
						set zmsg_type msg
						set more 1
						set size short
					}
					\x02 {
						set zmsg_type msg
						set more 0
						set size long
					}	
					\x03 {
						set zmsg_type msg
						set more 1
						set size long
					}
					\x04 {
						set zmsg_type cmd
						set more 0
						set size short
					}	
					\x06 {
						set zmsg_type cmd
						set more 0
						set size long
					}
					default {
						close $channel
						return -code error "ERROR: Unknown frame start [display $prefix]" 
					}
				}
				yield
				if {$size eq "short"} {
					set length [read $channel 1]
					binary scan $length c bytelength
					set bytelength [expr { $bytelength & 0xff }] 
				} {
					set length [read $channel 8]  
					binary scan $length W  bytelength
				}
				yield
				set frame [read $channel $bytelength]
				#puts "INFO: << [display $prefix$length[string range $frame 0 100]]"
				#puts "INFO: Frame length $bytelength"
				# Handle sub/unsub messages
				if {$type in "PUB SUB" && [string bytelength $frame] > 0} {
					set first [string index $frame 0]
					if {$first in "\x00 \x01"} {
						puts "INFO: PUBSUB handling [display $frame]"
						yield
						# Not sure why this read hangs sometimes
						fconfigure $channel -blocking 0
						append frame [read $channel 1]
						set msg_type pubsub
						puts "INFO: PUBSUB handling done"
						fconfigure $channel -blocking 1
					}
				}
				lappend frames $frame
			}
			puts "<<<< $name ($channel:$port:$zmsg_type)"
			flush stdout
			if {$zmsg_type eq "msg"} {
				set delimiter ""
				while {$delimiter ne {<IDS|MSG>}} {
					set frames [lassign $frames delimiter]
				}
				set jmsg [jmsg::new $channel $name $type $delimiter {*}$frames]
				on_recv $jmsg
			} else {
				# TODO: ignore commands and pubsub for now
			}
			yield
		}	
	}
	
	proc handle_command data {
		return {1 {}}

	}

	proc zlen {str} {
		if {[string length $str] < 256} {
			return \x04[len8 $str]
		} else {
			return \x06[len32 $str]
		}
	}

	proc len32 {str} {
			return [binary format I [string length $str]]
	}
	proc len8 {str} {
			return [binary format c [string length $str]]
	}



}

