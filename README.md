TRIVIAL-RPC
-----------

A Extendable asynchronous RPC framework for Common Lisp

The following text and code was extracted from: http://cl.kozachuk.info/2011/09/extendable-asynchronous-rpc-framework.html

# Introduction

Some days ago I looked for Remote-Procedure-Call (RPC) packages for Common Lisp, but found only things which are not very lispy and have either to much dependencies, or are too complicated, or both, like CORBA or XML-RPC based ones. So I decided to write my own RPC package. It makes fun to write something in CL, and even if it already exists somewhere, who cares? I'll call it trivial-rpc and it will have asynchronous semantics. The idea is to have a language for defining classes and methods, which is callable over an transport channel. As an example i will write here a simple file server which gives access to one file over RPC. Such a file server could be defined as follows:

```lisp

(define-rpc-class (file-server fs-stub) ()
  ((filename :initarg :filename
             :initform (error "No filename given"))))

```

It looks like normal defclass but with two class names, the first is a regular class name. The second class name is a stub, it will be used to define proxy-like objects, with exactly the same methods as the file-server class, but the method calls are routed to real objects. The method definition should look like follows:

```lisp

(define-rpc-method read-file ((fs file-server fs-stub) read-length &key)
  (with-slots (filename) fs
    (with-open-file (fd filename :direction :input)
      (let ((buffer (make-array read-length
                                :initial-element #\Nul
                                :element-type 'character)))
        (cons (read-sequence buffer fd) buffer)))))

```

This method reads given amount of data from a file. The definition have as its first argument a special definition, which gives the name of RPC object and defines the type of real objects and type of stub objects. So this definition creates two methods for the same generic method: one with a real body and one with a special stub body.

# Language implementation

Of course we implement our RPC definition language as Common Lisp macros. The first macro is for defining RPC classes: 

```lisp

(defmacro define-rpc-class ((classname stubname) parents &rest classdef)
  `(prog1 (defclass ,classname ,parents ,@classdef)
          (defclass ,stubname ,parents
            ((transport :initarg :transport
                        :initform (error "No transport given"))))))

```

It expands to two class definitions: the first is a conventional class and the second is a class with only a transport slot. With the transport slot, our stub knows where to route the method call. The second macro implements an language for method definition: 

```lisp

