;;; lambda-light-theme.el --- Lambda-theme light variant   -*- lexical-binding: t; -*-

;; Copyright (C) 2022  Colin McLear

;; Author: Colin McLear <mclear@unl.edu>
;; Keywords: faces,


;;; Code:
(require 'lambda-themes)

(deftheme lambda-light "Lambda theme, the light regular version")

(lambda-themes-create 'light 'lambda-light)

(run-hooks 'lambda-themes-after-load-theme-hook)

(provide-theme 'lambda-light)

(provide 'lambda-light-theme)

;; Local Variables:
;; eval: (when (fboundp 'rainbow-mode) (rainbow-mode +1))
;; End:

;;; lambda-light-theme.el ends here
