;;; sp-dyn-graph.el --- Interactive note graph for Vulpea -*- lexical-binding: t; -*-

;;; Commentary:

;;

;;; Code:

(use-package vulpea-graph
  :ensure (:host github :repo "Arenile/vulpea-graph-ui" :files ("*.el" "assets"))
  :after (websocket simple-httpd)
  :commands
  (vulpea-graph vulpea-graph-mode))

(provide 'sp-dyn-graph)
;; sp-dyn-graph.el ends here.
