;;; sp-scratch.el --- better scratch settings -*- lexical-binding: t -*-

;;; Commentary:

;; Better scratch settings
;; See https://www.reddit.com/r/emacs/comments/4cmfwp/scratch_buffer_hacks_to_increase_its_utility/
;;
;; Features:
;; - Provide options for persistent scratch buffer
;; - Don't kill scratch, bury it instead
;; - These settings can be enabled/disabled via the relevant variables
;; 
;; TODO: Bring in the settings from the older configuration

;;; Code:

;;;; Variables

(defcustom sp-persistent-scratch t
  "If t, make scratch buffer persist across sessions.
Default is to persist."
  :group 'sia-lambda
  :type 'boolean)

(defcustom sp-scratch-save-dir sp-cache-dir
  "Default directory for saving scratch file."
  :group 'sia-lambda
  :type 'string)

(defcustom sp-scratch-default-dir (expand-file-name "~/")
  "Default directory for scratch buffer.
User may prefer to set this to `sp-scratch-save-dir'."
  :group 'sia-lambda
  :type 'string)

;;;; Text to show in the scratch buffer
;;; NOTE: this was removed, you should look directly in the EWS configuration to see how to do it well.

(setq initial-major-mode 'org-mode)
      ; initial-scratch-message (concat "#+title: Emacs Writing Studio\n"
; "#+subtitle: Scratch Buffer\n\n"
;					"The text in this buffer is not saved "
;					"when exiting Emacs!\n\n")

;;;; Functions
;; I don't currently know what to do with this or if it's helping the scratch in any way.
(customize-set-variable 'sp-scratch-default-dir sp-scratch-save-dir)

(defun lem--bury-scratch ()
  "Don't kill scratch buffer, bury it."
  (if (eq (current-buffer) (get-buffer "*scratch*"))
      (progn (bury-buffer)
             nil)
    t))

(add-hook 'kill-buffer-query-functions 'lem--bury-scratch)

;;;; Saving persistent scratch

(defun lem--save-persistent-scratch ()
  "Save the contents of *scratch*."
  (with-current-buffer (get-buffer-create "*scratch*")
    (write-region (point-min) (point-max)
                  (concat sp-scratch-save-dir "scratch"))))

(defun lem--load-persistent-scratch ()
  "Reload the scratch buffer."
  (let ((scratch-file (concat sp-scratch-save-dir "scratch")))
    (if (file-exists-p scratch-file)
        (with-current-buffer (get-buffer "*scratch*")
          (delete-region (point-min) (point-max))
          (insert-file-contents scratch-file))))
  ;; set default dir for scratch buffer
  (with-current-buffer (get-buffer "*scratch*")
    (setq-local default-directory sp-scratch-default-dir)))

;; Hooks for loading and saving the scratch buffer
(cond (sp-persistent-scratch
       (add-hook 'after-init-hook 'lem--load-persistent-scratch)
       (add-hook 'kill-emacs-hook 'lem--save-persistent-scratch)
       ;; Save scratch buffer every 5 minutes (300 seconds)
       (run-with-idle-timer 300 t 'lem--save-persistent-scratch)))

;;; End Setup-Scratch
(provide 'sp-scratch)
;;; sp-scratch.el ends here