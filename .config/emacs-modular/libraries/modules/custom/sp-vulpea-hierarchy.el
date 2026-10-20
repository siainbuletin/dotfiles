;;; sp-vulpea-hierarchy.el --- Parent/child views of vulpea notes -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "29.1") (vulpea "2.7.0"))

;;; Commentary:

;; Builds a hierarchy from a parent link in each note's metadata and
;; shows part of it, starting from a note you choose:
;;
;;   M-x vulpea-hierarchy-graph   interactive graph in the browser (default)
;;   M-x vulpea-hierarchy-outline buttons in an Emacs buffer
;;   M-x vulpea-hierarchy-svg     static Graphviz SVG (needs `dot')
;;
;; Each command first asks for a starting note and a depth.  The depth
;; counts levels below the starting note.  Notes at the last level show
;; how many children they hide.  The browser graph can't load more, so
;; run the command again with a bigger depth.  The outline expands any
;; node on demand.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'json)
(require 'vulpea)
(require 'vulpea-select)

(defgroup vulpea-hierarchy nil
  "Parent/child views of vulpea notes."
  :group 'vulpea)

(defcustom vulpea-hierarchy-parent-key "parents"
  "Metadata key that holds a note's parent link."
  :type 'string)

(defcustom vulpea-hierarchy-default-depth 2
  "Depth offered by default when choosing how far to show the hierarchy."
  :type 'integer)

(defcustom vulpea-hierarchy-html-file
  (expand-file-name "vulpea-hierarchy.html" sp-cache-dir)
  "Where `vulpea-hierarchy-graph' writes its HTML page."
  :type 'file)

(defcustom vulpea-hierarchy-graph-file
  (expand-file-name "vulpea-hierarchy.svg" sp-cache-dir)
  "Where `vulpea-hierarchy-svg' writes its SVG."
  :type 'file)

(defcustom vulpea-hierarchy-rankdir "LR"
  "Graphviz layout direction: \"LR\" (left to right) or \"TB\" (top down)."
  :type '(choice (const "LR") (const "TB")))

;;;; Tree and scope

(defun vulpea-hierarchy--note (id notes)
  "Return the note with ID from NOTES, loading it from the database if needed."
  (or (gethash id notes)
      (when-let ((note (vulpea-db-get-by-id id)))
        (puthash id note notes)
        note)))

(defun vulpea-hierarchy--title (id notes)
  "Title of note ID from NOTES, or a marker for a dangling link."
  (if-let ((note (vulpea-hierarchy--note id notes)))
      (vulpea-note-title note)
    (format "<missing %s>" id)))

(defun vulpea-hierarchy--build ()
  "Return a plist describing the whole hierarchy.
:notes maps id to note, :children maps parent id to child ids,
:roots lists ids that are parents but have no parent themselves."
  (let ((notes (make-hash-table :test #'equal))
        (children (make-hash-table :test #'equal))
        (has-parent (make-hash-table :test #'equal))
        parent-ids)
    (dolist (note (vulpea-db-query-by-meta-key vulpea-hierarchy-parent-key))
      (puthash (vulpea-note-id note) note notes)
      (dolist (pid (vulpea-note-meta-get-list
                    note vulpea-hierarchy-parent-key 'link))
        (puthash (vulpea-note-id note) t has-parent)
        (push (vulpea-note-id note) (gethash pid children))
        (push pid parent-ids)))
    ;; Parents that carry no parent key themselves are not loaded yet.
    (dolist (note (vulpea-db-query-by-ids
                   (seq-remove (lambda (id) (gethash id notes))
                               (delete-dups parent-ids))))
      (puthash (vulpea-note-id note) note notes))
    (list :notes notes
          :children children
          :roots (sort (seq-remove (lambda (id) (gethash id has-parent))
                                   (delete-dups (copy-sequence parent-ids)))
                       (lambda (a b)
                         (string< (vulpea-hierarchy--title a notes)
                                  (vulpea-hierarchy--title b notes)))))))

(defun vulpea-hierarchy--sorted-children (id tree)
  "Child ids of ID in TREE, sorted by title."
  (let ((notes (plist-get tree :notes)))
    (sort (copy-sequence (gethash id (plist-get tree :children)))
          (lambda (a b)
            (string< (vulpea-hierarchy--title a notes)
                     (vulpea-hierarchy--title b notes))))))

(defun vulpea-hierarchy--scope (tree start depth)
  "Return the part of TREE reached from START within DEPTH levels.
The result has the same keys as the tree, plus :more, which maps an
id at the last level to how many children it hides, and :nodes, the
ids in scope.  :roots is just (START)."
  (let ((notes (plist-get tree :notes))
        (children (make-hash-table :test #'equal))
        (more (make-hash-table :test #'equal))
        (seen (make-hash-table :test #'equal))
        (nodes (list start))
        (queue (list (cons start 0))))
    (puthash start t seen)
    (while queue
      (pcase-let ((`(,id . ,level) (pop queue)))
        (let ((kids (vulpea-hierarchy--sorted-children id tree)))
          (if (< level depth)
              (dolist (kid kids)
                (puthash id (append (gethash id children) (list kid)) children)
                (unless (gethash kid seen)
                  (puthash kid t seen)
                  (push kid nodes)
                  (setq queue (append queue (list (cons kid (1+ level)))))))
            (when kids
              (puthash id (length kids) more))))))
    (list :notes notes
          :children children
          :more more
          :roots (list start)
          :nodes (nreverse nodes))))

(defun vulpea-hierarchy--read-scope ()
  "Ask for a starting note and a depth.  Return (START-ID . DEPTH)."
  (let* ((note (vulpea-select "Start note: " :require-match t))
         (depth (read-number "Depth: " vulpea-hierarchy-default-depth)))
    (unless (and note (vulpea-note-id note) (>= depth 1))
      (user-error "Need a starting note and a depth of at least 1"))
    (cons (vulpea-note-id note) (truncate depth))))

;;;; Browser view

(defconst vulpea-hierarchy--html-template
  "<!doctype html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">
<title>vulpea hierarchy</title>
<style>
:root{--bg:#fbfbfa;--fg:#222;--muted:#777;--node:#f2f2f0;--edge:#9a9a9a;--root:#d8e6f5}
@media (prefers-color-scheme: dark){:root:not([data-theme=\"light\"]){--bg:#1d1f21;--fg:#e6e6e6;--muted:#999;--node:#2a2d31;--edge:#666;--root:#2f4a66}}
:root[data-theme=\"dark\"]{--bg:#1d1f21;--fg:#e6e6e6;--muted:#999;--node:#2a2d31;--edge:#666;--root:#2f4a66}
html,body{margin:0;height:100%;background:var(--bg);color:var(--fg);font:14px system-ui,sans-serif}
header{height:22px;padding:8px 12px;color:var(--muted);border-bottom:1px solid var(--edge);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
svg{position:absolute;top:38px;left:0;width:100%;height:calc(100% - 38px);cursor:grab;touch-action:none}
.node rect{fill:var(--node);stroke:var(--edge)}
.node.root rect{fill:var(--root)}
.node text{fill:var(--fg);pointer-events:none}
.node .more{fill:var(--muted)}
.edge{fill:none;stroke:var(--edge);stroke-width:1.2}
</style>
</head>
<body>
<header id=\"head\"></header>
<svg id=\"v\" xmlns=\"http://www.w3.org/2000/svg\"><g id=\"vp\"></g></svg>
<script>
const D = __DATA__;
const NS = 'http://www.w3.org/2000/svg';
const W = 240, H = 34, GAP = 10, COL = 300;
const byId = new Map(D.nodes.map(n => [n.id, n]));
const kids = new Map();
for (const [p, c] of D.edges) { if (!kids.has(p)) kids.set(p, []); kids.get(p).push(c); }
const collapsed = new Set();
const view = { x: 40, y: 20, k: 1 };
const vp = document.getElementById('vp');
const svg = document.getElementById('v');
let dragStart = null, dragged = false;

document.getElementById('head').textContent =
  (byId.get(D.root) || {}).title + '  ·  depth ' + D.depth +
  '  ·  click a box to fold  ·  scroll to zoom, drag to pan  ·  +N = hidden children (rerun with a bigger depth)';

function trim(s) { return s.length > 34 ? s.slice(0, 33) + '…' : s; }

function el(tag, attrs, parent) {
  const e = document.createElementNS(NS, tag);
  for (const k in attrs) e.setAttribute(k, attrs[k]);
  parent.appendChild(e);
  return e;
}

function childrenOf(id) { return collapsed.has(id) ? [] : (kids.get(id) || []); }

function layout(id, depth, path, row) {
  const node = { id, depth, kids: [], y: 0 };
  if (!path.includes(id)) {
    for (const c of childrenOf(id)) node.kids.push(layout(c, depth + 1, [...path, id], row));
  }
  if (node.kids.length) node.y = node.kids.reduce((s, k) => s + k.y, 0) / node.kids.length;
  else node.y = row.n++ * (H + GAP);
  return node;
}

function draw(node, parent) {
  const n = byId.get(node.id) || { title: node.id, path: null, more: 0 };
  const x = node.depth * COL, y = node.y;
  if (parent) {
    const px = parent.x + W, py = parent.y + H / 2;
    el('path', { class: 'edge', d: `M${px},${py} C${px + 40},${py} ${x - 40},${y + H / 2} ${x},${y + H / 2}` }, vp);
  }
  const g = el('g', { class: 'node' + (node.id === D.root ? ' root' : ''), transform: `translate(${x},${y})` }, vp);
  const t = el('text', { x: 10, y: 22 }, g);
  t.textContent = trim(n.title);
  el('title', {}, g).textContent = n.path || n.title;
  if (n.more) {
    const m = el('text', { class: 'more', x: W - 10, y: 22, 'text-anchor': 'end' }, g);
    m.textContent = '+' + n.more;
  }
  el('rect', { width: W, height: H, rx: 6 }, g);
  g.insertBefore(g.lastElementChild, g.firstChild);
  if ((kids.get(node.id) || []).length) {
    g.style.cursor = 'pointer';
    g.addEventListener('click', () => {
      if (dragged) return;
      if (collapsed.has(node.id)) collapsed.delete(node.id); else collapsed.add(node.id);
      render();
    });
  }
  for (const k of node.kids) draw(k, { x, y });
}

function render() {
  vp.replaceChildren();
  draw(layout(D.root, 0, [], { n: 0 }), null);
  apply();
}

function apply() {
  vp.setAttribute('transform', `translate(${view.x},${view.y}) scale(${view.k})`);
}

svg.addEventListener('wheel', e => {
  e.preventDefault();
  view.k = Math.min(4, Math.max(0.2, view.k * (e.deltaY < 0 ? 1.1 : 1 / 1.1)));
  apply();
}, { passive: false });
svg.addEventListener('pointerdown', e => {
  dragStart = { x: e.clientX - view.x, y: e.clientY - view.y, cx: e.clientX, cy: e.clientY };
  dragged = false;
  svg.setPointerCapture(e.pointerId);
});
svg.addEventListener('pointermove', e => {
  if (!dragStart) return;
  if (Math.hypot(e.clientX - dragStart.cx, e.clientY - dragStart.cy) > 4) dragged = true;
  view.x = e.clientX - dragStart.x;
  view.y = e.clientY - dragStart.y;
  apply();
});
svg.addEventListener('pointerup', () => { dragStart = null; });
render();
</script>
</body>
</html>
"
  "Template for `vulpea-hierarchy--html'.  `__DATA__' is replaced with JSON.")

(defun vulpea-hierarchy--json-for-html (object)
  "Encode OBJECT as JSON that is safe inside a <script> element."
  (let ((json-encoding-pretty-print nil))
    (thread-last (json-encode object)
                 (string-replace "<" "\\u003c")
                 (string-replace ">" "\\u003e")
                 (string-replace "&" "\\u0026"))))

(defun vulpea-hierarchy--html (scope start depth)
  "Return a self-contained HTML page showing SCOPE from START to DEPTH."
  (let* ((notes (plist-get scope :notes))
         (nodes
          (vconcat
           (mapcar
            (lambda (id)
              (let ((note (vulpea-hierarchy--note id notes)))
                `((id . ,id)
                  (title . ,(vulpea-hierarchy--title id notes))
                  (path . ,(and note (vulpea-note-path note)))
                  (more . ,(gethash id (plist-get scope :more) 0)))))
            (plist-get scope :nodes))))
         (edges
          (vconcat
           (cl-loop for (parent . kids) in
                    (let (acc)
                      (maphash (lambda (k v) (push (cons k v) acc))
                               (plist-get scope :children))
                      acc)
                    append (mapcar (lambda (kid) (vector parent kid)) kids))))
         (data `((root . ,start)
                 (depth . ,depth)
                 (nodes . ,nodes)
                 (edges . ,edges))))
    (string-replace "__DATA__" (vulpea-hierarchy--json-for-html data)
                    vulpea-hierarchy--html-template)))


;;;###autoload
(defun vulpea-hierarchy-graph ()
  "Ask for a starting note and depth, then open the hierarchy in the browser."
  (interactive)
  (pcase-let* ((`(,start . ,depth) (vulpea-hierarchy--read-scope))
               (scope (vulpea-hierarchy--scope (vulpea-hierarchy--build) start depth)))
    (let ((coding-system-for-write 'utf-8))
      (with-temp-file vulpea-hierarchy-html-file
        (insert (vulpea-hierarchy--html scope start depth))))
    (browse-url-of-file vulpea-hierarchy-html-file)))

;;;; Native outline view

(defvar-local vulpea-hierarchy--tree nil
  "Full hierarchy shown in this buffer.")

(defvar-local vulpea-hierarchy--expanded nil
  "Hash table of ids whose children are shown.")

(defvar-local vulpea-hierarchy--start nil
  "Id of the note the outline starts from.")

(defvar-local vulpea-hierarchy--depth 2
  "Depth shown when the outline was opened.")

(defvar vulpea-hierarchy-view-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "TAB") #'vulpea-hierarchy-view-toggle)
    (define-key map (kbd "c") #'vulpea-hierarchy-view-recenter)
    (define-key map (kbd "g") #'vulpea-hierarchy-view-redraw)
    map)
  "Keymap for `vulpea-hierarchy-view-mode'.")

(define-derived-mode vulpea-hierarchy-view-mode special-mode "Hierarchy"
  "Major mode for the native vulpea hierarchy outline.
TAB or a [+]/[-] button expands or collapses a note.  RET on a
title visits the note.  c re-scopes, g rebuilds the view.")

(defun vulpea-hierarchy-view--expand-to-depth ()
  "Expand every node in the view above the starting depth."
  (let ((queue (list (cons vulpea-hierarchy--start 0))))
    (while queue
      (pcase-let ((`(,id . ,level) (pop queue)))
        (when (and (< level vulpea-hierarchy--depth)
                   (vulpea-hierarchy--sorted-children id vulpea-hierarchy--tree))
          (puthash id t vulpea-hierarchy--expanded)
          (dolist (kid (vulpea-hierarchy--sorted-children id vulpea-hierarchy--tree))
            (push (cons kid (1+ level)) queue)))))))

(defun vulpea-hierarchy-view--insert (id level path)
  "Insert the line for ID at indent LEVEL, then its children if expanded.
PATH holds the ancestors, so a cycle stops the recursion."
  (let* ((tree vulpea-hierarchy--tree)
         (notes (plist-get tree :notes))
         (kids (vulpea-hierarchy--sorted-children id tree))
         (open (and kids (gethash id vulpea-hierarchy--expanded)))
         (note (vulpea-hierarchy--note id notes)))
    (let ((start (point)))
      (insert (make-string (* 2 level) ?\s))
      (vulpea-hierarchy-view--insert-line-body id kids open note)
      (put-text-property start (point) 'vulpea-hierarchy-id id))
    (insert "\n")
    (when (and open (not (member id path)))
      (dolist (kid kids)
        (vulpea-hierarchy-view--insert kid (1+ level) (cons id path))))))

(defun vulpea-hierarchy-view--insert-line-body (id kids open note)
  "Insert the toggle and title buttons of ID's line, then its child count."
  (let ((notes (plist-get vulpea-hierarchy--tree :notes)))
    (if kids
        (insert-button (if open "[-]" "[+]")
                       'action #'vulpea-hierarchy-view--button-action
                       'follow-link t
                       'help-echo "Expand or collapse"
                       'vulpea-hierarchy-id id
                       'vulpea-hierarchy-kind 'toggle)
      (insert "   "))
    (insert " ")
    (insert-button (vulpea-hierarchy--title id notes)
                   'action #'vulpea-hierarchy-view--button-action
                   'follow-link t
                   'help-echo (or (and note (vulpea-note-path note)) "")
                   'vulpea-hierarchy-id id
                   'vulpea-hierarchy-kind 'visit)
    (when kids (insert (format "  (%d)" (length kids))))))

(defun vulpea-hierarchy-view--redraw ()
  "Erase the buffer and draw the view from its current state."
  (let ((inhibit-read-only t)
        (line (line-number-at-pos)))
    (erase-buffer)
    (insert (propertize (format "%s  ·  depth %d  ·  TAB expand  RET visit  c re-scope  g rebuild\n\n"
                                (vulpea-hierarchy--title
                                 vulpea-hierarchy--start
                                 (plist-get vulpea-hierarchy--tree :notes))
                                vulpea-hierarchy--depth)
                        'face 'shadow))
    (vulpea-hierarchy-view--insert vulpea-hierarchy--start 0 nil)
    (goto-char (point-min))
    (forward-line (max 0 (1- line)))))

(defun vulpea-hierarchy-view--button-action (button)
  "Expand or visit the note of BUTTON, depending on its kind."
  (let ((id (button-get button 'vulpea-hierarchy-id)))
    (pcase (button-get button 'vulpea-hierarchy-kind)
      ('toggle
       (if (gethash id vulpea-hierarchy--expanded)
           (remhash id vulpea-hierarchy--expanded)
         (puthash id t vulpea-hierarchy--expanded))
       (vulpea-hierarchy-view--redraw))
      ('visit
       (let ((note (vulpea-hierarchy--note id (plist-get vulpea-hierarchy--tree :notes))))
         (unless note (user-error "Note %s is not in the database" id))
         (find-file (vulpea-note-path note))
         (when (vulpea-note-pos note)
           (goto-char (vulpea-note-pos note))))))))

(defun vulpea-hierarchy-view-toggle ()
  "Expand or collapse the note at point."
  (interactive)
  (when-let ((id (get-text-property (point) 'vulpea-hierarchy-id)))
    (when (vulpea-hierarchy--sorted-children id vulpea-hierarchy--tree)
      (if (gethash id vulpea-hierarchy--expanded)
          (remhash id vulpea-hierarchy--expanded)
        (puthash id t vulpea-hierarchy--expanded))
      (vulpea-hierarchy-view--redraw))))

(defun vulpea-hierarchy-view-redraw ()
  "Rebuild the tree from the database and redraw."
  (interactive)
  (setq vulpea-hierarchy--tree (vulpea-hierarchy--build))
  (vulpea-hierarchy-view--expand-to-depth)
  (vulpea-hierarchy-view--redraw))

(defun vulpea-hierarchy-view-recenter ()
  "Ask for a new starting note and depth, then redraw."
  (interactive)
  (pcase-let ((`(,start . ,depth) (vulpea-hierarchy--read-scope)))
    (setq vulpea-hierarchy--start start
          vulpea-hierarchy--depth depth
          vulpea-hierarchy--expanded (make-hash-table :test #'equal))
    (vulpea-hierarchy-view--expand-to-depth)
    (vulpea-hierarchy-view--redraw)))

;;;###autoload
(defun vulpea-hierarchy-outline ()
  "Ask for a starting note and depth, then show the hierarchy as buttons."
  (interactive)
  (pcase-let ((`(,start . ,depth) (vulpea-hierarchy--read-scope)))
    (let ((buf (get-buffer-create "*vulpea hierarchy*")))
      (with-current-buffer buf
        (vulpea-hierarchy-view-mode)
        (setq vulpea-hierarchy--tree (vulpea-hierarchy--build)
              vulpea-hierarchy--start start
              vulpea-hierarchy--depth depth
              vulpea-hierarchy--expanded (make-hash-table :test #'equal))
        (vulpea-hierarchy-view--expand-to-depth)
        (vulpea-hierarchy-view--redraw))
      (pop-to-buffer buf))))

;;;; Static SVG export (Graphviz)

(defun vulpea-hierarchy--dot (tree)
  "Return Graphviz source for TREE, one cluster per root."
  (let ((notes (plist-get tree :notes))
        (children (plist-get tree :children))
        (drawn (make-hash-table :test #'equal)))
    (with-temp-buffer
      (insert "digraph vulpea {\n"
              (format "  rankdir=%s;\n" vulpea-hierarchy-rankdir)
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
                  (insert (format "    %S [label=%S%s];\n"
                                  id (vulpea-hierarchy--title id notes)
                                  (if (equal id root)
                                      ", fillcolor=\"#d8e6f5\", penwidth=2"
                                    "")))
                  (setq queue (append queue (gethash id children)))))))
          (insert "  }\n")))
      (maphash (lambda (pid kids)
                 (dolist (kid kids)
                   (insert (format "  %S -> %S;\n" pid kid))))
               children)
      (insert "}\n")
      (buffer-string))))

;;;###autoload
(defun vulpea-hierarchy-svg ()
  "Ask for a starting note and depth, then write and show a Graphviz SVG."
  (interactive)
  (unless (executable-find "dot")
    (user-error "Graphviz `dot' not found on PATH"))
  (pcase-let* ((`(,start . ,depth) (vulpea-hierarchy--read-scope))
               (scope (vulpea-hierarchy--scope (vulpea-hierarchy--build) start depth))
               (dot (vulpea-hierarchy--dot scope)))
    (with-temp-buffer
      (insert dot)
      (unless (zerop (call-process-region (point-min) (point-max) "dot" nil t nil
                                          "-Tsvg" "-o" vulpea-hierarchy-graph-file))
        (error "Graphviz failed: %s" (buffer-string))))
    (let ((buf (find-file-noselect vulpea-hierarchy-graph-file)))
      (with-current-buffer buf
        (revert-buffer t t))
      (pop-to-buffer buf))))

(provide 'sp-vulpea-hierarchy)
;;; sp-vulpea-hierarchy.el ends here
