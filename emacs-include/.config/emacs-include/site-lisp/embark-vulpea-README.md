# embark-vulpea

[Embark](https://github.com/oantolin/embark) integration for [Vulpea](https://github.com/d12frosted/vulpea) notes.

Provides contextual actions and an export buffer for `vulpea-note` completion candidates.

## Features

### Embark actions

When acting on a vulpea note candidate (e.g. during `vulpea-find`), the following actions are available:

| Key     | Action                             |
|---------|------------------------------------|
| `RET`   | Visit note                         |
| `o`     | Visit note in other window         |
| `i`     | Insert `id:` link at point         |
| `b`     | Find backlinks                     |
| `w`     | Copy note ID to kill ring          |
| `W`     | Copy org link to kill ring         |
| `D`     | Delete note (with confirmation)    |

All actions from `embark-general-map` are also inherited.

### Embark export

Use `embark-select` to mark multiple vulpea notes during completion, then call `embark-export` to create an org buffer containing links to all selected notes.

By default the export buffer contains a checklist with completion statistics. Set `embark-vulpea-export-readonly` to `t` for a plain read-only list instead.

## Requirements

- Emacs 27.2+
- [vulpea](https://github.com/d12frosted/vulpea) 2.0.0+
- [embark](https://github.com/oantolin/embark) 0.23+

## Installation

### Manual

Clone this repository, add it to your `load-path`, and require the package:

```elisp
(add-to-list 'load-path "/path/to/embark-vulpea")
(require 'embark-vulpea)
```

## Customization

| Variable                          | Default | Description                                     |
|-----------------------------------|---------|-------------------------------------------------|
| `embark-vulpea-export-readonly`   | `nil`   | When non-nil, export buffer is a plain read-only list instead of a checklist |

## Credits

Inspired by [embark-org-roam](https://github.com/bramadams/embark-org-roam).

## License

GPL-3.0. See [LICENSE](LICENSE).
