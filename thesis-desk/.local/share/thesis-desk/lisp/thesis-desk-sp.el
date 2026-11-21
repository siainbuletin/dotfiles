;;; thesis-desk-sp.el --- Plug thesis-desk into the emacs-modular configuration -*- lexical-binding: t; -*-

;;; Commentary:

;; The only file of thesis-desk that knows the `sp-*' modules.  Every call into
;; them is here, so a rename in the configuration breaks one place.
;;
;;   - claims: Vulpea notes with a DG_TYPE of claim or question count too;
;;   - DEVONthink: the front record, rating and links go through
;;     `sp-devonthink' (its `devonthink:' links, its page offset);
;;   - hotspots: the mentions come from the `sp-see-also' index;
;;   - keys: `thesis-desk-command-map' under the leader, `C-; r' (research).
;;
;; Each part is set up only when its module is loaded.

;;; Code:

(require 'thesis-desk)

(declare-function vulpea-db-query "vulpea-db")
(declare-function vulpea-note-properties "vulpea-note")
(declare-function vulpea-note-id "vulpea-note")
(declare-function vulpea-note-title "vulpea-note")
(declare-function vulpea-note-path "vulpea-note")
(declare-function sp-devonthink--parse-front "sp-devonthink")
(declare-function sp-devonthink-link-path "sp-devonthink")
(declare-function sp-reading--osascript "sp-reading")
(declare-function sp-see-also-index "sp-see-also")
(declare-function sp-see-also--concept-title "sp-see-also")
(defvar sp-devonthink--front-script)
(defvar lem+leader-map)

(defcustom thesis-desk-sp-leader-key "r"
  "Key under the leader (`C-;') for `thesis-desk-command-map'."
  :type 'string :group 'thesis-desk)

;;;; Settings of this configuration

(defvar sp-notes-dir)
(defvar sp-see-also-directory)

(unless thesis-desk-project-id
  ;; The bachelor's thesis project note: "Devalorizarea artei în capitalismul
  ;; de platformă".  Litnotes whose bib-project links it are the thesis material.
  (setq thesis-desk-project-id "806b08ac-3ed1-4338-a26e-3af9e0e9328c"))

(with-eval-after-load 'sp-see-also
  (setq thesis-desk-litnote-directory sp-see-also-directory))

(when (boundp 'sp-notes-dir)
  (setq thesis-desk-synthesis-directory (expand-file-name "synthesis/" sp-notes-dir)))

;;;; Claims from Vulpea

(defun thesis-desk-sp-vulpea-claims ()
  "Vulpea notes whose DG_TYPE is one of `thesis-desk-claim-types', as claims."
  (when (fboundp 'vulpea-db-query)
    (mapcar (lambda (note)
              (list :id (vulpea-note-id note)
                    :title (vulpea-note-title note)
                    :type (downcase (cdr (assoc "DG_TYPE" (vulpea-note-properties note))))
                    :file (vulpea-note-path note)))
            (vulpea-db-query
             (lambda (note)
               (when-let* ((type (cdr (assoc "DG_TYPE" (vulpea-note-properties note)))))
                 (member (downcase type) thesis-desk-claim-types)))))))

(with-eval-after-load 'vulpea
  (add-to-list 'thesis-desk-claim-sources #'thesis-desk-sp-vulpea-claims t))

;;;; DEVONthink through sp-devonthink

(defun thesis-desk-sp-front-record ()
  "The record DEVONthink shows, read with `sp-devonthink''s script.
Its page already has `sp-devonthink-store-page-offset' applied."
  (when-let* ((found (sp-devonthink--parse-front
                      (sp-reading--osascript sp-devonthink--front-script))))
    (list :uuid (plist-get found :uuid)
          :key (plist-get found :key)
          :name (concat (plist-get found :key) ".pdf")
          :page (plist-get found :page))))

(defun thesis-desk-sp-link (uuid page description)
  "A `devonthink:' link to UUID at PAGE with DESCRIPTION."
  (org-link-make-string (concat "devonthink:" (sp-devonthink-link-path uuid page)) description))

(with-eval-after-load 'sp-devonthink
  (setq thesis-desk-front-record-function #'thesis-desk-sp-front-record
        thesis-desk-record-link-function #'thesis-desk-sp-link))

;;;; Mentions from sp-see-also

(defun thesis-desk-sp-mentions ()
  "The concept to mentions table of the `sp-see-also' index."
  (plist-get (sp-see-also-index) :concepts))

(with-eval-after-load 'sp-see-also
  (setq thesis-desk-mentions-function #'thesis-desk-sp-mentions
        thesis-desk-concept-title-function #'sp-see-also--concept-title))

;;;; Watching DEVONthink opens

(defcustom thesis-desk-sp-watch t
  "Non-nil turns on `thesis-desk-watch-mode' on macOS when this file loads."
  :type 'boolean :group 'thesis-desk)

(when (and thesis-desk-sp-watch (eq system-type 'darwin))
  (thesis-desk-watch-mode 1))

;;;; Keys

(with-eval-after-load 'sp-keys
  (keymap-set lem+leader-map thesis-desk-sp-leader-key thesis-desk-command-map))
(when (boundp 'lem+leader-map)
  (keymap-set lem+leader-map thesis-desk-sp-leader-key thesis-desk-command-map))

(provide 'thesis-desk-sp)
;;; thesis-desk-sp.el ends here
