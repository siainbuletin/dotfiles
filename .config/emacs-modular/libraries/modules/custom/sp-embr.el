;;; sp-embr.el --- Show the annotator live view in an Emacs buffer -*- lexical-binding: t; -*-

;;; Commentary:

;; Generated from sp-embr.org -- edit that file, not this one.
;;
;; `sp-embr-open-annotator' shows the live graph view of
;; `sp-relationship-annotator' (a page on 127.0.0.1) in an Emacs buffer with
;; embr.el, which drives a headless Chromium.  `sp-embr-open' does the same
;; for any URL.  When embr cannot be used (Emacs older than 30.1, package not
;; installed, or it fails to start) the URL goes to `browse-url'.
;; `sp-embr-open-annotator-xwidget' does the same with `xwidget-webkit', and
;; `sp-embr-compare-annotator' shows both side by side.

;;; Code:

(require 'subr-x)

(when (>= emacs-major-version 30)
  (use-package embr
    :defer t
    :ensure (embr :host github
                  :repo "emacs-os/embr.el"
                  :files ("*.el" "*.py" "*.sh" "native/*.c" "native/Makefile"))
    :custom
    (embr-browser-engine 'chromium)))

(defgroup sp-embr nil
  "Show pages served on localhost in an Emacs buffer."
  :group 'tools
  :prefix "sp-embr-")

(defcustom sp-embr-annotator-host "127.0.0.1"
  "Host serving the relationship-annotator live view."
  :type 'string
  :group 'sp-embr)

(defcustom sp-embr-annotator-port nil
  "Port serving the relationship-annotator live view.
Nil means `relationship-annotator-live-port' when that is bound,
otherwise 8765."
  :type '(choice (const :tag "Follow the live view" nil) natnum)
  :group 'sp-embr)

(defcustom sp-embr-annotator-path "/"
  "Path of the live view on the server, starting with a slash."
  :type 'string
  :group 'sp-embr)

(defcustom sp-embr-fallback-function #'browse-url
  "Function called with the URL when embr cannot be used."
  :type 'function
  :group 'sp-embr)

(declare-function embr-browse "embr")

(defun sp-embr--annotator-port ()
  "Return the port of the live view."
  (or sp-embr-annotator-port
      (bound-and-true-p relationship-annotator-live-port)
      8765))

(defun sp-embr-annotator-url ()
  "Return the URL of the relationship-annotator live view."
  (format "http://%s:%d%s"
          sp-embr-annotator-host (sp-embr--annotator-port) sp-embr-annotator-path))

(defun sp-embr--usable-p ()
  "Return non-nil when embr can be used in this Emacs."
  (and (>= emacs-major-version 30)
       (or (featurep 'embr) (locate-library "embr"))))

(defun sp-embr--listening-p (host port)
  "Return non-nil when something accepts connections on HOST:PORT."
  (condition-case nil
      (progn (delete-process (open-network-stream "sp-embr-probe" nil host port))
             t)
    (error nil)))

(defun sp-embr--check-listening ()
  "Signal a `user-error' unless the live view is being served."
  (unless (sp-embr--listening-p sp-embr-annotator-host (sp-embr--annotator-port))
    (user-error "Nothing is listening on %s:%d; start the live view first (M-x relationship-annotator-live)"
                sp-embr-annotator-host (sp-embr--annotator-port))))

;;;###autoload
(defun sp-embr-open (url)
  "Show URL in an Emacs buffer with embr, or in `browse-url' if that fails."
  (interactive (list (read-string "URL: " (sp-embr-annotator-url))))
  (if (not (sp-embr--usable-p))
      (progn
        (message "sp-embr: embr is not usable here, using `%s'"
                 sp-embr-fallback-function)
        (funcall sp-embr-fallback-function url))
    (require 'embr)
    (condition-case err
        (embr-browse url)
      (error
       (message "sp-embr: embr failed (%s), using `%s'"
                (error-message-string err) sp-embr-fallback-function)
       (funcall sp-embr-fallback-function url)))))

;;;###autoload
(defun sp-embr-open-annotator ()
  "Show the relationship-annotator live view in an Emacs buffer with embr."
  (interactive)
  (sp-embr--check-listening)
  (sp-embr-open (sp-embr-annotator-url)))

(declare-function xwidget-webkit-browse-url "xwidget")

(defun sp-embr--xwidget-usable-p ()
  "Return non-nil when this Emacs can show an xwidget-webkit view."
  (and (display-graphic-p) (featurep 'xwidget-internal)))

;;;###autoload
(defun sp-embr-open-xwidget (url)
  "Show URL in an Emacs buffer with `xwidget-webkit', or in the fallback."
  (interactive (list (read-string "URL: " (sp-embr-annotator-url))))
  (if (sp-embr--xwidget-usable-p)
      (xwidget-webkit-browse-url url t)
    (message "sp-embr: no xwidgets in this Emacs, using `%s'"
             sp-embr-fallback-function)
    (funcall sp-embr-fallback-function url)))

;;;###autoload
(defun sp-embr-open-annotator-xwidget ()
  "Show the relationship-annotator live view with `xwidget-webkit'."
  (interactive)
  (sp-embr--check-listening)
  (sp-embr-open-xwidget (sp-embr-annotator-url)))

;;;###autoload
(defun sp-embr-compare-annotator ()
  "Show the live view with embr on the left and `xwidget-webkit' on the right."
  (interactive)
  (sp-embr--check-listening)
  (delete-other-windows)
  (let ((right (split-window-right)))
    (sp-embr-open (sp-embr-annotator-url))
    (select-window right)
    (sp-embr-open-xwidget (sp-embr-annotator-url))))

(provide 'sp-embr)
;;; sp-embr.el ends here
