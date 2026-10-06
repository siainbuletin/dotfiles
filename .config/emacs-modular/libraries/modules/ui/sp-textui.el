;; -*- lexical-binding: t; -*-

;; Better rendering for widgets
(require 'textui)

(require 'org-table-widget)
(add-hook 'org-mode-hook #'org-table-widget-mode)