;;; emacs-input-method-auto-switcher.el --- Non-blocking system input-method switcher -*- lexical-binding: t; -*-

;; Author: gongshangzheng
;; Keywords: convenience
;; Package-Requires: ((emacs "27.1"))

;;; Commentary:

;; Keeps the *system* input source in a predictable state when Emacs gains or
;; loses focus, without ever blocking the editor.
;;
;; Design rules (see openspec change `fix-input-method-switcher-hangs`):
;;
;; 1. Focus handlers never run a synchronous external command.  Every
;;    `im-select' invocation is a background process with a hard timeout.
;; 2. Focus events are debounced, and child frames / tty frames / invisible
;;    frames are ignored, so a burst of focus changes causes one switch.
;; 3. A missing helper disables the feature after a single message instead of
;;    erroring on every focus change.
;; 4. Losing focus does not touch the input source unless
;;    `emacs-input-method-auto-switcher-restore-on-focus-out' is non-nil, and
;;    then only the engine that was actually replaced is restored.
;;
;; macOS uses `im-select'.  Linux keeps the historical ibus/fcitx behaviour,
;; now started asynchronously and wrapped so failures cannot escape a hook.

;;; Code:

(require 'seq)
(require 'subr-x)

(defgroup emacs-input-method-auto-switcher nil
  "Switch the system input method on focus changes without blocking Emacs."
  :group 'convenience
  :prefix "emacs-input-method-auto-switcher-")

(defcustom emacs-input-method-auto-switcher-framework 'auto-detect
  "Input method framework to use.
One of `ibus', `fcitx', `fcitx5', `squirrel' (macOS, via `im-select') or
`auto-detect'."
  :type '(choice (const ibus)
                 (const fcitx)
                 (const fcitx5)
                 (const squirrel)
                 (const auto-detect)))

(defcustom emacs-input-method-auto-switcher-latin-engines
  '("com.apple.keylayout.ABC"
    "com.apple.keylayout.ABC-India"
    "com.apple.keylayout.Australian"
    "com.apple.keylayout.British"
    "com.apple.keylayout.Canadian"
    "com.apple.keylayout.Irish"
    "com.apple.keylayout.US"
    "com.apple.keylayout.USExtended"
    "xkb:us::eng")
  "Engine identifiers that already count as Latin input.
Focusing Emacs while one of these is active does not trigger a switch, so a
machine that is already in English never spawns a helper process."
  :type '(repeat string))

(defcustom emacs-input-method-auto-switcher-restore-on-focus-out nil
  "Whether to restore the previous input engine when Emacs loses focus.
When nil (the default) leaving Emacs never changes the input source, which is
what other applications expect and what keeps the application switch fast."
  :type 'boolean)

(defcustom emacs-input-method-auto-switcher-debounce 0.15
  "Seconds to wait before acting on a focus change.
Rapid focus changes inside this window are coalesced into one attempt."
  :type 'number)

(defcustom emacs-input-method-auto-switcher-timeout 0.5
  "Seconds after which a helper process is killed.
The helper is never allowed to hang: Emacs stays responsive even if it does."
  :type 'number)

(defcustom emacs-input-method-auto-switcher-debug nil
  "When non-nil, log every switch attempt (trigger, target, elapsed time)."
  :type 'boolean)

(defcustom emacs-input-method-auto-switcher-im-select-paths
  '("/opt/homebrew/bin/im-select"
    "/usr/local/bin/im-select"
    "/opt/local/bin/im-select"
    "/usr/bin/im-select")
  "Absolute locations tried when `im-select' is not on `PATH'.
A GUI Emacs started from the Dock often inherits a `PATH' without Homebrew."
  :type '(repeat string))

(defconst emacs-input-method-auto-switcher--mac-latin-engine
  "com.apple.keylayout.ABC"
  "Engine switched to on macOS.")

(defconst emacs-input-method-auto-switcher--linux-latin-engine
  "xkb:us::eng"
  "Engine switched to on Linux.")

(defvar emacs-input-method-auto-switcher--helper-path nil
  "Resolved path of the helper program, or nil.")

(defvar emacs-input-method-auto-switcher--helper-missing nil
  "Non-nil when the helper was already looked up and not found.")

(defvar emacs-input-method-auto-switcher--proc nil
  "Currently running helper process.  At most one at a time.")

(defvar emacs-input-method-auto-switcher--watchdog nil
  "Timer that kills `emacs-input-method-auto-switcher--proc'.")

