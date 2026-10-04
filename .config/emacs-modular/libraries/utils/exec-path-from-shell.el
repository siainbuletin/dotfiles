;; -*- lexical-binding: t; -*-
(defcustom siapip/exec-path-from-shell:enable nil
  "Try to get the environment variables form shell."
  :group 'siapip
  :type 'boolean)
(when siapip/exec-path-from-shell:enable
  (use-package exec-path-from-shell
    :demand t
    :ensure t
    :init
    (condition-case err
        (exec-path-from-shell-initialize)
      (error (message "Failed to get exec-path from shell: %S" err)))))
