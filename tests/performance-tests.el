(defun make-performance-shell (given-name)
  "Create a shell buffer with the GIVEN-NAME."
  (let ((name (concat "*test-performance-shell-" given-name "*")))
    (rename-buffer name)
    (refresh-terminal)
    (should (equal name (buffer-name)))
    (should (equal major-mode 'shell-mode))
    (goto-char (point-max))
    name))

(defun send-performance-commands (cmds &optional given-time)
  "Send each string in CMDS to the current buffer, with a delay of GIVEN-TIME."
  ;; Grab the start time
  (let* ((name  (buffer-name))
         (proc  (get-buffer-process name))
         (start nil)
         (time  (or given-time 3)))
    (dolist (cmd cmds)
      ;; Run each command
      (setq start (float-time))
      (comint-send-string name cmd)
      (comint-send-input)

      ;; Wait for the result
      (accept-process-output proc)
      (redraw-display)
      (while (< (- (float-time) start) time)
        (sleep-for 1)))))

(ert-deftest warbo-performance-longlines ()
  "Navigating a buffer with long lines can hang Emacs at 100% CPU"
  (with-temp-buffer
    ;; Write a command which will print a long line, with many parentheses to
    ;; be matched, etc.
    (make-performance-shell "longlines")
    (send-performance-commands
     (list "for N in $(seq 1 10000); do printf '{[('; done;"
           "for N in $(seq 1 10000); do printf ')]}'; done; echo"))

      ;; Make sure we don't have any long lines
    (goto-char (point-min))
    (while (< (point) (point-max))
      ;; Lines should be split at 1000 characters, but we give some leeway
      ;; for ANSI control characters and things. If our line-splitting's
      ;; broken, we'll end up an order of magnitude too big, so this margin
      ;; is fine.
      (should (< (- (line-end-position) (line-beginning-position)) 1500))
      (forward-line))))

(ert-deftest warbo-performance-existing-newlines ()
  "Don't split up output if it's already made of short lines"
  (with-temp-buffer
    ;; Write a command which will print lots of output, made of short lines
    (make-performance-shell "existing-newlines")
    (send-performance-commands
     (list "for N in $(seq 1 10000); do printf 'AB\n'; done; echo"))

    ;; Make sure all printed lines are 'AB'
    (let ((count 0))
      (goto-char (point-min))
      (while (< (point) (point-max))
        ;; Lines should either be prompts or "AB"; if a line begins with "B"
        ;; then some "AB" line must have been split inappropriately.
        (should-not (equal (char-after) ?B))

        ;; Any line beginning with "A" should be "AB" (i.e. there are no
        ;; inappropriately-split lines consisting of "A" and there are no
        ;; missing newlines like "ABABABAB...")
        (when (equal (char-after) ?A)
          ;; We count how many lines begin with "A" since this could be
          ;; vacuously true
          (setq count (+ 1 count))
          (should (string-equal (buffer-substring (line-beginning-position)
                                                  (line-end-position))
                                "AB")))
        (forward-line))

      ;; Ensure we actually saw some output lines (i.e. our test isn't vacuous)
      (should (> count 1000)))))
