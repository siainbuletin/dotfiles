;;; sp-embr.el --- Show the annotator live view in an Emacs buffer -*- lexical-binding: t; -*-

;;; Commentary:

;; Generated from sp-embr.org -- edit that file, not this one.
;;
;; Shows the live view of `sp-graphs' (its live view) in an Emacs buffer:
;;
;;   M-x rel-anno-live-embr      with embr.el (headless Chromium, Emacs 30+)
;;   M-x rel-anno-live-xwidget   with `xwidget-webkit' (needs xwidgets)
;;   M-x rel-anno-live-compare   both, side by side
;;
;; `rel-anno-live' still opens the page in the normal browser.  When a
;; viewer cannot be used the URL goes to `browse-url'.  `sp-embr-open' and
;; `sp-embr-open-xwidget' take any URL.

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

(defcustom sp-embr-fallback-function #'browse-url
  "Function called with the URL when embr or xwidget-webkit cannot be used."
  :type 'function
  :group 'sp-embr)

(declare-function embr-browse "embr")

(defun sp-embr--usable-p ()
  "Return non-nil when embr can be used in this Emacs."
  (and (>= emacs-major-version 30)
       (or (featurep 'embr) (locate-library "embr"))))

;;;###autoload
(defun sp-embr-open (url)
  "Show URL in an Emacs buffer with embr, or in the fallback if that fails."
  (interactive (list (read-string "URL: ")))
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

(declare-function xwidget-webkit-browse-url "xwidget")

(defun sp-embr--xwidget-usable-p ()
  "Return non-nil when this Emacs can show an xwidget-webkit view."
  (and (display-graphic-p) (featurep 'xwidget-internal)))

;;;###autoload
(defun sp-embr-open-xwidget (url)
  "Show URL in an Emacs buffer with `xwidget-webkit', or in the fallback."
  (interactive (list (read-string "URL: ")))
  (if (sp-embr--xwidget-usable-p)
      (xwidget-webkit-browse-url url t)
    (message "sp-embr: no xwidgets in this Emacs, using `%s'"
             sp-embr-fallback-function)
    (funcall sp-embr-fallback-function url)))

(defvar relationship-annotator-live--root)
(defvar relationship-annotator-live--depth)
(defvar relationship-annotator-default-depth)
(declare-function relationship-annotator--read-scope "sp-graphs")
(declare-function relationship-annotator-live--url "sp-graphs")
(declare-function rel-anno-live-start "sp-graphs")

(defun sp-embr--live-url ()
  "Start the live view server and return its address.
Asks for a starting note and depth when there is none yet."
  (require 'sp-graphs)
  (unless relationship-annotator-live--root
    (pcase-let ((`(,start . ,depth) (relationship-annotator--read-scope)))
      (setq relationship-annotator-live--root start
            relationship-annotator-live--depth depth)))
  (rel-anno-live-start)
  (relationship-annotator-live--url
   relationship-annotator-live--root
   (or relationship-annotator-live--depth relationship-annotator-default-depth)))

;;;###autoload
(defun rel-anno-live-embr ()
  "Show the live relationship graph in an Emacs buffer with embr."
  (interactive)
  (sp-embr-open (sp-embr--live-url)))

;;;###autoload
(defun rel-anno-live-xwidget ()
  "Show the live relationship graph in an Emacs buffer with `xwidget-webkit'."
  (interactive)
  (sp-embr-open-xwidget (sp-embr--live-url)))

;;;###autoload
(defun rel-anno-live-compare ()
  "Show the live graph with embr on the left and `xwidget-webkit' on the right."
  (interactive)
  (let ((url (sp-embr--live-url)))
    (delete-other-windows)
    (let ((right (split-window-right)))
      (sp-embr-open url)
      (select-window right)
      (sp-embr-open-xwidget url))))

(provide 'sp-embr)
;;; sp-embr.el ends here
