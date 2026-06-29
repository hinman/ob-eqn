;;; ob-eqn.el --- Babel functions for eqn            -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Lee Hinman <hinman@gmail.com>
;; SPDX-License-Identifier: BSD-2-Clause

;; Author: Lee Hinman <hinman@gmail.com>
;; Assisted-by: Claude:claude-sonnet-4-6
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.4"))
;; Keywords: org babel eqn groff troff wp
;; URL: https://github.com/hinman/ob-eqn

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Org-Babel support for evaluating eqn source blocks.
;;
;; eqn is the equation typesetting preprocessor for groff/troff.
;; For language reference see groff_eqn(7).
;;
;; Characteristics:
;;
;; - No sessions (eqn is a batch preprocessor, not interactive).
;;
;; - Results are always of type "file"; the default extension is "png".
;;
;; - Supported output formats: png, pdf, ps.
;;
;; - PNG output is tightly cropped to the equation via a two-pass
;;   Ghostscript pipeline: pass 1 extracts the bounding box, pass 2
;;   renders only that region at the configured DPI.
;;
;; - The groff -ms macro package is used by default for proper
;;   display-equation centering and spacing.  Override with
;;   `ob-eqn-groff-ms-args'.
;;
;; Pipeline:
;;
;;   User body → expand-body (auto-wrap or pass-through)
;;             → temp groff source file
;;             → groff -ms -e -T{pdf,ps,ps}
;;             → for PNG: two-pass gs crop → output.png
;;             → for PDF/PS: direct output
;;
;; Requirements:
;;
;;   groff   (with eqn support, i.e. the -e flag)
;;   gs      (Ghostscript, for PNG output)
;;
;; Usage example:
;;
;;   #+begin_src eqn :file pythagoras.png
;;   x sup 2 + y sup 2 = z sup 2
;;   #+end_src
;;
;;   #+begin_src eqn :file integral.png :cmdline "-rPS=14"
;;   .EQ
;;   int from 0 to inf e sup {-x sup 2} dx ~=~ {sqrt pi} over 2
;;   .EN
;;   #+end_src

;;; Code:

(require 'ob)

(defgroup ob-eqn nil
  "Org Babel functions for eqn source blocks."
  :group 'org-babel)

(defvar org-babel-default-header-args:eqn
  '((:results  . "file graphics")
    (:exports  . "results")
    (:file-ext . "png"))
  "Default header arguments for eqn source blocks.")

(defcustom ob-eqn-groff-cmd "groff"
  "Path to the groff executable."
  :group 'ob-eqn
  :type 'string
  :risky t)

(defcustom ob-eqn-groff-ms-args "-ms"
  "Groff macro package argument passed to every invocation.
Common values: \"-ms\" (default), \"-me\", \"-mom\", or \"\" for none."
  :group 'ob-eqn
  :type 'string)

(defcustom ob-eqn-gs-cmd "gs"
  "Path to the Ghostscript executable, used for PNG output."
  :group 'ob-eqn
  :type 'string
  :risky t)

(defcustom ob-eqn-png-dpi 150
  "Resolution in dots per inch for PNG output."
  :group 'ob-eqn
  :type 'integer)

(defcustom ob-eqn-png-padding 6
  "Padding in points added on each side of the bounding box for PNG output."
  :group 'ob-eqn
  :type 'integer)

(defcustom ob-eqn-preamble ""
  "Groff/troff commands inserted at the top of every eqn document.
Use this to set registers such as \".nr PS 12\" or override -ms defaults.
The preamble is placed before the .EQ block (or before the user body
when pass-through mode is active)."
  :group 'ob-eqn
  :type 'string)

;;; Body expansion

(defun org-babel-expand-body:eqn (body params)
  "Prepare the full groff document for BODY according to PARAMS.
If BODY already begins with a .EQ line (possibly preceded by whitespace),
it is used as-is (pass-through mode) so the user can supply custom eqn
delimiters or inline equations.  Otherwise BODY is wrapped in .EQ / .EN.
In both cases `ob-eqn-preamble' is prepended, and the :prologue
and :epilogue header arguments are applied."
  (let ((prologue (cdr (assq :prologue params)))
        (epilogue (cdr (assq :epilogue params)))
        (inner
         (if (string-match-p "\\`[[:space:]]*\\.EQ" body)
             body
           (concat ".EQ\n" body "\n.EN"))))
    (concat
     (and prologue (concat prologue "\n"))
     (and (not (string-empty-p ob-eqn-preamble))
          (concat ob-eqn-preamble "\n"))
     inner
     (and epilogue (concat "\n" epilogue)))))

