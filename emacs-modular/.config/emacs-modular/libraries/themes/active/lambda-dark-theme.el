;;; lambda-dark-theme.el --- Lambda-theme dark variant   -*- lexical-binding: t; -*-

;; Copyright (C) 2022  Colin McLear

;; Author: Colin McLear <mclear@unl.edu>
;; Keywords: faces,


;;; Code:

(require 'lambda-themes)

(deftheme lambda-dark "Lambda theme, the dark regular version")

(lambda-themes-create 'dark 'lambda-dark)

(run-hooks 'lambda-themes-after-load-theme-hook)

(provide-theme 'lambda-dark)

(provide 'lambda-dark-theme)

;; Local Variables:
;; eval: (when (fboundp 'rainbow-mode) (rainbow-mode +1))
;; End:

;;; lambda-dark-theme.el ends here
