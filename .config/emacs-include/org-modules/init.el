(use-package elpher
  :ensure t)

(use-package consult-omni
  :ensure (consult-omni :type git :host github :repo "armindarvish/consult-omni" :branch "main" :files (:defaults "sources/*.el"))
  :after consult

  :custom
  ;; General settings that apply to all sources
  (consult-omni-show-preview t) ;;; show previews
  (consult-omni-preview-key "C-o") ;;; set the preview key to C-o
  (consult-omni-highlight-matches-in-minibuffer t) ;;; highlight matches in minibuffer
  (consult-omni-highlight-matches-in-file t) ;;; highlight matches in files
  (consult-omni-default-count 5) ;;; set default count
  (consult-omni-default-page 0) ;;; set the default page (default is 0 for the first page)

  ;; optionally change the consult-omni debounce, throttle and delay.
  ;; Adjust these (e.g. increase to avoid hiting a source (e.g. an API) too frequently)
  (consult-omni-dynamic-input-debounce 0.8)
  (consult-omni-dynamic-input-throttle 1.6)
  (consult-omni-dynamic-refresh-delay 0.8)
  ;; Optionally set backend for http request (either 'url, 'request, or 'plz)
  ;; (consult-omni-http-retrieve-backend 'plz)

  :config
  ;; Load Sources Core code
  (require 'consult-omni-sources)
  ;; Load Embark Actions
  (require 'consult-omni-embark)

  ;; Either load all source modules or a selected list

     ;;; Select a list of modules you want to aload, otherwise all sources all laoded
     					; (setq consult-omni-sources-modules-to-load (list 'consult-omni-wkipedia 'consult-omni-notes))
  (consult-omni-sources-load-modules))

;;; set multiple sources for consult-omni-multi command. Change these lists as needed for different interactive commands. Keep in mind that each source has to be a key in `consult-omni-sources-alist'.
(setq consult-omni-multi-sources '("calc"
                                   ;; "File"
                                   ;; "Buffer"
                                   ;; "Bookmark"
                                   "Apps"
                                   ;; "Brave"
                                   "Dictionary"
                                   "Google"
                                   "Wikipedia"
                                   "elfeed"
                                   ;; "mu4e"
                                   ;; "buffers text search"
                                   "Notes Search"
                                   "Org Agenda"
                                   "GitHub"
                                   ;; "Invidious"
                                   "YouTube"))

				   ;; Per source customization

     ;;; Set API KEYs. It is recommended to use a function that returns the string for better security.
				   (setq consult-omni-google-customsearch-key "AIzaSyATWnKE9vvojb4GxN8Qxyh49LIUtlQQ7yQ")
				   (setq consult-omni-google-customsearch-cx "174666cd8e7b94976")
				   ;; (setq consult-omni-brave-api-key "YOUR-BRAVE-API-KEY-OR-FUNCTION")
				   ;; (setq consult-omni-stackexchange-api-key "YOUR-STACKEXCHANGE-API-KEY-OR-FUNCTION")
				   ;; (setq consult-omni-pubmed-api-key "YOUR-PUBMED-API-KEY-OR-FUNCTION")

				   ;; default terminal
				   (setq consult-omni-embark-default-term #'vterm)

				   ;; default video player (I haven't actually set up mpv)
				   ;; (setq consult-omni-embark-video-default-player  #'mpv-play-url)

				   ;; pretty prompt for launcher
				   (setq consult-omni-open-with-prompt "  ")

   ;;; Set your shorthand favorite interactive command
				   (setq consult-omni-default-interactive-command #'consult-omni-multi)

   ;;; Pick you favorite autosuggest command.
				   (setq consult-omni-default-autosuggest-command #'consult-omni-dynamic-brave-autosuggest) ;;or any other autosuggest source you define

;;; Optionally Set back-end for notes search to ripgrep-all (requires ripgrep-all) so it's faster across the board
				   ;; (setq consult-omni-notes-backend-command "rga")

    ;;; Set your shorthand favorite interactive command
				   (setq consult-omni-default-interactive-command #'consult-omni-multi))

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
See `consult-omni-multi' for more details.
"
  (interactive "P")
  (let ((prompt (or prompt (concat "[" (propertize "consult-omni-web" 'face 'consult-omni-prompt-face) "]" " Search:  ")))
        (sources (or sources consult-omni-web-sources)))
    (consult-omni-multi initial prompt sources no-callback args)))

(defvar consult-omni-local-sources (list "ripgrep"
                                         "mdfind"
                                         "Notes Search"
                                         "Apps"
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

(setq consult-omni-scholar-sources (list "PubMed" "Scopus" "Notes Search" "gptel"))

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

;; AutoSuggest at point
(defun consult-omni-autosuggest-at-point ()
  (interactive)
  (let ((input (or (thing-at-point 'url) (thing-at-point 'filename) (thing-at-point 'symbol) (thing-at-point 'sexp) (thing-at-point 'word))))
    (when (and (minibuffer-window-active-p (selected-window))
               (equal (substring input 0 1) (consult--async-split-initial nil)))
      (setq input (substring input 1)))
    (consult-omni-brave-autosuggest input)))
