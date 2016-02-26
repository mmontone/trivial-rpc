(asdf:defsystem #:trivial-rpc-zmq
  :description "ZeroMQ transport for trivial-rpc"
  :author "Oleksandr Kozachuk"
  :maintainer "Mariano Montone <marianomontone@gmail.com>"
  :serial t
  :components ((:file "cl-store"))
  :depends-on (:pzqm
               :trivial-rpc))
