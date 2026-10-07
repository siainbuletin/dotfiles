;;; -*- lexical-binding: t -*-

;;; Code:

;;;; Capture mechanisms

;; Org-capture note creation with Denote
(with-eval-after-load 'org-capture
  (add-to-list 'org-capture-templates
               '("n" "New note (with Denote)" plain
                 (file denote-last-path)
                 #'denote-org-capture
                 :no-save t
                 :immediate-finish nil
                 :kill-buffer t
                 :jump-to-captured t)))

;; Example note creation function
(defun lem-insert-header-and-time-property ()
  "Insert an org heading with a created time string property."
  (interactive)
  (insert "* ")
  (org-set-property "CREATED" (format-time-string "[%Y-%m-%d %T]")))

;;;; Bindings
(keymap-global-set "C-c c" #'org-capture)

(keymap-global-set "C-x t l"
                (lambda () "Open inbox capture window"
                    (interactive)
                    (org-capture nil "l")))

(keymap-global-set "C-x t a"
                (lambda () "Open inbox capture window"
                    (interactive)
                    (org-capture nil "t")))

(keymap-global-set "C-x t i"
                (lambda () "Open inbox capture window"
                    (interactive)
                    (org-capture nil "i")))

(setq org-capture-templates
        '(
          ("l" "Listening log" entry
           (file+datetree "~/notes/inbox/listening-log.org")
           "* %U\n %i\n %a")

          ("t" "Task to the inbox" entry
           (file "~/notes/inbox/inbox-capture.org")
           "* TODO %?\n %i\n %a")

          ("i" "Idea or quick thought to take care of" entry
           (file "~/notes/inbox/thoughts-capture.org"))
))

(provide 'sp-org-capture)