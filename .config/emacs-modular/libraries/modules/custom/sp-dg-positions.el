;;; sp-dg-positions.el --- Position graph and status views for discourse-graphs -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "29.1") (discourse-graphs "1.0.0"))

;;; Commentary:

;; Reads the nodes and relations of discourse-graphs and shows them as
;; positions: which claims answer which question, what supports,
;; opposes or contests them, and what is missing.
;;
;;   M-x dg-positions-outline  foldable Org outline of id links
;;   M-x dg-positions-graph    Graphviz graph rendered as SVG
;;   M-x dg-positions-status   the outline for one status only
;;   M-x dg-positions-gaps     what each node still lacks
;;   M-x dg-positions-check    rule and data problems
;;
;; Node types, relations, statuses and gaps are declared as readable
;; rules in `dg-positions-rules'.  The graph view needs `dot' (Graphviz).

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(declare-function dg-all-nodes "discourse-graphs")
(declare-function dg-all-relations "discourse-graphs")
(declare-function org-content "org")
(defvar dg-node-types)
(defvar dg-relation-types)
(defvar dg-relation-patterns)
(defvar dg--relation-map)
(defvar sp-cache-dir)
(defvar vulpea-hierarchy-rankdir)

(defgroup dg-positions nil
  "Position graph and status views for discourse-graphs."
  :group 'discourse-graphs)

(defcustom dg-positions-rules
  '(;; Node types
    (node-type question "QUE" :color "lightblue" :desc "Research question")
    (node-type claim "CLM" :color "lightyellow" :desc "Assertion or position")
    (node-type evidence "EVD" :color "lightgreen" :desc "Supporting data")
    (node-type source "SRC" :color "lightgray" :desc "Reference material")

    ;; Relations that discourse-graphs already has
    (relation supports "Supported By"
              :from (evidence claim) :to (claim)
              :counts-as support :color "green")
    (relation opposes "Opposed By"
              :from (evidence claim) :to (claim)
              :counts-as oppose :color "red" :style dashed)
    (relation informs "Informed By"
              :from (evidence) :to (source)
              :grounds t :color "blue")
    (relation answers "Answered By"
              :from (claim) :to (question)
              :color "purple")

    ;; Following an idea through the literature
    (relation adopts "Adopted By"
              :from (claim) :to (claim)
              :counts-as support :color "darkgreen" :style dotted)
    (relation contests "Contested By"
              :from (claim) :to (claim)
              :counts-as oppose :color "orange" :style dashed)
    (relation extends "Extended By"
              :from (claim) :to (claim)
              :color "teal")
    (relation reframes "Reframed By"
              :from (claim) :to (claim)
              :color "orchid" :style dotted)
    (relation appropriates "Appropriated By"
              :from (claim) :to (claim)
              :color "sienna" :style dashed)
    (relation supersedes "Superseded By"
              :from (claim) :to (claim)
              :retires t :color "gray" :style dotted)

    ;; Statuses of a claim, first match wins
    (status challenged :for (claim)
            :when (and (> oppose 0) (<= support oppose))
            :color "#f8c8c8")
    (status contested :for (claim)
            :when (> oppose 0)
            :color "#fff3b0")
    (status supported :for (claim)
            :when (> support 0)
            :color "#c8e6c9")
    (status unsupported :for (claim)
            :when (= support 0)
            :color "#e0e0e0")

    ;; Gaps, every one that holds is reported
    (gap no-answer :for (question)
         :when (= (in answers) 0)
         :text "No claim answers this question")
    (gap no-support :for (claim)
         :when (= support 0)
         :text "Nothing supports this claim")
    (gap no-source :for (evidence)
         :when (= (out informs) 0)
         :text "This evidence cites no source")
    (gap unanswered-opposition :for (claim)
         :when (and (> oppose 0) (<= support oppose))
         :text "Objections outweigh the support"))
  "Rules for node types, relations, statuses and gaps.
Each rule is a list that starts with its kind:

  (node-type NAME \"SHORT\" :color COLOR :desc TEXT)
  (relation NAME \"Inverse Label\" :from TYPES :to TYPES
            :counts-as support|oppose :retires t :grounds t
            :color COLOR :style solid|dashed|dotted)
  (status NAME :for TYPES :when CONDITION :color COLOR)
  (gap NAME :for TYPES :when CONDITION :text TEXT)

A CONDITION is a Lisp expression that may use `support' and `oppose'
\(counts of relations that count as such), `(in REL)' and `(out REL)'
\(counts of REL relations pointing at, and away from, the node) and
`type'.  Statuses are tried in order and the first match wins."
  :type 'sexp
  :group 'spcustom)

(defcustom dg-positions-graph-file
  (expand-file-name "dg-positions.svg"
                    (if (boundp 'sp-cache-dir) sp-cache-dir temporary-file-directory))
  "Where `dg-positions-graph' writes its SVG."
  :type 'file
  :group 'spcustom)

(defcustom dg-positions-rankdir
  (if (boundp 'vulpea-hierarchy-rankdir) vulpea-hierarchy-rankdir "LR")
  "Graphviz layout direction: \"LR\" (left to right) or \"TB\" (top down).
Follows `vulpea-hierarchy-rankdir' when that is loaded first."
  :type '(choice (const "LR") (const "TB"))
  :group 'spcustom)

(defcustom dg-positions-question-first t
  "When non-nil, lay questions out first, like parents in the hierarchy graph.
Arrows keep pointing from the supporting node to the supported one."
  :type 'boolean
  :group 'spcustom)

(defcustom dg-positions-question-type 'question
  "Node type that roots a cluster of positions."
  :type 'symbol
  :group 'spcustom)

(defcustom dg-positions-show-retired nil
  "When non-nil, show nodes retired by a `:retires' relation."
  :type 'boolean
  :group 'spcustom)

(defcustom dg-positions-show-isolated nil
  "When non-nil, the graph also draws nodes that have no relations."
  :type 'boolean
  :group 'spcustom)

;;; Rules

(defconst dg-positions--rule-shapes
  '((node-type 2 (:color :desc))
    (relation 2 (:from :to :counts-as :retires :grounds :color :style))
    (status 1 (:for :when :color))
    (gap 1 (:for :when :text)))
  "For each rule kind: its number of arguments after the kind, and its options.")

(defun dg-positions--plist (rule)
  "The keyword options of RULE."
  (nthcdr (1+ (nth 1 (assq (car rule) dg-positions--rule-shapes))) rule))

(defun dg-positions--opt (rule key)
  "Option KEY of RULE."
  (plist-get (dg-positions--plist rule) key))

(defun dg-positions--rules (kind)
  "All rules of KIND, in the order they are written."
  (seq-filter (lambda (rule) (eq (car rule) kind)) dg-positions-rules))

(defun dg-positions--rule (kind name)
  "The rule of KIND called NAME, or nil."
  (seq-find (lambda (rule) (eq (nth 1 rule) name)) (dg-positions--rules kind)))

(defun dg-positions--rel-opt (rel key)
  "Option KEY of the relation rule for REL, or nil when REL has no rule."
  (when-let* ((rule (dg-positions--rule 'relation rel)))
    (dg-positions--opt rule key)))

(defun dg-positions-validate-rules (&optional rules)
  "Signal a `user-error' naming the first malformed rule in RULES.
RULES defaults to `dg-positions-rules'."
  (let (seen)
    (dolist (rule (or rules dg-positions-rules))
      (let ((shape (assq (car-safe rule) dg-positions--rule-shapes)))
        (unless shape
          (user-error "dg-positions: unknown rule kind in %S (use %s)"
                      rule (mapconcat #'symbol-name
                                      (mapcar #'car dg-positions--rule-shapes) ", ")))
        (let ((id (list (car rule) (nth 1 rule)))
              (options (nthcdr (1+ (nth 1 shape)) rule)))
          (when (member id seen)
            (user-error "dg-positions: %s `%s' is declared twice" (car rule) (nth 1 rule)))
          (push id seen)
          (unless (symbolp (nth 1 rule))
            (user-error "dg-positions: the name in %S must be a symbol" rule))
          (when (and (memq (car rule) '(node-type relation))
                     (not (stringp (nth 2 rule))))
            (user-error "dg-positions: %s `%s' needs a string after its name (%s)"
                        (car rule) (nth 1 rule)
                        (if (eq (car rule) 'relation) "its inverse label" "its short label")))
          (unless (zerop (% (length options) 2))
            (user-error "dg-positions: %s `%s' has an option without a value"
                        (car rule) (nth 1 rule)))
          (cl-loop for (key _value) on options by #'cddr
                   unless (memq key (nth 2 shape))
                   do (user-error "dg-positions: %s `%s' has unknown option %s (use %s)"
                                  (car rule) (nth 1 rule) key
                                  (mapconcat #'symbol-name (nth 2 shape) ", ")))
          (when (and (eq (car rule) 'relation)
                     (not (memq (plist-get options :counts-as) '(nil support oppose))))
            (user-error "dg-positions: relation `%s' has :counts-as %S, use support or oppose"
                        (nth 1 rule) (plist-get options :counts-as)))
          (when (and (memq (car rule) '(status gap))
                     (not (plist-member options :when)))
            (user-error "dg-positions: %s `%s' needs a :when condition"
                        (car rule) (nth 1 rule))))))
    t))

;;; Graph

(defun dg-positions--sym (x)
  "X as a symbol; discourse-graphs keeps types as strings."
  (if (stringp x) (intern x) x))

(defun dg-positions--make-graph (nodes relations)
  "Build a graph from NODES and RELATIONS.
NODES are plists with :id :type :title.  RELATIONS are plists with
:from :type :to.  Returns a plist of hash tables keyed by node id."
  (let ((table (make-hash-table :test #'equal))
        (in (make-hash-table :test #'equal))
        (out (make-hash-table :test #'equal))
        (retired (make-hash-table :test #'equal))
        dangling)
    (dolist (node nodes)
      (puthash (plist-get node :id)
               (list :id (plist-get node :id)
                     :type (dg-positions--sym (plist-get node :type))
                     :title (or (plist-get node :title) ""))
               table))
    (dolist (relation relations)
      (let ((from (plist-get relation :from))
            (to (plist-get relation :to))
            (rel (dg-positions--sym (plist-get relation :type))))
        (if (and (gethash from table) (gethash to table))
            (progn
              (push (cons rel to) (gethash from out))
              (push (cons rel from) (gethash to in))
              (when (dg-positions--rel-opt rel :retires)
                (puthash to t retired)))
          (push relation dangling))))
    (list :nodes table :in in :out out :retired retired
          :relations relations :dangling (nreverse dangling))))

(defun dg-positions--read ()
  "Read the discourse-graphs database into a graph."
  (unless (fboundp 'dg-all-nodes)
    (user-error "discourse-graphs is not loaded"))
  (dg-positions-validate-rules)
  (dg-positions--make-graph (dg-all-nodes) (dg-all-relations)))

(defun dg-positions--visible-p (graph id)
  "Non-nil when node ID is shown in GRAPH (not retired, or retired nodes are on)."
  (or dg-positions-show-retired
      (not (gethash id (plist-get graph :retired)))))

(defun dg-positions--type (graph id)
  "Type symbol of node ID."
  (plist-get (gethash id (plist-get graph :nodes)) :type))

(defun dg-positions--title (graph id)
  "Title of node ID."
  (plist-get (gethash id (plist-get graph :nodes)) :title))

(defun dg-positions--edges (graph id direction)
  "Visible edges of node ID as (REL . OTHER-ID) pairs.
DIRECTION is `in' (edges pointing at ID) or `out' (edges leaving it).
A node that is not shown has no edges."
  (when (dg-positions--visible-p graph id)
    (seq-filter (lambda (edge) (dg-positions--visible-p graph (cdr edge)))
                (gethash id (plist-get graph (if (eq direction 'in) :in :out))))))

(defun dg-positions--ids (graph)
  "Ids of the visible nodes in GRAPH, sorted by title."
  (let (ids)
    (maphash (lambda (id _node)
               (when (dg-positions--visible-p graph id) (push id ids)))
             (plist-get graph :nodes))
    (sort ids (lambda (a b) (string< (dg-positions--title graph a)
                                     (dg-positions--title graph b))))))

(defun dg-positions--questions (graph)
  "Ids of the visible question nodes in GRAPH, sorted by title."
  (seq-filter (lambda (id) (eq (dg-positions--type graph id) dg-positions-question-type))
              (dg-positions--ids graph)))

;;; Statuses and gaps

(defvar dg-positions--graph nil "Graph a condition is being evaluated against.")
(defvar dg-positions--id nil "Node a condition is being evaluated for.")

(defun dg-positions--role-count (graph id role)
  "How many visible relations pointing at ID count as ROLE."
  (cl-count-if (lambda (edge) (eq (dg-positions--rel-opt (car edge) :counts-as) role))
               (dg-positions--edges graph id 'in)))

(defun dg-positions--count-rel (direction rel)
  "Number of REL edges in DIRECTION for the node under evaluation."
  (cl-count rel (dg-positions--edges dg-positions--graph dg-positions--id direction)
            :key #'car))

(defun dg-positions--applies-p (rule graph id)
  "Non-nil when RULE's :for list covers node ID."
  (let ((types (dg-positions--opt rule :for)))
    (or (null types) (memq (dg-positions--type graph id) types))))

(defun dg-positions--quote-relations (form)
  "FORM with the relation names in `(in REL)' and `(out REL)' quoted.
This lets a rule say `(in answers)' instead of `(in (quote answers))'."
  (cond ((and (consp form) (memq (car form) '(in out))
              (proper-list-p form) (= (length form) 2) (symbolp (cadr form)))
         (list (car form) (list 'quote (cadr form))))
        ((proper-list-p form)
         (mapcar #'dg-positions--quote-relations form))
        (t form)))

(defun dg-positions--holds-p (rule graph id)
  "Non-nil when the :when condition of RULE holds for node ID."
  (let ((dg-positions--graph graph)
        (dg-positions--id id))
    (condition-case err
        (eval `(let ((support ,(dg-positions--role-count graph id 'support))
                     (oppose ,(dg-positions--role-count graph id 'oppose))
                     (type ',(dg-positions--type graph id)))
                 (cl-flet ((in (rel) (dg-positions--count-rel 'in rel))
                           (out (rel) (dg-positions--count-rel 'out rel)))
                   ,(dg-positions--quote-relations (dg-positions--opt rule :when))))
              t)
      (error (user-error "dg-positions: rule `%s' failed on \"%s\": %s"
                         (nth 1 rule) (dg-positions--title graph id)
                         (error-message-string err))))))

(defun dg-positions-status-of (graph id)
  "Status symbol of node ID in GRAPH, or nil.
The first status rule that applies and holds wins."
  (cl-loop for rule in (dg-positions--rules 'status)
           when (and (dg-positions--applies-p rule graph id)
                     (dg-positions--holds-p rule graph id))
           return (nth 1 rule)))

(defun dg-positions-gaps-of (graph id)
  "Names of every gap that holds for node ID in GRAPH."
  (cl-loop for rule in (dg-positions--rules 'gap)
           when (and (dg-positions--applies-p rule graph id)
                     (dg-positions--holds-p rule graph id))
           collect (nth 1 rule)))

(defun dg-positions--status-color (status)
  "Fill colour of STATUS."
  (or (when-let* ((rule (dg-positions--rule 'status status)))
        (dg-positions--opt rule :color))
      "white"))

(defun dg-positions--type-color (type)
  "Fill colour of nodes of TYPE."
  (or (when-let* ((rule (dg-positions--rule 'node-type type)))
        (dg-positions--opt rule :color))
      "white"))

(defun dg-positions--short (type)
  "Short label of TYPE."
  (if-let* ((rule (dg-positions--rule 'node-type type)))
      (nth 2 rule)
    (upcase (symbol-name type))))

;;; Tree

(defun dg-positions--children (graph id)
  "Edges (REL . CHILD) shown beneath node ID.
These are the edges pointing at ID, except grounding ones, plus the
grounding edges that leave it.  They are ordered by the order of the
relation rules and then by title."
  (let* ((rels (mapcar #'cadr (dg-positions--rules 'relation)))
         (edges (append
                 (seq-remove (lambda (edge) (dg-positions--rel-opt (car edge) :grounds))
                             (dg-positions--edges graph id 'in))
                 (seq-filter (lambda (edge) (dg-positions--rel-opt (car edge) :grounds))
                             (dg-positions--edges graph id 'out))))
         (rank (lambda (edge) (or (seq-position rels (car edge)) (length rels)))))
    (sort (delete-dups (copy-sequence edges))
          (lambda (a b)
            (let ((ra (funcall rank a)) (rb (funcall rank b)))
              (or (< ra rb)
                  (and (= ra rb)
                       (string< (dg-positions--title graph (cdr a))
                                (dg-positions--title graph (cdr b))))))))))

(defun dg-positions--loose-positions (graph)
  "Ids of nodes that have a status but point at nothing.
These are positions answering no question and supporting no other."
  (seq-filter (lambda (id)
                (and (null (dg-positions--edges graph id 'out))
                     (dg-positions-status-of graph id)))
              (dg-positions--ids graph)))

;;; Outline views

(defun dg-positions--tag (symbol)
  "SYMBOL as a valid Org tag."
  (replace-regexp-in-string "[^[:alnum:]_@#%]" "_" (symbol-name symbol)))

(defun dg-positions--tags (graph id)
  "Org tags for node ID: its status, then its gaps."
  (mapcar #'dg-positions--tag
          (delq nil (cons (dg-positions-status-of graph id)
                          (dg-positions-gaps-of graph id)))))

(defun dg-positions--heading (graph id rel)
  "Heading text for node ID, reached through REL (or nil at the top)."
  (format "%s[[id:%s][%s]] (%s)"
          (if rel (format "[%s] " rel) "")
          id
          (replace-regexp-in-string "[][]" "" (dg-positions--title graph id))
          (dg-positions--short (dg-positions--type graph id))))

(defun dg-positions--summary (graph id)
  "Count of the children of ID by status, as text, or nil when none has one.
Statuses are listed in the order of their rules."
  (let ((statuses (mapcar (lambda (edge) (dg-positions-status-of graph (cdr edge)))
                          (dg-positions--children graph id)))
        parts)
    (dolist (rule (dg-positions--rules 'status))
      (let ((n (cl-count (nth 1 rule) statuses)))
        (when (> n 0)
          (push (format "%d %s" n (nth 1 rule)) parts))))
    (when parts
      (concat " {" (string-join (nreverse parts) ", ") "}"))))

(defun dg-positions--insert-line (graph id rel depth)
  "Insert the heading line for node ID at DEPTH stars."
  (let ((kids (dg-positions--children graph id))
        (tags (dg-positions--tags graph id)))
    (insert (make-string depth ?*) " " (dg-positions--heading graph id rel))
    (when kids
      (insert (format " [%d]" (length kids))))
    (when-let* ((summary (and (eq (dg-positions--type graph id) dg-positions-question-type)
                             (dg-positions--summary graph id))))
      (insert summary))
    (when tags
      (insert " :" (string-join tags ":") ":"))
    (insert "\n")))

(defun dg-positions--insert-outline (graph id rel depth seen)
  "Insert node ID and everything beneath it as Org headings at DEPTH.
SEEN holds the ids above it, and guards against cycles."
  (dg-positions--insert-line graph id rel depth)
  (if (member id seen)
      (insert (make-string (1+ depth) ?*) " cycle back to this note\n")
    (dolist (edge (dg-positions--children graph id))
      (dg-positions--insert-outline graph (cdr edge) (car edge) (1+ depth)
                                    (cons id seen)))))

(defun dg-positions--render-outline (graph buffer-name &optional status)
  "Show GRAPH in BUFFER-NAME as an outline, limited to STATUS when given.
The status limits the answers listed under each question, and the
positions that answer none."
  (let ((buf (get-buffer-create buffer-name)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (org-mode)
        (dolist (question (dg-positions--questions graph))
          (let* ((answers (dg-positions--children graph question))
                 (shown (if status
                            (seq-filter (lambda (edge)
                                          (eq (dg-positions-status-of graph (cdr edge)) status))
                                        answers)
                          answers)))
            (when (or shown (not status))
              (dg-positions--insert-line graph question nil 1)
              (dolist (edge shown)
                (dg-positions--insert-outline graph (cdr edge) (car edge) 2
                                              (list question))))))
        (let ((loose (seq-filter (lambda (id)
                                   (or (null status)
                                       (eq (dg-positions-status-of graph id) status)))
                                 (dg-positions--loose-positions graph))))
          (when loose
            (insert "* Positions that answer no question\n")
            (dolist (id loose)
              (dg-positions--insert-outline graph id nil 2 nil))))
        (goto-char (point-min))
        (org-content 2))
      (setq buffer-read-only t))
    (pop-to-buffer buf)))

;;;###autoload
(defun dg-positions-outline ()
  "Show every question with its answers, evidence and sources as an Org outline."
  (interactive)
  (dg-positions--render-outline (dg-positions--read) "*dg positions*"))

;;;###autoload
(defun dg-positions-status (status)
  "Show only the answers whose status is STATUS, grouped by question."
  (interactive
   (list (intern (completing-read
                  "Status: "
                  (mapcar (lambda (rule) (symbol-name (nth 1 rule)))
                          (dg-positions--rules 'status))
                  nil t))))
  (dg-positions--render-outline (dg-positions--read)
                                (format "*dg positions: %s*" status)
                                status))

;;; Gaps view

;;;###autoload
(defun dg-positions-gaps ()
  "List what each node still lacks, one section per gap."
  (interactive)
  (let* ((graph (dg-positions--read))
         (buf (get-buffer-create "*dg positions: gaps*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (org-mode)
        (dolist (rule (dg-positions--rules 'gap))
          (let ((ids (seq-filter
                      (lambda (id) (memq (nth 1 rule) (dg-positions-gaps-of graph id)))
                      (dg-positions--ids graph))))
            (when ids
              (insert (format "* %s: %s [%d]\n" (nth 1 rule)
                              (or (dg-positions--opt rule :text) "") (length ids)))
              (dolist (id ids)
                (insert (format "- %s\n" (dg-positions--heading graph id nil)))))))
        (when (zerop (buffer-size))
          (insert "No gaps.\n"))
        (goto-char (point-min))
        (org-content 2))
      (setq buffer-read-only t))
    (pop-to-buffer buf)))

;;; Graph view

(defun dg-positions--quote (string)
  "STRING as a Graphviz quoted string; a newline becomes a line break."
  (concat "\""
          (replace-regexp-in-string
           "\n" "\\\\n"
           (replace-regexp-in-string "\"" "\\\\\""
                                     (replace-regexp-in-string "\\\\" "\\\\\\\\" string)))
          "\""))

(defun dg-positions--wrap (string width)
  "STRING with line breaks so that lines are about WIDTH characters."
  (let (lines (line ""))
    (dolist (word (split-string string))
      (if (and (> (length line) 0) (> (+ (length line) 1 (length word)) width))
          (progn (push line lines) (setq line word))
        (setq line (if (string-empty-p line) word (concat line " " word)))))
    (push line lines)
    (string-join (nreverse lines) "\n")))

(defun dg-positions--dot-node (graph id)
  "Graphviz line for node ID."
  (let* ((type (dg-positions--type graph id))
         (status (dg-positions-status-of graph id))
         (head (if status
                   (format "%s · %s" (dg-positions--short type) status)
                 (dg-positions--short type))))
    (format "    %s [label=%s, fillcolor=%s%s];\n"
            (dg-positions--quote id)
            (dg-positions--quote
             (concat head "\n" (dg-positions--wrap (dg-positions--title graph id) 28)))
            (dg-positions--quote (if status
                                     (dg-positions--status-color status)
                                   (dg-positions--type-color type)))
            (if (eq type dg-positions-question-type) ", penwidth=2" ""))))

(defun dg-positions--dot-edge (graph from rel to)
  "Graphviz line for the edge FROM -REL-> TO."
  (let ((reverse dg-positions-question-first)
        (color (or (dg-positions--rel-opt rel :color) "gray40"))
        (style (or (dg-positions--rel-opt rel :style) 'solid)))
    (ignore graph)
    (format "  %s -> %s [label=%s, color=%s, fontcolor=%s, style=%s, fontsize=9%s];\n"
            (dg-positions--quote (if reverse to from))
            (dg-positions--quote (if reverse from to))
            (dg-positions--quote (symbol-name rel))
            (dg-positions--quote color)
            (dg-positions--quote color)
            (dg-positions--quote (format "%s" style))
            (if reverse ", dir=back" ""))))

(defun dg-positions--reach (graph root drawn)
  "Ids beneath ROOT in GRAPH that are not yet in the hash table DRAWN.
They are added to DRAWN."
  (let ((queue (list root)) ids)
    (while queue
      (let ((id (pop queue)))
        (unless (gethash id drawn)
          (puthash id t drawn)
          (push id ids)
          (setq queue (append queue (mapcar #'cdr (dg-positions--children graph id)))))))
    (nreverse ids)))

(defun dg-positions--dot (graph)
  "Return Graphviz source for GRAPH, one cluster per question."
  (let ((drawn (make-hash-table :test #'equal))
        (n 0))
    (with-temp-buffer
      (insert "digraph positions {\n"
              (format "  rankdir=%s;\n" dg-positions-rankdir)
              "  node [shape=box, style=\"rounded,filled\", fontname=\"Helvetica\"];\n"
              "  edge [fontname=\"Helvetica\"];\n")
      (dolist (question (dg-positions--questions graph))
        (insert (format "  subgraph cluster_%d {\n    style=\"rounded\"; color=\"#bbbbbb\"; label=%s;\n"
                        (cl-incf n)
                        (dg-positions--quote (dg-positions--wrap
                                              (dg-positions--title graph question) 60))))
        (dolist (id (dg-positions--reach graph question drawn))
          (insert (dg-positions--dot-node graph id)))
        (insert "  }\n"))
      (let ((rest (seq-filter
                   (lambda (id)
                     (and (not (gethash id drawn))
                          (or dg-positions-show-isolated
                              (dg-positions--edges graph id 'in)
                              (dg-positions--edges graph id 'out))))
                   (dg-positions--ids graph))))
        (when rest
          (insert (format "  subgraph cluster_%d {\n    style=\"rounded,dashed\"; color=\"#bbbbbb\"; label=\"Under no question\";\n"
                          (cl-incf n)))
          (dolist (id rest)
            (puthash id t drawn)
            (insert (dg-positions--dot-node graph id)))
          (insert "  }\n")))
      (dolist (id (dg-positions--ids graph))
        (when (gethash id drawn)
          (dolist (edge (dg-positions--edges graph id 'out))
            (when (gethash (cdr edge) drawn)
              (insert (dg-positions--dot-edge graph id (car edge) (cdr edge)))))))
      (insert "}\n")
      (buffer-string))))

;;;###autoload
(defun dg-positions-graph ()
  "Render the positions with Graphviz and display the SVG."
  (interactive)
  (unless (executable-find "dot")
    (user-error "Graphviz `dot' not found on PATH"))
  (let ((dot (dg-positions--dot (dg-positions--read))))
    (with-temp-buffer
      (insert dot)
      (unless (zerop (call-process-region (point-min) (point-max) "dot" nil t nil
                                          "-Tsvg" "-o" dg-positions-graph-file))
        (error "Graphviz failed: %s" (buffer-string))))
    (let ((buf (find-file-noselect dg-positions-graph-file)))
      (with-current-buffer buf
        (revert-buffer t t))
      (pop-to-buffer buf))))

;;; Check

;;;###autoload
(defun dg-positions-check ()
  "List relations without a rule, dangling edges and unexpected type pairs."
  (interactive)
  (let* ((graph (dg-positions--read))
         (nodes (plist-get graph :nodes))
         (unknown nil) (odd nil))
    (dolist (relation (plist-get graph :relations))
      (let ((rel (dg-positions--sym (plist-get relation :type))))
        (unless (dg-positions--rule 'relation rel)
          (cl-pushnew rel unknown))))
    (maphash
     (lambda (from node)
       (dolist (edge (gethash from (plist-get graph :out)))
         (let ((from-types (dg-positions--rel-opt (car edge) :from))
               (to-types (dg-positions--rel-opt (car edge) :to))
               (to-type (dg-positions--type graph (cdr edge))))
           (when (or (and from-types (not (memq (plist-get node :type) from-types)))
                     (and to-types (not (memq to-type to-types))))
             (push (list from (car edge) (cdr edge)) odd)))))
     nodes)
    (let ((buf (get-buffer-create "*dg positions: check*")))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (erase-buffer)
          (org-mode)
          (insert "* Relations without a rule\n")
          (if unknown
              (dolist (rel unknown)
                (insert (format "- %s (add a (relation %s \"Inverse Label\" ...) rule)\n" rel rel)))
            (insert "None.\n"))
          (insert "* Edges to nodes that no longer exist\n")
          (if (plist-get graph :dangling)
              (dolist (relation (plist-get graph :dangling))
                (insert (format "- %s -%s-> %s\n" (plist-get relation :from)
                                (plist-get relation :type) (plist-get relation :to))))
            (insert "None.\n"))
          (insert "* Edges between unexpected types\n")
          (if odd
              (dolist (edge (nreverse odd))
                (insert (format "- %s -%s-> %s\n"
                                (dg-positions--heading graph (nth 0 edge) nil)
                                (nth 1 edge)
                                (dg-positions--heading graph (nth 2 edge) nil))))
            (insert "None.\n"))
          (goto-char (point-min)))
        (setq buffer-read-only t))
      (pop-to-buffer buf))))

;;; Registering with discourse-graphs

;;;###autoload
(defun dg-positions-install ()
  "Copy node types and relations from `dg-positions-rules' into discourse-graphs.
Entries discourse-graphs already has are left alone.  Run
`dg-rebuild-cache' afterwards so that the new relations are read."
  (interactive)
  (dg-positions-validate-rules)
  (dolist (rule (dg-positions--rules 'node-type))
    (unless (assq (nth 1 rule) dg-node-types)
      (setq dg-node-types
            (append dg-node-types
                    (list (cons (nth 1 rule)
                                (list :short (nth 2 rule)
                                      :color (or (dg-positions--opt rule :color) "white")
                                      :desc (or (dg-positions--opt rule :desc) ""))))))))
  (dolist (rule (dg-positions--rules 'relation))
    (let ((name (nth 1 rule)))
      (unless (assq name dg-relation-types)
        (setq dg-relation-types
              (append dg-relation-types
                      (list (cons name (list :inverse (nth 2 rule)
                                             :color (or (dg-positions--opt rule :color) "gray")
                                             :style (format "%s" (or (dg-positions--opt rule :style)
                                                                     'solid))))))))
      (when (and (boundp 'dg--relation-map)
                 (not (assoc (nth 2 rule) dg--relation-map)))
        (setq dg--relation-map
              (append dg--relation-map
                      (list (cons (nth 2 rule) (list :rel (symbol-name name) :dir 'incoming))
                            (cons (symbol-name name) (list :rel (symbol-name name) :dir 'outgoing))))))
      (when (and (not (assq name dg-relation-patterns))
                 (or (dg-positions--opt rule :from) (dg-positions--opt rule :to)))
        (setq dg-relation-patterns
              (append dg-relation-patterns
                      (list (cons name (list :source (dg-positions--opt rule :from)
                                             :target (dg-positions--opt rule :to)))))))))
  (when (called-interactively-p 'interactive)
    (message "dg-positions: rules registered; run M-x dg-rebuild-cache to re-read the notes")))

(with-eval-after-load 'discourse-graphs
  (dg-positions-install))

(provide 'sp-dg-positions)
;;; sp-dg-positions.el ends here
