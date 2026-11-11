;;; sp-vulpea-grouped-backlinks-test.el --- Tests for sp-vulpea-grouped-backlinks  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'org)

;; The real Vulpea and the table module are not needed: only the functions
;; the module calls are stubbed, with notes as plists.
(when noninteractive
  (provide 'vulpea)
  (provide 'sp-collection-query-core)
  (defvar sp-vulpea-grouped-backlinks-test--links nil
    "Alist of (TARGET-ID . LINK-PLISTS) the stubbed database answers with.")
  (defvar sp-vulpea-grouped-backlinks-test--notes nil
    "Alist of (ID . NOTE-PLIST) the stubbed database answers with.")
  (defun vulpea-db-query-links-to (id)
    (cdr (assoc id sp-vulpea-grouped-backlinks-test--links)))
  (defun vulpea-db-get-by-id (id)
    (cdr (assoc id sp-vulpea-grouped-backlinks-test--notes)))
  (defun vulpea-note-id (note) (plist-get note :id))
  (defun vulpea-note-title (note) (plist-get note :title))
  (defun vulpea-note-path (note) (plist-get note :path))
  (defun sp-collec-query-select-note (_prompt) nil)
  ;; vulpea-ui: the module only calls these three.
  (provide 'vulpea-ui)
  (defvar sp-vulpea-grouped-backlinks-test--main nil
    "Note the stubbed main window shows, or nil.")
  (defvar sp-vulpea-grouped-backlinks-test--visited nil
    "Last note passed to the stubbed `vulpea-ui-visit-note'.")
  (defun vulpea-ui--get-main-window (&optional _frame) (selected-window))
  (defun vulpea-ui--get-note-from-buffer (_buffer)
    sp-vulpea-grouped-backlinks-test--main)
  (defun vulpea-ui-visit-note (note)
    (setq sp-vulpea-grouped-backlinks-test--visited note)))

(load (expand-file-name
       "../libraries/modules/vulpea/sp-vulpea-grouped-backlinks.el"
       (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(defmacro sp-vulpea-grouped-backlinks-test--with-vault (&rest body)
  "Run BODY with two source notes linking to note \"target\".
Note \"a\" has a plain mention and note \"b\" lists the target under
`pub-author'.  The files are real, in a temporary directory."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "sp-gb-" t))
          (file-a (expand-file-name "a.org" dir))
          (file-b (expand-file-name "b.org" dir)))
     (unwind-protect
         (progn
           (with-temp-file file-a
             (insert "* A\nSome prose with [[id:target][T]] inside.\n"))
           (with-temp-file file-b
             (insert "* B\n- pub-author :: [[id:target][T]]\n"))
           (let ((sp-vulpea-grouped-backlinks-test--notes
                  `(("a" . (:id "a" :title "Note A" :path ,file-a))
                    ("b" . (:id "b" :title "Note B" :path ,file-b))
                    ("target" . (:id "target" :title "Target" :path ,file-a))))
                 (sp-vulpea-grouped-backlinks-test--links
                  `(("target" . ((:source "a" :pos 20)
                                 (:source "a" :pos 20)
                                 (:source "b" :pos 12))))))
             ,@body))
       (mapc #'kill-buffer (delq nil (mapcar #'find-buffer-visiting
                                             (list file-a file-b))))
       (delete-directory dir t))))

(ert-deftest sp-vulpea-grouped-backlinks-test-meta-key-found-on-meta-line ()
  (sp-vulpea-grouped-backlinks-test--with-vault
    (should (equal (sp-vulpea-grouped-backlinks--meta-key-at file-b 12)
                   "pub-author"))))

(ert-deftest sp-vulpea-grouped-backlinks-test-no-meta-key-in-prose ()
  (sp-vulpea-grouped-backlinks-test--with-vault
    (should-not (sp-vulpea-grouped-backlinks--meta-key-at file-a 20))))

(ert-deftest sp-vulpea-grouped-backlinks-test-classify-groups-and-dedups ()
  (sp-vulpea-grouped-backlinks-test--with-vault
    (let ((groups (sp-vulpea-grouped-backlinks-classify "target")))
      (should (equal (sort (mapcar #'car groups) #'string<)
                     '("Mentions" "pub-author")))
      (should (equal (mapcar #'vulpea-note-id (cdr (assoc "Mentions" groups)))
                     '("a")))
      (should (equal (mapcar #'vulpea-note-id (cdr (assoc "pub-author" groups)))
                     '("b"))))))

(ert-deftest sp-vulpea-grouped-backlinks-test-org-detached-fills-an-org-buffer ()
  (sp-vulpea-grouped-backlinks-test--with-vault
    (cl-letf (((symbol-function 'display-buffer) #'ignore))
      (sp-vulpea-grouped-backlinks-org-detached
       (cdr (assoc "target" sp-vulpea-grouped-backlinks-test--notes))))
    (with-current-buffer "*vulpea backlinks: Target*"
      (should (derived-mode-p 'org-mode))
      (let ((text (buffer-string)))
        (should (string-match-p "^\\* Backlinks to Target$" text))
        (should (string-match-p "^\\*\\* Mentions (1)$" text))
        (should (string-match-p "^\\*\\* pub-author (1)$" text))
        (should (string-match-p "\\[\\[id:a\\]\\[Note A\\]\\]" text))
        (should (< (string-match "Mentions" text)
                   (string-match "pub-author" text))))
      (kill-buffer))))

(ert-deftest sp-vulpea-grouped-backlinks-test-old-names-are-gone ()
  (dolist (old '(sia-vulpea-show-grouped-backlinks
                 sia-vulpea-classify-backlinks
                 sia-vulpea--line-meta-key-at))
    (should-not (fboundp old))))

;;;; Widget

;; The real `vui' macros are replaced by small stand-ins that turn a component
;; into a plain function returning nested lists, so the test sees its shape.
(defvar sp-vulpea-grouped-backlinks-test--registered nil
  "Arguments of the stubbed `vulpea-ui-register-widget' calls.")
(when noninteractive
  (provide 'vui)
  (defun use-vulpea-ui-note () sp-vulpea-grouped-backlinks-test--main)
  (defmacro vui-use-memo (_deps &rest body) `(progn ,@body))
  (defmacro vui-defcomponent (name _args &rest body)
    `(defun ,name () ,(cadr (memq :render body))))
  (defun vui-text (text &rest _) (list 'text text))
  (defun vui-vstack (&rest args)
    (cons 'vstack (if (eq (car args) :indent) (cddr args) args)))
  (defun vui-component (type &rest props)
    (if (plist-get props :children)
        (list type (plist-get props :title) (plist-get props :count)
              (funcall (plist-get props :children)))
      (list type (plist-get props :note))))
  (defun vulpea-ui-register-widget (name &rest props)
    (push (cons name props) sp-vulpea-grouped-backlinks-test--registered)))

(load (expand-file-name
       "../libraries/modules/vulpea/sp-vulpea-grouped-backlinks-widget.el"
       (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(ert-deftest sp-vulpea-grouped-backlinks-test-widget-is-registered ()
  (let ((entry (assq 'grouped-backlinks
                     sp-vulpea-grouped-backlinks-test--registered)))
    (should entry)
    (should (eq (plist-get (cdr entry) :component)
                'sp-vulpea-grouped-backlinks-widget))
    (should (= (plist-get (cdr entry) :order) 310))))

(ert-deftest sp-vulpea-grouped-backlinks-test-widget-renders-the-groups ()
  (sp-vulpea-grouped-backlinks-test--with-vault
    (let* ((sp-vulpea-grouped-backlinks-test--main
            (cdr (assoc "target" sp-vulpea-grouped-backlinks-test--notes)))
           (tree (sp-vulpea-grouped-backlinks-widget)))
      (should (eq (car tree) 'vulpea-ui-widget))
      (should (equal (nth 1 tree) "Grouped backlinks"))
      (should (= (nth 2 tree) 2))
      (let ((flat (format "%S" (nth 3 tree))))
        (should (string-match-p "Mentions (1)" flat))
        (should (string-match-p "pub-author (1)" flat))
        (should (string-match-p "vulpea-ui-note-link" flat))
        (should (string-match-p ":id \"b\"" flat))))))

(ert-deftest sp-vulpea-grouped-backlinks-test-widget-says-so-without-backlinks ()
  (sp-vulpea-grouped-backlinks-test--with-vault
    (let* ((sp-vulpea-grouped-backlinks-test--main
            (cdr (assoc "a" sp-vulpea-grouped-backlinks-test--notes)))
           (tree (sp-vulpea-grouped-backlinks-widget)))
      (should (= (nth 2 tree) 0))
      (should (equal (nth 3 tree) '(text "No backlinks"))))))

(ert-deftest sp-vulpea-grouped-backlinks-test-widget-renders-nothing-without-a-note ()
  (let ((sp-vulpea-grouped-backlinks-test--main nil))
    (should-not (sp-vulpea-grouped-backlinks-widget))))

;;;; Sidebar

(defmacro sp-vulpea-grouped-backlinks-test--with-sidebar (&rest body)
  "Run BODY in a vault whose main window shows note \"target\"."
  (declare (indent 0))
  `(sp-vulpea-grouped-backlinks-test--with-vault
     (let ((sp-vulpea-grouped-backlinks-test--main
            (cdr (assoc "target" sp-vulpea-grouped-backlinks-test--notes)))
           (sp-vulpea-grouped-backlinks-sidebar-follow t))
       (unwind-protect (progn ,@body)
         (sp-vulpea-grouped-backlinks-sidebar-close)))))

(defun sp-vulpea-grouped-backlinks-test--sidebar-text ()
  (with-current-buffer sp-vulpea-grouped-backlinks-sidebar-buffer-name
    (buffer-string)))

(ert-deftest sp-vulpea-grouped-backlinks-test-sorted-puts-mentions-first ()
  (sp-vulpea-grouped-backlinks-test--with-vault
    (should (equal (mapcar #'car (sp-vulpea-grouped-backlinks-sorted "target"))
                   '("Mentions" "pub-author")))))

(ert-deftest sp-vulpea-grouped-backlinks-test-sidebar-opens-in-a-side-window ()
  (sp-vulpea-grouped-backlinks-test--with-sidebar
    (sp-vulpea-grouped-backlinks-sidebar)
    (let ((win (get-buffer-window sp-vulpea-grouped-backlinks-sidebar-buffer-name)))
      (should (window-live-p win))
      (should (eq (window-parameter win 'window-side) 'right)))
    (let ((text (sp-vulpea-grouped-backlinks-test--sidebar-text)))
      (should (string-match-p "Backlinks to Target" text))
      (should (string-match-p "Mentions (1)" text))
      (should (string-match-p "pub-author (1)" text))
      (should (string-match-p "following the main note" text)))))

(ert-deftest sp-vulpea-grouped-backlinks-test-sidebar-command-toggles ()
  (sp-vulpea-grouped-backlinks-test--with-sidebar
    (sp-vulpea-grouped-backlinks-sidebar)
    (sp-vulpea-grouped-backlinks-sidebar)
    (should-not (get-buffer sp-vulpea-grouped-backlinks-sidebar-buffer-name))
    (should-not (memq #'sp-vulpea-grouped-backlinks-sidebar--on-window-change
                      window-buffer-change-functions))))

(ert-deftest sp-vulpea-grouped-backlinks-test-sidebar-follows-the-main-note ()
  (sp-vulpea-grouped-backlinks-test--with-sidebar
    (sp-vulpea-grouped-backlinks-sidebar)
    (setq sp-vulpea-grouped-backlinks-test--main
          (cdr (assoc "a" sp-vulpea-grouped-backlinks-test--notes)))
    (sp-vulpea-grouped-backlinks-sidebar--sync)
    (should (string-match-p "Backlinks to Note A"
                            (sp-vulpea-grouped-backlinks-test--sidebar-text)))))

(ert-deftest sp-vulpea-grouped-backlinks-test-sidebar-stays-when-follow-is-off ()
  (sp-vulpea-grouped-backlinks-test--with-sidebar
    (sp-vulpea-grouped-backlinks-sidebar)
    (setq sp-vulpea-grouped-backlinks-sidebar-follow nil
          sp-vulpea-grouped-backlinks-test--main
          (cdr (assoc "a" sp-vulpea-grouped-backlinks-test--notes)))
    (sp-vulpea-grouped-backlinks-sidebar--sync)
    (should (string-match-p "Backlinks to Target"
                            (sp-vulpea-grouped-backlinks-test--sidebar-text)))))

(ert-deftest sp-vulpea-grouped-backlinks-test-sidebar-keeps-note-outside-notes ()
  (sp-vulpea-grouped-backlinks-test--with-sidebar
    (sp-vulpea-grouped-backlinks-sidebar)
    (setq sp-vulpea-grouped-backlinks-test--main nil)
    (sp-vulpea-grouped-backlinks-sidebar--sync)
    (should (string-match-p "Backlinks to Target"
                            (sp-vulpea-grouped-backlinks-test--sidebar-text)))))

(ert-deftest sp-vulpea-grouped-backlinks-test-toggle-follow-flips-and-catches-up ()
  (sp-vulpea-grouped-backlinks-test--with-sidebar
    (sp-vulpea-grouped-backlinks-sidebar)
    (setq sp-vulpea-grouped-backlinks-sidebar-follow nil
          sp-vulpea-grouped-backlinks-test--main
          (cdr (assoc "a" sp-vulpea-grouped-backlinks-test--notes)))
    (sp-vulpea-grouped-backlinks-sidebar-toggle-follow)
    (should sp-vulpea-grouped-backlinks-sidebar-follow)
    (let ((text (sp-vulpea-grouped-backlinks-test--sidebar-text)))
      (should (string-match-p "Backlinks to Note A" text))
      (should (string-match-p "following the main note" text)))
    (sp-vulpea-grouped-backlinks-sidebar-toggle-follow)
    (should (string-match-p "pinned"
                            (sp-vulpea-grouped-backlinks-test--sidebar-text)))))

(ert-deftest sp-vulpea-grouped-backlinks-test-window-change-arms-one-timer ()
  (let ((sp-vulpea-grouped-backlinks-sidebar--timer nil)
        (armed 0))
    (cl-letf (((symbol-function 'run-with-timer)
               (lambda (&rest _) (cl-incf armed) 'timer)))
      (sp-vulpea-grouped-backlinks-sidebar--on-window-change)
      (sp-vulpea-grouped-backlinks-sidebar--on-window-change))
    (should (= armed 1))))

(ert-deftest sp-vulpea-grouped-backlinks-test-button-visits-in-main-window ()
  (sp-vulpea-grouped-backlinks-test--with-sidebar
    (sp-vulpea-grouped-backlinks-sidebar)
    (with-current-buffer sp-vulpea-grouped-backlinks-sidebar-buffer-name
      (goto-char (point-min))
      (search-forward "Note B")
      (backward-char 1)
      (push-button))
    (should (equal (vulpea-note-id sp-vulpea-grouped-backlinks-test--visited)
                   "b"))))

(provide 'sp-vulpea-grouped-backlinks-test)
;;; sp-vulpea-grouped-backlinks-test.el ends here
