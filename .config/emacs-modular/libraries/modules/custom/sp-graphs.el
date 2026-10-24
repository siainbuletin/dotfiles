;;; sp-graphs.el --- Graphs of notes: discourse-graphs, vulpea-graph and the relationship annotator -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "29.1") (vulpea "2.7.0") (vui "1.4.0"))

;;; Commentary:

;; Everything that draws or analyses graphs of notes, in one file.
;;
;; Installed with `use-package' (Elpaca `:ensure'):
;;   `discourse-graphs'  typed nodes in Org headings, SQLite cache, context panel
;;   `vulpea-graph'      interactive graph of Vulpea notes in the browser
;;
;; Custom code, written here:
;;   Relationship annotator  relations between Vulpea notes, as a browser
;;                           graph, outlines, an SVG and a review buffer
;;     M-x rel-anno-graph-static   static HTML page in the browser
;;     M-x rel-anno-outline-native buttons in an Emacs buffer
;;     M-x rel-anno-outline-vui    the same outline built with vui (trial)
;;     M-x rel-anno-svg            static Graphviz SVG (needs `dot')
;;     M-x rel-anno-review         anomalies, gaps and strength of answers
;;   Live view               the same page served on 127.0.0.1, reloaded
;;                           when the graph data changes
;;     M-x rel-anno-graph         ask for a note, start, open
;;     M-x rel-anno-live-open     open the last note again
;;     M-x rel-anno-live-start    start the server
;;     M-x rel-anno-live-stop     stop the server
;;     M-x rel-anno-live-refresh  make open pages reload
;;
;; Each annotator command first asks for a starting note and a depth.  The
;; depth counts levels below the starting note.  Notes at the last level
;; show how many children they hide.  The browser graph holds
;; `relationship-annotator-embed-depth' levels (4) and can't load more, so
;; run the command again from another note, or with a bigger depth.  The
;; outline expands any node on demand.
;;
;; Other relations between notes (`supports', `opposes', ...) are drawn as
;; labelled links.  See `relationship-annotator-relations' for how to
;; declare them and where each one is read from.
;;
;; docs/tangles/custom/sp-graphs.org is the source of this file.

;;; Code:

;;; Installed with use-package

(use-package discourse-graphs
  :ensure (discourse-graphs :type git
                            :host github
                            :repo "LuciusChen/discourse-graphs"
                            :files ("*.el"
                            "discourse-graphs-ui/out/*.html"
                            "discourse-graphs-ui/out/assets/*"))
  :config
  (setq dg-directories ;; This is where we scan for nodes
  (list sp-notes-dir)
  )
  (setq dg-recursive t)
  (setq dg-db-file "~/.config/emacs-include/discourse-graphs.db") ;; this is where the SQLite will live

(discourse-graphs-mode 1)
)

;; Use with denote
(setq dg-use-denote t)

(setq dg-context-window-width 0.3)

;; Auto-update context when moving between nodes
(setq dg-context-auto-update t)

;; Maximum lines to display per node in context panel (nil for unlimited)
(setq dg-context-max-lines 30)

;; Show overlays on headings
(setq dg-overlay-enable t)

;; Synthesis dashboard file location
(setq dg-synthesis-file (sp-path sp-notes-dir "dg-synthesis.org"))

(setq dg-discourse-attributes
      '(
        (claim
         . (
            (evidence-score . "{count:Supported By:evidence} - {count:Opposed By:evidence}")
            (robustness . "{count:Supported By:evidence} + {count:Supported By:claim}*0.5 - {count:Opposed By:evidence}")
            (overlay . evidence-score)
                )
           )

        (question
         . (
          (answer-count . "{count:Answered By:claim}")
            (overlay . answer-count)
              )
         )
        ;; ... more types
        )
)

(setq dg-node-types
      '(
        (question . (:short "QUE"
                          :color "lightblue"
                          :desc "Research question"))
        (claim    . (:short "CLM"
                          :color "lightyellow"
                          :desc "Assertion, thesis or position in a debate"))
        (evidence . (:short "EVD"
                          :color "lightgreen"
                          :desc "Argument, proof, or supporting empirical data"))
        (source   . (:short "SRC"
                          :color "lightgray"
                          :desc "Reference material / Philosophical text"))
        (theory   . (:short "THY"
                                  :color "lightcoral"
                          :desc "Theoretical framework"))
        ))

(setq dg-relation-types
      '(
      (supports  . (:inverse "Supported By"
                             :color "green"
                             :style "solid"))
      (opposes   . (:inverse "Opposed By"
                             :color "red"
                             :style "dashed"))
      (informs   . (:inverse "Informed By"
                             :color "blue"
                             :style "solid"))
      (answers   . (:inverse "Answered By"
                             :color "purple"
                             :style "solid"))
      )
      )

(setq dg-relation-patterns
      '((supports . (:source (evidence)
                           :target (claim)))
      (opposes  . (:source (evidence)
                           :target (claim)))
      (informs  . (:source (source)
                           :target (evidence)))
      (answers  . (:source (claim)
                           :target (question)))
      )
        )

(use-package vulpea-graph
  :ensure (:host github :repo "Arenile/vulpea-graph-ui" :files ("*.el" "assets"))
  :after (websocket simple-httpd)
  :commands
  (vulpea-graph vulpea-graph-mode))

;;; Custom code: the relationship annotator, then its live view

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'json)
(require 'vulpea)
(require 'vulpea-select)
(require 'vui)

(defgroup relationship-annotator nil
  "Typed relationships between vulpea notes, as graphs and outlines."
  :group 'vulpea)

(defcustom relationship-annotator-relations
  '((parent :label "parent" :color "#888888" :inverse "children"
            :sources ((meta "parents") (meta-inverse "children")))
    (supports :label "supports" :color "#2e8b57" :direction right
              :inverse "Supported By"
              :subject-types (evidence) :object-types (claim)
              :sources ((meta "supports") (property "DG_SUPPORTS")))
    (opposes :label "opposes" :color "#c0392b" :direction left
             :inverse "Opposed By"
             :subject-types (evidence) :object-types (claim)
             :sources ((meta "opposes") (property "DG_OPPOSES")))
    (informs :label "informs" :color "#2874a6" :direction 45
             :inverse "Informed By"
             :subject-types (source) :object-types (evidence)
             :sources ((meta "informs") (property "DG_INFORMS")))
    (answers :label "answers" :color "#8e44ad" :direction up
             :inverse "Answered By"
             :subject-types (claim) :object-types (question)
             :sources ((meta "answers") (property "DG_ANSWERS"))))
  "Relations between notes, as (NAME :label LABEL :color COLOR :direction DIRECTION :inverse INVERSE :subject-types TYPES :object-types TYPES :sources SOURCES).
The relation `parent' is the one that builds the tree: its edges run
from a parent down to its children.  Every other relation is drawn as a
labelled link between two notes that are both in view.

An edge reads \"SUBJECT NAME OBJECT\", for example \"claim supports
question\".  Each of SOURCES says where to look for edges, and a
relation may have several:

  (meta KEY)           the note is the subject; the links in its
                       metadata KEY (\"- KEY :: [[id:..][..]]\") are objects.
  (meta-inverse KEY)   the note is the object; the links in its metadata
                       KEY are subjects.  \"- children :: ..\" on a note
                       gives the parent edge of each child.
  (property KEY)       the note is the subject; the links, or bare ids,
                       in its file property KEY are objects.
  (property-inverse KEY)
                       like `meta-inverse', but read from a file property.

COLOR is used for the links in the browser page and the SVG export.

DIRECTION says where the object of the relation is drawn, as seen from
its subject, in the browser page: `up', `down', `left' or `right', or an
angle in degrees, where 0 is right and 90 is up, so 45 is up and to the
right.  An angle leans on both axes at once.  The relation `parent' has
no direction, because it always puts parents above their children.  A
relation with no DIRECTION is drawn to the right.  The page treats a
direction as a request: when two requests contradict each other, the
later one is dropped.

INVERSE names the relation as seen from its object, such as \"Supported
By\".  Formulas in `relationship-annotator-attributes' use it to count
incoming edges.  SUBJECT-TYPES and OBJECT-TYPES list the node types, from
`relationship-annotator-node-types', that an edge of this relation
should connect.  An edge between other types is not refused, only
reported as an anomaly.  A relation without them accepts any types."
  :type '(alist :key-type symbol :value-type plist))

(defcustom relationship-annotator-tag-colors
  '(("root" . "#4e79a7")
    ("idea" . "#f28e2b")
    ("question" . "#b07aa1")
    ("claim" . "#59a14f")
    ("evidence" . "#76b7b2")
    ("source" . "#edc948"))
  "Colours for boxes, as (FILE-TAG . COLOR).
A note takes the colour of the first of its file tags that is listed
here, in the order the tags are stored.  Notes with no listed tag keep
the default box colour.  COLOR must be in hex form, such as
\"#4e79a7\"; the views draw it as a tint, so text stays readable in
light and dark themes."
  :type '(alist :key-type string :value-type string))

(defcustom relationship-annotator-default-depth 2
  "Depth offered by default when choosing how far to show the hierarchy."
  :type 'integer)

(defcustom relationship-annotator-embed-depth 4
  "Levels below the starting note that the browser page holds.
The page recentres and changes depth only within them.  Notes at the
last level show how many children they hide; run the command again from
another note to go further.  A larger depth, when you ask for one, wins."
  :type 'integer)

(defcustom relationship-annotator-html-file
  (expand-file-name "relationship-annotator.html" sp-cache-dir)
  "Where `rel-anno-graph-static' writes its HTML page."
  :type 'file)

(defcustom relationship-annotator-svg-directory
  (expand-file-name "relationship-annotator/" sp-cache-dir)
  "Directory where `rel-anno-svg' writes its SVG files."
  :type 'directory)

(defcustom relationship-annotator-rankdir "TB"
  "Graphviz layout direction: \"TB\" (parents on top) or \"LR\" (parents on the left)."
  :type '(choice (const "LR") (const "TB")))

(defcustom relationship-annotator-wrap-width 28
  "Number of characters after which node labels wrap in the SVG export."
  :type 'integer)

;;;; Tree and scope

(defun relationship-annotator--note (id notes)
  "Return the note with ID from NOTES, loading it from the database if needed."
  (or (gethash id notes)
      (when-let ((note (vulpea-db-get-by-id id)))
        (puthash id note notes)
        note)))

(defun relationship-annotator--title (id notes)
  "Title of note ID from NOTES, or a marker for a dangling link."
  (if-let ((note (relationship-annotator--note id notes)))
      (vulpea-note-title note)
    (format "<missing %s>" id)))

(defun relationship-annotator--value-ids (values)
  "Return the ids named in VALUES, a list of strings.
A value may hold several links, separated by commas or not.  Every link
counts, not only the first one in a value.  A value with no link is
read as bare ids separated by commas or spaces."
  (let (ids)
    (dolist (value values)
      (let ((pos 0) (found nil))
        (while (string-match org-link-bracket-re value pos)
          (setq found t)
          (let ((link (match-string 1 value)))
            (when (string-prefix-p "id:" link)
              (push (string-remove-prefix "id:" link) ids)))
          (setq pos (match-end 0)))
        (unless found
          (dolist (word (split-string value "[ ,]+" t))
            (push word ids)))))
    (delete-dups (seq-remove #'string-empty-p (nreverse ids)))))

(defun relationship-annotator--source-values (note source)
  "Return the strings that SOURCE finds in NOTE."
  (pcase source
    ((or `(meta ,key) `(meta-inverse ,key))
     (cdr (assoc key (vulpea-note-meta note))))
    ((or `(property ,key) `(property-inverse ,key))
     (when-let ((value (cdr (assoc key (vulpea-note-properties note)))))
       (list value)))))

(defun relationship-annotator--source-notes (source)
  "Return the notes that may hold SOURCE."
  (pcase source
    ((or `(meta ,key) `(meta-inverse ,key))
     (vulpea-db-query-by-meta-key key))
    ((or `(property ,key) `(property-inverse ,key))
     (vulpea-db-query
      (lambda (note) (assoc key (vulpea-note-properties note)))))))

(defun relationship-annotator--edges ()
  "Return every edge as (SUBJECT RELATION OBJECT), and the notes read.
The second value is a hash table from id to note."
  (let ((notes (make-hash-table :test #'equal))
        (seen (make-hash-table :test #'equal))
        edges)
    (pcase-dolist (`(,relation . ,plist) relationship-annotator-relations)
      (dolist (source (plist-get plist :sources))
        (dolist (note (relationship-annotator--source-notes source))
          (puthash (vulpea-note-id note) note notes)
          (dolist (id (relationship-annotator--value-ids
                       (relationship-annotator--source-values note source)))
            (let* ((inverse (memq (car source) '(meta-inverse property-inverse)))
                   (edge (if inverse
                             (list id relation (vulpea-note-id note))
                           (list (vulpea-note-id note) relation id))))
              (unless (gethash edge seen)
                (puthash edge t seen)
                (push edge edges)))))))
    (cons (nreverse edges) notes)))

(defun relationship-annotator--build ()
  "Return a plist describing the whole hierarchy.
:notes maps id to note, :children maps parent id to child ids,
:roots lists ids that are parents but have no parent themselves, and
:links lists the edges (SUBJECT RELATION OBJECT) of every other relation."
  (pcase-let* ((`(,edges . ,notes) (relationship-annotator--edges))
               (children (make-hash-table :test #'equal))
               (has-parent (make-hash-table :test #'equal))
               (parent-ids nil)
               (links nil)
               (ids nil))
    (pcase-dolist (`(,subject ,relation ,object) edges)
      (push subject ids)
      (push object ids)
      (if (eq relation 'parent)
          (progn (puthash subject t has-parent)
                 (push subject (gethash object children))
                 (push object parent-ids))
        (push (list subject relation object) links)))
    ;; Notes that only appear as the object of an edge are not loaded yet.
    (dolist (note (vulpea-db-query-by-ids
                   (seq-remove (lambda (id) (gethash id notes))
                               (delete-dups ids))))
      (puthash (vulpea-note-id note) note notes))
    (list :notes notes
          :children children
          :links (nreverse links)
          :roots (sort (seq-remove (lambda (id) (gethash id has-parent))
                                   (delete-dups (copy-sequence parent-ids)))
                       (lambda (a b)
                         (string< (relationship-annotator--title a notes)
                                  (relationship-annotator--title b notes)))))))

(defun relationship-annotator--sorted-children (id tree)
  "Child ids of ID in TREE, sorted by title."
  (let ((notes (plist-get tree :notes)))
    (sort (copy-sequence (gethash id (plist-get tree :children)))
          (lambda (a b)
            (string< (relationship-annotator--title a notes)
                     (relationship-annotator--title b notes))))))

(defun relationship-annotator--scope (tree start depth)
  "Return the part of TREE reached from START within DEPTH levels.
The result has the same keys as the tree, plus :more, which maps an
id at the last level to how many children it hides, and :nodes, the
ids in scope.  :roots is just (START).  :links keeps the other
relations between two notes that are both in scope."
  (let ((notes (plist-get tree :notes))
        (children (make-hash-table :test #'equal))
        (more (make-hash-table :test #'equal))
        (seen (make-hash-table :test #'equal))
        (nodes (list start))
        (queue (list (cons start 0))))
    (puthash start t seen)
    (while queue
      (pcase-let ((`(,id . ,level) (pop queue)))
        (let ((kids (relationship-annotator--sorted-children id tree)))
          (if (< level depth)
              (dolist (kid kids)
                (puthash id (append (gethash id children) (list kid)) children)
                (unless (gethash kid seen)
                  (puthash kid t seen)
                  (push kid nodes)
                  (setq queue (append queue (list (cons kid (1+ level)))))))
            (when kids
              (puthash id (length kids) more))))))
    (setq nodes (nreverse nodes))
    (list :notes notes
          :children children
          :more more
          :roots (list start)
          :nodes nodes
          :links (seq-filter (pcase-lambda (`(,subject ,_ ,object))
                               (and (gethash subject seen) (gethash object seen)))
                             (plist-get tree :links)))))

(defun relationship-annotator--read-scope ()
  "Ask for a starting note and a depth.  Return (START-ID . DEPTH)."
  (let* ((note (vulpea-select "Start note: " :require-match t))
         (depth (read-number "Depth: " relationship-annotator-default-depth)))
    (unless (and note (vulpea-note-id note) (>= depth 1))
      (user-error "Need a starting note and a depth of at least 1"))
    (cons (vulpea-note-id note) (truncate depth))))

;;;; Discourse layer

;; Ported from the `discourse-graphs' package: node types, the patterns
;; that say which types a relation should connect, the anomaly check,
;; and attributes computed from formulas.  The package keeps its nodes
;; in an SQLite cache that it fills by scanning files.  Here vulpea
;; already is that database, so the layer works on the tree that
;; `relationship-annotator--build' returns.

(defcustom relationship-annotator-node-types
  '((question :short "QUE" :color "#b07aa1" :desc "Research question")
    (claim :short "CLM" :color "#59a14f" :desc "Assertion or thesis")
    (evidence :short "EVD" :color "#76b7b2" :desc "Supporting data")
    (source :short "SRC" :color "#edc948" :desc "Reference material"))
  "Node types, as (TYPE :short ABBREVIATION :color COLOR :desc TEXT).
A note with a type is drawn in the colour of its type, unless one of its
file tags has a colour in `relationship-annotator-tag-colors'.  COLOR
must be in hex form."
  :type '(alist :key-type symbol :value-type plist))

(defcustom relationship-annotator-type-sources
  '((property "DG_TYPE") (meta "type") tag)
  "Where to read the type of a note, tried in order.
(property KEY) reads a file property, (meta KEY) the first value of a
metadata field, and `tag' the first file tag that names a type in
`relationship-annotator-node-types'.  The first source that gives a
known type wins.  A note whose sources give none has no type, and the
anomaly check skips its edges."
  :type '(repeat sexp))

(defcustom relationship-annotator-attributes
  '((claim :overlay evidence-score
           :attributes
           ((evidence-score . "{count:Supported By:evidence} - {count:Opposed By:evidence}")
            (robustness . "{count:Supported By:evidence} + {count:Supported By:claim}*0.5 - {count:Opposed By:evidence} - {count:Opposed By:claim}*0.5")
            (total-support . "{count:Supported By:evidence} + {count:Supported By:claim}")))
    (question :overlay answer-count
              :attributes
              ((answer-count . "{count:Answered By:claim}")
               (informed-count . "{count:Informed By:evidence} + {count:Informed By:source}")))
    (evidence :attributes
              ((source-count . "{count:Informed By:source}")
               (supports-count . "{count:supports:claim}")))
    (source :overlay usage-count
            :attributes
            ((usage-count . "{count:informs:evidence}"))))
  "Numbers computed for notes of each type, as (TYPE :overlay NAME :attributes ALIST).
ALIST holds (NAME . FORMULA).  The attribute named by :overlay is shown
in brackets after the title in the browser page.

A formula is arithmetic (+ - * / and parentheses) over numbers and
terms written {OP:RELATION:TYPE} or {OP:RELATION:TYPE:ATTRIBUTE}.
RELATION is a relation name, to follow its edges from the note, or the
:inverse label of a relation, to follow them backwards.  TYPE keeps only
the related notes of that type, and may be empty.  OP is `count', or
`sum' and `avg' of the ATTRIBUTE of the related notes."
  :type '(alist :key-type symbol :value-type plist))

;;;;; Types

(defun relationship-annotator--note-type (note)
  "Return the node type of NOTE, a symbol, or nil when it has none."
  (when note
    (seq-some
     (lambda (source)
       (let ((value
              (pcase source
                (`(property ,key)
                 (cdr (assoc key (vulpea-note-properties note))))
                (`(meta ,key)
                 (cadr (assoc key (vulpea-note-meta note))))
                ('tag
                 (seq-find (lambda (tag)
                             (assq (intern tag) relationship-annotator-node-types))
                           (vulpea-note-tags note))))))
         (when (stringp value)
           (let ((type (intern (downcase (string-trim value)))))
             (and (assq type relationship-annotator-node-types) type)))))
     relationship-annotator-type-sources)))

(defun relationship-annotator--type-style (type key)
  "Return KEY of TYPE in `relationship-annotator-node-types'."
  (plist-get (cdr (assq type relationship-annotator-node-types)) key))

(defun relationship-annotator--type-names (types)
  "Return the symbols in TYPES as one string, such as \"evidence or claim\"."
  (mapconcat #'symbol-name types " or "))

;;;;; Edges and the pattern check

(defun relationship-annotator--all-edges (tree)
  "Return every edge of TREE as (SUBJECT RELATION OBJECT), parent edges included."
  (let (edges)
    (maphash (lambda (parent kids)
               (dolist (kid kids)
                 (push (list kid 'parent parent) edges)))
             (plist-get tree :children))
    (append (nreverse edges) (plist-get tree :links))))

(defun relationship-annotator--anomaly (subject-type relation object-type)
  "Return a message when SUBJECT-TYPE RELATION OBJECT-TYPE breaks the patterns.
The patterns are :subject-types and :object-types in
`relationship-annotator-relations'.  Return nil when the edge fits, when
the relation has no patterns, or when a type is nil (an untyped note
is not checked)."
  (let* ((plist (cdr (assq relation relationship-annotator-relations)))
         (want-subject (plist-get plist :subject-types))
         (want-object (plist-get plist :object-types))
         (bad-subject (and want-subject subject-type
                           (not (memq subject-type want-subject))))
         (bad-object (and want-object object-type
                          (not (memq object-type want-object)))))
    (cond
     ((and bad-subject bad-object)
      (format "%s %s %s, expected %s %s %s" subject-type relation object-type
              (relationship-annotator--type-names want-subject) relation
              (relationship-annotator--type-names want-object)))
     (bad-subject
      (format "%s %s %s, the subject should be %s" subject-type relation
              object-type (relationship-annotator--type-names want-subject)))
     (bad-object
      (format "%s %s %s, the object should be %s" subject-type relation
              object-type (relationship-annotator--type-names want-object))))))

(defun relationship-annotator--anomalies (tree)
  "Return the edges of TREE that break the patterns, as (SUBJECT RELATION OBJECT MESSAGE)."
  (let ((notes (plist-get tree :notes)) found)
    (pcase-dolist (`(,subject ,relation ,object)
                   (relationship-annotator--all-edges tree))
      (when-let ((message (relationship-annotator--anomaly
                           (relationship-annotator--note-type
                            (relationship-annotator--note subject notes))
                           relation
                           (relationship-annotator--note-type
                            (relationship-annotator--note object notes)))))
        (push (list subject relation object message) found)))
    (nreverse found)))

;;;;; Formulas

(defvar relationship-annotator--computing nil
  "Attributes being computed, as (ID . NAME), to catch formulas that refer to themselves.")

(defun relationship-annotator--parse-term (spec formula)
  "Return the term (func OP RELATION TYPE ATTRIBUTE) written SPEC in FORMULA.
SPEC is the text between braces."
  (pcase-let* ((`(,op ,relation ,type ,attribute) (split-string spec ":"))
               (op (pcase (and op (downcase op))
                     ("count" 'count) ("sum" 'sum)
                     ((or "avg" "average") 'avg)
                     (_ (user-error "Unknown operation in {%s} in formula %S"
                                    spec formula)))))
    (unless (and relation (not (string-empty-p relation)))
      (user-error "No relation in {%s} in formula %S" spec formula))
    (when (and (memq op '(sum avg)) (not (and attribute (not (string-empty-p attribute)))))
      (user-error "%s needs an attribute in {%s} in formula %S" op spec formula))
    (list 'func op relation
          (and type (not (string-empty-p type)) (intern (downcase type)))
          (and attribute (not (string-empty-p attribute)) (intern attribute)))))

(defun relationship-annotator--tokenize (formula)
  "Split FORMULA into numbers, operator symbols and terms."
  (let ((pos 0) tokens)
    (while (< pos (length formula))
      (let ((char (aref formula pos)))
        (cond
         ((memq char '(?\s ?\t)) (cl-incf pos))
         ((memq char '(?+ ?- ?* ?/))
          (push (intern (string char)) tokens) (cl-incf pos))
         ((eq char ?\() (push 'open tokens) (cl-incf pos))
         ((eq char ?\)) (push 'close tokens) (cl-incf pos))
         ((eq char ?{)
          (let ((end (string-search "}" formula pos)))
            (unless end (user-error "Unclosed { in formula %S" formula))
            (push (relationship-annotator--parse-term
                   (substring formula (1+ pos) end) formula)
                  tokens)
            (setq pos (1+ end))))
         ((eq pos (string-match "[0-9]+\\(?:\\.[0-9]+\\)?" formula pos))
          (push (float (string-to-number (match-string 0 formula))) tokens)
          (setq pos (match-end 0)))
         (t (user-error "Unexpected %c in formula %S" char formula)))))
    (nreverse tokens)))

(defun relationship-annotator--parse-formula (formula)
  "Return the parse tree of FORMULA.
A tree is a number, a term (func ...), or (OPERATOR LEFT RIGHT) with
OPERATOR one of + - * /."
  (let ((tokens (relationship-annotator--tokenize formula)))
    (cl-labels
        ((peek () (car tokens))
         (next () (pop tokens))
         (expr ()
           (let ((left (term)))
             (while (memq (peek) '(+ -))
               (let ((op (next)))
                 (setq left (list op left (term)))))
             left))
         (term ()
           (let ((left (factor)))
             (while (memq (peek) '(* /))
               (let ((op (next)))
                 (setq left (list op left (factor)))))
             left))
         (factor ()
           (let ((token (next)))
             (cond
              ((numberp token) token)
              ((eq token 'open)
               (prog1 (expr)
                 (unless (eq (next) 'close)
                   (user-error "Missing ) in formula %S" formula))))
              ((eq token '-) (list '- 0.0 (factor)))
              ((eq (car-safe token) 'func) token)
              (t (user-error "Unexpected %s in formula %S"
                             (or token "end") formula))))))
      (prog1 (expr)
        (when tokens (user-error "Unexpected %s in formula %S" (car tokens) formula))))))

(defun relationship-annotator--index (tree)
  "Return (OUTGOING . INCOMING) tables for the edges of TREE.
OUTGOING maps (SUBJECT . RELATION) to the objects and INCOMING maps
(OBJECT . RELATION) to the subjects."
  (let ((out (make-hash-table :test #'equal))
        (in (make-hash-table :test #'equal)))
    (pcase-dolist (`(,subject ,relation ,object)
                   (relationship-annotator--all-edges tree))
      (push object (gethash (cons subject relation) out))
      (push subject (gethash (cons object relation) in)))
    (cons out in)))

(defun relationship-annotator--context (tree)
  "Return what formulas need to run on TREE."
  (list :notes (plist-get tree :notes)
        :index (relationship-annotator--index tree)
        :cache (make-hash-table :test #'equal)))

(defun relationship-annotator--type-of (id context)
  "Return the node type of note ID, using CONTEXT."
  (relationship-annotator--note-type
   (relationship-annotator--note id (plist-get context :notes))))

(defun relationship-annotator--resolve-relation (name)
  "Return (RELATION . DIRECTION) for NAME, `out' or `in', or nil.
NAME is a relation name, or an :inverse label, ignoring case."
  (let ((name (downcase name)))
    (seq-some
     (pcase-lambda (`(,relation . ,plist))
       (cond ((string= name (downcase (symbol-name relation)))
              (cons relation 'out))
             ((let ((inverse (plist-get plist :inverse)))
                (and inverse (string= name (downcase inverse))))
              (cons relation 'in))))
     relationship-annotator-relations)))

(defun relationship-annotator--eval (tree id context)
  "Evaluate the parse TREE of a formula for note ID, using CONTEXT."
  (pcase tree
    ((pred numberp) tree)
    (`(func ,op ,name ,type ,attribute)
     (pcase-let* ((`(,relation . ,direction)
                   (or (relationship-annotator--resolve-relation name)
                       (user-error "Unknown relation %S in a formula" name)))
                  (index (plist-get context :index))
                  (related (gethash (cons id relation)
                                    (if (eq direction 'out) (car index) (cdr index))))
                  (related (if type
                               (seq-filter
                                (lambda (other)
                                  (eq (relationship-annotator--type-of other context)
                                      type))
                                related)
                             related)))
       (if (eq op 'count)
           (length related)
         (let ((total (apply #'+ (mapcar (lambda (other)
                                           (relationship-annotator--attribute
                                            other attribute context))
                                         related))))
           (if (eq op 'sum)
               total
             (if related (/ total (float (length related))) 0))))))
    (`(,op ,left ,right)
     (let ((a (relationship-annotator--eval left id context))
           (b (relationship-annotator--eval right id context)))
       (pcase op
         ('+ (+ a b)) ('- (- a b)) ('* (* a b))
         ('/ (if (zerop b) 0 (/ (float a) b))))))))

(defun relationship-annotator--attribute (id name context)
  "Return attribute NAME of note ID, a number, using CONTEXT.
A note whose type has no such attribute gets 0."
  (let* ((type (relationship-annotator--type-of id context))
         (formula (cdr (assq name (plist-get
                                   (cdr (assq type relationship-annotator-attributes))
                                   :attributes))))
         (key (cons id name))
         (cache (plist-get context :cache)))
    (cond
     ((null formula) 0)
     ((member key relationship-annotator--computing)
      (user-error "The attribute %s of %s refers to itself" name id))
     (t
      (let ((hit (gethash key cache 'none)))
        (if (not (eq hit 'none))
            hit
          (let* ((relationship-annotator--computing
                  (cons key relationship-annotator--computing))
                 (parsed (or (gethash formula cache)
                             (puthash formula
                                      (relationship-annotator--parse-formula formula)
                                      cache))))
            (puthash key (relationship-annotator--eval parsed id context)
                     cache))))))))

(defun relationship-annotator--attributes (id context)
  "Return the attributes of note ID as ((NAME . VALUE) ...), using CONTEXT."
  (let ((type (relationship-annotator--type-of id context)))
    (mapcar (pcase-lambda (`(,name . ,_))
              (cons name (relationship-annotator--attribute id name context)))
            (plist-get (cdr (assq type relationship-annotator-attributes))
                       :attributes))))

(defun relationship-annotator--number (value)
  "Format VALUE without a fraction when it is whole."
  (if (= value (ftruncate (float value)))
      (format "%d" value)
    (format "%.1f" value)))

(defun relationship-annotator--badge (id context)
  "Return the overlay attribute of note ID as \"[N]\", or nil."
  (let* ((type (relationship-annotator--type-of id context))
         (name (plist-get (cdr (assq type relationship-annotator-attributes))
                          :overlay)))
    (when name
      (format "[%s]" (relationship-annotator--number
                      (relationship-annotator--attribute id name context))))))

;;;;; Argument gaps

(defun relationship-annotator--argument-gaps (id context)
  "Return the gaps in the argument for claim ID, a list of symbols.
`no-support' means no evidence supports it.  `no-source' means some
does, but none of that evidence has a source informing it.
`unanswered-opposition' means opposing evidence is at least as plentiful
as supporting evidence."
  (let* ((index (plist-get context :index))
         (supporters (gethash (cons id 'supports) (cdr index)))
         (opposers (gethash (cons id 'opposes) (cdr index))))
    (append
     (unless supporters '(no-support))
     (when (and supporters
                (not (seq-some (lambda (evidence)
                                 (gethash (cons evidence 'informs) (cdr index)))
                               supporters)))
       '(no-source))
     (when (and opposers (<= (length supporters) (length opposers)))
       '(unanswered-opposition)))))

(defun relationship-annotator--strength (id context)
  "Return how well claim ID stands, as a symbol.
One of `unsupported', `challenged', `contested', `supported' or
`unknown'."
  (let* ((gaps (relationship-annotator--argument-gaps id context))
         (index (plist-get context :index)))
    (cond ((memq 'no-support gaps) 'unsupported)
          ((memq 'unanswered-opposition gaps) 'challenged)
          ((gethash (cons id 'opposes) (cdr index)) 'contested)
          ((gethash (cons id 'supports) (cdr index)) 'supported)
          (t 'unknown))))

;;;;; Review buffer

(defvar-local relationship-annotator--review-tree nil
  "The tree the review buffer was built from.")

(defun relationship-annotator--insert-note-button (id tree)
  "Insert a button that visits note ID of TREE."
  (let ((notes (plist-get tree :notes)))
    (insert-button (relationship-annotator--title id notes)
                   'action (lambda (_)
                             (relationship-annotator--visit
                              id relationship-annotator--review-tree))
                   'follow-link t
                   'help-echo (or (when-let ((note (relationship-annotator--note id notes)))
                                    (vulpea-note-path note))
                                  ""))))

;;;###autoload
(defun rel-anno-review ()
  "List edges that break the type patterns, gaps in claims, and answers.
Three sections: edges whose note types do not fit the relation, claims
with gaps in their argument, and each question with its answers and how
well each stands.  RET on a title visits the note."
  (interactive)
  (let* ((tree (relationship-annotator--build))
         (context (relationship-annotator--context tree))
         (notes (plist-get tree :notes))
         (buffer (get-buffer-create "*relationship review*")))
    (with-current-buffer buffer
      (special-mode)
      (setq relationship-annotator--review-tree tree)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize "Edges that break the type patterns\n" 'face 'bold))
        (let ((anomalies (relationship-annotator--anomalies tree)))
          (if (null anomalies)
              (insert "  none\n")
            (pcase-dolist (`(,subject ,relation ,object ,message) anomalies)
              (insert "  ")
              (relationship-annotator--insert-note-button subject tree)
              (insert (format " %s " relation))
              (relationship-annotator--insert-note-button object tree)
              (insert (propertize (format "   (%s)\n" message) 'face 'shadow)))))
        (insert (propertize "\nClaims with gaps in their argument\n" 'face 'bold))
        (let (any)
          (dolist (id (sort (hash-table-keys notes) #'string<))
            (when (eq (relationship-annotator--type-of id context) 'claim)
              (when-let ((gaps (relationship-annotator--argument-gaps id context)))
                (setq any t)
                (insert "  ")
                (relationship-annotator--insert-note-button id tree)
                (insert (propertize (format "   %s\n" (mapconcat #'symbol-name gaps ", "))
                                    'face 'shadow)))))
          (unless any (insert "  none\n")))
        (insert (propertize "\nQuestions and their answers\n" 'face 'bold))
        (let ((index (plist-get context :index)) any)
          (dolist (id (sort (hash-table-keys notes) #'string<))
            (when (eq (relationship-annotator--type-of id context) 'question)
              (setq any t)
              (insert "  ")
              (relationship-annotator--insert-note-button id tree)
              (insert "\n")
              (let ((answers (gethash (cons id 'answers) (cdr index))))
                (if (null answers)
                    (insert (propertize "    no answers\n" 'face 'shadow))
                  (dolist (answer answers)
                    (insert "    ")
                    (relationship-annotator--insert-note-button answer tree)
                    (insert (propertize (format "   %s\n"
                                                (relationship-annotator--strength
                                                 answer context))
                                        'face 'shadow)))))))
          (unless any (insert "  none\n")))
        (goto-char (point-min))))
    (pop-to-buffer buffer)))

;;;; Browser view

(defconst relationship-annotator--html-template-file
  (expand-file-name "sp-graphs.html"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "File holding the HTML template for the graph pages.
The placeholder `__DATA__' is replaced with the JSON data.")

(defun relationship-annotator--html-template ()
  "Return the text of `relationship-annotator--html-template-file'."
  (with-temp-buffer
    (insert-file-contents relationship-annotator--html-template-file)
    (buffer-string)))

(defconst relationship-annotator--vendor-directory
  (expand-file-name "vendor/relationship-annotator/"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory holding the scripts that the browser page includes.")

(defconst relationship-annotator--vendor-scripts
  '("layout-base.min.js" "cose-base.min.js" "cytoscape.min.js"
    "cytoscape-fcose.min.js")
  "Scripts of `relationship-annotator--vendor-directory', in the order the page loads them.")

(defun relationship-annotator--libraries ()
  "Return the text of the vendored scripts, one after the other."
  (with-temp-buffer
    (dolist (file relationship-annotator--vendor-scripts)
      (insert-file-contents (expand-file-name file relationship-annotator--vendor-directory))
      (goto-char (point-max))
      (insert "\n"))
    (buffer-string)))

(defun relationship-annotator--json-for-html (object)
  "Encode OBJECT as JSON that is safe inside a <script> element."
  (let ((json-encoding-pretty-print nil))
    (thread-last (json-encode object)
                 (string-replace "<" "\\u003c")
                 (string-replace ">" "\\u003e")
                 (string-replace "&" "\\u0026"))))

(defun relationship-annotator--relation-style (relation key &optional default)
  "Return KEY of RELATION from `relationship-annotator-relations', or DEFAULT."
  (or (plist-get (cdr (assq relation relationship-annotator-relations)) key) default))

(defun relationship-annotator--direction-vector (direction)
  "Return DIRECTION as a unit vector [DX DY] on a screen, where DY grows downward."
  (let ((degrees (pcase direction
                   ('right 0) ('up 90) ('left 180) ('down 270)
                   ((pred numberp) direction)
                   (_ 0))))
    (vector (/ (round (* 1000 (cos (degrees-to-radians degrees)))) 1000.0)
            (/ (round (* -1000 (sin (degrees-to-radians degrees)))) 1000.0))))

(defun relationship-annotator--relations-json (links)
  "Return the name, label and colour of each relation used by LINKS."
  (vconcat
   (mapcar (lambda (relation)
             `((name . ,(symbol-name relation))
               (label . ,(relationship-annotator--relation-style
                          relation :label (symbol-name relation)))
               (color . ,(relationship-annotator--relation-style
                          relation :color "#888888"))
               (direction . ,(relationship-annotator--direction-vector
                              (relationship-annotator--relation-style
                               relation :direction 'right)))))
           (delete-dups (mapcar #'cadr links)))))

(defun relationship-annotator--tag-color (note)
  "Return (NAME . COLOR) for the box colour of NOTE, or nil.
The first tag of NOTE in `relationship-annotator-tag-colors' decides.
Without one, the colour of the node type of NOTE does, named by the type."
  (when note
    (or (seq-some (lambda (tag) (assoc tag relationship-annotator-tag-colors))
                  (vulpea-note-tags note))
        (when-let* ((type (relationship-annotator--note-type note))
                    (color (relationship-annotator--type-style type :color)))
          (cons (symbol-name type) color)))))

(defun relationship-annotator--html (tree start depth)
  "Return a self-contained HTML page showing TREE from START to DEPTH.
TREE is already cut to the levels the page holds, see
`relationship-annotator--scope'.  The page can recentre on any note
in it and cut the part to show by itself."
  (let* ((notes (plist-get tree :notes))
         (context (relationship-annotator--context tree))
         (ids (let ((acc (make-hash-table :test #'equal)))
                (puthash start t acc)
                (maphash (lambda (k v)
                           (puthash k t acc)
                           (dolist (kid v) (puthash kid t acc)))
                         (plist-get tree :children))
                (pcase-dolist (`(,subject ,_ ,object) (plist-get tree :links))
                  (puthash subject t acc)
                  (puthash object t acc))
                (sort (hash-table-keys acc) #'string<)))
         (nodes
          (vconcat
           (mapcar
            (lambda (id)
              (let* ((note (relationship-annotator--note id notes))
                     (color (relationship-annotator--tag-color note)))
                `((id . ,id)
                  (title . ,(relationship-annotator--title id notes))
                  (path . ,(and note (vulpea-note-path note)))
                  (tags . ,(vconcat (and note (vulpea-note-tags note))))
                  (colorTag . ,(car color))
                  (color . ,(cdr color))
                  (badge . ,(relationship-annotator--badge id context)))))
            ids)))
         (edges
          (vconcat
           (cl-loop for (parent . kids) in
                    (let (acc)
                      (maphash (lambda (k v) (push (cons k v) acc))
                               (plist-get tree :children))
                      acc)
                    append (mapcar (lambda (kid) (vector parent kid)) kids))))
         (links
          (vconcat
           (mapcar (pcase-lambda (`(,subject ,relation ,object))
                     `((from . ,subject) (to . ,object)
                       (rel . ,(symbol-name relation))
                       (anomaly
                        . ,(relationship-annotator--anomaly
                            (relationship-annotator--type-of subject context)
                            relation
                            (relationship-annotator--type-of object context)))))
                   (plist-get tree :links))))
         (data `((root . ,start)
                 (depth . ,depth)
                 (nodes . ,nodes)
                 (edges . ,edges)
                 (links . ,links)
                 (hidden . ,(let (acc)
                              (maphash (lambda (id count) (push (cons id count) acc))
                                       (plist-get tree :more))
                              acc))
                 (relations . ,(relationship-annotator--relations-json
                                (plist-get tree :links))))))
    (string-replace "__DATA__" (relationship-annotator--json-for-html data)
                    (string-replace "__LIBS__" (relationship-annotator--libraries)
                                    (relationship-annotator--html-template)))))

;;;###autoload
(defun rel-anno-graph-static ()
  "Ask for a starting note and depth, then open a static HTML page of the hierarchy.
The page holds `relationship-annotator-embed-depth' levels below the starting
note.  Clicking a box recentres the graph on it, within those levels."
  (interactive)
  (pcase-let* ((`(,start . ,depth) (relationship-annotator--read-scope))
               (tree (relationship-annotator--scope
                      (relationship-annotator--build) start
                      (max depth relationship-annotator-embed-depth))))
    (let ((coding-system-for-write 'utf-8))
      (with-temp-file relationship-annotator-html-file
        (insert (relationship-annotator--html tree start depth))))
    (browse-url-of-file relationship-annotator-html-file)))

;;;; Native outline view

(defvar-local relationship-annotator--tree nil
  "Full hierarchy shown in this buffer.")

(defvar-local relationship-annotator--expanded nil
  "Hash table of ids whose children are shown.")

(defvar-local relationship-annotator--start nil
  "Id of the note the outline starts from.")

(defvar-local relationship-annotator--depth 2
  "Depth shown when the outline was opened.")

(defvar relationship-annotator-view-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "TAB") #'rel-anno-view-toggle)
    (define-key map (kbd "c") #'rel-anno-view-recenter)
    (define-key map (kbd "g") #'rel-anno-view-redraw)
    map)
  "Keymap for `relationship-annotator-view-mode'.")

(define-derived-mode relationship-annotator-view-mode special-mode "Hierarchy"
  "Major mode for the native relationship outline.
TAB or a [+]/[-] button expands or collapses a note.  RET on a
title visits the note.  c re-scopes, g rebuilds the view.")

(defun relationship-annotator-view--expand-to-depth ()
  "Expand every node in the view above the starting depth."
  (let ((queue (list (cons relationship-annotator--start 0))))
    (while queue
      (pcase-let ((`(,id . ,level) (pop queue)))
        (when (and (< level relationship-annotator--depth)
                   (relationship-annotator--sorted-children id relationship-annotator--tree))
          (puthash id t relationship-annotator--expanded)
          (dolist (kid (relationship-annotator--sorted-children id relationship-annotator--tree))
            (push (cons kid (1+ level)) queue)))))))

(defun relationship-annotator-view--insert (id level path)
  "Insert the line for ID at indent LEVEL, then its children if expanded.
PATH holds the ancestors, so a cycle stops the recursion."
  (let* ((tree relationship-annotator--tree)
         (notes (plist-get tree :notes))
         (kids (relationship-annotator--sorted-children id tree))
         (open (and kids (gethash id relationship-annotator--expanded)))
         (note (relationship-annotator--note id notes)))
    (let ((start (point)))
      (insert (make-string (* 2 level) ?\s))
      (relationship-annotator-view--insert-line-body id kids open note)
      (put-text-property start (point) 'relationship-annotator-id id))
    (insert "\n")
    (when (and open (not (member id path)))
      (dolist (kid kids)
        (relationship-annotator-view--insert kid (1+ level) (cons id path))))))

(defun relationship-annotator-view--insert-line-body (id kids open note)
  "Insert the toggle and title buttons of ID's line, then its child count."
  (let ((notes (plist-get relationship-annotator--tree :notes)))
    (if kids
        (insert-button (if open "[-]" "[+]")
                       'action #'relationship-annotator-view--button-action
                       'follow-link t
                       'help-echo "Expand or collapse"
                       'relationship-annotator-id id
                       'relationship-annotator-kind 'toggle)
      (insert "   "))
    (insert " ")
    (insert-button (relationship-annotator--title id notes)
                   'action #'relationship-annotator-view--button-action
                   'follow-link t
                   'help-echo (or (and note (vulpea-note-path note)) "")
                   'relationship-annotator-id id
                   'relationship-annotator-kind 'visit)
    (when kids (insert (format "  (%d)" (length kids))))))

(defun relationship-annotator-view--redraw ()
  "Erase the buffer and draw the view from its current state."
  (let ((inhibit-read-only t)
        (line (line-number-at-pos)))
    (erase-buffer)
    (insert (propertize (format "%s  ·  depth %d  ·  TAB expand  RET visit  c re-scope  g rebuild\n\n"
                                (relationship-annotator--title
                                 relationship-annotator--start
                                 (plist-get relationship-annotator--tree :notes))
                                relationship-annotator--depth)
                        'face 'shadow))
    (relationship-annotator-view--insert relationship-annotator--start 0 nil)
    (goto-char (point-min))
    (forward-line (max 0 (1- line)))))

(defun relationship-annotator-view--button-action (button)
  "Expand or visit the note of BUTTON, depending on its kind."
  (let ((id (button-get button 'relationship-annotator-id)))
    (pcase (button-get button 'relationship-annotator-kind)
      ('toggle
       (if (gethash id relationship-annotator--expanded)
           (remhash id relationship-annotator--expanded)
         (puthash id t relationship-annotator--expanded))
       (relationship-annotator-view--redraw))
      ('visit
       (let ((note (relationship-annotator--note id (plist-get relationship-annotator--tree :notes))))
         (unless note (user-error "Note %s is not in the database" id))
         (find-file (vulpea-note-path note))
         (when (vulpea-note-pos note)
           (goto-char (vulpea-note-pos note))))))))

(defun rel-anno-view-toggle ()
  "Expand or collapse the note at point."
  (interactive)
  (when-let ((id (get-text-property (point) 'relationship-annotator-id)))
    (when (relationship-annotator--sorted-children id relationship-annotator--tree)
      (if (gethash id relationship-annotator--expanded)
          (remhash id relationship-annotator--expanded)
        (puthash id t relationship-annotator--expanded))
      (relationship-annotator-view--redraw))))

(defun rel-anno-view-redraw ()
  "Rebuild the tree from the database and redraw."
  (interactive)
  (setq relationship-annotator--tree (relationship-annotator--build))
  (relationship-annotator-view--expand-to-depth)
  (relationship-annotator-view--redraw))

(defun rel-anno-view-recenter ()
  "Ask for a new starting note and depth, then redraw."
  (interactive)
  (pcase-let ((`(,start . ,depth) (relationship-annotator--read-scope)))
    (setq relationship-annotator--start start
          relationship-annotator--depth depth
          relationship-annotator--expanded (make-hash-table :test #'equal))
    (relationship-annotator-view--expand-to-depth)
    (relationship-annotator-view--redraw)))

;;;###autoload
(defun rel-anno-outline-native ()
  "Ask for a starting note and depth, then show the hierarchy as buttons."
  (interactive)
  (pcase-let ((`(,start . ,depth) (relationship-annotator--read-scope)))
    (let ((buf (get-buffer-create "*relationship annotator*")))
      (with-current-buffer buf
        (relationship-annotator-view-mode)
        (setq relationship-annotator--tree (relationship-annotator--build)
              relationship-annotator--start start
              relationship-annotator--depth depth
              relationship-annotator--expanded (make-hash-table :test #'equal))
        (relationship-annotator-view--expand-to-depth)
        (relationship-annotator-view--redraw))
      (pop-to-buffer buf))))

;;;; Outline built with vui (trial)

(defun relationship-annotator--visit (id tree)
  "Visit the note ID from TREE in its file."
  (let ((note (relationship-annotator--note id (plist-get tree :notes))))
    (unless note (user-error "Note %s is not in the database" id))
    (find-file (vulpea-note-path note))
    (when (vulpea-note-pos note)
      (goto-char (vulpea-note-pos note)))))

(vui-defcomponent relationship-annotator-node (id level path tree depth initially-open)
  "One note in the vui outline, with its children below when open."
  :state ((toggled nil))
  :render
  (let* ((kids (relationship-annotator--sorted-children id tree))
         (open (if toggled (not initially-open) initially-open))
         (notes (plist-get tree :notes))
         (note (relationship-annotator--note id notes)))
    (vui-vstack
     (vui-hstack
      (vui-space (* 2 level))
      (if kids
          (vui-button (if open "-" "+")
                      :on-click (lambda () (vui-set-state :toggled (not toggled))))
        (vui-text "   "))
      (vui-button (relationship-annotator--title id notes)
                  :no-decoration t
                  :help-echo (and note (vulpea-note-path note))
                  :on-click (lambda () (relationship-annotator--visit id tree)))
      (if kids
          (vui-text (format "(%d)" (length kids)) :face 'shadow)
        (vui-fragment)))
     (if (and open kids (not (member id path)))
         (vui-list kids
                   (lambda (kid)
                     (vui-component 'relationship-annotator-node
                       :id kid :level (1+ level) :path (cons id path)
                       :tree tree :depth depth
                       :initially-open (< (1+ level) depth))))
       (vui-fragment)))))

(vui-defcomponent relationship-annotator-root (start depth tree)
  "The vui outline: a header line, then the starting note."
  :render
  (vui-vstack
   (vui-text (format "%s  ·  depth %d  ·  [+]/[-] expands  ·  title visits  ·  run the command again to re-scope"
                     (relationship-annotator--title start (plist-get tree :notes))
                     depth)
             :face 'shadow)
   (vui-newline)
   (vui-component 'relationship-annotator-node
     :id start :level 0 :path nil :tree tree :depth depth
     :initially-open (> depth 0))))

;;;###autoload
(defun rel-anno-outline-vui ()
  "Ask for a starting note and depth, then show the hierarchy with vui."
  (interactive)
  (pcase-let ((`(,start . ,depth) (relationship-annotator--read-scope)))
    (vui-mount (vui-component 'relationship-annotator-root
                 :start start :depth depth :tree (relationship-annotator--build))
               "*relationship annotator (vui)*")))

;;;; Static SVG export (Graphviz)

(defun relationship-annotator--wrap (text width)
  "Return TEXT as a list of lines no longer than WIDTH, breaking long words."
  (let (lines (line ""))
    (dolist (word (split-string text))
      (while (> (length word) width)
        (when (> (length line) 0) (push line lines) (setq line ""))
        (push (substring word 0 width) lines)
        (setq word (substring word width)))
      (cond ((string-empty-p line) (setq line word))
            ((<= (+ (length line) 1 (length word)) width)
             (setq line (concat line " " word)))
            (t (push line lines) (setq line word))))
    (unless (string-empty-p line) (push line lines))
    (nreverse (or lines (list "")))))

(defun relationship-annotator--label (id notes)
  "Return the title of ID from NOTES followed by its file tags, like :a:b:."
  (let* ((note (relationship-annotator--note id notes))
         (tags (and note (vulpea-note-tags note))))
    (concat (relationship-annotator--title id notes)
            (and tags (format " :%s:" (string-join tags ":"))))))

(defun relationship-annotator--dot-label (id notes)
  "Return the wrapped, escaped Graphviz label text for ID."
  (mapconcat (lambda (line) (replace-regexp-in-string "[\"\\\\]" "\\\\\\&" line))
             (relationship-annotator--wrap (relationship-annotator--label id notes)
                                     relationship-annotator-wrap-width)
             "\\n"))

(defun relationship-annotator--dot-fill (note rootp)
  "Return the Graphviz attributes for the fill of NOTE.
A note with a coloured tag gets that colour as a tint.  The root gets a
thick border, and a blue fill when it has no coloured tag."
  (let ((color (cdr (relationship-annotator--tag-color note))))
    (concat (cond (color (format ", fillcolor=\"%s66\"" color))
                  (rootp ", fillcolor=\"#d8e6f5\""))
            (and rootp ", penwidth=2"))))

(defun relationship-annotator--dot (tree)
  "Return Graphviz source for TREE, one cluster per root."
  (let ((notes (plist-get tree :notes))
        (children (plist-get tree :children))
        (drawn (make-hash-table :test #'equal)))
    (with-temp-buffer
      (insert "digraph vulpea {\n"
              (format "  rankdir=%s;\n" relationship-annotator-rankdir)
              "  node [shape=box, style=\"rounded,filled\", fillcolor=\"#f4f4f4\","
              " fontname=\"Helvetica\"];\n"
              "  edge [color=\"#888888\"];\n")
      (let ((n 0))
        (dolist (root (plist-get tree :roots))
          (insert (format "  subgraph cluster_%d {\n    style=invis;\n" (cl-incf n)))
          (let ((queue (list root)))
            (while queue
              (let ((id (pop queue)))
                (unless (gethash id drawn)
                  (puthash id t drawn)
                  (insert (format "    %S [label=\"%s\"%s];\n"
                                  id (relationship-annotator--dot-label id notes)
                                  (relationship-annotator--dot-fill
                                   (relationship-annotator--note id notes)
                                   (equal id root))))
                  (setq queue (append queue (gethash id children)))))))
          (insert "  }\n")))
      (maphash (lambda (pid kids)
                 (dolist (kid kids)
                   (insert (format "  %S -> %S;\n" pid kid))))
               children)
      (pcase-dolist (`(,subject ,relation ,object) (plist-get tree :links))
        (insert (format "  %S -> %S [constraint=false, style=dashed, label=%S, fontsize=10, color=%S, fontcolor=%S];\n"
                        subject object
                        (relationship-annotator--relation-style
                         relation :label (symbol-name relation))
                        (relationship-annotator--relation-style relation :color "#888888")
                        (relationship-annotator--relation-style relation :color "#888888"))))
      (insert "}\n")
      (buffer-string))))

(defun relationship-annotator--slug (title)
  "Return TITLE as a file-name slug, such as \"value-form\"."
  (string-trim (downcase (replace-regexp-in-string "[^[:alnum:]]+" "-" title))
               "-+" "-+"))

(defun relationship-annotator--svg-file (start depth notes)
  "Return a new SVG file name for the scope from START to DEPTH.
The name is <creation date and time>-<note name>-<depth>.svg, so
exports of the same note never overwrite each other."
  (make-directory relationship-annotator-svg-directory t)
  (expand-file-name
   (format "%s-%s-%d.svg"
           (format-time-string "%Y%m%dT%H%M%S")
           (relationship-annotator--slug (relationship-annotator--title start notes))
           depth)
   relationship-annotator-svg-directory))

;;;###autoload
(defun rel-anno-svg ()
  "Ask for a starting note and depth, then write and show a Graphviz SVG."
  (interactive)
  (unless (executable-find "dot")
    (user-error "Graphviz `dot' not found on PATH"))
  (pcase-let* ((`(,start . ,depth) (relationship-annotator--read-scope))
               (tree (relationship-annotator--build))
               (scope (relationship-annotator--scope tree start depth))
               (dot (relationship-annotator--dot scope))
               (file (relationship-annotator--svg-file start depth (plist-get tree :notes))))
    (with-temp-buffer
      (insert dot)
      (unless (zerop (call-process-region (point-min) (point-max) "dot" nil t nil
                                          "-Tsvg" "-o" file))
        (error "Graphviz failed: %s" (buffer-string))))
    (pop-to-buffer (find-file-noselect file))))

(require 'url-util)
(require 'filenotify)

(defgroup rel-anno-live nil
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
  "Return the tree below START, cut like `rel-anno-graph-static' does."
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
  const key = 'rel-anno-live';
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
      (error (message "Live graph: cannot watch the database (%s); use rel-anno-live-refresh"
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
            "Run M-x rel-anno-graph in Emacs to pick a note."))
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
(defun rel-anno-live-start ()
  "Start the live view server on 127.0.0.1, at `relationship-annotator-live-port'."
  (interactive)
  (unless (process-live-p relationship-annotator-live--server)
    (setq relationship-annotator-live--server
          (condition-case err
              (make-network-process
               :name "rel-anno-live"
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
(defun rel-anno-live-stop ()
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
(defun rel-anno-live ()
  "Ask for a starting note and depth, then show the hierarchy live in the browser.
The page is served by Emacs on localhost and reloads when its data changes."
  (interactive)
  (pcase-let ((`(,start . ,depth) (relationship-annotator--read-scope)))
    (setq relationship-annotator-live--root start
          relationship-annotator-live--depth depth)
    (rel-anno-live-open)))

;;;###autoload
(defalias 'rel-anno-graph #'rel-anno-live)

;;;###autoload
(defun rel-anno-live-open ()
  "Open the live view in the browser on the last starting note, or ask for one."
  (interactive)
  (unless relationship-annotator-live--root
    (pcase-let ((`(,start . ,depth) (relationship-annotator--read-scope)))
      (setq relationship-annotator-live--root start
            relationship-annotator-live--depth depth)))
  (rel-anno-live-start)
  (browse-url (relationship-annotator-live--url
               relationship-annotator-live--root
               (or relationship-annotator-live--depth
                   relationship-annotator-default-depth))))

;;;###autoload
(defun rel-anno-live-refresh ()
  "Make every open live page reload now."
  (interactive)
  (relationship-annotator-live--check-all t))

(provide 'sp-graphs)
;;; sp-graphs.el ends here
