;;; lambda-dark-faded-theme.el --- Lambda-theme dark variant   -*- lexical-binding: t; -*-

;; Copyright (C) 2022  Colin McLear

;; Author: Colin McLear <mclear@unl.edu>
;; Keywords: faces,


;;; Code:

(require 'lambda-themes)

(deftheme lambda-dark-faded "Lambda theme, the dark faded version")

(lambda-themes-create 'dark-faded 'lambda-dark-faded)

(run-hooks 'lambda-themes-after-load-theme-hook)

(provide-theme 'lambda-dark-faded)

(provide 'lambda-dark-faded-theme)

;; Local Variables:
;; eval: (when (fboundp 'rainbow-mode) (rainbow-mode +1))
;; End:

;;; lambda-dark-faded-theme.el ends here
