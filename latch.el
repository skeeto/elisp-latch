;;; latch.el --- promises and latches for Elisp

;; This is free and unencumbered software released into the public domain.

;;; Commentary:

;; This code (ab)uses `accept-process-output' and processes to provide
;; asynchronous blocking, allowing other functions to run before the
;; current execution context completes. All blocking will freeze the
;; Emacs display, but timers and I/O will continue to run.

;; Three classes are provided, each building on the last: latch,
;; one-time-latch, and promise. See `make-latch',
;; `make-one-time-latch', and `make-promise'.

;; Each latch has an associated process, which doesn't get garbage
;; collected, so they need to be destroyed when no longer in
;; use. One-time-latches destroy themselves automatically after one
;; use. Use `destroy-all-latches' to clean up during debugging.

;; Methods:

;; (`wait' latch &optional timeout)
;;    Blocking wait on a latch for a `notify'.
;; (`nodify' latch &optional value)
;;    Resume all executation contexts waiting on the latch.
;; (`destroy' latch)
;;    Free resources consumed by the latch.

;; (`deliver' promise value)
;;    Deliver a value to a promise. Only happens once per promise.
;; (`retrieve' promise)
;;    Retrieve a value from a promise, blocking if necessary.

;; A promise is basically a one-time-latch whose result can be
;; retrieved more than once (i.e. cached).

;; For example, to implement your own `sleep-for' function.

;; (defun my-sleep-for (n)
;;   (let ((latch (make-one-time-latch)))
;;     (run-at-time n nil #'notify latch t)
;;     (wait latch)))

;; Or turn an asynchronous function (requires a callback to receive
;; the result) into a synchronous one (returns the result). Note the
;; important use of `lexical-let'!

;; (lexical-let ((latch (make-one-time-latch)))
;;   (skewer-eval "Math.pow(3.1, 2.1)" (apply-partially #'notify latch))
;;   (wait latch))

;; The same thing using a promise,

;; (lexical-let ((promise (make-promise)))
;;   (skewer-eval "Math.pow(3.1, 2.1)" (apply-partially #'deliver promise))
;;   (retrieve promise))

;; Futures:

;; A `future' macro is provided for educational purposes, but it is
;; completely useless in Emacs' single-threaded environment. Don't use
;; it.

;; Notice:

;; Due to a segfault bug (Debian #698096) in Emacs 24.2, this code
;; uses heavier PTY connections instead of pipes.

;;; Code:

(require 'cl)
(require 'eieio)

(defclass latch ()
  ((process :initform (start-process "latch" nil nil))
   (value :initform nil))
  :documentation "A blocking latch that can be used any number of times.")

(defmethod wait ((latch latch) &optional timeout)
  "Blocking wait on LATCH for a corresponding `notify', returning
the value passed by the notification. Wait at most TIMEOUT
seconds (float allowed), returning nil if the timeout was reached
with no input. The Emacs display will not update during this
period but I/O and timers will continue to run."
  (accept-process-output (slot-value latch 'process) timeout)
  (slot-value latch 'value))

(defmethod notify ((latch latch) &optional value)
  "Release all execution contexts waiting on LATCH, passing them VALUE."
  (setf (slot-value latch 'value) value)
  (process-send-string (slot-value latch 'process) "\n"))

(defmethod destroy ((latch latch))
  "Destroy a latch, since they can't be fully memory managed."
  (ignore-errors
    (delete-process (slot-value latch 'process))))

(defun make-latch ()
  "Make a latch which can be used any number of times. It must be
`destroy'ed when no longer used, because the underlying process
will not be garbage collected."
  (make-instance 'latch))

(defun destroy-all-latches ()
  "Destroy all known latches."
  (loop for process in (process-list)
        when (string-match-p "latch\\(<[0-9]+>\\)?" (process-name process))
        do (delete-process process)))

;; One-use latches

(defclass one-time-latch (latch)
  ()
  :documentation "A latch that is destroyed automatically after one use.")

(defmethod wait :after ((latch one-time-latch) &optional timeout)
  (destroy latch))

(defun make-one-time-latch ()
  "Make a latch that is destroyed automatically after a single use."
  (make-instance 'one-time-latch))

;; Promises

(defclass promise ()
  ((latch :initform (make-one-time-latch))
   (delivered :initform nil)
   (value :initform nil))
  :documentation "Promise built on top of a one-time latch.")

(defmethod deliver ((promise promise) value)
  "Deliver a VALUE to PROMISE, releasing any execution contexts
waiting on it."
  (if (slot-value promise 'delivered)
      (error "Promise has already been delivered.")
    (setf (slot-value promise 'value) value)
    (setf (slot-value promise 'delivered) t)
    (notify (slot-value promise 'latch) value)))

(defmethod retrieve ((promise promise))
  "Resolve the value for PROMISE, blocking if necessary. The
Emacs display will freeze, but I/O and timers will continue to
run."
  (if (slot-value promise 'delivered)
      (slot-value promise 'value)
    (wait (slot-value promise 'latch))))

(defun make-promise ()
  "Make a new, unresolved promise. `deliver' a value to it so
that it can be `retrieve'd."
  (make-instance 'promise))

;; Futures

(defmacro future (&rest body)
  "Run BODY in another execution context, returning a promise for
the result. This is completely useless in Emacs Lisp."
  (declare (indent defun))
  (let ((promise (gensym)))
    `(lexical-let ((,promise (make-promise)))
       (run-at-time 0 nil (lambda () (deliver ,promise (progn ,@body))))
       ,promise)))

(provide 'latch)

;;; latch.el ends here
