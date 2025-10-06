# Emacs 输入法自动切换器

[English Version](./README.md)

一个 Emacs 扩展包，可以在 Emacs 获得或失去焦点时自动切换输入法，帮助你在编程时无缝地在英文和其他语言之间切换。

## 功能特性

- 🎯 **自动检测输入法框架**：自动检测可用的输入法框架（ibus、fcitx、fcitx5、macOS 上的 Squirrel）
- 🔄 **智能切换**：当 Emacs 获得焦点时自动切换到英文输入法
- 💾 **上下文恢复**：当 Emacs 失去焦点时恢复之前的输入法
- 🌐 **跨平台支持**：支持 Linux（ibus、fcitx、fcitx5）和 macOS（im-select/Squirrel）
- ⚙️ **可自定义**：可配置哪些输入法引擎会触发自动切换

## 系统要求

### macOS
- 需要安装 [im-select](https://github.com/daipeihust/im-select)：
  ```bash
  brew install im-select
  ```

### Linux
需要以下输入法框架之一：
- **ibus**：需要 `ibus` 命令
- **fcitx**：需要 `fcitx-remote` 命令
- **fcitx5**：需要 `fcitx5-remote` 命令

## 安装方法

### Doom Emacs

1. 将此仓库克隆到 Doom 模块目录：
   ```bash
   git clone https://github.com/yourusername/emacs-input-method-auto-switcher ~/.doom.d/modules/
   ```

2. 在 `~/.doom.d/init.el` 中添加：
   ```elisp
   (doom! :input
          emacs-input-method-auto-switcher)
   ```

3. 运行 `doom sync` 完成安装。

### 手动安装

1. 克隆此仓库：
   ```bash
   git clone https://github.com/yourusername/emacs-input-method-auto-switcher
   ```

2. 在你的 Emacs 配置中添加：
   ```elisp
   (add-to-list 'load-path "/path/to/emacs-input-method-auto-switcher")
   (require 'emacs-input-method-auto-switcher)
   (emacs-input-method-auto-switcher-setup)
   ```

## 配置说明

### 基础配置

```elisp
;; 自动检测框架（默认）
(setq emacs-input-method-auto-switcher-framework 'auto-detect)

;; 或者指定特定的框架
(setq emacs-input-method-auto-switcher-framework 'fcitx5)  ; 选项：'ibus、'fcitx、'fcitx5、'squirrel
```

### 配置非拉丁输入法引擎

自定义哪些输入法引擎会触发自动切换到英文：

```elisp
(setq emacs-input-method-auto-switcher-non-latin-engines
      '("im.rime.inputmethod.Squirrel.Hans"  ; 中文（macOS 上的 Rime）
        "com.apple.keylayout.ABC"             ; ABC 输入法
        "rime"                                 ; Linux 上的 Rime
        "pinyin"                               ; 拼音
        "mozc"                                 ; 日文
        "anthy"                                ; 日文
        "kkc"))                                ; 日文
```

### macOS 专用配置

对于 macOS 用户，请确保已安装 `im-select` 并可访问。该包会自动检测并使用它：

```bash
# 安装 im-select
brew install im-select

# 验证安装
which im-select
```

macOS 上常见的输入法标识符：
- `com.apple.keylayout.ABC` - ABC（英文）
- `im.rime.inputmethod.Squirrel.Hans` - Rime 中文（简体）
- `im.rime.inputmethod.Squirrel.Hant` - Rime 中文（繁体）
- `com.apple.inputmethod.SCIM.ITABC` - 拼音
- `com.apple.inputmethod.SCIM.Shuangpin` - 双拼

你可以通过运行以下命令获取当前输入法标识符：
```bash
im-select
```

## 使用方法

安装和配置完成后，该包会自动工作：

1. **当 Emacs 获得焦点时**：自动切换到英文输入法
2. **当 Emacs 失去焦点时**：恢复之前的输入法

### 手动切换（可选）

你也可以绑定一个快捷键来手动切换输入法：

```elisp
(global-set-key (kbd "C-\\") #'emacs-input-method-auto-switcher-toggle-with-latin)
```

## 工作原理

该包使用 Emacs 内置的 `focus-in-hook` 和 `focus-out-hook` 来检测 Emacs 何时获得或失去焦点：

1. **获得焦点时**：
   - 检测当前输入法
   - 如果是非拉丁输入法，则切换到英文
   - 存储之前的输入法

2. **失去焦点时**：
   - 恢复之前存储的输入法

## 故障排除

### macOS：提示 "im-select is not available"
确保已安装 `im-select` 并在 PATH 中：
```bash
brew install im-select
```

### Linux：输入法没有切换
1. 验证输入法框架是否正在运行：
   ```bash
   # 对于 ibus
   ibus engine
   
   # 对于 fcitx5
   fcitx5-remote -n
   ```

2. 确保命令行工具可用：
   ```bash
   which ibus          # 或 fcitx-remote、fcitx5-remote
   ```

### 自定义输入法未被识别
将你的输入法标识符添加到 `emacs-input-method-auto-switcher-non-latin-engines`：

```elisp
(add-to-list 'emacs-input-method-auto-switcher-non-latin-engines "你的输入法名称")
```

查找输入法标识符的方法：
- macOS：在终端运行 `im-select`
- ibus：运行 `ibus engine`
- fcitx/fcitx5：运行 `fcitx-remote -n` 或 `fcitx5-remote -n`

## 贡献

欢迎贡献！请随时提交 Pull Request。

## 许可证

MIT License

## 作者

为使用多语言的 Emacs 用户用心创建 ❤️

## 相关项目

- [im-select](https://github.com/daipeihust/im-select) - macOS 输入法切换工具
- [emacs-rime](https://github.com/DogLooksGood/emacs-rime) - Emacs 的 Rime 输入法
- [fcitx.el](https://github.com/cute-jumper/fcitx.el) - Emacs 的 Fcitx 集成

