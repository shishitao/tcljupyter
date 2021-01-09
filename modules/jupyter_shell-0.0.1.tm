package require zmq
package require rl_json
package require jmsg

namespace import rl_json::json

proc start {address iopubthread} {
zmq context context

zmq socket zsocket context ROUTER
zsocket bind $address

while 1 {
    set zmsg [zmsg recv zsocket]
    puts "Shell received $zmsg"
}
}



