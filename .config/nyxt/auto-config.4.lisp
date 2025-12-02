(define-configuration (web-buffer)
  ((default-modes (pushnew 'nyxt/mode/style:dark-mode %slot-value%))))

(define-configuration (web-buffer)
  ((default-modes
    (remove-if (lambda (nyxt::m) (string= (symbol-name nyxt::m) "DARK-MODE"))
               %slot-value%))))
