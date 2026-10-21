;;; sp-relationship-annotator-live.el --- Serve the relationship graph on localhost, and keep it up to date -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "29.1"))

;;; Commentary:

;; Serves the page of `relationship-annotator-graph-static' from a small
;; HTTP server inside Emacs, bound to 127.0.0.1 only, instead of writing
;; an HTML file and opening it from disk.  The page is rendered from the
;; vulpea database on each load.  An open page keeps an event stream to
;; Emacs and reloads when, and only when, the data it shows has changed.
;;
;;   M-x relationship-annotator-graph         ask for a note, start, open
;;   M-x relationship-annotator-live-open     open the last note again
;;   M-x relationship-annotator-live-start    start the server
;;   M-x relationship-annotator-live-stop     stop the server
;;   M-x relationship-annotator-live-refresh  make open pages reload

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'url-util)
(require 'filenotify)
(require 'sp-relationship-annotator)

(defgroup relationship-annotator-live nil
  "A live view of the relationship graph on localhost."
  :group 'relationship-annotator)

(defcustom relationship-annotator-live-port 8765
  "Port of the live view, on 127.0.0.1."
  :type 'integer)

(defcustom relationship-annotator-live-debounce 0.5
  "Seconds Emacs must be idle after a database change before pages are checked."
  :type 'number)

(defconst relationship-annotator-live--address "127.0.0.1"
  "The only address the server listens on.")

(defvar relationship-annotator-live--server nil
  "The listening process, or nil.")

(defvar relationship-annotator-live--clients nil
  "Connections kept open as event streams.")

(defvar relationship-annotator-live--root nil
  "Id of the note the live view was last opened on.")

(defvar relationship-annotator-live--depth nil
  "Depth the live view was last opened with.")

(defvar relationship-annotator-live--watch nil
  "The `file-notify' descriptor on the folder of the database, or nil.")

(defvar relationship-annotator-live--timer nil
  "The idle timer that will check the open pages, or nil.")

(defvar relationship-annotator-live--seen nil
  "Signature of the database files at the last event or check.")

(defvar relationship-annotator-live--full-tree nil
  "The whole tree while a check is running, so it is built once.")

(defun relationship-annotator-live--tree (start depth)
  "Return the tree below START, cut like `relationship-annotator-graph-static' does."
  (relationship-annotator--scope
   (or relationship-annotator-live--full-tree (relationship-annotator--build))
   start (max depth relationship-annotator-embed-depth)))

