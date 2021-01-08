package require tmq
package require rl_json
package require sha256
package require jmsg

namespace import rl_json::json

set script [file normalize [info script]]
set modfile [file root [file tail $script]]
lassign [split $modfile -] _ modver

proc connect {connection_file} {
    set f [open $connection_file]
    set conn [read $f]
    close $f
    set key [json get $conn key]
    puts $conn
    interp alias {} hmac {} sha2::hmac -hex -key $key
    set iopub [tmq::serve pub [json get $conn iopub_port] iopub recv_iopub]
    tmq::serve router [json get $conn shell_port] shell [list recv_shell $iopub]
    tmq::serve router [json get $conn control_port] control recv_control
    tmq::serve router [json get $conn stdin_port] stdin recv_stdin

    interp alias {} iopub {} $iopub
    tmq::serve rep [json get $conn hb_port] hb recv_hb
    vwait forever
}


proc recv_shell {iopub zsocket frames} {
     # shell needs an available iopub channel to
     # show status
     if {[info commands $iopub] eq {}} {
        puts "No IOPUB connection yet, waiting.."
        after 100 [list recv_shell $iopub $cmd $zsocket $frames]
     }
     set jmsg [jmsg::new $frames]

     set msgtype [jmsg::msgtype $jmsg]
     puts "shell: $zsocket ($msgtype) << $jmsg"
     handle_$msgtype $zsocket $jmsg
}


proc recv_control {zsocket zmsg} {
     puts "control: $zsocket << [tmq::display $zmsg]"
}

proc recv_iopub {zsocket zmsg} {
     puts "iopub: $zsocket << [tmq::display $zmsg]"
}

proc handle_kernel_info_request {zsocket jmsg} {
    # puts "Handling info request: $jmsg"
    variable modver
    set parent [dict get $jmsg header]
    dict with jmsg {
        set parent $header
        set username [json get $header username]
        set header  [jmsg::newheader $username kernel_info_reply]
        set version [info patchlevel]
	set banner [format "Tcl %s :: TclJupyter kernel %s \nProtocol v%s" \
			$version \
			$modver \
			"5.3"]
        set content [json template $::kernel_info]
    }
    iopub send [jmsg::frames [jmsg::status $parent busy]]
    set frames [jmsg::frames $jmsg]
    $zsocket send $frames
    iopub send [jmsg::frames [jmsg::status $parent idle]]
    # respond shell $jmsg
}
set kernel_info { {
    "status" : "ok",
    "protocol_version": "5.3",
    "implementation": "tcljupyter",
    "implementation_version": "~S:modver",
    "language_info": {
        "name": "tcl",
        "version": "~S:version",
        "mimetype": "txt/x-tcl",
        "file_extension": ".tcl"
    },
    "banner" : "~S:banner"
}}
