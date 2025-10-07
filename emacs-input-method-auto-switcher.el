;;; emacs-input-method-auto-switcher.el --- Auto-switcher for managing input methods in Emacs -*- lexical-binding: t; -*-

(defgroup emacs-input-method-auto-switcher nil
  "Helper for managing input methods in Emacs."
  :group 'convenience)

(defcustom emacs-input-method-auto-switcher-framework 'auto-detect
  "Input method framework to use.
Can be 'ibus, 'fcitx, 'fcitx5, 'squirrel (macOS only), or 'auto-detect."
  :type '(choice (const ibus)
                 (const fcitx)
                 (const fcitx5)
                 (const squirrel)  ; macOS only
                 (const auto-detect)))

(defcustom emacs-input-method-auto-switcher-non-latin-engines
  '("im.rime.inputmethod.Squirrel.Hans"  ; Rime Chinese (macOS)
    "com.apple.keylayout.ABC"             ; ABC (macOS)
    "rime"                                 ; Rime (Linux)
    "pinyin"                               ; Pinyin
    "mozc"                                 ; Japanese
    "anthy"                                ; Japanese
    "kkc"                                  ; Japanese
    "fcitx-keyboard-us")                   ; Fcitx
  "List of input engines that should trigger auto-switch to Latin."
  :type '(repeat string))

(defvar emacs-input-method-auto-switcher--current-engine nil
  "Stores the current input method engine before Emacs loses focus.")

(defun emacs-input-method-auto-switcher--detect-framework ()
  "Detect available input method framework."
  (cond
   ((executable-find "im-select") 'squirrel)  ; macOS uses im-select (Squirrel)
   ((executable-find "ibus") 'ibus)
   ((executable-find "fcitx5") 'fcitx5)
   ((executable-find "fcitx") 'fcitx)
   (t nil)))

(defun emacs-input-method-auto-switcher--detect-im-select ()
  "Check if im-select is available."
  (executable-find "im-select"))

(defun emacs-input-method-auto-switcher--latin-engine ()
  "Return a Latin input method engine string based on current framework/platform."
  (let ((framework (if (eq emacs-input-method-auto-switcher-framework 'auto-detect)
                       (emacs-input-method-auto-switcher--detect-framework)
                     emacs-input-method-auto-switcher-framework)))
    (pcase framework
      ('squirrel "com.apple.keylayout.ABC")
      ('fcitx5 "xkb:us::eng")
      (_ "xkb:us::eng"))))

(defun emacs-input-method-auto-switcher--get-current-engine ()
  "Get current input engine based on configured framework."
  (let ((framework (if (eq emacs-input-method-auto-switcher-framework 'auto-detect)
                       (emacs-input-method-auto-switcher--detect-framework)
                     emacs-input-method-auto-switcher-framework)))
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

(defun emacs-input-method-auto-switcher--set-engine (engine)
  "Set input method ENGINE."
  (let ((framework (if (eq emacs-input-method-auto-switcher-framework 'auto-detect)
                       (emacs-input-method-auto-switcher--detect-framework)
                     emacs-input-method-auto-switcher-framework)))
    (when framework
      (pcase framework
        ('ibus (start-process "ibus-set" nil "ibus" "engine" engine))
        ('fcitx (call-process "fcitx-remote" nil nil nil "-s" engine))
        ('fcitx5 (call-process "fcitx5-remote" nil nil nil "-s" engine))
        ('squirrel (if (eq system-type 'darwin)
                       (call-process "im-select" nil nil nil engine)  ; macOS 使用 im-select 切换输入法
                     nil))  ; 非 macOS 系统不处理
        (_ nil)))))

(defun emacs-input-method-auto-switcher-on-focus-in ()
  "Switch to Latin input when Emacs gains focus."
  (setq emacs-input-method-auto-switcher--current-engine (emacs-input-method-auto-switcher--get-current-engine))
  (when (member emacs-input-method-auto-switcher--current-engine emacs-input-method-auto-switcher-non-latin-engines)
    (let ((latin (emacs-input-method-auto-switcher--latin-engine)))
      (if (eq system-type 'darwin)  ; 判断是否是 macOS 平台
          (if (emacs-input-method-auto-switcher--detect-im-select)
              (emacs-input-method-auto-switcher--set-engine latin)
            (message "im-select is not available. Cannot switch input method."))
        (emacs-input-method-auto-switcher--set-engine latin)))))  ; 非 macOS 使用对应框架的拉丁输入法

(defun emacs-input-method-auto-switcher-on-focus-out ()
  "Restore original input method when Emacs loses focus."
  (when emacs-input-method-auto-switcher--current-engine
    (if (eq system-type 'darwin)  ; 判断是否是 macOS 平台
        (if (emacs-input-method-auto-switcher--detect-im-select)
            (emacs-input-method-auto-switcher--set-engine emacs-input-method-auto-switcher--current-engine)
          (message "im-select is not available. Cannot restore original input method."))
      (emacs-input-method-auto-switcher--set-engine emacs-input-method-auto-switcher--current-engine))))  ; Linux 恢复原输入法

(defun emacs-input-method-auto-switcher-toggle-with-latin ()
  "Switch to Latin before toggling input method."
  (interactive)
  (let ((latin (emacs-input-method-auto-switcher--latin-engine)))
    (if (eq system-type 'darwin)  ; 判断是否是 macOS 平台
        (if (emacs-input-method-auto-switcher--detect-im-select)
            (emacs-input-method-auto-switcher--set-engine latin)
          (message "im-select is not available. Cannot switch to Latin input."))
      (emacs-input-method-auto-switcher--set-engine latin)))  ; 非 macOS 使用对应框架的拉丁输入法
  (toggle-input-method))

;;;###autoload
(defun emacs-input-method-auto-switcher-setup ()
  "Setup input method helper."
  (add-hook 'focus-in-hook #'emacs-input-method-auto-switcher-on-focus-in)
  (add-hook 'focus-out-hook #'emacs-input-method-auto-switcher-on-focus-out))

(provide 'emacs-input-method-auto-switcher)
