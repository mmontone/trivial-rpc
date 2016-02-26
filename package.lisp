(defpackage :trivial-rpc
  (:nicknames :rpc)
  (:use :common-lisp :bordeaux-threads)
  (:export :define-rpc-class
           :define-rpc-method

           :transport
           :transport-client
           :transport-server
           :null-transport
           :transport-mt
           :transport-mt-server
           :transport-mt-client
           :transport-serialized
           :transport-zeromq
           :transport-client-zeromq
           :transport-server-zeromq

           :run-rpc-server
           :start-rpc-server

           :send-packet
           :recv-packet

           :transport-close
           :transport-zeromq-url))
