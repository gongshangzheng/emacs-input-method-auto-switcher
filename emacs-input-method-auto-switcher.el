;;; input-method-helper.el --- Helper for managing input methods in Emacs -*- lexical-binding: t; -*-

(defgroup input-method-helper nil
  "Helper for managing input methods in Emacs."
  :group 'convenience)

(defcustom input-method-helper-framework 'auto-detect
  "Input method framework to use.
Can be 'ibus, 'fcitx, 'fcitx5, 'squirrel (macOS only), or 'auto-detect."
  :type '(choice (const ibus)
                 (const fcitx)
                 (const fcitx5)
                 (const squirrel)  ; macOS only
                 (const auto-detect)))

(defcustom input-method-helper-non-latin-engines
  '("rime" "pinyin" "mozc" "anthy" "kkc" "fcitx-keyboard-us")
  "List of input engines that should trigger auto-switch to Latin."
  :type '(repeat string))

(defvar input-method-helper--current-engine nil
  "Stores the current input engine.")

(defun input-method-helper--detect-framework ()
  "Detect available input method framework."
  (cond
   ((executable-find "im-select") 'squirrel)  ; macOS uses im-select (Squirrel)
   ((executable-find "ibus") 'ibus)
   ((executable-find "fcitx5") 'fcitx5)
   ((executable-find "fcitx") 'fcitx)
   (t nil)))

(defvar input-method-helper--current-engine nil
  "Stores the current input method engine before Emacs loses focus.")

(defvar input-method-helper-non-latin-engines '("im.rime.inputmethod.Squirrel.Hans" "com.apple.keylayout.ABC")
  "List of non-latin input methods.")

(defun input-method-helper--detect-im-select ()
  "Check if im-select is available."
  (executable-find "im-select"))

(defun input-method-helper--get-current-engine ()
  "Get current input engine based on configured framework."
  (let ((framework (if (eq input-method-helper-framework 'auto-detect)
                       (input-method-helper--detect-framework)
                     input-method-helper-framework)))
    (when framework
      (string-trim
       (pcase framework
         ('ibus (shell-command-to-string "ibus engine"))
         ('fcitx (shell-command-to-string "fcitx-remote -n"))
         ('fcitx5 (shell-command-to-string "fcitx5-remote -n"))
         ('squirrel (if (eq system-type 'darwin)
                       (shell-command-to-string "im-select")  ; 使用 im-select 查看当前输入法
                     ""))  ; 非 macOS 系统返回空字符串
         (_ ""))))))

(defun input-method-helper--set-engine (engine)
  "Set input method ENGINE."
  (let ((framework (if (eq input-method-helper-framework 'auto-detect)
                       (input-method-helper--detect-framework)
                     input-method-helper-framework)))
    (when framework
      (pcase framework
        ('ibus (start-process "ibus-set" nil "ibus" "engine" engine))
        ('fcitx (call-process "fcitx-remote" nil nil nil "-s" engine))
        ('fcitx5 (call-process "fcitx5-remote" nil nil nil "-s" engine))
        ('squirrel (if (eq system-type 'darwin)
                       (call-process "im-select" nil nil nil engine)  ; macOS 使用 im-select 切换输入法
                     nil))  ; 非 macOS 系统不处理
        (_ nil)))))

(defun input-method-helper-on-focus-in ()
  "Switch to Latin input when Emacs gains focus."
  (setq input-method-helper--current-engine (input-method-helper--get-current-engine))
  (when (member input-method-helper--current-engine input-method-helper-non-latin-engines)
    (if (eq system-type 'darwin)  ; 判断是否是 macOS 平台
        (if (input-method-helper--detect-im-select)
            (input-method-helper--set-engine "xkb:us::eng")  ; 使用 im-select 切换输入法
          (message "im-select is not available. Cannot switch input method."))
      (input-method-helper--set-engine "xkb:us::eng"))))  ; Linux 默认切换到拉丁输入法

(defun input-method-helper-on-focus-out ()
  "Restore original input method when Emacs loses focus."
  (when input-method-helper--current-engine
    (if (eq system-type 'darwin)  ; 判断是否是 macOS 平台
        (if (input-method-helper--detect-im-select)
            (input-method-helper--set-engine input-method-helper--current-engine)
          (message "im-select is not available. Cannot restore original input method."))
      (input-method-helper--set-engine input-method-helper--current-engine))))  ; Linux 恢复原输入法

(defun input-method-helper-toggle-with-latin ()
  "Switch to Latin before toggling input method."
  (interactive)
  (if (eq system-type 'darwin)  ; 判断是否是 macOS 平台
      (if (input-method-helper--detect-im-select)
          (input-method-helper--set-engine "xkb:us::eng")
        (message "im-select is not available. Cannot switch to Latin input."))
    (input-method-helper--set-engine "xkb:us::eng"))  ; Linux 默认切换到拉丁输入法
  (toggle-input-method))

;;;###autoload
(defun input-method-helper-setup ()
  "Setup input method helper."
  (add-hook 'focus-in-hook #'input-method-helper-on-focus-in)
  (add-hook 'focus-out-hook #'input-method-helper-on-focus-out))

(provide 'input-method-helper)
