(asdf:defsystem #:trivial-rpc-cl-store
  :description "CL-STORE serializer for trivial-rpc"
  :author "Oleksandr Kozachuk"
  :maintainer "Mariano Montone <marianomontone@gmail.com>"
  :serial t
  :components ((:file "cl-store"))
  :depends-on (:cl-store
               :trivial-rpc))
