;;; test-ob-eqn.el --- ERT tests for ob-eqn.el       -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Lee Hinman <hinman@gmail.com>
;; SPDX-License-Identifier: BSD-2-Clause

;; Author: Lee Hinman <hinman@gmail.com>

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Three tiers of tests:
;;
;; Tier 1 — unit tests: pure Elisp logic; external tools mocked via cl-letf.
;;           Always run.
;;
;; Tier 2 — integration tests: require groff and gs to be on PATH.
;;           Each test begins with (skip-unless ...) and executes a real
;;           eqn block, verifying the output file.
;;
;; Tier 3 — groff-only tests: require only groff; verify that expand-body
;;           output is accepted by groff without errors.
;;
;; Run from the command line:
;;   emacs -batch -L . -L /path/to/org/lisp \
;;         -l test-ob-eqn.el \
;;         -f ert-run-tests-batch-and-exit
;;
;; Or interactively:
;;   M-x ert RET t RET

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Ensure ob-eqn.el in the same directory is loaded.
(let ((here (file-name-directory (or load-file-name buffer-file-name
                                     default-directory))))
  (add-to-list 'load-path here))

(require 'ob-eqn)

;;;; Tier 1 — Unit tests (no external tools required)

;;; Feature / variable sanity

(ert-deftest ob-eqn/feature-provision ()
  "ob-eqn provides itself."
  (should (featurep 'ob-eqn)))

(ert-deftest ob-eqn/default-header-args-bound ()
  "`org-babel-default-header-args:eqn' is bound."
  (should (boundp 'org-babel-default-header-args:eqn)))

(ert-deftest ob-eqn/default-results-file-graphics ()
  "Default :results value includes \"file graphics\"."
  (should (string= "file graphics"
                   (cdr (assq :results
                              org-babel-default-header-args:eqn)))))

(ert-deftest ob-eqn/default-file-ext-png ()
  "Default :file-ext is \"png\"."
  (should (string= "png"
                   (cdr (assq :file-ext
                              org-babel-default-header-args:eqn)))))

(ert-deftest ob-eqn/default-exports-results ()
  "Default :exports is \"results\"."
  (should (string= "results"
                   (cdr (assq :exports
                              org-babel-default-header-args:eqn)))))

(ert-deftest ob-eqn/customvars-bound ()
  "All defcustoms are bound after loading."
  (should (boundp 'org-babel-eqn-groff-cmd))
  (should (boundp 'org-babel-eqn-groff-ms-args))
  (should (boundp 'org-babel-eqn-gs-cmd))
  (should (boundp 'org-babel-eqn-png-dpi))
  (should (boundp 'org-babel-eqn-png-padding))
  (should (boundp 'org-babel-eqn-preamble)))

(ert-deftest ob-eqn/no-sessions ()
  "`org-babel-prep-session:eqn' signals an error."
  (should-error (org-babel-prep-session:eqn nil nil)))

;;; expand-body tests

(ert-deftest ob-eqn/expand-body-auto-wrap ()
  "Plain body is wrapped in .EQ / .EN."
  (let ((org-babel-eqn-preamble ""))
    (let ((result (org-babel-expand-body:eqn "x sup 2" '())))
      (should (string-match-p "\\.EQ" result))
      (should (string-match-p "\\.EN" result))
      (should (string-match-p "x sup 2" result)))))

(ert-deftest ob-eqn/expand-body-auto-wrap-order ()
  ".EQ precedes body which precedes .EN."
  (let ((org-babel-eqn-preamble ""))
    (let ((result (org-babel-expand-body:eqn "x sup 2" '())))
      (should (< (string-match "\\.EQ" result)
                 (string-match "x sup 2" result)))
      (should (< (string-match "x sup 2" result)
                 (string-match "\\.EN" result))))))

(ert-deftest ob-eqn/expand-body-passthrough-dotEQ ()
  "Body starting with .EQ is not double-wrapped."
  (let ((org-babel-eqn-preamble ""))
    (let ((result (org-babel-expand-body:eqn ".EQ\nx sup 2\n.EN" '())))
      ;; Should contain exactly one .EQ
      (should (= 1 (cl-count-if
                    (lambda (m) m)
                    (let (matches)
                      (with-temp-buffer
                        (insert result)
                        (goto-char (point-min))
                        (while (re-search-forward "^\\.EQ$" nil t)
                          (push t matches)))
                      matches)))))))

(ert-deftest ob-eqn/expand-body-passthrough-preserves-body ()
  "Pass-through body text is present unchanged in the output."
  (let ((org-babel-eqn-preamble ""))
    (let* ((body ".EQ\nint from 0 to inf\n.EN")
           (result (org-babel-expand-body:eqn body '())))
      (should (string-match-p "int from 0 to inf" result)))))

(ert-deftest ob-eqn/expand-body-passthrough-whitespace ()
  "Leading whitespace before .EQ is still detected as pass-through."
  (let ((org-babel-eqn-preamble ""))
    (let ((result (org-babel-expand-body:eqn "  .EQ\nx\n.EN" '())))
      ;; Should not gain an extra .EQ wrapper
      (should-not (string-match-p "\\.EQ\n\\.EQ" result)))))

(ert-deftest ob-eqn/expand-body-preamble-prepended ()
  "`org-babel-eqn-preamble' appears before .EQ in the output."
  (let ((org-babel-eqn-preamble ".nr PS 12"))
    (let ((result (org-babel-expand-body:eqn "x sup 2" '())))
      (should (string-match-p "\\.nr PS 12" result))
      (should (< (string-match "\\.nr PS 12" result)
                 (string-match "\\.EQ" result))))))

(ert-deftest ob-eqn/expand-body-empty-preamble ()
  "Empty preamble produces no stray blank line before .EQ."
  (let ((org-babel-eqn-preamble ""))
    (let ((result (org-babel-expand-body:eqn "x" '())))
      (should (string-prefix-p ".EQ" result)))))

(ert-deftest ob-eqn/expand-body-prologue ()
  ":prologue param is prepended before preamble."
  (let ((org-babel-eqn-preamble ".nr PS 12"))
    (let ((result (org-babel-expand-body:eqn
                   "x sup 2"
                   '((:prologue . ".nr PO 0.25i")))))
      (should (string-match-p "\\.nr PO 0\\.25i" result))
      (should (< (string-match "\\.nr PO 0\\.25i" result)
                 (string-match "\\.nr PS 12" result))))))

(ert-deftest ob-eqn/expand-body-epilogue ()
  ":epilogue param is appended after .EN."
  (let ((org-babel-eqn-preamble ""))
    (let ((result (org-babel-expand-body:eqn
                   "x sup 2"
                   '((:epilogue . ".bp")))))
      (should (string-match-p "\\.bp" result))
      (should (< (string-match "\\.EN" result)
                 (string-match "\\.bp" result))))))

;;; ob-eqn--gs-bbox tests (mock shell-command-to-string)

(defconst ob-eqn--test-bbox-output
  "%%BoundingBox: 72 705 121 717\n\
%%HiResBoundingBox: 72.503998 705.509978 120.365996 716.507978\n"
  "Sample Ghostscript bbox device output used in unit tests.")

(ert-deftest ob-eqn/gs-bbox-parses-hires ()
  "`ob-eqn--gs-bbox' extracts the four HiResBoundingBox values."
  (cl-letf (((symbol-function 'shell-command-to-string)
             (lambda (_cmd) ob-eqn--test-bbox-output)))
    (let ((result (ob-eqn--gs-bbox "/fake.ps")))
      (should (= 4 (length result)))
      (should (cl-every #'numberp result)))))

(ert-deftest ob-eqn/gs-bbox-correct-values ()
  "`ob-eqn--gs-bbox' returns the exact float values from the bbox line."
  (cl-letf (((symbol-function 'shell-command-to-string)
             (lambda (_cmd) ob-eqn--test-bbox-output)))
    (let ((result (ob-eqn--gs-bbox "/fake.ps")))
      (should (= (nth 0 result) 72.503998))
      (should (= (nth 1 result) 705.509978))
      (should (= (nth 2 result) 120.365996))
      (should (= (nth 3 result) 716.507978)))))

(ert-deftest ob-eqn/gs-bbox-returns-nil-no-content ()
  "`ob-eqn--gs-bbox' returns nil when gs reports no content."
  (cl-letf (((symbol-function 'shell-command-to-string)
             (lambda (_cmd) "")))
    (should-not (ob-eqn--gs-bbox "/empty.ps"))))

(ert-deftest ob-eqn/gs-bbox-uses-hires-not-lowres ()
  "Prefer %%HiResBoundingBox over the integer %%BoundingBox."
  (cl-letf (((symbol-function 'shell-command-to-string)
             (lambda (_cmd) ob-eqn--test-bbox-output)))
    (let ((result (ob-eqn--gs-bbox "/fake.ps")))
      ;; Low-res would give exactly 72; high-res gives 72.503998
      (should (> (nth 0 result) 72.0)))))

;;; PNG crop math test

(ert-deftest ob-eqn/png-crop-math ()
  "Bounding box arithmetic produces correct W, H, TX, TY in the gs command.
Bbox (72.5 705.5 120.4 716.5) with padding 6 gives:
  W = ceil(120.4 - 72.5 + 12) = ceil(59.9) = 60
  H = ceil(716.5 - 705.5 + 12) = ceil(23)  = 23
  TX = -(72.5 - 6) = -66.5
  TY = -(705.5 - 6) = -699.5"
  (let (captured-cmd)
    (cl-letf (((symbol-function 'ob-eqn--gs-bbox)
               (lambda (_f) '(72.5 705.5 120.4 716.5)))
              ((symbol-function 'shell-command)
               (lambda (cmd) (setq captured-cmd cmd) 0)))
      (ob-eqn--ps-to-png "/fake.ps" "/fake.png" 150 6)
      (should (string-match-p "DEVICEWIDTHPOINTS=60"  captured-cmd))
      (should (string-match-p "DEVICEHEIGHTPOINTS=23" captured-cmd))
      (should (string-match-p "-66\\.5 -699\\.5 translate" captured-cmd)))))

;;; Command construction tests (mock shell-command and org-babel-temp-file)

(defmacro ob-eqn--with-mock-shell (&rest body)
  "Bind `captured-cmds' to a list of shell commands issued during BODY.
Also stubs `org-babel-temp-file' to return predictable paths."
  (declare (indent 0))
  `(let (captured-cmds)
     (cl-letf (((symbol-function 'shell-command)
                (lambda (cmd)
                  (push cmd captured-cmds)
                  0))
               ((symbol-function 'shell-command-to-string)
                (lambda (_cmd) ob-eqn--test-bbox-output))
               ((symbol-function 'org-babel-temp-file)
                (lambda (prefix &optional suffix)
                  (concat "/tmp/" prefix "test" (or suffix ""))))
               ((symbol-function 'with-temp-file)
                (lambda (_file &rest _body) nil)))
       ,@body
       (nreverse captured-cmds))))

(ert-deftest ob-eqn/execute-pdf-uses-tpdf ()
  "`org-babel-execute:eqn' with .pdf calls groff -Tpdf."
  (let ((cmds (ob-eqn--with-mock-shell
                (org-babel-execute:eqn "x sup 2" '((:file . "/out.pdf"))))))
    (should (= 1 (length cmds)))
    (should (string-match-p "-Tpdf" (car cmds)))))

(ert-deftest ob-eqn/execute-pdf-no-gs-call ()
  "PDF output does not invoke Ghostscript."
  (let ((cmds (ob-eqn--with-mock-shell
                (org-babel-execute:eqn "x sup 2" '((:file . "/out.pdf"))))))
    (should-not (cl-some (lambda (c) (string-match-p "pngalpha\\|bbox" c))
                         cmds))))

(ert-deftest ob-eqn/execute-ps-uses-tps ()
  "`org-babel-execute:eqn' with .ps calls groff -Tps."
  (let ((cmds (ob-eqn--with-mock-shell
                (org-babel-execute:eqn "x sup 2" '((:file . "/out.ps"))))))
    (should (= 1 (length cmds)))
    (should (string-match-p "-Tps" (car cmds)))))

(ert-deftest ob-eqn/execute-png-two-shell-commands ()
  "PNG output issues exactly two shell commands: groff then gs."
  (let ((cmds (ob-eqn--with-mock-shell
                (org-babel-execute:eqn "x sup 2" '((:file . "/out.png"))))))
    (should (= 2 (length cmds)))))

(ert-deftest ob-eqn/execute-png-groff-then-gs ()
  "First shell call is groff -Tps; second is gs pngalpha."
  (let ((cmds (ob-eqn--with-mock-shell
                (org-babel-execute:eqn "x sup 2" '((:file . "/out.png"))))))
    (should (string-match-p "-Tps"     (nth 0 cmds)))
    (should (string-match-p "pngalpha" (nth 1 cmds)))))

(ert-deftest ob-eqn/execute-cmdline-forwarded ()
  ":cmdline value appears in the groff invocation."
  (let ((cmds (ob-eqn--with-mock-shell
                (org-babel-execute:eqn
                 "x sup 2"
                 '((:file . "/out.pdf") (:cmdline . "-rPS=14"))))))
    (should (string-match-p "-rPS=14" (car cmds)))))

(ert-deftest ob-eqn/execute-ms-args-in-cmd ()
  "`org-babel-eqn-groff-ms-args' appears in the groff invocation."
  (let ((org-babel-eqn-groff-ms-args "-me"))
    (let ((cmds (ob-eqn--with-mock-shell
                  (org-babel-execute:eqn "x" '((:file . "/out.pdf"))))))
      (should (string-match-p "-me" (car cmds))))))

(ert-deftest ob-eqn/execute-missing-file-errors ()
  "Missing :file header argument signals an error."
  (should-error
   (ob-eqn--with-mock-shell
     (org-babel-execute:eqn "x sup 2" '()))))

(ert-deftest ob-eqn/execute-unsupported-ext-errors ()
  "Unsupported output extension signals an error."
  (should-error
   (ob-eqn--with-mock-shell
     (org-babel-execute:eqn "x sup 2" '((:file . "/out.svg"))))))

(ert-deftest ob-eqn/execute-returns-nil ()
  "`org-babel-execute:eqn' returns nil (output written to file)."
  (cl-letf (((symbol-function 'shell-command)
             (lambda (_cmd) 0))
            ((symbol-function 'org-babel-temp-file)
             (lambda (prefix &optional suffix)
               (concat "/tmp/" prefix "test" (or suffix ""))))
            ((symbol-function 'with-temp-file)
             (lambda (_file &rest _body) nil)))
    (should (null (org-babel-execute:eqn
                   "x" '((:file . "/tmp/ob-eqn-ret-test.pdf")))))))

;;;; Tier 3 — groff-only tests (require groff; skip otherwise)

(ert-deftest ob-eqn/groff-accepts-auto-wrapped-body ()
  "groff -ms -e -Tps accepts the output of `expand-body' for a plain body."
  (skip-unless (executable-find "groff"))
  (let* ((org-babel-eqn-preamble "")
         (doc (org-babel-expand-body:eqn "x sup 2 + y sup 2 = z sup 2" '()))
         (in-file (make-temp-file "ob-eqn-test-" nil ".eqn"))
         (exit-code nil))
    (unwind-protect
        (progn
          (with-temp-file in-file (insert doc))
          (setq exit-code
                (call-process "groff" nil nil nil "-ms" "-e" "-Tps" in-file))
          (should (= 0 exit-code)))
      (delete-file in-file))))

(ert-deftest ob-eqn/groff-accepts-passthrough-body ()
  "groff -ms -e -Tps accepts pass-through body (user supplies .EQ/.EN)."
  (skip-unless (executable-find "groff"))
  (let* ((org-babel-eqn-preamble "")
         (body ".EQ\nint from 0 to inf e sup {-x sup 2} dx\n.EN")
         (doc (org-babel-expand-body:eqn body '()))
         (in-file (make-temp-file "ob-eqn-test-" nil ".eqn"))
         (exit-code nil))
    (unwind-protect
        (progn
          (with-temp-file in-file (insert doc))
          (setq exit-code
                (call-process "groff" nil nil nil "-ms" "-e" "-Tps" in-file))
          (should (= 0 exit-code)))
      (delete-file in-file))))

;;;; Tier 2 — Integration tests (require groff and gs)

(defun ob-eqn--tools-available-p ()
  "Return non-nil when both groff and gs are on PATH."
  (and (executable-find "groff") (executable-find "gs")))

(defmacro ob-eqn--with-output-file (ext body-str params-extra &rest assertions)
  "Execute an eqn block and run ASSERTIONS with `out-file' bound.
EXT is the file extension (string).  BODY-STR is the eqn source.
PARAMS-EXTRA is a list of extra params (alist entries).  The output
file is deleted after assertions run."
  (declare (indent 3))
  `(let* ((out-file (make-temp-file "ob-eqn-integ-" nil (concat "." ,ext))))
     (unwind-protect
         (progn
           (org-babel-execute:eqn
            ,body-str
            (append (list (cons :file out-file)) ,params-extra))
           ,@assertions)
       (when (file-exists-p out-file)
         (delete-file out-file)))))

(ert-deftest ob-eqn/integration-png-file-created ()
  "Executing a simple eqn block creates the output PNG file."
  (skip-unless (ob-eqn--tools-available-p))
  (ob-eqn--with-output-file "png" "x sup 2 + y sup 2 = z sup 2" '()
    (should (file-exists-p out-file))))

(ert-deftest ob-eqn/integration-png-is-nonempty ()
  "PNG output file is non-empty."
  (skip-unless (ob-eqn--tools-available-p))
  (ob-eqn--with-output-file "png" "x sup 2" '()
    (should (> (file-attribute-size (file-attributes out-file)) 0))))

(ert-deftest ob-eqn/integration-png-valid-header ()
  "PNG output begins with the PNG magic bytes."
  (skip-unless (ob-eqn--tools-available-p))
  (ob-eqn--with-output-file "png" "x sup 2 + y sup 2 = z sup 2" '()
    (let ((magic (with-temp-buffer
                   (set-buffer-multibyte nil)
                   (insert-file-contents-literally out-file nil 0 8)
                   (buffer-string))))
      (should (string= "\x89PNG\r\n\x1a\n" magic)))))

(ert-deftest ob-eqn/integration-png-is-tight ()
  "PNG output is tightly cropped: smaller than a full letter page at 150 DPI.
A full letter page at 150 DPI is 1275x1650; a tight equation should be
well under 400x200."
  (skip-unless (ob-eqn--tools-available-p))
  (ob-eqn--with-output-file "png" "x sup 2 + y sup 2 = z sup 2" '()
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (insert-file-contents-literally out-file nil 0 24)
      (let* ((data (buffer-string))
             ;; PNG IHDR: bytes 16-19 = width (big-endian), 20-23 = height
             (w (+ (* 16777216 (aref data 16))
                   (*    65536 (aref data 17))
                   (*      256 (aref data 18))
                   (aref data 19)))
             (h (+ (* 16777216 (aref data 20))
                   (*    65536 (aref data 21))
                   (*      256 (aref data 22))
                   (aref data 23))))
        (should (< w 400))
        (should (< h 200))))))

(ert-deftest ob-eqn/integration-pdf-file-created ()
  "Executing an eqn block with :file out.pdf creates the output file."
  (skip-unless (ob-eqn--tools-available-p))
  (ob-eqn--with-output-file "pdf" "x sup 2 + y sup 2 = z sup 2" '()
    (should (file-exists-p out-file))))

(ert-deftest ob-eqn/integration-pdf-valid-header ()
  "PDF output begins with %PDF."
  (skip-unless (ob-eqn--tools-available-p))
  (ob-eqn--with-output-file "pdf" "x sup 2" '()
    (let ((header (with-temp-buffer
                    (insert-file-contents out-file nil 0 4)
                    (buffer-string))))
      (should (string= "%PDF" header)))))

(ert-deftest ob-eqn/integration-passthrough-eqn ()
  "A block whose body starts with .EQ produces a valid PNG."
  (skip-unless (ob-eqn--tools-available-p))
  (ob-eqn--with-output-file
      "png"
      ".EQ\nint from 0 to inf e sup {-x sup 2} dx ~=~ {sqrt pi} over 2\n.EN"
      '()
    (should (file-exists-p out-file))
    (should (> (file-attribute-size (file-attributes out-file)) 0))))

(ert-deftest ob-eqn/integration-complex-equation ()
  "A multi-term equation with fractions and summation produces a valid PNG."
  (skip-unless (ob-eqn--tools-available-p))
  (ob-eqn--with-output-file
      "png"
      "sum from {i=0} to {n} x sub i ~=~ {n(n+1)} over 2"
      '()
    (should (file-exists-p out-file))
    (let ((magic (with-temp-buffer
                   (set-buffer-multibyte nil)
                   (insert-file-contents-literally out-file nil 0 8)
                   (buffer-string))))
      (should (string= "\x89PNG\r\n\x1a\n" magic)))))

(provide 'test-ob-eqn)

;;; test-ob-eqn.el ends here
