# ob-eqn

Org Babel backend for [eqn](https://man7.org/linux/man-pages/man7/groff_eqn.7.html), the equation typesetting preprocessor for [groff](https://www.gnu.org/software/groff/)/[troff](https://n-t-roff.github.io/heirloom/doctools.html).

`ob-eqn` lets you write eqn source blocks in Org mode and evaluate them to produce PNG, PDF, or PS output files, which Org can then inline or export like any other result.

## Requirements

- **groff** with eqn support (the `-e` flag)
- **Ghostscript** (`gs`) — required for PNG output only

## Installation

Copy `ob-eqn.el` to a directory on your `load-path`.

### Manual

```emacs-lisp
(add-to-list 'load-path "/path/to/ob-eqn")
```

## Enabling in Emacs

Load `ob-eqn` and register `eqn` as a Babel language:

```emacs-lisp
(require 'ob-eqn)
(org-babel-do-load-languages
 'org-babel-load-languages
 (append org-babel-load-languages
         '((eqn . t))))
```

## Usage

Every eqn source block requires a `:file` header argument specifying the output path. The file extension determines the output format (`png`, `pdf`, or `ps`).

### Simple expression (auto-wrapped)

When the body does not begin with `.EQ`, ob-eqn wraps it automatically:

```org
#+begin_src eqn :file pythagoras.png
x sup 2 + y sup 2 = z sup 2
#+end_src
```

### Pass-through mode

If the body already starts with `.EQ`, it is used as-is, giving you full control over eqn delimiters and inline equations:

```org
#+begin_src eqn :file integral.png
.EQ
int from 0 to inf e sup {-x sup 2} dx ~=~ {sqrt pi} over 2
.EN
#+end_src
```

### PDF output

```org
#+begin_src eqn :file maxwell.pdf
del cdot bold E ~=~ rho over epsilon sub 0
#+end_src
```

### Passing groff registers via `:cmdline`

```org
#+begin_src eqn :file big.png :cmdline "-rPS=18"
x sup 2 + y sup 2 = z sup 2
#+end_src
```

## Configuration

All options belong to the `ob-eqn` customization group (`M-x customize-group RET ob-eqn`).

| Variable | Default | Description |
|---|---|---|
| `ob-eqn-groff-cmd` | `"groff"` | Path to the groff executable |
| `ob-eqn-groff-ms-args` | `"-ms"` | Groff macro package (`-ms`, `-me`, `-mom`, or `""`) |
| `ob-eqn-gs-cmd` | `"gs"` | Path to the Ghostscript executable |
| `ob-eqn-png-dpi` | `150` | PNG output resolution in dots per inch |
| `ob-eqn-png-padding` | `6` | Padding in points added around the PNG bounding box |
| `ob-eqn-preamble` | `""` | groff/troff commands inserted at the top of every document |

### Example: increase PNG resolution

```emacs-lisp
(setq ob-eqn-png-dpi 300)
```

### Example: add a preamble to set the point size

```emacs-lisp
(setq ob-eqn-preamble ".nr PS 14")
```

## How it works

For PNG output, ob-eqn uses a two-pass Ghostscript pipeline: the first pass extracts the tight bounding box of the rendered equation using the `bbox` device (reading the `%%HiResBoundingBox` comment from stderr), and the second pass renders only that region at the configured DPI. The crop is applied via a PostScript `BeginPage` hook registered through `setpagedevice`, which translates the coordinate origin so that the equation fills the computed canvas. This produces a cleanly cropped image with no surrounding whitespace beyond the configurable padding.

For PDF and PS output the groff PostScript driver is used directly, with no Ghostscript step required.

## License

BSD 2-Clause. See [LICENSE](LICENSE).