(defun relationship-annotator-live--json (tree start depth)
  "Return the data of the page for TREE, START and DEPTH, as a JSON string."
  (cl-letf (((symbol-function 'relationship-annotator--html-template)
             (lambda () "__DATA__"))
            ((symbol-function 'relationship-annotator--libraries)
             (lambda () "")))
    (relationship-annotator--html tree start depth)))

(defun relationship-annotator-live--hash (json)
  "Return a short token for JSON."
  (substring (secure-hash 'sha1 json) 0 12))

(defun relationship-annotator-live--script (start depth hash)
  "Return the script that follows the data of START and DEPTH, rendered as HASH."
  (format "<script>
(() => {
  const startRoot = %s, startDepth = %d, hash = %s, base = document.title;
  const key = 'relationship-annotator-live';
  try {
    const saved = JSON.parse(sessionStorage.getItem(key) || 'null');
    sessionStorage.removeItem(key);
    if (saved && byId.has(saved.root)) {
      if (saved.root !== root || saved.depth !== depth) recentre(saved.root, saved.depth, false);
      saved.collapsed.forEach(id => collapsed.add(id));
      render(false);
      Object.assign(view, saved.view);
      apply();
    }
  } catch (e) {}
  const events = new EventSource('/events?root=' + encodeURIComponent(startRoot)
                                 + '&depth=' + startDepth + '&since=' + hash);
  events.onopen = () => { document.title = base; };
  events.onerror = () => { document.title = base + ' (offline)'; };
  events.addEventListener('changed', () => {
    try {
      sessionStorage.setItem(key, JSON.stringify(
        { root, depth, view, collapsed: [...collapsed] }));
    } catch (e) {}
    location.replace('/?root=' + encodeURIComponent(startRoot) + '&depth=' + startDepth);
  });
})();
</script>
"
          (json-encode-string start) depth (json-encode-string hash)))

(defun relationship-annotator-live--page (start depth)
  "Return the page for START and DEPTH, with the script that follows the database."
  (let* ((tree (relationship-annotator-live--tree start depth))
         (html (relationship-annotator--html tree start depth))
         (script (relationship-annotator-live--script
                  start depth
                  (relationship-annotator-live--hash
                   (relationship-annotator-live--json tree start depth))))
         (end (string-match-p "</body>\\s-*</html>\\s-*\\'" html)))
    (if end
        (concat (substring html 0 end) script (substring html end))
      (concat html script))))

(defun relationship-annotator-live--notify (process hash)
  "Tell the page on PROCESS that its data changed, and remember HASH for it."
  (process-put process :hash hash)
  (process-send-string process "event: changed\ndata: reload\n\n"))

(defun relationship-annotator-live--check-client (process &optional force)
  "Send `changed' on PROCESS when its page is out of date, or always with FORCE."
  (let ((hash (condition-case nil
                  (let ((root (process-get process :root))
                        (depth (process-get process :depth)))
                    (relationship-annotator-live--hash
                     (relationship-annotator-live--json
                      (relationship-annotator-live--tree root depth) root depth)))
                (error "error"))))
    (when (or force (not (equal hash (process-get process :hash))))
      (relationship-annotator-live--notify process hash))))

(defun relationship-annotator-live--check-all (&optional force)
  "Check every open page, building the tree once.  With FORCE, reload them all."
  (setq relationship-annotator-live--timer nil
        relationship-annotator-live--clients
        (seq-filter #'process-live-p relationship-annotator-live--clients))
  (when relationship-annotator-live--clients
    (let ((relationship-annotator-live--full-tree
           (ignore-errors (relationship-annotator--build))))
      (dolist (process relationship-annotator-live--clients)
        (relationship-annotator-live--check-client process force)))))

(defun relationship-annotator-live--files ()
  "Return the vulpea database file and its write-ahead log."
  (when-let* ((db (and (boundp 'vulpea-db-location) vulpea-db-location)))
    (list (expand-file-name db) (concat (expand-file-name db) "-wal"))))

(defun relationship-annotator-live--signature ()
  "Return the modification time and size of the database files."
  (mapcar (lambda (file)
            (when-let* ((attributes (file-attributes file)))
              (list (file-attribute-modification-time attributes)
                    (file-attribute-size attributes))))
          (relationship-annotator-live--files)))

(defun relationship-annotator-live--on-file-change (event)
  "React to a `file-notify' EVENT when it changed a database file."
  (let ((file (nth 2 event)))
    (when (and file
               (member (expand-file-name file) (relationship-annotator-live--files))
               (not (equal (relationship-annotator-live--signature)
                           relationship-annotator-live--seen)))
      (setq relationship-annotator-live--seen (relationship-annotator-live--signature))
      (when (timerp relationship-annotator-live--timer)
        (cancel-timer relationship-annotator-live--timer))
      (setq relationship-annotator-live--timer
            (run-with-idle-timer relationship-annotator-live-debounce nil
                                 #'relationship-annotator-live--check-all)))))

(defun relationship-annotator-live--watch-start ()
  "Watch the folder of the vulpea database for changes."
  (when-let* ((file (car (relationship-annotator-live--files)))
              ((file-directory-p (file-name-directory file)))
              ((not relationship-annotator-live--watch)))
    (setq relationship-annotator-live--seen (relationship-annotator-live--signature))
    (condition-case err
        (setq relationship-annotator-live--watch
              (file-notify-add-watch (file-name-directory file) '(change)
                                     #'relationship-annotator-live--on-file-change))
      (error (message "Live graph: cannot watch the database (%s); use relationship-annotator-live-refresh"
                      (error-message-string err))))))

(defun relationship-annotator-live--watch-stop ()
  "Stop watching the database."
  (when relationship-annotator-live--watch
    (ignore-errors (file-notify-rm-watch relationship-annotator-live--watch))
    (setq relationship-annotator-live--watch nil))
  (when (timerp relationship-annotator-live--timer)
    (cancel-timer relationship-annotator-live--timer))
  (setq relationship-annotator-live--timer nil))

(defun relationship-annotator-live--respond (process status type body)
  "Send BODY with STATUS and content TYPE on PROCESS, then close it."
  (let ((bytes (encode-coding-string body 'utf-8)))
    (process-send-string
     process
     (concat
      (encode-coding-string
       (format (concat "HTTP/1.1 %s\r\nContent-Type: %s; charset=utf-8\r\n"
                       "Content-Length: %d\r\nCache-Control: no-store\r\n"
                       "Connection: close\r\n\r\n")
               status type (length bytes))
       'utf-8)
      bytes))
    (delete-process process)))

(defun relationship-annotator-live--host-ok (host)
  "Non-nil when the Host header HOST names this machine and this port."
  (and host
       (string-match "\\`\\(localhost\\|127\\.0\\.0\\.1\\|\\[::1\\]\\)\\(?::\\([0-9]+\\)\\)?\\'" host)
       (let ((port (match-string 2 host)))
         (or (null port)
             (= (string-to-number port) relationship-annotator-live-port)))))

(defun relationship-annotator-live--params (query)
  "Return (ROOT . DEPTH) from the parsed QUERY, or from the last start note."
  (cons (or (cadr (assoc "root" query)) relationship-annotator-live--root)
        (max 1 (min 20 (or (and (cadr (assoc "depth" query))
                                (string-to-number (cadr (assoc "depth" query))))
                           relationship-annotator-live--depth
                           relationship-annotator-default-depth)))))

(defun relationship-annotator-live--subscribe (process query)
  "Keep PROCESS open as an event stream for the page described by QUERY."
  (pcase-let ((`(,root . ,depth) (relationship-annotator-live--params query)))
    (process-send-string
     process (concat "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n"
                     "Cache-Control: no-store\r\nConnection: keep-alive\r\n\r\n"
                     "retry: 3000\n\n"))
    (process-put process :root root)
    (process-put process :depth depth)
    (process-put process :hash (cadr (assoc "since" query)))
    (push process relationship-annotator-live--clients)
    (relationship-annotator-live--check-client process)))

(defun relationship-annotator-live--route (path query)
  "Return (STATUS TYPE BODY) for PATH and the parsed QUERY."
  (pcase-let ((`(,root . ,depth) (relationship-annotator-live--params query)))
    (cond
     ((equal path "/favicon.ico")
      (list "204 No Content" "text/plain" ""))
     ((not (member path '("/" "/graph.json")))
      (list "404 Not Found" "text/plain" "Not found"))
     ((null root)
      (list "200 OK" "text/plain"
            "Run M-x relationship-annotator-graph in Emacs to pick a note."))
     ((not (vulpea-db-query-by-ids (list root)))
      (list "404 Not Found" "text/plain" (format "No note with id %s" root)))
     ((equal path "/graph.json")
      (list "200 OK" "application/json"
            (relationship-annotator-live--json
             (relationship-annotator-live--tree root depth) root depth)))
     (t
      (list "200 OK" "text/html" (relationship-annotator-live--page root depth))))))

(defun relationship-annotator-live--handle (process request)
  "Answer REQUEST, the text of a request head, on PROCESS."
  (let* ((lines (split-string request "\r\n"))
         (first (split-string (car lines) " "))
         (method (nth 0 first))
         (target (or (nth 1 first) ""))
         (host (cl-some (lambda (line)
                          (when (string-match "\\`[Hh]ost:[ \t]*\\(.*?\\)[ \t]*\\'" line)
                            (match-string 1 line)))
                        (cdr lines)))
         (parts (split-string target "?"))
         (query (url-parse-query-string (or (cadr parts) ""))))
    (cond
     ((not (equal method "GET"))
      (relationship-annotator-live--respond
       process "405 Method Not Allowed" "text/plain" "GET only"))
     ((not (relationship-annotator-live--host-ok host))
      (relationship-annotator-live--respond
       process "403 Forbidden" "text/plain" "Forbidden"))
     ((equal (car parts) "/events")
      (relationship-annotator-live--subscribe process query))
     (t
      (condition-case err
          (apply #'relationship-annotator-live--respond process
                 (relationship-annotator-live--route (car parts) query))
        (error
         (relationship-annotator-live--respond
          process "500 Internal Server Error" "text/plain"
          (error-message-string err))))))))

(defun relationship-annotator-live--filter (process string)
  "Collect STRING from PROCESS until the request head is complete, then answer."
  (let ((data (concat (or (process-get process :data) "") string)))
    (process-put process :data data)
    (cond
     ((process-get process :root))
     ((string-search "\r\n\r\n" data)
      (process-put process :data nil)
      (relationship-annotator-live--handle process data))
     ((> (length data) 16384)
      (delete-process process)))))

(defun relationship-annotator-live--sentinel (process _event)
  "Forget PROCESS as an event stream once it is closed."
  (unless (process-live-p process)
    (setq relationship-annotator-live--clients
          (delq process relationship-annotator-live--clients))))

;;;###autoload
(defun relationship-annotator-live-start ()
  "Start the live view server on 127.0.0.1, at `relationship-annotator-live-port'."
  (interactive)
  (unless (process-live-p relationship-annotator-live--server)
    (setq relationship-annotator-live--server
          (condition-case err
              (make-network-process
               :name "relationship-annotator-live"
               :server t :noquery t :family 'ipv4 :coding 'binary
               :host relationship-annotator-live--address
               :service relationship-annotator-live-port
               :filter #'relationship-annotator-live--filter
               :sentinel #'relationship-annotator-live--sentinel)
            (file-error
             (user-error "Cannot listen on %s:%d: %s"
                         relationship-annotator-live--address
                         relationship-annotator-live-port
                         (error-message-string err))))))
  (relationship-annotator-live--watch-start)
  (message "Relationship graph at http://%s:%d/"
           relationship-annotator-live--address relationship-annotator-live-port))

;;;###autoload
(defun relationship-annotator-live-stop ()
  "Stop the live view server."
  (interactive)
  (relationship-annotator-live--watch-stop)
  (mapc #'delete-process relationship-annotator-live--clients)
  (setq relationship-annotator-live--clients nil)
  (when (process-live-p relationship-annotator-live--server)
    (delete-process relationship-annotator-live--server))
  (setq relationship-annotator-live--server nil)
  (message "Relationship graph server stopped"))

(defun relationship-annotator-live--url (start depth)
  "Return the address of the page for START and DEPTH."
  (format "http://%s:%d/?root=%s&depth=%d"
          relationship-annotator-live--address relationship-annotator-live-port
          (url-hexify-string start) depth))

;;;###autoload
(defun relationship-annotator-live ()
  "Ask for a starting note and depth, then show the hierarchy live in the browser.
The page is served by Emacs on localhost and reloads when its data changes."
  (interactive)
  (pcase-let ((`(,start . ,depth) (relationship-annotator--read-scope)))
    (setq relationship-annotator-live--root start
          relationship-annotator-live--depth depth)
    (relationship-annotator-live-open)))

;;;###autoload
(defalias 'relationship-annotator-graph #'relationship-annotator-live)

;;;###autoload
(defun relationship-annotator-live-open ()
  "Open the live view in the browser on the last starting note, or ask for one."
  (interactive)
  (unless relationship-annotator-live--root
    (pcase-let ((`(,start . ,depth) (relationship-annotator--read-scope)))
      (setq relationship-annotator-live--root start
            relationship-annotator-live--depth depth)))
  (relationship-annotator-live-start)
  (browse-url (relationship-annotator-live--url
               relationship-annotator-live--root
               (or relationship-annotator-live--depth
                   relationship-annotator-default-depth))))

;;;###autoload
(defun relationship-annotator-live-refresh ()
  "Make every open live page reload now."
  (interactive)
  (relationship-annotator-live--check-all t))

(provide 'sp-relationship-annotator-live)
;;; sp-relationship-annotator-live.el ends here