(defmacro define-rpc-method (method ((self class stub) &rest args)
                                    &body body)
  (let ((argnames (loop for x in args
                        if (listp x) collect (car x) else
                        unless (find x lambda-list-keywords) collect x)))
    `(prog1 (defmethod ,method ((,self ,class) ,@args) ,@body)
       (defmethod ,method ((,self ,stub) ,@args)
         (let ((transport (slot-value ,self 'transport)))
           (send-packet transport (cons ',method (list ,@argnames)))
           (lambda () (recv-packet transport)))))))

```

The stub method uses the object in transport slot to send the method's name and list of given arguments. Finally it returns a closure which will wait for the return value and then return it. It is possible to start multiple RPC calls on several servers in parallel and wait until they will be finished. 

# Transport concept and null transporter

The main functionality is in the transport object, which transports the call information to the server. We will create a tree of transport classes, to make it extendable. Each of this classes adds to final transporters some specialized functionality, so we can extend it easily with creating new classes or methods in the tree. The client and the server work slightly different, so we will also differentiate between them in our class tree. 

```lisp

(defclass transport () ())
(defclass transport-client (transport) ())
(defclass transport-server (transport) ())

```

To get an idea about how the transport should work, we define very simple null-transport which puts the call to a queue on send-package and on recv-packet executes and returns the real method. 

```lisp

(defclass null-transport (transport-client)
  ((object :initarg :object
           :initform (error "No object given"))
   (requests :initform nil)))

```

A null-transport dont need for an server. We need also only define methods for the client class: 

```lisp

(defgeneric send-packet (transport packet &key))
(defgeneric recv-packet (transport &key))

(defmethod send-packet ((transport null-transport) packet &key)
  (push packet (slot-value transport 'requests)))

(defmethod recv-packet ((transport null-transport) &key)
  (with-slots (object requests) transport
    (let ((req (pop requests)))
      (if (null req) (error "No requests pending")
          (apply (car req) object (cdr req))))))

```

The send-packet function simply pushes the packet to request slot in null-transport class. The recv-packet function pops the request, checks it, applies it to the stored object and returns the result. Now we can test our framework:

```lisp
CL-USER> (setf fs (make-instance 'file-server :filename "test.txt"))
#<a FILE-SERVER>
CL-USER> (setf tp (make-instance 'null-transport :object fs))
#<a NULL-TRANSPORT>
CL-USER> (setf stub (make-instance 'fs-stub :transport tp))
#<a FS-STUB>
```
On calling the method read-file with variable fs as its first argument, the regular implementation of this method will be called. But if we call it with variable stub, the call will be transferred to the real object through the null-transport in variable tp:

```lisp
CL-USER> (read-file fs 4)
(4 . "text")
CL-USER> (setf temp (read-file stub 4))
#<bytecompiled-closure #<bytecompiled-function 0000000003c18eb0>>
CL-USER> (funcall temp)
(4 . "text")
```

As you can see, it gives the same result with real object and with the asynchronous interface on stub object. 


# Multi thread transporter


A null-transporter is not very useful, so we go further, and define a transporter between threads. We will use bordeaux-threads for it. For the first, we will write a general RPC server, which works with all our transporters: 

```lisp

(defgeneric run-rpc-server (transport object &key))

(defmethod run-rpc-server ((transport transport-server) object &key)
  (loop for request = (recv-packet transport) do
        (if (eql (car request) :shutdown)
          (return (send-packet transport nil))
          (send-packet transport
            (handler-case (apply (car request) object (cdr request))
              (condition (c) c))))))

```

This method starts recv-packet in a loop, applies received requests to the given object and calls send-packet to send the result. If method's name is keyword :shutdown, the server should immediately return. On a condition, the condition will be send as return value. It is possible to differentiate strictly between the types of request and return values with additional tags in requests and responses, but for the sake of simplicity we will not do that. Now we can define classes for the multithreaded transport: 

```lisp

(defclass transport-mt () ())

(defclass transport-mt-server (transport-server transport-mt)
  ((lock :initform (make-lock 'transport-mt-lock))
   (cond :initform (make-condition-variable))
   (request :initform nil)
   (response :initform nil)))

(defclass transport-mt-client (transport-client transport-mt)
  ((server :initarg :server
           :initform (error "No server given"))))

```

Server has a request and response store, both will be secured with a lock. The client holds simply an reference to the server. The code for sending and receiving packets in server and client is mirrored, so we define macros, to use it in both cases. First macro is for sending packets:

```lisp

(defmacro send-mt-packet (transport slot packet)
  `(with-slots (lock cond ,slot) ,transport
     (with-lock-held (lock)
       (loop while ,slot do (condition-wait cond lock))
       (setf ,slot ,packet)
       (condition-notify cond))))

```

It stores the packet simply in the given slot, but waits as long as the slot contains something. The packet receiver works similar:

```lisp

(defmacro recv-mt-packet (transport slot)
  `(with-slots (lock cond ,slot) ,transport
     (with-lock-held (lock)
       (loop until ,slot do (condition-wait cond lock))
       (let ((packet ,slot))
         (prog1 packet
           (setf ,slot nil)
           (condition-notify cond))))))

```

It reads a packet from given slot and returns it. When the slot doesn't contain a packet, receiver waits for it. Both operations notify the waiting threads. These macros are not hygienic, if you want to make them hygienic use the defmacro! macro from Let over Lambda book by Doug Hoyte, but it is not really required here. Definitions of send-packet and recv-packet are very simple now:

```lisp

(defmethod send-packet ((transport transport-mt-client) packet &key)
  (send-mt-packet (slot-value transport 'server) request packet))
(defmethod recv-packet ((transport transport-mt-client) &key)
  (recv-mt-packet (slot-value transport 'server) response))
(defmethod send-packet ((transport transport-mt-server) packet &key)
  (send-mt-packet transport response packet))
(defmethod recv-packet ((transport transport-mt-server) &key)
  (recv-mt-packet transport request))

```

We define also a method to start our server in a new thread, this server uses the method we have defined earlier - run-rpc-server:

```lisp

(defgeneric transport-close (transport &key))

(defgeneric start-rpc-server (transport object &key))

(defmethod start-rpc-server ((transport transport-mt-server) object &key)
  (make-thread #'(lambda () (run-rpc-server transport object))
               :name (format nil "RPC/MT Server for ~S" object)))

```

Now we can test our asynchronous RPC framework based on threads, for the first we initialize all required objects:

```lisp
CL-USER> (setf fs (make-instance 'file-server :filename "test.txt"))
#<a FILE-SERVER>
CL-USER> (setf tps (make-instance 'transport-mt-server))
#<a TRANSPORT-MT-SERVER>
CL-USER> (setf tpc (make-instance 'transport-mt-client :server tps))
#<a TRANSPORT-MT-CLIENT>
CL-USER> (setf stub (make-instance 'fs-stub :transport tpc))
#<a FS-STUB>
```

The usage is simple: start the server and use the stub object instead of the real object.

```lisp
CL-USER> (start-rpc-server tps fs)
#<process "RPC/MT Server for #<a FILE-SERVER>">
CL-USER> (setf temp (read-file stub 4))
#<bytecompiled-closure #<bytecompiled-function 000000000236ba34>>
CL-USER> (funcall temp)
(4 . "text")
```

Because of splitting the RPC functionality and transportation of call information, you can use the same objects with different communication mediums.


# Serialized transport


But before we can use other transports, we should be able to send the packets over an stream, therefore we need serialization. We could use some modules like cl-store or cl-prevalence, cl-json is also interesting, but I would like to show, that the Common Lisp's reader and printer are also very useful. So we define a special transport class, which serializes data transparently:

```lisp

(defclass transport-serialized (transport) ())

(defmethod send-packet :around ((transport transport-serialized)
                                packet &key)
  (call-next-method transport
    (write-to-string packet
                     :array t :base 10 :case :downcase :circle t
                     :escape t :gensym t :length nil :level nil
                     :lines nil :pretty nil :radix nil :readably nil)))

(defmethod recv-packet :around ((transport transport-serialized) &key)
  (first (multiple-value-list (read-from-string (call-next-method)))))

```

The main functions here are write-to-string and read-from-string, they come from Common Lisp standard. The methods are declared with :around modifier, so they work simply as wrappers over regular send-packet/recv-packet methods and transparently serializes and deserialize the packets.


# Summary


We have written a very simple but flexible and powerful RPC framework for Common Lisp in just couple of code lines. How do you think, what should be the next step for this package? Maybe a usocket and cl-store support to get an high speed RPC communication? Or poll-like waiting for asynchronous calls?

I have used ECL as Common Lisp platform, great implementation. Everyone knows the HyperSpec, but nevertheless I would like to mention it here.
Ahhh, and my editor is VIM :-)

Have fun with great programming language - Common Lisp!