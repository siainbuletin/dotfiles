;;; thesis-desk-dt.el --- DEVONthink through osascript for thesis-desk -*- lexical-binding: t; -*-

;;; Commentary:

;; The few things thesis-desk asks DEVONthink: which record is showing (with
;; its page), a link to a record at a page, and setting a rating.  Everything
;; goes through `osascript'; the database package is never read as files.
;;
;; Each step is a variable holding a function, so `thesis-desk-sp' can hand
;; them to the existing `sp-devonthink' code and the tests can fake them.
;;
;; Untested on the Mac: the AppleScript below was written from the
;; DEVONthink dictionary (`current page', `rating').  See README.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'ol)

(defcustom thesis-desk-front-record-function #'thesis-desk-dt-front-record
  "Function of no arguments returning the record DEVONthink shows, or nil.
The result is a plist with :uuid, :name, :key (the name without .pdf, the
citekey in your setup) and :page (counted from 1, or nil)."
  :type 'function :group 'thesis-desk)

(defcustom thesis-desk-set-rating-function #'thesis-desk-dt-set-rating
  "Function of (UUID RATING) that sets the rating of a DEVONthink record."
  :type 'function :group 'thesis-desk)

(defcustom thesis-desk-record-link-function #'thesis-desk-dt-link
  "Function of (UUID PAGE DESCRIPTION) returning an Org link to a record at PAGE."
  :type 'function :group 'thesis-desk)

(defcustom thesis-desk-page-offset 0
  "Added to the page DEVONthink reports to get the page counted from 1.
DEVONthink's `current page' may count from 0; probe it and set 1 if so."
  :type 'integer :group 'thesis-desk)

(defun thesis-desk-dt--quote (string)
  "STRING as an AppleScript string literal."
  (concat "\""
          (replace-regexp-in-string
           "\"" "\\\\\"" (replace-regexp-in-string "\\\\" "\\\\\\\\" string))
          "\""))

(defun thesis-desk-dt--osascript (script)
  "Run the AppleScript SCRIPT; return its output without the final newline."
  (unless (executable-find "osascript")
    (user-error "No osascript here: DEVONthink is only reachable on macOS"))
  (with-temp-buffer
    (let ((status (call-process "osascript" nil t nil "-e" script)))
      (unless (eql status 0)
        (error "osascript failed: %s" (string-trim (buffer-string))))
      (string-trim-right (buffer-string) "\n"))))

(defconst thesis-desk-dt--front-script
  "set tb to character id 9
tell application id \"DNtp\"
  repeat with theWindow in (every think window)
    try
      set theRecord to content record of theWindow
      set thePage to \"\"
      try
        set thePage to (current page of theWindow) as text
      end try
      return (uuid of theRecord) & tb & (name of theRecord) & tb & thePage
    end try
  end repeat
  return \"\"
end tell"
  "AppleScript printing UUID, name and page of the frontmost window with a record.")

(defun thesis-desk-dt-parse-front (output)
  "Parse OUTPUT of the front-record script (UUID, name, page by tabs) into a plist."
  (let ((parts (split-string (string-trim-right (or output "") "\n") "\t")))
    (when (and (>= (length parts) 2)
               (string-match-p "\\`[0-9A-Fa-f-]\\{20,\\}\\'" (car parts)))
      (let ((page (nth 2 parts))
            (name (nth 1 parts)))
        (list :uuid (car parts)
              :name name
              :key (replace-regexp-in-string "\\.pdf\\'" "" name t t)
              :page (when (and page (string-match-p "\\`[0-9]+\\'" page))
                      (let ((n (+ (string-to-number page) thesis-desk-page-offset)))
                        (and (>= n 1) n))))))))

(defun thesis-desk-dt-front-record ()
  "The record DEVONthink shows now, as `thesis-desk-front-record-function' says."
  (thesis-desk-dt-parse-front (thesis-desk-dt--osascript thesis-desk-dt--front-script)))

(defun thesis-desk-dt-set-rating (uuid rating)
  "Set the rating of the record UUID to RATING (0 to 5)."
  (thesis-desk-dt--osascript
   (format "tell application id \"DNtp\"
  set theRecord to get record with uuid %s
  if theRecord is missing value then error \"No record \" & %s
  set rating of theRecord to %d
end tell" (thesis-desk-dt--quote uuid) (thesis-desk-dt--quote uuid) rating)))

(defun thesis-desk-dt-url (uuid &optional page)
  "The x-devonthink-item URL of UUID, at PAGE (counted from 1) when given."
  (concat "x-devonthink-item://" uuid
          (when (and page (> page 0)) (format "?page=%d" (1- page)))))

(defun thesis-desk-dt-link (uuid page description)
  "An Org link to UUID at PAGE with DESCRIPTION."
  (org-link-make-string (thesis-desk-dt-url uuid page) description))

(defun thesis-desk-front-record ()
  "The record DEVONthink shows, or nil when it cannot be read."
  (condition-case err
      (funcall thesis-desk-front-record-function)
    (error (message "[thesis-desk] could not read DEVONthink: %s"
                    (error-message-string err))
           nil)))

(provide 'thesis-desk-dt)
;;; thesis-desk-dt.el ends here
