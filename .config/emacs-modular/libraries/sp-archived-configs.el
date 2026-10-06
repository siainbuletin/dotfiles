;; Autochange theme with dark mode
;; Archived: 2026-10-04

;; this file was initially generated with ChatGPT and it did the job, but the
;; current version now found in sp-macos.el also ensures that the correct theme
;; is triggered on the startup of Emacs, before actually showing the frame, so I don't
;; have to manually fire the system appearance switch immediately after init.
;;
;; The newer version makes everything automatic.

(defun my-load-theme (appearance)
  (mapc #'disable-theme custom-enabled-themes)
  (pcase appearance
    ('light (load-theme 'ef-melissa-light t))
    ('dark  (load-theme 'ef-dream t))))

(add-hook 'ns-system-appearance-change-functions #'my-load-theme)