(asdf:defsystem #:trivial-rpc
  :description "Extendable asynchronous RPC framework for Common Lisp"
  :author "Oleksandr Kozachuk"
  :maintainer "Mariano Montone <marianomontone@gmail.com>"
  :serial t
  :components ((:file "package")
               (:file "rpc"))
  :depends-on (:bordeaux-threads))
