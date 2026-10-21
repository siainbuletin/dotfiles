;;; sp-relationship-annotator-live.el --- Serve the relationship graph on localhost, and keep it up to date -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "29.1"))

;;; Commentary:

;; Serves the page of `relationship-annotator-graph' from a small HTTP
;; server inside Emacs, bound to 127.0.0.1 only, instead of writing an
;; HTML file and opening it from disk.  The page is rendered from the
;; vulpea database on each load, and an open page reloads itself when the
;; database changes.
;;
;;   M-x relationship-annotator-live          ask for a note, start, open
;;   M-x relationship-annotator-live-open     open the last note again
;;   M-x relationship-annotator-live-start    start the server
;;   M-x relationship-annotator-live-stop     stop the server
;;   M-x relationship-annotator-live-refresh  make open pages reload
;;
;; The static export (`relationship-annotator-graph') is not changed.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'url-util)
(require 'sp-relationship-annotator)

(defgroup relationship-annotator-live nil
  "A live view of the relationship graph on localhost."
  :group 'relationship-annotator)

(defcustom relationship-annotator-live-port 8765
  "Port of the live view, on 127.0.0.1."
  :type 'integer)

(defcustom relationship-annotator-live-poll-interval 2
  "Seconds between two checks of an open page for a changed database."
  :type 'number)

(defconst relationship-annotator-live--address "127.0.0.1"
  "The only address the server listens on.")

(defvar relationship-annotator-live--server nil
  "The listening process, or nil.")

(defvar relationship-annotator-live--root nil
  "Id of the note the live view was last opened on.")

(defvar relationship-annotator-live--depth nil
  "Depth the live view was last opened with.")

(defvar relationship-annotator-live--bumps 0
  "Number of times `relationship-annotator-live-refresh' was called.")

(defun relationship-annotator-live--files ()
  "Return the vulpea database file and its write-ahead log."
  (when-let* ((db (and (boundp 'vulpea-db-location) vulpea-db-location)))
    (list db (concat db "-wal"))))

(defun relationship-annotator-live--version ()
  "Return a token that changes when the vulpea database does."
  (format "%x"
          (sxhash-equal
           (cons relationship-annotator-live--bumps
                 (mapcar (lambda (file)
                           (when-let* ((attributes (file-attributes file)))
                             (list (file-attribute-modification-time attributes)
                                   (file-attribute-size attributes))))
                         (relationship-annotator-live--files))))))

(defun relationship-annotator-live--tree (start depth)
  "Return the tree below START, cut like `relationship-annotator-graph' does."
  (relationship-annotator--scope
   (relationship-annotator--build) start
   (max depth relationship-annotator-embed-depth)))

(defun relationship-annotator-live--script (version)
  "Return the script that reloads a page when the token differs from VERSION."
  (format "<script>
(() => {
  const version = %s, base = document.title;
  setInterval(async () => {
    try {
      const response = await fetch('/version', { cache: 'no-store' });
      const now = (await response.text()).trim();
      document.title = base;
      if (now !== version)
        location.replace('/?root=' + encodeURIComponent(root) + '&depth=' + depth);
    } catch (e) { document.title = base + ' (offline)'; }
  }, %d);
})();
</script>
"
          (json-encode-string version)
          (round (* 1000 relationship-annotator-live-poll-interval))))

(defun relationship-annotator-live--page (start depth)
  "Return the page for START and DEPTH, with the script that follows the database."
  (let* ((html (relationship-annotator--html
                (relationship-annotator-live--tree start depth) start depth))
         (script (relationship-annotator-live--script
                  (relationship-annotator-live--version)))
         (end (string-match-p "</body>\\s-*</html>\\s-*\\'" html)))
    (if end
        (concat (substring html 0 end) script (substring html end))
      (concat html script))))

(defun relationship-annotator-live--json (start depth)
  "Return the data of the page for START and DEPTH, as a JSON string."
  (cl-letf (((symbol-function 'relationship-annotator--html-template)
             (lambda () "__DATA__"))
            ((symbol-function 'relationship-annotator--libraries)
             (lambda () "")))
    (relationship-annotator--html
     (relationship-annotator-live--tree start depth) start depth)))

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

(defun relationship-annotator-live--route (path query)
  "Return (STATUS TYPE BODY) for PATH and the parsed QUERY."
  (let* ((root (or (cadr (assoc "root" query)) relationship-annotator-live--root))
         (depth (max 1 (min 20 (or (and (cadr (assoc "depth" query))
                                         (string-to-number (cadr (assoc "depth" query))))
                                    relationship-annotator-live--depth
                                    relationship-annotator-default-depth)))))
    (cond
     ((equal path "/version")
      (list "200 OK" "text/plain" (relationship-annotator-live--version)))
     ((equal path "/favicon.ico")
      (list "204 No Content" "text/plain" ""))
     ((not (member path '("/" "/graph.json")))
      (list "404 Not Found" "text/plain" "Not found"))
     ((null root)
      (list "200 OK" "text/plain"
            "Run M-x relationship-annotator-live in Emacs to pick a note."))
     ((not (vulpea-db-query-by-ids (list root)))
      (list "404 Not Found" "text/plain" (format "No note with id %s" root)))
     ((equal path "/graph.json")
      (list "200 OK" "application/json"
            (relationship-annotator-live--json root depth)))
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
     ((string-search "\r\n\r\n" data)
      (process-put process :data nil)
      (relationship-annotator-live--handle process data))
     ((> (length data) 16384)
      (delete-process process)))))

(defun relationship-annotator-live--sentinel (_process _event)
  "Ignore connection events: each connection is closed once it is answered.")

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
  (message "Relationship graph at http://%s:%d/"
           relationship-annotator-live--address relationship-annotator-live-port))

;;;###autoload
(defun relationship-annotator-live-stop ()
  "Stop the live view server."
  (interactive)
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
The page is served by Emacs on localhost and reloads when the notes change."
  (interactive)
  (pcase-let ((`(,start . ,depth) (relationship-annotator--read-scope)))
    (setq relationship-annotator-live--root start
          relationship-annotator-live--depth depth)
    (relationship-annotator-live-open)))

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
  "Make the open live pages reload on their next poll."
  (interactive)
  (cl-incf relationship-annotator-live--bumps)
  (message "Live pages will reload within %s seconds"
           relationship-annotator-live-poll-interval))

(provide 'sp-relationship-annotator-live)
;;; sp-relationship-annotator-live.el ends here
