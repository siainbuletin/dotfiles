;;; sp-globals.el --- My most important settings, in one place -*- lexical-binding: t; -*-

;;; Commentary:

;; The settings that are mine rather than a package's: which credentials file
;; Emacs reads, and so on.  They sit here, not in the module that happens to
;; use them, so that this is the one file to open when one of them has to
;; change.  `sp-paths' does the same for locations.
;;
;; Each setting is a `defcustom' in the `spcustom' group whose :set function
;; also applies it to the variable it controls, so editing the default below
;; and changing it with Customize have the same effect.  Load it right after
;; `sp-paths', before any module that reads one of these.

;;; Code:

(defcustom sp-auth-sources '("~/.authinfo")
  "Where Emacs looks for credentials, as in `auth-sources'.
The default is the plain-text file ~/.authinfo only, so ~/.authinfo.gpg and
the keychain are not read.  Forge, for example, takes its GitHub token from
here."
  :type '(repeat sexp)
  :set (lambda (symbol value)
         (set-default symbol value)
         (setq auth-sources value))
  :group 'spcustom)

(provide 'sp-globals)
;; sp-globals.el ends here.
