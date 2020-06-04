package require zmq
package require Thread
package require rl_json

namespace eval tclkernel {
  variable conn
  namespace import ::rl_json::json
  proc connect {connection_file} {
    variable conn
    set f [open $connection_file]
    set conn [read $f]
    puts $conn
    listen hb REP
    listen shell ROUTER
    listen control ROUTER
    listen stdin ROUTER
    listen iopub PUB
    puts ok
  }

  proc listen {portname type} {
    set t [thread::create]
    thread::send $t -async [list set auto_path $::auto_path]
    thread::send $t -async "package require zmq"
    thread::send $t -async {zmq context context}
    thread::send $t -async [list zmq socket zsocket context $type]
    thread::send $t -async [list zsocket bind [address $portname]]
    thread::send $t -async [puts [list start [address $portname]]]
    thread::send $t -async {puts [zsocket recv]}
    thread::send $t -async [list puts stdout $portname]
    thread::send $t -async {puts end}
    puts "here"

  }

  proc handle_hb {} {
    puts [hb recv]
  }

  proc address {portname} {
    variable conn
    set address [json get $conn transport]://
    append address [json get $conn ip]:
    append address [json get $conn ${portname}_port]
    return $address

  }

}

