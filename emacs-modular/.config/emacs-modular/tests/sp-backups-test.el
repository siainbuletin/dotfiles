;;; sp-backups-test.el --- Tests for long backup and auto-save names -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-backups)

(defconst sp-backups-test--long-path
  (concat "/Users/x/Documents/literature/inbox/"
          "Capitalism and Communication_ Global Culture and the -- Nicholas Garnham; "
          "edited by Fred Inglis -- The Media, culture & society series, Media, -- "
          "isbn13 9780803982574 -- 78f40ccc4fb9dd0f733a8f7a2765a186 -- Anna’s Archive.pdf"))

(ert-deftest sp-backups-shorten-name-keeps-short-names ()
  (should (equal (sp-backups--shorten-name "/tmp/a/b.pdf") "/tmp/a/b.pdf")))

(ert-deftest sp-backups-shorten-name-fits-and-is-unique ()
  (let* ((a (sp-backups--shorten-name sp-backups-test--long-path))
         (b (sp-backups--shorten-name (concat sp-backups-test--long-path "x"))))
    (should (<= (string-bytes (file-name-nondirectory a)) sp-backups-max-name-bytes))
    (should (equal (file-name-directory a) "/Users/x/Documents/literature/inbox/"))
    (should-not (equal a b))))

(ert-deftest sp-backups-shorten-name-keeps-auto-save-hash ()
  (let ((n (sp-backups--shorten-name (concat "/tmp/#" (make-string 300 ?é) "#"))))
    (should (string-suffix-p "#" n))
    (should (<= (string-bytes (file-name-nondirectory n)) sp-backups-max-name-bytes))))

(ert-deftest sp-backups-auto-save-name-is-safe ()
  "A path over 255 bytes gets a short auto-save name."
  (let ((buffer-file-name sp-backups-test--long-path)
        (auto-save-file-name-transforms '((".*" "/tmp/as/" sha1))))
    (let ((n (make-auto-save-file-name)))
      (should (<= (string-bytes (file-name-nondirectory n)) 255))
      (should (string-prefix-p "/tmp/as/#" n)))))

(ert-deftest sp-backups-backup-name-is-safe ()
  (let* ((dir (file-name-as-directory (make-temp-file "sp-bk" t)))
         (backup-directory-alist `(("." . ,dir)))
         (n (make-backup-file-name sp-backups-test--long-path)))
    (unwind-protect
        (progn
          (should (> (string-bytes (subst-char-in-string ?/ ?! sp-backups-test--long-path)) 255))
          (should (<= (string-bytes (file-name-nondirectory n)) (1+ sp-backups-max-name-bytes)))
          (should (string-prefix-p dir n)))
      (delete-directory dir t))))

(provide 'sp-backups-test)
