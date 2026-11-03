;;; sp-textui.el --- TextUI widgets and Org table widgets -*- lexical-binding: t; -*-

;;; Commentary:

;; TextUI is a new package that is supposed to provide better
;; rendering for widgets in the buffer.

;;; Code:

(use-package textui
    :ensure (:host github :repo "yibie/textui"))

(use-package org-table-widget
    :ensure (:host github :repo "yibie/org-table-widget"))

(add-hook 'org-mode-hook #'org-table-widget-mode)

(provide 'sp-textui)
;; sp-textui.el ends here.