;;; Ghostscript bounding-box helpers

(defun ob-eqn--gs-bbox (ps-file)
  "Return the content bounding box of PS-FILE as (llx lly urx ury).
Uses Ghostscript's bbox device.  The values are floats taken from the
%%HiResBoundingBox comment in gs output (written to stderr; captured via
2>&1).  Returns nil when no renderable content is detected."
  (let ((out (shell-command-to-string
              (format "%s -sDEVICE=bbox -dBATCH -dNOPAUSE -dSAFER -q %s 2>&1"
                      ob-eqn-gs-cmd
                      (shell-quote-argument ps-file)))))
    (when (string-match
           "%%HiResBoundingBox: \
\\([0-9.]+\\) \\([0-9.]+\\) \\([0-9.]+\\) \\([0-9.]+\\)"
           out)
      (mapcar #'string-to-number
              (list (match-string 1 out) (match-string 2 out)
                    (match-string 3 out) (match-string 4 out))))))

(defun ob-eqn--ps-to-png (ps-file out-file dpi padding)
  "Convert PS-FILE to a cropped PNG at OUT-FILE.
DPI controls resolution; PADDING (in points) is added around the
detected bounding box.  Signals an error if no content is found."
  (let* ((bbox (or (ob-eqn--gs-bbox ps-file)
                   (error "ob-eqn: no renderable content detected in \
groff output (check your eqn syntax)")))
         (llx (nth 0 bbox)) (lly (nth 1 bbox))
         (urx (nth 2 bbox)) (ury (nth 3 bbox))
         (W   (ceiling (+ (- urx llx) (* 2 padding))))
         (H   (ceiling (+ (- ury lly) (* 2 padding))))
         (TX  (- padding llx))
         (TY  (- padding lly)))
    (shell-command
     (format
      "%s -sDEVICE=pngalpha -r%d -dBATCH -dNOPAUSE -dSAFER \
-dFIXEDMEDIA -dDEVICEWIDTHPOINTS=%d -dDEVICEHEIGHTPOINTS=%d \
-sOutputFile=%s \
-c \"<< /BeginPage { pop %g %g translate } bind >> setpagedevice\" \
-f %s"
      ob-eqn-gs-cmd dpi W H
      (shell-quote-argument out-file)
      TX TY
      (shell-quote-argument ps-file)))))

;;; Execution

(defun org-babel-execute:eqn (body params)
  "Execute an eqn source BODY block according to PARAMS.
This function is called by `org-babel-execute-src-block'."
  (let* ((out-file (or (cdr (assq :file params))
                       (error "ob-eqn: ':file' header argument is required")))
         (ext      (file-name-extension out-file))
         (cmdline  (or (cdr (assq :cmdline params)) ""))
         (in-file  (org-babel-temp-file "eqn-"))
         (groff-base (string-join
                      (delete "" (list ob-eqn-groff-cmd
                                       ob-eqn-groff-ms-args
                                       "-e"
                                       cmdline))
                      " ")))
    (with-temp-file in-file
      (insert (org-babel-expand-body:eqn body params)))
    (pcase ext
      ("pdf"
       (shell-command
        (format "%s -Tpdf %s > %s"
                groff-base
                (shell-quote-argument in-file)
                (shell-quote-argument out-file))))
      ("ps"
       (shell-command
        (format "%s -Tps %s > %s"
                groff-base
                (shell-quote-argument in-file)
                (shell-quote-argument out-file))))
      ("png"
       (let ((ps-tmp (org-babel-temp-file "eqn-ps-" ".ps")))
         (shell-command
          (format "%s -Tps %s > %s"
                  groff-base
                  (shell-quote-argument in-file)
                  (shell-quote-argument ps-tmp)))
         (ob-eqn--ps-to-png ps-tmp out-file
                             ob-eqn-png-dpi
                             ob-eqn-png-padding)))
      (_
       (error "ob-eqn: unsupported output format %S (use png, pdf, or ps)"
              ext)))
    nil))

(defun org-babel-prep-session:eqn (_session _params)
  "Signal an error: eqn does not support interactive sessions."
  (error "ob-eqn: eqn does not support sessions"))

(provide 'ob-eqn)

;;; ob-eqn.el ends here
