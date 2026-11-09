;;; sp-bibtex-types-test.el --- Tests for sp-bibtex-types -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-bibtex-types)

(ert-deftest sp-bibtex-types-tag-mapping ()
  (dolist (pair '(("BookSection" . "booksection") ("InCollection" . "incollection")
                  ("Article" . "journalarticle") ("Book" . "book")
                  ("MvCollection" . "collection") ("Collection" . "collection")
                  ("PhdThesis" . "phdthesis") ("MastersThesis" . "mastersthesis")))
    (should (equal (sp-bibtex-types-tag (car pair)) (cdr pair)))
    (should (equal (sp-bibtex-types-tag (downcase (car pair))) (cdr pair)))))

(ert-deftest sp-bibtex-types-tag-default ()
  (dolist (type '("misc" "InProceedings" "Report" "" nil))
    (should (equal (sp-bibtex-types-tag type) "text"))))

(ert-deftest sp-bibtex-types-entry-tag ()
  (should (equal (sp-bibtex-types-entry-tag '(("=type=" . "article") ("=key=" . "a"))) "journalarticle"))
  (should (equal (sp-bibtex-types-entry-tag nil) "text")))

(ert-deftest sp-bibtex-types-collection-p ()
  (should (sp-bibtex-types-collection-p "mvcollection"))
  (should (sp-bibtex-types-collection-p "Collection"))
  (should-not (sp-bibtex-types-collection-p "book"))
  (should-not (sp-bibtex-types-collection-p "proceedings")))

(defconst sp-bibtex-types-test--root
  (file-name-directory (directory-file-name (file-name-directory (or load-file-name buffer-file-name)))))

(ert-deftest sp-bibtex-types-all-tags-have-schemas-and-registry ()
  "Every tag has a vulpea-schema in sp-vulpea-schemas.el and is a registered tag."
  (let* ((root sp-bibtex-types-test--root)
         (schemas (with-temp-buffer
                    (insert-file-contents (expand-file-name "libraries/modules/vulpea/sp-vulpea-schemas.el" root))
                    (buffer-string)))
         (registry (with-temp-buffer
                     (insert-file-contents (expand-file-name "libraries/modules/funct/sp-org-tag-registry.el" root))
                     (buffer-string))))
    (dolist (tag (sp-bibtex-types-all-tags))
      (should (string-match-p (regexp-quote (format "(member \"%s\" (vulpea-note-tags note))" tag)) schemas))
      (should (string-match-p (format "\"%s\"" tag) registry)))))

(provide 'sp-bibtex-types-test)
;;; sp-bibtex-types-test.el ends here
