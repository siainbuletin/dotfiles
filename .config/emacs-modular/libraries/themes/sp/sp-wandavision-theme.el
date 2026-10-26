;;; sp-wandavision-theme.el --- wandavision palette, imported -*- lexical-binding: t; -*-

;;; Commentary:

;; Made by `sp-theme-import-palette'.  The colours are the palette below;
;; change them and load the theme again.

;;; Code:

(require 'sp-theme-engine)

(unless (assq 'wandavision sp-theme-flavors)
  (push (cons 'wandavision
              (sp-theme-flavor-from-palette
               '("#2a3156" "#8f8280" "#4e5044" "#8a4160" "#8d2025")
               :variant 'dark
               :roles nil))
        sp-theme-flavors))

(sp-theme-define sp-wandavision wandavision "wandavision palette, imported")

(provide 'sp-wandavision-theme)
;;; sp-wandavision-theme.el ends here
