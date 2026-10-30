;;; sp-browsing.el --- Web browsing inside Emacs -*- lexical-binding: t; -*-

;;; Commentary:

;; Good, focused browsing should happen as much as possible within
;; Emacs. This means that some of the workflows that have me context-
;; switching between Emacs and the browser is eliminated.

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
  (use-package consult-omni
    :ensure (:type git :host github :repo "armindarvish/consult-omni" :branch "main" :files (:defaults "sources/*.el"))
    :after consult

    :custom
    (consult-omni-show-preview t) ;;; show previews
    (consult-omni-preview-key "C-o") ;;; set the preview key to C-o
    (consult-omni-highlight-matches-in-minibuffer t) ;;; highlight matches in minibuffer
    (consult-omni-highlight-matches-in-file t) ;;; highlight matches in files
    (consult-omni-default-count 5) ;;; set default count
    (consult-omni-default-page 0) ;;; set the default page (default is 0 for the first page)

    (consult-omni-default-format-candidate 'consult-omni--higlight-format-candidate) ;; show annotations for the results

    ;; optionally change the consult-omni debounce, throttle and delay.
    ;; Adjust these (e.g. increase to avoid hiting a source (e.g. an API) too frequently)
    (consult-omni-dynamic-input-debounce 0.8)
    (consult-omni-dynamic-input-throttle 1.6)
    (consult-omni-dynamic-refresh-delay 0.8)
    ;; Optionally set backend for http request (either 'url, 'request, or 'plz)
    ;; (consult-omni-http-retrieve-backend 'plz)

    :config
    (require 'consult-omni-embark)  ;; Load Embark Actions
    (require 'consult-omni-sources) ;; Loading the set of sources
)

(setq consult-omni-multi-sources '("Apps"
                                   "buffers text search"
                                   "Dictionary"
                                   "doiorg"
                                   "elfeed"
                                   "Google"
                                   "Notes Search"
                                   "Org Agenda"
                                   "GitHub"
                                   "YouTube"
                                   "Wikipedia"))

(setq consult-omni-default-browse-function 'browse-url)
(setq consult-omni-alternate-browse-function 'eww-browse-url)
(setq consult-omni-default-preview-function #'xwidget-webkit-browse-url)

  (defvar consult-omni-web-sources (list "gptel"
                                         "Brave"
                                         "elfeed"
                                         "mu4e"
                                         "Wikipedia"
                                         "GitHub"
                                         "Invidious"
                                         ))

  (defun consult-omni-web (&optional initial prompt sources no-callback &rest args)
    "Interactive web search”

  This is similar to `consult-omni-multi', but runs the search on
  web sources defined in `consult-omni-web-sources'.
  See `consult-omni-multi' for more details."
    (interactive "P")
    (let ((prompt (or prompt (concat "[" (propertize "consult-omni-web" 'face 'consult-omni-prompt-face) "]" " Search:  ")))
          (sources (or sources consult-omni-web-sources)))
      (consult-omni-multi initial prompt sources no-callback args)))

  (defvar consult-omni-local-sources (list "ripgrep"
                                           "Org Agenda"))

  (defun consult-omni-local (&optional initial prompt sources no-callback &rest args)
    "Interactive local search”

  This is similar to `consult-omni-multi', but runs the search on
  local sources defined in `consult-omni-local-sources'.
  See `consult-omni-multi' for more details.
  "
    (interactive "P")
    (let ((prompt (or prompt (concat "[" (propertize "consult-omni-local" 'face 'consult-omni-prompt-face) "]" " Search:  ")))
          (sources (or sources consult-omni-local-sources)))
      (consult-omni-multi initial prompt sources no-callback args)))

  (setq consult-omni-scholar-sources (list "Scopus"
                                           "Notes Search"
                                           "gptel"))

  (defun consult-omni-scholar (&optional initial prompt sources no-callback &rest args)
    "Interactive “multi-source acadmic literature” search

  This is similar to `consult-omni-multi', but runs the search on
  academic literature sources defined in `consult-omni-scholar-sources'.
  See `consult-omni-multi' for more details.
  "
    (interactive "P")
    (let ((prompt (or prompt (concat "[" (propertize "consult-omni-multi" 'face 'consult-omni-prompt-face) "]" " Search:  ")))
          (sources (or sources consult-omni-scholar-sources)))
      (consult-omni-multi initial prompt sources no-callback args)))
