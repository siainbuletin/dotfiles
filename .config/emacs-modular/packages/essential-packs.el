;; -*- lexical-binding: t; -*-

(use-package transient
  :ensure t)

(use-package p-search
  :ensure (:host github :repo "zkry/p-search"))

(use-package websocket
  :ensure (:wait t)
)

(use-package helm
    :ensure (:wait t))

(use-package ess
  :ensure t)

(use-package taxy
  :ensure t)