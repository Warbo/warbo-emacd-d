(defun compile-with-make ()
  "Run COMPILE, without prompting for a command"
  (interactive)
  (let ((compilation-read-command nil))
    (compile (cond
              ((file-exists-p "render.sh")   "render.sh")
              ((file-exists-p "Makefile")    "make -k ")
              ((file-exists-p "default.nix")
               "nix-build --option sandbox false --show-trace && { killall -HUP mupdf-x11 || true; }")
              (t (error "Couldn't find render.sh, Makefile or default.nix"))))))

(use-package latex
  :ensure auctex
  :mode ("\\.tex\\'" . latex-mode)
  :bind
  (:map LaTeX-mode-map
        ("<f9>" . compile-with-make))
  :config
  (add-hook 'LaTeX-mode-hook 'visual-line-mode)
  (add-hook 'LaTeX-mode-hook 'flyspell-mode)  ;; Relies on aspell
  (add-hook 'LaTeX-mode-hook (lambda () (whitespace-mode 0)))
  (setq TeX-auto-save  t)
  (setq TeX-parse-self t))
(use-package org
  :mode (("\\.org$" . org-mode))
  :ensure org-plus-contrib
  :bind (("<f9>" . (lambda ()
                     (let* ((pdf (replace-regexp-in-string "\.org$" ".pdf"
                                                           (buffer-name)))
                            (buf (get-buffer pdf)))
                       (when buf (with-current-buffer buf (auto-revert-mode 1)))
                       (save-buffer)
                       (org-latex-export-to-pdf)
                       (unless buf (find-file pdf))))))
  :init
  (progn
    ;; Don't clobber windmove bindings (this must run before ORG loads)
    ;; "(add-hook 'org-shiftup-final-hook 'windmove-up)", etc. don't seem to
    ;; work. Default disputed keys remap so that windowmove commands aren't
    ;; overridden.
    (setq org-disputed-keys '(([(shift up)] . [(meta p)])
                              ([(shift down)] . [(meta n)])
                              ([(shift left)] . [(meta -)])
                              ([(shift right)] . [(meta +)])
                              ([(meta return)] . [(control meta return)])
                              ([(control shift right)] . [(meta shift +)])
                              ([(control shift left)] . [(meta shift -)])))
    (setq org-replace-disputed-keys t))
  :config
  (progn
    ;; Active Babel languages
    (org-babel-do-load-languages 'org-babel-load-languages '((haskell    . t)
                                                             (shell      . t)
                                                             (gnuplot    . t)
                                                             (dot        . t)))

    ;; Don't ask whether we can run code every time
    (setq org-confirm-babel-evaluate nil)

    (setq org-src-fontify-natively t)

    ;; Visual line wrapping in document modes
    (add-hook 'org-mode-hook 'turn-on-visual-line-mode)

    (add-hook 'org-mode-hook (lambda ()
                               (whitespace-mode 0)
                               (setq-local whitespace-style
                                           (remove-if (lambda (x)
                                                        (member x '(lines-tail
                                                                    lines)))
                                                      whitespace-style))
                               (whitespace-mode 1)))))

(add-hook 'markdown-mode-hook 'turn-on-visual-line-mode)

(defun compile-with-make-setup-markdown ()
  (bind-key (kbd "<f9>") 'compile-with-make markdown-mode-map))

(add-hook  'markdown-mode-hook 'compile-with-make-setup-markdown)

;; Buffers for writing
(dolist (dir '("~/Writing/PhDThesis"))
  (when (file-directory-p dir)
    (unless (get-buffer "PhDThesis")
      (save-excursion (dired dir)))))

;; Open our master Bibtex file in ebib
(setq ebib-hide-cursor nil)
(setq ebib-file-field "localfile")
(setq ebib-file-associations '(("pdf" . "mupdf-x11") ("ps" . "gv")))
(defun bib ()
  (interactive)
  (ebib "~/Writing/Bibtex.bib"))
