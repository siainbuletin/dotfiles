;;; sp-xml.el --- XML editing with nXML -*- lexical-binding: t; -*-

;;; Commentary:

;; A one-form module that configures the built-in `nxml-mode' for XML schema
;; and stylesheet files. It ends with `(provide 'sp-xml)', but it is not listed
;; in any profile in `init.el' or `sp-config-profiles.el', so it appears to be
;; unused at present.

;;; Code:

(use-package nxml-mode
  :ensure nil
  :defer t
  :mode (("\\.xsd\\'" . nxml-mode)
         ("\\.xslt\\'" . nxml-mode))
  :hook (nxml-mode . (lambda ()
	               (make-local-variable 'indent-tabs-mode)
	               (setq indent-tabs-mode nil)
	               (add-to-list 'rng-schema-locating-files
			            "~/.emacs.d/nxml-schemas/schemas.xml"))))

(provide 'sp-xml)
