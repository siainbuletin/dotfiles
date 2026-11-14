;;; sp-citations-preload-test.el --- Preloading the citar cache -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
;; The preload is loaded BEFORE the citar-cache stand-ins exist, as in Emacs: this
;; file is loaded before citar is.  `setf' on an accessor then cannot be expanded.
(let ((file (expand-file-name "../libraries/modules/academic/sp-citations.el"
                              (file-name-directory (or load-file-name buffer-file-name))))
      (copy (make-temp-file "sp-citations-preload" nil ".el"))
      forms)
  (with-temp-buffer
    (insert-file-contents file)
    (search-forward ";;;; Preload the bibliography")
    (condition-case nil
        (while t
          (let ((form (read (current-buffer))))
            (when (memq (car-safe form) '(defvar defcustom defconst defun))
              (push form forms))))
      (end-of-file nil)))
  ;; `load' expands macros eagerly, as it did for the real file: a `setf' on an
  ;; accessor of the not yet defined struct would break here.
  (with-temp-file copy
    (insert ";;; -*- lexical-binding: t -*-\n")
    (dolist (form (nreverse forms)) (prin1 form (current-buffer)) (insert "\n")))
  (load copy nil t))
;; Stand-ins for the parts of citar-cache that the preload uses.
(cl-defstruct (citar-cache--bibliography
               (:constructor citar-cache--make-bibliography (filename)))
  filename buffers props
  (entries (make-hash-table :test 'equal)))
(defvar citar-cache--bibliographies (make-hash-table :test 'equal))
(provide 'citar)
(defvar sp-citations-test--parses nil "Files the fake parser read.")
(defvar sp-citations-test--files nil)
(defun citar--bibliography-files (&rest _) sp-citations-test--files)
(defun citar-cache--get-bibliography (file)
  "Like citar: reuse the entry when size and hash agree, else parse again."
  (let* ((cached (gethash file citar-cache--bibliographies))
         (size (file-attribute-size (file-attributes file)))
         (hash (with-temp-buffer (insert-file-contents file) (buffer-hash)))
         (props (list :size size :hash hash :fields '("title")))
         (bib (or cached (citar-cache--make-bibliography file))))
    (unless (and cached
                 (equal (plist-get (citar-cache--bibliography-props cached) :size) size)
                 (equal (plist-get (citar-cache--bibliography-props cached) :hash) hash)
                 (equal (plist-get (citar-cache--bibliography-props cached) :fields) '("title")))
      (push file sp-citations-test--parses)
      (let ((table (make-hash-table :test 'equal)))
        (puthash (concat "key-" (file-name-base file)) (list (cons "title" "T")) table)
        (setf (citar-cache--bibliography-entries bib) table)))
    (setf (citar-cache--bibliography-props bib) props)
    (unless cached (puthash file bib citar-cache--bibliographies))
    bib))
(defmacro sp-citations-test--with-bibs (&rest body)
  `(let* ((dir (make-temp-file "bibs" t))
          (a (expand-file-name "a.bib" dir))
          (b (expand-file-name "b.bib" dir))
          (sp-citations-preload-cache-file (expand-file-name "cache.eld" dir))
          (sp-citations-preload-persist t)
          (sp-citations-test--parses nil)
          (sp-citations-test--files (list a b))
          (citar-cache--bibliographies (make-hash-table :test 'equal)))
     (write-region "@book{x, title={A}}" nil a)
     (write-region "@book{y, title={B}}" nil b)
     ,@body))

(defun sp-citations-test--run ()
  (setq sp-citations-preload--queue (sp-citations-preload--files)
        sp-citations-preload--changed nil)
  (sp-citations-preload--prime sp-citations-preload--queue)
  (while sp-citations-preload--queue
    (sp-citations-preload--next)
    (when (timerp sp-citations-preload--timer)
      (cancel-timer sp-citations-preload--timer)))
  (sp-citations-preload--next))

(ert-deftest sp-citations-preload-reads-all-and-ties-to-global ()
  (sp-citations-test--with-bibs
   (sp-citations-test--run)
   (should (= (length sp-citations-test--parses) 2))
   (maphash (lambda (_f bib) (should (memq 'global (citar-cache--bibliography-buffers bib))))
            citar-cache--bibliographies)
   (should (file-exists-p sp-citations-preload-cache-file))))

(ert-deftest sp-citations-preload-second-pass-reads-nothing ()
  (sp-citations-test--with-bibs
   (sp-citations-test--run)
   (setq sp-citations-test--parses nil)
   (sp-citations-test--run)
   (should-not sp-citations-test--parses)))

(ert-deftest sp-citations-preload-new-session-uses-disk-cache ()
  (sp-citations-test--with-bibs
   (sp-citations-test--run)
   (clrhash citar-cache--bibliographies)
   (setq sp-citations-test--parses nil)
   (sp-citations-test--run)
   (should-not sp-citations-test--parses)
   (should (= (hash-table-count citar-cache--bibliographies) 2))))

(ert-deftest sp-citations-preload-changed-file-is-parsed-again ()
  (sp-citations-test--with-bibs
   (sp-citations-test--run)
   (clrhash citar-cache--bibliographies)
   (write-region "@book{x, title={A longer title}}" nil a)
   (setq sp-citations-test--parses nil)
   (sp-citations-test--run)
   (should (equal sp-citations-test--parses (list a)))))

(ert-deftest sp-citations-preload-ignores-a-damaged-cache ()
  (sp-citations-test--with-bibs
   (write-region "(1 (\"broken" nil sp-citations-preload-cache-file)
   (sp-citations-test--run)
   (should (= (length sp-citations-test--parses) 2))))

(ert-deftest sp-citations-preload-error-stops-quietly ()
  (sp-citations-test--with-bibs
   (cl-letf (((symbol-function 'citar-cache--get-bibliography)
              (lambda (_f) (error "boom"))))
     (setq sp-citations-preload--queue (list a b))
     (sp-citations-preload--next)
     (should-not sp-citations-preload--queue))))
;;;; Compatibility and persistence

(ert-deftest sp-citations-preload-works-when-loaded-before-citar ()
  "Regression: `setf' on citar's accessors was void when the preload loaded first."
  (sp-citations-test--with-bibs
   (let ((bib (citar-cache--get-bibliography a)))
     (sp-citations-preload--set-slot bib 'buffers (list 'global))
     (should (equal (sp-citations-preload--slot bib 'buffers) '(global))))))

(ert-deftest sp-citations-preload-writes-the-cache-file ()
  (sp-citations-test--with-bibs
   (should-not (file-exists-p sp-citations-preload-cache-file))
   (sp-citations-test--run)
   (should (file-exists-p sp-citations-preload-cache-file))))

(ert-deftest sp-citations-preload-saves-after-an-error-and-at-exit ()
  "A pass that stops on an error still saves, and exit saves what citar parsed."
  (sp-citations-test--with-bibs
   (let ((sp-citations-preload-persist t))
     (citar-cache--get-bibliography a)   ; as a citar call would
     (setq sp-citations-preload--saved nil)
     (sp-citations-preload--save-if-needed)
     (should (file-exists-p sp-citations-preload-cache-file))
     (delete-file sp-citations-preload-cache-file)
     (setq sp-citations-preload--saved (sp-citations-preload--snapshot))
     (sp-citations-preload--save-if-needed)   ; nothing new, but no file: written
     (should (file-exists-p sp-citations-preload-cache-file)))))

(ert-deftest sp-citations-preload-does-not-rewrite-an-unchanged-cache ()
  (sp-citations-test--with-bibs
   (sp-citations-test--run)
   (let ((mtime (file-attribute-modification-time
                 (file-attributes sp-citations-preload-cache-file))))
     (sleep-for 1.1)
     (sp-citations-preload--save-if-needed)
     (should (equal mtime (file-attribute-modification-time
                           (file-attributes sp-citations-preload-cache-file)))))))

(ert-deftest sp-citations-preload-off-when-citar-differs ()
  (sp-citations-test--with-bibs
   (should (sp-citations-preload--compatible-p))
   (cl-letf (((symbol-function 'citar-cache--make-bibliography) nil))
     (fmakunbound 'citar-cache--make-bibliography)
     (should-not (sp-citations-preload--compatible-p)))))
;;; sp-citations-preload-test.el ends here
