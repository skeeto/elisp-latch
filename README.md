# Promises and Latches for Emacs Lisp

This package (ab)uses `accept-process-output` and processes to provide
asynchronous blocking, allowing other functions to run before the
current execution context completes. All blocking will freeze the
Emacs display, but timers and I/O will continue to run. Use with
caution.

## Usage

Promises have `deliver` and `retrieve` methods.

```el
;; Make promise
(defvar p (make-promise))

;; Deliver a value to the promise in 5 seconds.
(run-at-time 5 nil #'deliver p "Hello, world")

;; Retrieve the value from the promise. This blocks until a value is
;; delivered. The timer can still deliver a value when this is
;; blocked, but Emacs' display will freeze.
(retrieve p)
```

Latches have `wait` and `notify`, which can optionally pass a value.

This example turns an asynchronous function into a synchronous
one. The function `skewer-eval` takes a string containing JavaScript
and a callback, `eval`s the string in a browser, and gives the
evaluation result to the callback. Say we'd rather return the value
directly,

```el
(defun skewer-eval-synchronously (js-code)
  (lexical-let ((latch (make-one-time-latch)))
    (skewer-eval js-code (apply-partially #'notify latch))
    (wait latch)))
```

## Garbage Collection

Latches use processes underneath and are not properly garbage
collected. Use the `destroy` method to destroy them when done using
them, or use a one-time-latch which will destroy itself
automatically. Use `destroy-all-latches` when you're
debugging/experimenting and made a mess of things.