(defvar emacs-input-method-auto-switcher--timer nil
  "Pending debounce timer.")

(defvar emacs-input-method-auto-switcher--saved-engine nil
  "Engine that was replaced by an automatic switch, for opt-in restore.")

(defvar emacs-input-method-auto-switcher--warned nil
  "Non-nil once a runtime failure has been reported.")

(defvar emacs-input-method-auto-switcher--disabled nil
  "Non-nil when switching was disabled for this session.")

(defvar emacs-input-method-auto-switcher--previous-focus-function #'ignore
  "Value of `after-focus-change-function' before setup, chained by us.")

;;;; Framework detection

(defun emacs-input-method-auto-switcher--framework ()
  "Return the effective framework symbol."
  (let ((framework emacs-input-method-auto-switcher-framework))
    (if (eq framework 'auto-detect)
        (cond
         ((eq system-type 'darwin) 'squirrel)
         ((executable-find "ibus") 'ibus)
         ((executable-find "fcitx5") 'fcitx5)
         ((executable-find "fcitx") 'fcitx)
         (t nil))
      framework)))

(defun emacs-input-method-auto-switcher--latin-engine ()
  "Return the engine string that means \"English\" on this machine."
  (if (eq system-type 'darwin)
      emacs-input-method-auto-switcher--mac-latin-engine
    emacs-input-method-auto-switcher--linux-latin-engine))

(defun emacs-input-method-auto-switcher--helper ()
  "Return the helper executable path, or nil when unavailable."
  (and (eq (emacs-input-method-auto-switcher--framework) 'squirrel)
       (or emacs-input-method-auto-switcher--helper-path
           (setq emacs-input-method-auto-switcher--helper-path
                 (and (not emacs-input-method-auto-switcher--helper-missing)
                      (or (executable-find "im-select")
                          (seq-find (lambda (path)
                                      (and (file-executable-p path) path))
                                    emacs-input-method-auto-switcher-im-select-paths)))))))

;;;; Logging / failure reporting

(defun emacs-input-method-auto-switcher--debug (format-string &rest args)
  "Log FORMAT-STRING with ARGS when debugging is enabled."
  (when emacs-input-method-auto-switcher-debug
    (message "[eimas] %s" (apply #'format format-string args))))

(defun emacs-input-method-auto-switcher--warn (message-text)
  "Report MESSAGE-TEXT once per session."
  (unless emacs-input-method-auto-switcher--warned
    (setq emacs-input-method-auto-switcher--warned t)
    (message "[eimas] %s" message-text)))

;;;; Background helper execution

(defun emacs-input-method-auto-switcher--finish (proc start output args callback)
  "Handle completion of PROC started at START with OUTPUT, ARGS and CALLBACK."
  ;; A sentinel may run before the filter has drained the last chunk (see
  ;; "Sentinel" in the Emacs Lisp manual).  The process is already finished, so
  ;; this returns at once; the timeout is only a safety net.
  (when (memq (process-status proc) '(exit signal failed))
    (accept-process-output proc 0.05))
  (when (process-get proc 'eimas-filter-output)
    (setq output (process-get proc 'eimas-filter-output)))
  (when (timerp emacs-input-method-auto-switcher--watchdog)
    (cancel-timer emacs-input-method-auto-switcher--watchdog))
  (setq emacs-input-method-auto-switcher--watchdog nil)
  (when (eq proc emacs-input-method-auto-switcher--proc)
    (setq emacs-input-method-auto-switcher--proc nil))
  (let ((status (process-status proc))
        (elapsed (round (* 1000 (- (float-time) start)))))
    (emacs-input-method-auto-switcher--debug
     "helper args=%S status=%s elapsed=%dms output=%S"
     args status elapsed (string-trim (or output "")))
    (when (memq status '(signal failed))
      (emacs-input-method-auto-switcher--warn
       (format "im-select %s 失败（%s）" args status)))
    (condition-case err
        (funcall callback status (string-trim (or output "")))
      (error
       (emacs-input-method-auto-switcher--warn
        (format "处理切换结果失败: %s" err))))))

(defun emacs-input-method-auto-switcher--spawn (args callback)
  "Run `im-select' with ARGS in the background, then call CALLBACK with status/output.
Returns the process, or nil when nothing was started.  Never blocks."
  (let ((helper (emacs-input-method-auto-switcher--helper)))
    (cond
     ((null helper)
      (emacs-input-method-auto-switcher--disable
       "找不到 im-select（已尝试 PATH 与 /opt/homebrew/bin 等常见路径）")
      nil)
     ((process-live-p emacs-input-method-auto-switcher--proc)
      (emacs-input-method-auto-switcher--debug "skip: previous helper still running")
      nil)
     (t
      (let ((start (float-time))
            (output ""))
        (condition-case err
            (let ((proc (make-process
                         :name "eimas-im-select"
                         :command (cons helper args)
                         :connection-type 'pipe
                         :noquery t
                         :filter (lambda (p chunk)
                                   (setq output (concat output chunk))
                                   (process-put p 'eimas-filter-output output))
                         :sentinel (lambda (finished _event)
                                     (emacs-input-method-auto-switcher--finish
                                      finished start output args callback)))))
              (setq emacs-input-method-auto-switcher--proc proc)
              (setq emacs-input-method-auto-switcher--watchdog
                    (run-with-timer
                     emacs-input-method-auto-switcher-timeout nil
                     (lambda (target)
                       (when (process-live-p target)
                         (emacs-input-method-auto-switcher--warn
                          (format "im-select %s 超时（%.2fs），已终止"
                                  args emacs-input-method-auto-switcher-timeout))
                         (delete-process target)))
                     proc))
              proc)
          (error
           (emacs-input-method-auto-switcher--warn
            (format "启动 %s 失败: %s" helper err))
           nil)))))))

(defun emacs-input-method-auto-switcher--write-engine (engine &optional callback)
  "Switch the system input source to ENGINE in the background.
Optional CALLBACK is called with the helper process status and output."
  (emacs-input-method-auto-switcher--debug "switch to %s" engine)
  (pcase (emacs-input-method-auto-switcher--framework)
    ('squirrel
     (emacs-input-method-auto-switcher--spawn
      (list engine)
      (lambda (status output)
        (when (and callback (eq status 'exit))
          (funcall callback status output)))))
    ('ibus
     (condition-case err
         (start-process "eimas-ibus" nil "ibus" "engine" engine)
       (error (emacs-input-method-auto-switcher--warn (format "ibus 切换失败: %s" err)))))
    ((or 'fcitx 'fcitx5)
     (let ((command (if (eq (emacs-input-method-auto-switcher--framework) 'fcitx5)
                        "fcitx5-remote"
                      "fcitx-remote")))
       (condition-case err
           (start-process "eimas-fcitx" nil command "-s" engine)
         (error (emacs-input-method-auto-switcher--warn (format "%s 切换失败: %s" command err))))))
    (_
     (emacs-input-method-auto-switcher--warn "没有可用的输入法框架"))))

(defun emacs-input-method-auto-switcher--read-engine (callback)
  "Read the current engine in the background and call CALLBACK with it.
CALLBACK receives the engine string, the symbol `unknown' when it cannot be
determined, or the symbol `failed' when the helper itself failed.  A failed
read MUST NOT be retried immediately: that would double the work (and the
stall) for every focus change while the helper is unhealthy."
  (if (eq (emacs-input-method-auto-switcher--framework) 'squirrel)
      (emacs-input-method-auto-switcher--spawn
       nil
       (lambda (status output)
         (funcall callback
                  (cond
                   ((not (eq status 'exit)) 'failed)
                   ((string-empty-p output) 'unknown)
                   (t output)))))
    ;; Linux: reading was a synchronous `shell-command-to-string' before.  We
    ;; give up on it rather than block; unknown simply means "switch anyway".
    (funcall callback 'unknown)))

;;;; Debounce

(defun emacs-input-method-auto-switcher--run-later (function)
  "Run FUNCTION after the debounce delay, cancelling any pending call."
  (when (timerp emacs-input-method-auto-switcher--timer)
    (cancel-timer emacs-input-method-auto-switcher--timer))
  (setq emacs-input-method-auto-switcher--timer
        (condition-case nil
            (run-with-timer
             emacs-input-method-auto-switcher-debounce nil
             (lambda ()
               (setq emacs-input-method-auto-switcher--timer nil)
               (condition-case err
                   (funcall function)
                 (error
                  (emacs-input-method-auto-switcher--warn
                   (format "切换输入法失败: %s" err))))))
          (error
           ;; Environments without timers (or a bogus delay) still work, just
           ;; without debouncing.
           nil)))
  (unless (timerp emacs-input-method-auto-switcher--timer)
    (condition-case err
        (funcall function)
      (error
       (emacs-input-method-auto-switcher--warn (format "切换输入法失败: %s" err))))))

;;;; Switching

(defun emacs-input-method-auto-switcher--switch-to-latin ()
  "Switch to the Latin engine unless it is already active."
  (let ((latin (emacs-input-method-auto-switcher--latin-engine)))
    (emacs-input-method-auto-switcher--read-engine
     (lambda (current)
       (cond
        ((eq current 'failed)
         (emacs-input-method-auto-switcher--debug
          "read failed, not switching this time"))
        ((eq current 'unknown)
         (emacs-input-method-auto-switcher--debug
          "engine unknown, switching to %s anyway" latin)
         (emacs-input-method-auto-switcher--write-engine latin))
        ((member current emacs-input-method-auto-switcher-latin-engines)
         (emacs-input-method-auto-switcher--debug "already latin (%s)" current))
        (t
         (setq emacs-input-method-auto-switcher--saved-engine current)
         (emacs-input-method-auto-switcher--debug "saved=%s, switching to %s" current latin)
         (emacs-input-method-auto-switcher--write-engine latin)))))))

(defun emacs-input-method-auto-switcher--restore-saved-engine ()
  "Restore the engine that an automatic switch replaced, if any."
  (when emacs-input-method-auto-switcher--saved-engine
    (let ((engine emacs-input-method-auto-switcher--saved-engine))
      (setq emacs-input-method-auto-switcher--saved-engine nil)
      (emacs-input-method-auto-switcher--debug "restoring %s" engine)
      (emacs-input-method-auto-switcher--write-engine engine))))

;;;; Focus plumbing

(defun emacs-input-method-auto-switcher--frame-eligible-p (frame)
  "Return non-nil when FRAME can carry a system input source."
  (and frame
       (frame-live-p frame)
       (frame-parameter frame 'window-system)
       (null (frame-parameter frame 'parent-frame))   ; posframe/tooltip child
       (not (eq (frame-parameter frame 'visibility) 'hidden))
       (not (eq (frame-parameter frame 'visibility) nil))))

(defun emacs-input-method-auto-switcher--enabled-p ()
  "Return non-nil when switching is active."
  (not emacs-input-method-auto-switcher--disabled))

(defun emacs-input-method-auto-switcher--handle-focus-in (frame trigger)
  "Handle gaining focus on FRAME, logging TRIGGER."
  (when (and (emacs-input-method-auto-switcher--enabled-p)
             (emacs-input-method-auto-switcher--frame-eligible-p frame))
    (emacs-input-method-auto-switcher--debug "trigger=%s" trigger)
    (emacs-input-method-auto-switcher--run-later
     #'emacs-input-method-auto-switcher--switch-to-latin)))

(defun emacs-input-method-auto-switcher--handle-focus-out (frame trigger)
  "Handle losing focus on FRAME, logging TRIGGER."
  (when (and (emacs-input-method-auto-switcher--enabled-p)
             emacs-input-method-auto-switcher-restore-on-focus-out
             (emacs-input-method-auto-switcher--frame-eligible-p frame))
    (emacs-input-method-auto-switcher--debug "trigger=%s" trigger)
    (emacs-input-method-auto-switcher--run-later
     #'emacs-input-method-auto-switcher--restore-saved-engine)))

(defun emacs-input-method-auto-switcher--after-focus-change ()
  "Focus dispatcher installed on `after-focus-change-function'."
  (let ((frame (selected-frame)))
    (pcase (frame-focus-state frame)
      ('t (emacs-input-method-auto-switcher--handle-focus-in frame "focus-in"))
      ('nil (emacs-input-method-auto-switcher--handle-focus-out frame "focus-out"))
      ;; 'unknown: the window system did not tell us; do nothing rather than
      ;; guess and switch the user's input source.
      (_ nil)))
  (when (functionp emacs-input-method-auto-switcher--previous-focus-function)
    (funcall emacs-input-method-auto-switcher--previous-focus-function)))

(defun emacs-input-method-auto-switcher--legacy-focus-in (&rest _)
  "Compatibility hook for Emacs versions without `after-focus-change-function'."
  (emacs-input-method-auto-switcher--handle-focus-in (selected-frame) "focus-in"))

(defun emacs-input-method-auto-switcher--legacy-focus-out (&rest _)
  "Compatibility hook for Emacs versions without `after-focus-change-function'."
  (emacs-input-method-auto-switcher--handle-focus-out (selected-frame) "focus-out"))

;;;; Public entry points

(defun emacs-input-method-auto-switcher-toggle-with-latin ()
  "Switch the system source to Latin in the background, then toggle the IM.
Returns immediately: the editor input method toggles before the system source
finishes switching."
  (interactive)
  (emacs-input-method-auto-switcher--write-engine
   (emacs-input-method-auto-switcher--latin-engine))
  (toggle-input-method))

(defun emacs-input-method-auto-switcher--teardown-hooks ()
  "Remove every focus handler this module may have installed."
  (when (and (boundp 'after-focus-change-function)
             (eq after-focus-change-function
                 #'emacs-input-method-auto-switcher--after-focus-change))
    (setq after-focus-change-function
          (or emacs-input-method-auto-switcher--previous-focus-function #'ignore)))
  (remove-hook 'focus-in-hook #'emacs-input-method-auto-switcher--legacy-focus-in)
  (remove-hook 'focus-out-hook #'emacs-input-method-auto-switcher--legacy-focus-out))

(defun emacs-input-method-auto-switcher--disable (reason)
  "Disable switching for this session, reporting REASON once."
  (unless emacs-input-method-auto-switcher--disabled
    (setq emacs-input-method-auto-switcher--disabled t)
    (message "[eimas] %s — 已停用输入法自动切换" reason))
  (emacs-input-method-auto-switcher--teardown-hooks))

;;;###autoload
(defun emacs-input-method-auto-switcher-setup ()
  "Install the non-blocking focus handlers.  Safe to call repeatedly."
  (interactive)
  (emacs-input-method-auto-switcher--teardown-hooks)
  (setq emacs-input-method-auto-switcher--disabled nil
        emacs-input-method-auto-switcher--warned nil)
  (if (boundp 'after-focus-change-function)
      (progn
        (setq emacs-input-method-auto-switcher--previous-focus-function
              (if (functionp after-focus-change-function)
                  after-focus-change-function
                #'ignore))
        (setq after-focus-change-function
              #'emacs-input-method-auto-switcher--after-focus-change))
    (add-hook 'focus-in-hook #'emacs-input-method-auto-switcher--legacy-focus-in)
    (add-hook 'focus-out-hook #'emacs-input-method-auto-switcher--legacy-focus-out))
  (if (emacs-input-method-auto-switcher--helper)
      (emacs-input-method-auto-switcher--debug "setup done (helper=%s)"
                                               emacs-input-method-auto-switcher--helper-path)
    (emacs-input-method-auto-switcher--disable
     "找不到 im-select（已尝试 PATH 与 /opt/homebrew/bin 等常见路径）"))
  emacs-input-method-auto-switcher--disabled)

;;;###autoload
(defun emacs-input-method-auto-switcher-unload ()
  "Remove handlers, timers and any running helper process."
  (interactive)
  (emacs-input-method-auto-switcher--teardown-hooks)
  (when (timerp emacs-input-method-auto-switcher--timer)
    (cancel-timer emacs-input-method-auto-switcher--timer)
    (setq emacs-input-method-auto-switcher--timer nil))
  (when (timerp emacs-input-method-auto-switcher--watchdog)
    (cancel-timer emacs-input-method-auto-switcher--watchdog)
    (setq emacs-input-method-auto-switcher--watchdog nil))
  (when (process-live-p emacs-input-method-auto-switcher--proc)
    (delete-process emacs-input-method-auto-switcher--proc)
    (setq emacs-input-method-auto-switcher--proc nil)))

;;;###autoload
(defun emacs-input-method-auto-switcher-on-focus-in ()
  "Compatibility wrapper: treat this as a focus-in event."
  (interactive)
  (emacs-input-method-auto-switcher--handle-focus-in (selected-frame) "manual"))

;;;###autoload
(defun emacs-input-method-auto-switcher-on-focus-out ()
  "Compatibility wrapper: treat this as a focus-out event."
  (interactive)
  (emacs-input-method-auto-switcher--handle-focus-out (selected-frame) "manual"))

(provide 'emacs-input-method-auto-switcher)
;;; emacs-input-method-auto-switcher.el ends here
