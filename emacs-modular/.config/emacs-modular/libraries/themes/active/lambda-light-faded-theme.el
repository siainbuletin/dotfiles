;;; lambda-light-faded-theme.el --- Lambda-theme light variant   -*- lexical-binding: t; -*-

;; Copyright (C) 2022  Colin McLear

;; Author: Colin McLear <mclear@unl.edu>
;; Keywords: faces,


;;; Code:
(require 'lambda-themes)

(deftheme lambda-light-faded "Lambda theme, the light faded version")

(lambda-themes-create 'light-faded 'lambda-light-faded)

(run-hooks 'lambda-themes-after-load-theme-hook)

(provide-theme 'lambda-light-faded)

(provide 'lambda-light-faded-theme)

;; Local Variables:
;; eval: (when (fboundp 'rainbow-mode) (rainbow-mode +1))
;; End:

;;; lambda-light-faded-theme.el ends here
