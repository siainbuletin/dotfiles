;;; sp-see-also-keywords-test.el --- Tests for sp-see-also-keywords -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'org)
(defvar sp-org-keywords-research)
(defvar sp-bibtex-files nil)
(require 'sp-see-also)
(require 'sp-see-also-keywords)

(defconst sp-see-also-keywords-test--bib
  "@article{smith2020,
  author = {Smith, Jane and Doe, John and Roe, Rick},
  title = {Value {Form} and Money},
  journal = {Capital \\& Class},
  year = {2020}, volume = {12}, number = {3}, pages = {10--25},
  doi = {10.1/abc},
  keywords = {value form; money},
}
@book{marx1867,
  author = {Marx, Karl},
  title = {Das Kapital},
  address = {Hamburg}, publisher = {Meissner},
  year = {1867},
  keywords = {value form, labour},
}
@incollection{rubin1972,
  author = {Rubin, Isaak Illich},
  editor = {Smith, Jane and Doe, John},
  title = {Essays},
  booktitle = {Studies in Value},
  year = {1972}, pages = {1--9},
  address = {Detroit}, publisher = {Black \\& Red},
  keywords = {value form},
}
@phdthesis{lone2001,
  author = {Lone, Anna},
  title = {A Thesis},
  school = {Univ. X},
  year = {2001},
  keywords = {money},
}
")

(defun sp-see-also-keywords-test--str (entry-text)
  (substring-no-properties
   (sp-see-also-keywords-reference
    (sp-see-also-keywords--entry
     (with-temp-buffer (insert entry-text) (delay-mode-hooks (bibtex-mode))
                       (goto-char (point-min)) (bibtex-parse-entry t))))))

(ert-deftest sp-see-also-keywords-chicago-article ()
  (should (equal (sp-see-also-keywords-test--str
                  "@article{a, author = {Smith, Jane and Doe, John and Roe, Rick}, title = {Value Form}, journal = {Capital \\& Class}, year = {2020}, volume = {12}, number = {3}, pages = {10--25}, doi = {10.1/abc}}")
                 "Smith, Jane, John Doe, and Rick Roe. 2020. “Value Form” Capital & Class 12 (3): 10–25. 10.1/abc.")))

(ert-deftest sp-see-also-keywords-chicago-book-and-chapter ()
  (should (equal (sp-see-also-keywords-test--str
                  "@book{b, author = {Marx, Karl}, title = {Das Kapital}, address = {Hamburg}, publisher = {Meissner}, year = {1867}}")
                 "Marx, Karl. 1867. Das Kapital. Hamburg: Meissner."))
  (should (equal (sp-see-also-keywords-test--str
                  "@incollection{c, author = {Rubin, Isaak}, editor = {Smith, Jane and Doe, John}, title = {Essays}, booktitle = {Studies in Value}, year = {1972}, pages = {1--9}, address = {Detroit}, publisher = {Black}}")
                 "Rubin, Isaak. 1972. “Essays” In Studies in Value, edited by Jane Smith and John Doe, 1–9. Detroit: Black."))
  (should (equal (sp-see-also-keywords-test--str
                  "@phdthesis{t, author = {Lone, Anna}, title = {A Thesis}, school = {Univ. X}, year = {2001}}")
                 "Lone, Anna. 2001. “A Thesis” PhD diss., Univ. X."))
  (should (equal (sp-see-also-keywords-test--str "@misc{m, title = {Notes?}}")
                 "n.d. Notes?")))

(ert-deftest sp-see-also-keywords-chicago-many-authors-and-faces ()
  (let* ((authors (mapconcat (lambda (i) (format "A%d, B" i)) (number-sequence 1 12) " and "))
         (s (sp-see-also-keywords-test--str (format "@book{x, author = {%s}, title = {T}, year = {2000}}" authors))))
    (should (string-match-p "et al\\." s)))
  (let ((str (sp-see-also-keywords-reference
              (list :type "book" :fields '(("author" . "Marx, Karl") ("title" . "Kapital") ("year" . "1867"))))))
    (should (eq (get-text-property 0 'face str) 'sp-see-also-ref-author))
    (should (eq (get-text-property (string-search "Kapital" str) 'face str) 'sp-see-also-ref-container))))

(defun sp-see-also-keywords-test--setup (dir)
  "Write litnotes and a .bib in DIR and clear the caches."
  (let ((notes (expand-file-name "litnotes" dir)))
    (make-directory notes)
    (with-temp-file (expand-file-name "smith2020.org" notes)
      (insert ":PROPERTIES:\n:ID: s\n:ROAM_REFS: @smith2020\n:END:\n#+title: Smith (2020) Value\n\n- pub-year :: 2020\nKEYWORDS: value form, money\n\n* Body\nKEYWORDS: ignored under a heading\n"))
    (with-temp-file (expand-file-name "marx1867.org" notes)
      (insert ":PROPERTIES:\n:ID: m\n:ROAM_REFS: @marx1867\n:END:\n#+title: Marx\n\nKEYWORDS: value form, labour\n"))
    (with-temp-file (expand-file-name "nokw.org" notes)
      (insert ":PROPERTIES:\n:ID: n\n:END:\n#+title: No keywords\n"))
    (with-temp-file (expand-file-name "all.bib" dir) (insert sp-see-also-keywords-test--bib))
    (sp-see-also-keywords-reindex)
    notes))

(defmacro sp-see-also-keywords-test--with-vault (&rest body)
  `(let* ((dir (make-temp-file "sp-sak" t))
          (notes (sp-see-also-keywords-test--setup dir))
          (sp-bibtex-files (list (expand-file-name "all.bib" dir)))
          (sp-see-also-files-function (lambda () (directory-files notes t "\\.org\\'"))))
     (cl-letf (((symbol-function 'sp-author-notes-bibtex--files) (lambda () sp-bibtex-files))
               ((symbol-function 'message) #'ignore))
       (unwind-protect (progn ,@body) (delete-directory dir t)))))

(ert-deftest sp-see-also-keywords-reads-the-line-before-the-first-heading ()
  (sp-see-also-keywords-test--with-vault
   (let ((data (sp-see-also-keywords--note-data (expand-file-name "smith2020.org" notes))))
     (should (equal (plist-get data :keywords) '("value form" "money")))
     (should (equal (plist-get data :keys) '("smith2020")))
     (should (equal (plist-get data :title) "Smith (2020) Value")))
   (should-not (plist-get (sp-see-also-keywords--note-data (expand-file-name "nokw.org" notes)) :keywords))))

(ert-deftest sp-see-also-keywords-find-litnotes-and-bibtex-only ()
  (sp-see-also-keywords-test--with-vault
   (let* ((groups (sp-see-also-keywords-find '("value form" "money")
                                             (expand-file-name "smith2020.org" notes) '("smith2020")))
          (vf (cdr (assoc "value form" groups)))
          (money (cdr (assoc "money" groups))))
     ;; litnote first (marx), then the BibTeX-only rubin; smith2020 itself excluded
     (should (equal (mapcar (lambda (i) (plist-get i :key)) vf) '("marx1867" "rubin1972")))
     (should (equal (mapcar (lambda (i) (plist-get i :kind)) vf) '(litnote bib)))
     ;; marx's litnote has its BibTeX entry, so it renders as a reference
     (should (plist-get (car vf) :entry))
     ;; money: only the thesis (no litnote)
     (should (equal (mapcar (lambda (i) (plist-get i :key)) money) '("lone2001"))))
   (let ((sp-see-also-keywords-bibtex nil))
     (should (equal (mapcar (lambda (i) (plist-get i :kind)) (cdr (assoc "money" (sp-see-also-keywords-find '("money")))))
                    '(litnote))))))

(ert-deftest sp-see-also-keywords-of-note-falls-back-to-bibtex ()
  (sp-see-also-keywords-test--with-vault
   (should (equal (sp-see-also-keywords-of (list :file (expand-file-name "smith2020.org" notes) :own t))
                  '("value form" "money")))
   (should (equal (sp-see-also-keywords-of (list :file (expand-file-name "nokw.org" notes) :own t :citekey '("lone2001")))
                  '("money")))
   (should-not (sp-see-also-keywords-of (list :file (expand-file-name "nokw.org" notes) :own t)))
   (should (member "labour" (sp-see-also-keywords-all)))))

(ert-deftest sp-see-also-keywords-cache-follows-the-file ()
  (sp-see-also-keywords-test--with-vault
   (let ((file (expand-file-name "marx1867.org" notes)))
     (should (equal (plist-get (sp-see-also-keywords--note-data file) :keywords) '("value form" "labour")))
     (sleep-for 0.05)
     (with-temp-file file (insert ":PROPERTIES:\n:ID: m\n:END:\n#+title: Marx\n\nKEYWORDS: only, this\n"))
     (should (equal (plist-get (sp-see-also-keywords--note-data file) :keywords) '("only" "this"))))))

(ert-deftest sp-see-also-keywords-section-renders-in-the-view ()
  (sp-see-also-keywords-test--with-vault
   (let ((sp-see-also-view--redraw nil))
     (with-temp-buffer
       (sp-see-also-view-mode)
       (let ((inhibit-read-only t))
         (cl-letf (((symbol-function 'sp-see-also-view--width) (lambda () 80)))
           (sp-see-also-keywords--section
            (list :file (expand-file-name "smith2020.org" notes) :own t :citekey '("smith2020")))))
       (let ((text (buffer-string)))
         (should (string-match-p "── Same keywords ──" text))
         (should (string-match-p "value form" text))
         (should (string-match-p "● Marx, Karl\\. 1867\\. Das Kapital\\. Hamburg: Meissner\\." text))
         (should (string-match-p "○ Rubin, Isaak Illich\\. 1972\\." text))
         (should-not (string-match-p "also:" text))      ; nothing shares both keywords
         (should (string-match-p "1 litnote · 1 BibTeX only" text)))
       ;; the reference keeps its faces
       (goto-char (point-min))
       (search-forward "Marx, Karl")
       (should (memq 'sp-see-also-ref-author (ensure-list (get-text-property (1- (point)) 'face))))))))

(ert-deftest sp-see-also-keywords-section-is-silent-without-keywords ()
  (sp-see-also-keywords-test--with-vault
   (with-temp-buffer
     (sp-see-also-view-mode)
     (let ((inhibit-read-only t))
       (sp-see-also-keywords--section (list :file (expand-file-name "nokw.org" notes) :own t)))
     (should (string-empty-p (buffer-string))))))

(provide 'sp-see-also-keywords-test)
;;; sp-see-also-keywords-test.el ends here
