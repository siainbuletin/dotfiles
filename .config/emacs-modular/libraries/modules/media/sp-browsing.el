;;; sp-browsing.el --- Web browsing inside Emacs -*- lexical-binding: t; -*-

;;; Commentary:

;; Creating the environment for browsing within Emacs.

;;; Code:

;;;; Defining variables

;;;; EWW (built-in)

;;;;; Helper functions for eww

;; Open link in eww or browser
(defun open-link-at-point-or-minibuffer-with-choice ()
  "Use `consult` to select a link at point, in the buffer, from `consult-omni` results, or prompt for a URL.
  Then choose to open it in macOS default browser or eww.
  If 'eww' is chosen, the link is opened in a window that occupies 80% of the frame height below the current one."
  (interactive)
  (let* ((url (or (thing-at-point 'url)                             ;; Check if there's a URL at point
                (consult--read (thing-at-point--list 'url))       ;; Use consult to select a URL from the buffer
                (consult-omni)                                    ;; Use consult-omni results to select a link
                (read-string "Enter URL: "))))                    ;; Fall back to manual URL entry
    (if url
      (let ((choice (completing-read "Open link in: " '("macOS Browser" "eww"))))
        (cond
         ((string-equal choice "macOS Browser")
          (shell-command (concat "open " (shell-quote-argument url))))
         ((string-equal choice "eww")
          ;; Calculate the height for the top window (20% of the frame height)
          (let ((window (selected-window))
                (top-window-height (floor (* 0.2 (window-total-height)))))
            ;; Split window with 20% height on top and 80% height for eww on the bottom
            (select-window (split-window window top-window-height))
            (eww url)))))
      (message "No URL provided."))))

;;;; Elpher

;;;; consult-omni
