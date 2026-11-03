;;; sp-debug.el --- Startup debugging and profiling -*- lexical-binding: t; -*-

;;; Commentary:

;; A very small module for diagnosing Emacs performance. For now it only turns
;; on use-package's timing statistics.

;;; Code:

;; This is for profiling and setting up different

;; Getting information on the launch time for packages.
(setq use-package-compute-statistics t)

(provide 'sp-debug)
;; sp-debug ends here.
