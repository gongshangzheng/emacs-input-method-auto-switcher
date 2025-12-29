# Emacs Input Method Auto Switcher

[中文版](./README.md)

An Emacs package that automatically switches input methods when Emacs gains or loses focus, helping you seamlessly switch between English and other languages while coding.

## Features

- 🎯 **Auto-detect Input Method Framework**: Automatically detects available input method frameworks (ibus, fcitx, fcitx5, Squirrel on macOS)
- 🔄 **Smart Switching**: Automatically switches to Latin/English input when Emacs gains focus
- 💾 **Context Restoration**: Restores your previous input method when Emacs loses focus
- 🌐 **Cross-platform Support**: Works on Linux (ibus, fcitx, fcitx5) and macOS (im-select/Squirrel)
- ⚙️ **Customizable**: Configure which input engines should trigger auto-switching

## Requirements

### macOS
- [im-select](https://github.com/daipeihust/im-select) - Install via:
  ```bash
  brew install im-select
  ```

### Linux
One of the following input method frameworks:
- **ibus**: `ibus`
- **fcitx**: `fcitx-remote`
- **fcitx5**: `fcitx5-remote`

## Installation

### Doom Emacs

1. Clone this repository to your Doom modules directory:
   ```bash
   git clone https://github.com/yourusername/emacs-input-method-auto-switcher ~/.doom.d/modules/
   ```

2. Add to your `~/.doom.d/init.el`:
   ```elisp
   (doom! :input
          emacs-input-method-auto-switcher)
   ```

3. Run `doom sync` to install.

### Manual Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/emacs-input-method-auto-switcher
   ```

2. Add to your Emacs configuration:
   ```elisp
   (add-to-list 'load-path "/path/to/emacs-input-method-auto-switcher")
   (require 'emacs-input-method-auto-switcher)
   (emacs-input-method-auto-switcher-setup)
   ```

## Configuration

### Basic Configuration

```elisp
;; Auto-detect framework (default)
(setq emacs-input-method-auto-switcher-framework 'auto-detect)

;; Or specify a specific framework
(setq emacs-input-method-auto-switcher-framework 'fcitx5)  ; Options: 'ibus, 'fcitx, 'fcitx5, 'squirrel
```

### Configure Latin Engines Whitelist

By default, only the following Latin input methods will NOT trigger auto-switch (whitelist mode):
- `com.apple.keylayout.ABC` - macOS Latin input
- `xkb:us::eng` - Linux fcitx5 Latin input

**All other input methods** (including Chinese, Japanese, Korean, etc.) will automatically switch to the corresponding Latin input method when Emacs gains focus.

If you need to customize the whitelist (usually not necessary), you can modify:

```elisp
(setq emacs-input-method-auto-switcher-latin-engines
      '("com.apple.keylayout.ABC"  ; macOS Latin input
        "xkb:us::eng"))             ; Linux fcitx5 Latin input
```

### macOS Specific Configuration

For macOS users, make sure `im-select` is installed and accessible. The package will automatically detect and use it:

```bash
# Install im-select
brew install im-select

# Verify installation
which im-select
```

Common input method identifiers on macOS:
- `com.apple.keylayout.ABC` - ABC (English)
- `im.rime.inputmethod.Squirrel.Hans` - Rime Chinese (Simplified)
- `im.rime.inputmethod.Squirrel.Hant` - Rime Chinese (Traditional)
- `com.apple.inputmethod.SCIM.ITABC` - Pinyin
- `com.apple.inputmethod.SCIM.Shuangpin` - Shuangpin

You can get your current input method identifier by running:
```bash
im-select
```

## Usage

Once installed and configured, the package works automatically:

1. **When Emacs gains focus**: Automatically switches to English/Latin input
2. **When Emacs loses focus**: Restores your previous input method

### Manual Toggle (Optional)

You can also bind a key to manually toggle input methods:

```elisp
(global-set-key (kbd "C-\\") #'emacs-input-method-auto-switcher-toggle-with-latin)
```

## Recommendations

### Recommended: Use emacs-rime for Chinese Input

For users who need to input Chinese (or other CJK languages) in Emacs, we **strongly recommend** using [emacs-rime](https://github.com/DogLooksGood/emacs-rime) to manage input within Emacs.

#### Why emacs-rime?

Using system input methods for Chinese input in Emacs often causes problems:
- 🚫 **Key Binding Conflicts**: System input methods may intercept Emacs keybindings (like `C-n`, `C-p`), breaking normal editing
- 😰 **Context Switching**: Frequent switching between editing and Chinese input creates a poor user experience
- 🐛 **Candidate Window Issues**: System input method candidate windows may not integrate well with Emacs interface

**Benefits of emacs-rime**:
- ✅ **Perfect Integration**: As a native Emacs input method, it avoids all key binding conflicts
- ✅ **Seamless Switching**: Toggle between English and Chinese instantly with `C-\` without leaving Emacs
- ✅ **Consistent Experience**: Candidate window integrates perfectly with Emacs UI
- ✅ **Full-Featured**: Supports all Rime features (Pinyin, Shuangpin, Wubi, etc.)

#### Combined Usage

emacs-rime works perfectly with this package:
- **Inside Emacs**: Use emacs-rime for Chinese input (toggle with `C-\`)
- **Outside Emacs**: Use system input method
- **Focus Changes**: This package automatically manages system input method state when Emacs gains/loses focus

#### Quick Start with emacs-rime

```elisp
;; For Doom Emacs users, add to packages.el
(package! rime)

;; Configure in config.el
(use-package rime
  :custom
  (default-input-method "rime")  ; Set default input method
  (rime-show-candidate 'posframe))  ; Use posframe for candidate display
```

For more details, see: [emacs-rime documentation](https://github.com/DogLooksGood/emacs-rime)

## How It Works

The package uses Emacs' built-in `focus-in-hook` and `focus-out-hook` to detect when Emacs gains or loses focus:

1. **On Focus In**: 
   - Detects current input method
   - If it's a non-Latin input method, switches to English
   - Stores the previous input method

2. **On Focus Out**:
   - Restores the previously stored input method

## Troubleshooting

### macOS: "im-select is not available"
Make sure `im-select` is installed and in your PATH:
```bash
brew install im-select
```

### Linux: Input method not switching
1. Verify your input method framework is running:
   ```bash
   # For ibus
   ibus engine
   
   # For fcitx5
   fcitx5-remote -n
   ```

2. Make sure the command-line tools are available:
   ```bash
   which ibus          # or fcitx-remote, fcitx5-remote
   ```

### Customize Latin Engines Whitelist
If you need to add other input methods to the whitelist (to prevent auto-switching), you can modify:

```elisp
(add-to-list 'emacs-input-method-auto-switcher-latin-engines "your-latin-input-method-identifier")
```

**Note**: Only Latin input methods should be added to the whitelist. Non-Latin input methods (Chinese, Japanese, etc.) should NOT be added to the whitelist, as they will automatically switch to Latin input.

To find your input method identifier:
- macOS: Run `im-select` in terminal
- ibus: Run `ibus engine`
- fcitx/fcitx5: Run `fcitx-remote -n` or `fcitx5-remote -n`

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License

## Author

Created with ❤️ for Emacs users who work with multiple languages.

## Related Projects

- [im-select](https://github.com/daipeihust/im-select) - Input method switcher for macOS
- [emacs-rime](https://github.com/DogLooksGood/emacs-rime) - Rime input method for Emacs
- [fcitx.el](https://github.com/cute-jumper/fcitx.el) - Fcitx integration for Emacs
