;; Set some repositories for the package manager
(setq package-archives '(("gnu"       . "http://elpa.gnu.org/packages/")
                         ("marmalade" . "http://marmalade-repo.org/packages/")
                         ("melpa"     . "http://melpa.milkbox.net/packages/")
                         ))

;; Resize windows with Shift-Control-Arrow-Cursor
(global-set-key (kbd "S-C-<left>")  'shrink-window-horizontally)
(global-set-key (kbd "S-C-<right>") 'enlarge-window-horizontally)
(global-set-key (kbd "S-C-<down>")  'shrink-window)
(global-set-key (kbd "S-C-<up>")    'enlarge-window)

;; When TRAMP connections die, auto-save can hang
(setq auto-save-default t)

;; Turn off Prelude's auto-save-when-switching-buffer
(ad-unadvise 'switch-to-buffer)
(ad-unadvise 'other-window)
(ad-unadvise 'windmove-up)
(ad-unadvise 'windmove-down)
(ad-unadvise 'windmove-left)
(ad-unadvise 'windmove-right)

;; Disable expensive modes when long lines are found
(when (require 'so-long nil :noerror)
  (so-long-enable))

;; Bi-directional text can slow down Emacs's processing
(setq-default bidi-display-reordering nil)

;; Disable smartparens mode, as it's really slow
(with-eval-after-load 'smartparens
  (show-smartparens-global-mode -1))

;; Disable which-key, as it's slow and swallows keypresses
(which-key-mode -1)

;; Hovering tooltips are annoying
(setq tooltip-use-echo-area t)
(tooltip-mode nil)

;; Flycheck all the things
(require 'flycheck)
(add-hook 'after-init-hook #'global-flycheck-mode)
(add-to-list 'flycheck-checkers 'nix)

;; Flycheck builds a command to run, e.g. ("myCompiler" "check" "MyFile.ext"),
;; but that assumes the executable (e.g. "myCompiler") is in PATH. We'd rather
;; encapsulate such things as dependencies of a project's Nix derivation, which
;; are then available if we run "nix-shell".

;; Running nix-shell over and over can be slow, so we use functions from
;; nix-sandbox which cache the environment (e.g. the PATH), which makes looking
;; up the relevant executable much faster.

;; The default behaviour of nix-sandbox isn't ideal, for two reasons: firstly we
;; can spend a while waiting for a nix-shell to get built synchronously, just
;; for some throwaway command like a syntax checker. Secondly, if we cancel the
;; synchronous call (e.g. with C-g) then the sandbox will probably need to be
;; rebuilt from scratch next time.

;; To avoid this we augment nix-sandbox in the following way:
;;  - We run nix-shell processes asynchronously, to avoid having to wait.
;;  - We error-out immediately if the sandbox is still being built.

;; This way, we can carry on working (without checkers) while builds are going
;; on in the background, and the checkers will start working once the builds
;; finish.

;; Stores the builder processes
(defvar nix-sandbox-builders-map (make-hash-table :test 'equal :size 100))

(defun nix-sandbox-build-asynchronously (sandbox)
  "Launch a process to build a nix-shell in SANDBOX.
The build command is copypasta from nix-create-sandbox-rc."
  (or (gethash sandbox nix-sandbox-builders-map)
      (let* ((name (concat "nix-sandbox-builder-" sandbox))
             (proc (puthash sandbox
                            (start-process
                             name name
                             "nostderr" "nix-shell" "--run"
                             "declare +x shellHook; declare -x; declare -xf")
                            nix-sandbox-builders-map)))
        (message "Starting nix-shell builder for dir %s\n" sandbox)

        ;; Prevents 'Process foo finished' messages polluting the output buffer
        (set-process-sentinel proc #'ignore)
        proc)))

(defun nix-create-sandbox-rc-async (sandbox)
  "Replacement for nix-create-sandbox-rc.
Looks up or creates a nix-shell process in the SANDBOX dir.  If the process is
running (e.g. if it's newly created, or takes a while) then an interrupt is
triggered, as if the user cancelled this operation.  If it's no longer running,
we dump its output to a temp file and return it."
  (let ((proc (nix-sandbox-build-asynchronously sandbox)))
    ;; When we're not finished yet, pretend we cancelled with C-g
    (when (process-live-p proc)
      (keyboard-quit))

    ;; Process is finished, remove it from cache.
    (message "Found finished builder for nix-shell dir %s\n" sandbox)
    (remhash sandbox nix-sandbox-builders-map)

    ;; Write output to a file
    (let ((filename (make-temp-file "nix-sandbox-rc-")))
      (with-current-buffer (process-buffer proc)
        (write-file filename)
        (kill-buffer))

      ;; Return filename, to use as our 'rc' file
      filename)))

;; Override nix-create-sandbox-rc. Using advice is inefficient, but will work
;; even if nix-sandbox hasn't been loaded yet.
(advice-add 'nix-create-sandbox-rc :override #'nix-create-sandbox-rc-async)

;; Tell flycheck to look up commands in Nix sandboxes, if we're in one
(setq flycheck-command-wrapper-function
      (lambda (command)
        (let ((sandbox (nix-current-sandbox)))
          (if sandbox
              (apply 'nix-shell-command sandbox command)
              command)))

      flycheck-executable-find
      (lambda (command)
        (let ((sandbox (nix-current-sandbox)))
          (if sandbox
              (nix-executable-find sandbox command)
            (executable-find command)))))

;; Compile using nix-build if there's a default.nix file
(require 'dwim-compile)
(add-to-list 'dwim-c/build-tool-alist
             '(nix "\\`default\\.nix\\'" "nix-build"))

;; Allow commands to use Nix
(setenv "NIX_REMOTE" "daemon")
(setenv "NIX_PATH"
        (replace-regexp-in-string
         (rx (* (any " \t\n")) eos)
         ""
         (shell-command-to-string
          "/run/current-system/sw/bin/bash -l -c 'echo \"$NIX_PATH\"'")))

;; Set PATH
(require 'subr-x)
(setenv "PATH"
        (string-join `(,(getenv "PATH")
                       "/run/current-system/sw/bin"
                       "/home/chris/.nix-profile/bin"
                       "/home/chris/System/Programs/bin")
                     ":"))
(setq exec-path (append exec-path '("/run/current-system/sw/bin"
                                    "/home/chris/.nix-profile/bin"
                                    "/home/chris/System/Programs/bin")))

;; Set a reasonable value for COLUMNS, e.g. for shell buffers
(setenv "COLUMNS" "80")

;; Enable fill-column-indicator when editing files
(setq-default fill-column 80)

;; Show '...' in place of long Nix hashes
(require 'use-package)
(use-package pretty-sha-path
  :ensure t
  :config (pretty-sha-path-global-mode))

;; Allow invoked programs to use pulseaudio
(setenv "PULSE_SERVER" "/run/user/1000/pulse/native")

;; Wrap the display of long lines, without altering the text itself
(global-visual-line-mode)

;; Start emacs server, so emacsclient works. We can only run one emacs server at
;; a time, so skip this if this emacs instance is just for running tests.
(unless (getenv "EMACS_UNDER_TEST")
  (defer 'server-start))

;; Force font. This does nothing in terminal mode, so we poll until there's a
;; graphical display, set the font, then cancel the polling

(defvar desired-font "Liberation Mono" "The font the use in graphical mode")

;; We store the timer
(when (boundp 'force-font-timer)
  (cancel-timer force-font-timer)
  (makunbound 'force-font-timer))

(setq force-font-timer
      (run-with-timer 5 5 (lambda ()
                            (when (display-graphic-p)
                              (if (member desired-font (font-family-list))
                                  (set-face-attribute 'default nil
                                                      :font desired-font
                                                      :height 80)
                                (message "Font %S wasn't found" desired-font))

                              ;; While we're here, enable fci-mode globally too
                              (require 'fill-column-indicator)
                              (define-globalized-minor-mode
                                my-global-fci-mode
                                fci-mode
                                (lambda ()
                                  (when (buffer-file-name)
                                    (turn-on-fci-mode))))
                              (my-global-fci-mode 1)

                              (cancel-timer force-font-timer)))))
