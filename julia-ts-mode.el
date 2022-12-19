;;; julia-ts-mode.el --- Major mode for Julia source code using tree-sitter -*- lexical-binding: t; -*-

;; Copyright (C) 2022  Ronan Arraes Jardim Chagas
;; URL: https://github.com/ronisbr/julia-ts-mode
;; Version: 0.0.1
;; Keywords: languages
;; Package-Requires: ((emacs "29"))

;;; Usage:
;; 1. Install the Julia tree-sitter grammar.
;; 2. Put the following code in your .emacs, site-load.el, or other relevant
;;    file:
;; (add-to-list 'load-path "path-to-julia-ts-mode")
;; (require 'julia-ts-mode)

;;; Commentary:
;; This version is highly experimental.

;;; License:
;; Permission is hereby granted, free of charge, to any person obtaining
;; a copy of this software and associated documentation files (the
;; "Software"), to deal in the Software without restriction, including
;; without limitation the rights to use, copy, modify, merge, publish,
;; distribute, sublicense, and/or sell copies of the Software, and to
;; permit persons to whom the Software is furnished to do so, subject to
;; the following conditions:
;;
;; The above copyright notice and this permission notice shall be
;; included in all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
;; LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
;; OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
;; WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

(require 'treesit)

(declare-function treesit-parser-create "treesit.c")

(defcustom julia-ts-mode-align-parameter-list-to-first-sibling nil
  "Align the parameter list to the first sibling.

If it is set to `t', the following indentation is used:

    function myfunc(a,
                    b,
                    c)

Otherwise, the indentation is:

    function myfunc(
        a,
        b,
        c
    )
"
  :version "29"
  :type 'boolean
  :group 'julia)

(defcustom julia-ts-mode-indent-offset 4
  "Number of spaces for each indentation step in `julia-ts-mode'."
  :version "29"
  :type 'integer
  :safe 'intergerp
  :group 'julia)

(defface julia-ts-mode-macro-face
  '((t :inherit font-lock-preprocessor-face))
  "Face for Julia macro invocations in `julia-ts-mode'.")

(defface julia-ts-mode-quoted-symbol-face
  '((t :inherit font-lock-constant-face))
  "Face for quoted Julia symbols in `julia-ts-mode', e.g. :foo.")

;; The syntax table was copied from the `julia-mode'.
(defvar julia-ts-mode--syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?_ "_" table)
    (modify-syntax-entry ?@ "_" table)
    (modify-syntax-entry ?! "_" table)
    (modify-syntax-entry ?# "< 14" table)  ; # single-line and multiline start
    (modify-syntax-entry ?= ". 23bn" table)
    (modify-syntax-entry ?\n ">" table)  ; \n single-line comment end
    (modify-syntax-entry ?\{ "(} " table)
    (modify-syntax-entry ?\} "){ " table)
    (modify-syntax-entry ?\[ "(] " table)
    (modify-syntax-entry ?\] ")[ " table)
    (modify-syntax-entry ?\( "() " table)
    (modify-syntax-entry ?\) ")( " table)
    ;; Here, we treat ' as punctuation (when it's used for transpose),
    ;; see our use of `julia-char-regex' for handling ' as a character
    ;; delimiter
    (modify-syntax-entry ?'  "." table)
    (modify-syntax-entry ?\" "\"" table)
    (modify-syntax-entry ?` "\"" table)
    ;; Backslash has escape syntax for use in strings but
    ;; julia-syntax-propertize-function sets punctuation syntax on it
    ;; outside strings.
    (modify-syntax-entry ?\\ "\\" table)

    (modify-syntax-entry ?. "." table)
    (modify-syntax-entry ?? "." table)
    (modify-syntax-entry ?$ "." table)
    (modify-syntax-entry ?& "." table)
    (modify-syntax-entry ?* "." table)
    (modify-syntax-entry ?/ "." table)
    (modify-syntax-entry ?+ "." table)
    (modify-syntax-entry ?- "." table)
    (modify-syntax-entry ?< "." table)
    (modify-syntax-entry ?> "." table)
    (modify-syntax-entry ?% "." table)

    (modify-syntax-entry ?′ "w" table) ; \prime is a word constituent
    table)
  "Syntax table for `julia-ts-mode'.")

(defvar julia-ts-mode--keywords
  '("baremodule" "begin" "catch" "const" "do" "else" "elseif" "end" "export"
    "finally" "for" "function" "global" "if" "import" "let" "local" "macro"
    "quote" "return" "try" "using" "where" "while")
  "Keywords for `julia-ts-mode'.")

(defvar julia-ts-mode--treesit-font-lock-settings
  (treesit-font-lock-rules
   :language 'julia
   :feature 'constant
   `((true) @font-lock-constant-face
     (false) @font-lock-constant-face
     (quote_expression) @julia-ts-mode-quoted-symbol-face
     ((identifier) @font-lock-builtin-face
      (:match
       "^\\(:?NaN\\|NaN16\\|NaN32\\|NaN64\\|nothing\\|missing\\|undef\\)$"
       @font-lock-builtin-face)))

   :language 'julia
   :feature 'comment
   `((line_comment) @font-lock-comment-face)

   :language 'julia
   :feature 'definition
   `((function_definition
      name: (identifier) @font-lock-function-name-face)
     (macro_definition
      name: (identifier) @font-lock-function-name-face))

   :language 'julia
   :feature 'keyword
   `(([,@julia-ts-mode--keywords]) @font-lock-keyword-face)

   :language 'julia
   :feature 'literal
   `((character_literal) @font-lock-constant-face
     (integer_literal) @font-lock-constant-face
     (float_literal) @font-lock-constant-face)

   :language 'julia
   :feature 'macro_call
   `((macro_identifier) @julia-ts-mode-macro-face)

   :language 'julia
   :feature 'operator
   `((operator) @font-lock-type-face
     (ternary_expression ["?" ":"] @font-lock-type-face))

   :language 'julia
   :feature 'string
   `((command_literal) @font-lock-string-face
     (prefixed_command_literal) @font-lock-string-face
     (string_literal) @font-lock-string-face
     (prefixed_string_literal) @font-lock-string-face)

   :language 'julia
   :feature 'type
   `((constrained_type_parameter
      supertype: (identifier) @font-lock-type-face)
     (constrained_type_parameter
      supertype: (parametrized_type_expression) @font-lock-type-face)
     (subtype_clause (parametrized_type_expression) @font-lock-type-face)
     (typed_parameter
      type: (identifier) @font-lock-type-face)
     (typed_parameter
      type: (parametrized_type_expression) @font-lock-type-face)
     ((typed_expression (identifier) (identifier) @font-lock-type-face))))
  "Tree-sitter font-lock settings for `julia-ts-mode'.")

(defvar julia-ts-mode--treesit-indent-rules
  `((julia
     ((node-is "end") (and parent parent-bol) 0)
     ((node-is "elseif") parent-bol 0)
     ((node-is "else") parent-bol 0)
     ((node-is "catch") parent-bol 0)
     ((node-is "finally") parent-bol 0)
     ((node-is ")") parent-bol 0)
     ((node-is "]") parent-bol 0)
     ((parent-is "_statement") parent-bol julia-ts-mode-indent-offset)
     ((parent-is "_declaration") parent-bol julia-ts-mode-indent-offset)
     ((parent-is "_expression") parent-bol julia-ts-mode-indent-offset)
     ((parent-is "_clause") parent-bol julia-ts-mode-indent-offset)
     ,@(if julia-ts-mode-align-parameter-list-to-first-sibling
           (list '((parent-is "parameter_list") first-sibling 1))
         (list '((parent-is "parameter_list") parent-bol julia-ts-mode-indent-offset)))

     ;; This rule takes care of blank lines most of the time.
     (no-node parent-bol 0)))
  "Tree-sitter indent rules for `julia-ts-mode'."
  )

;;;###autoload
(define-derived-mode julia-ts-mode prog-mode "Julia"
  "Major mode for Julia files using tree-sitter"
  :group 'julia
  :syntax-table julia-ts-mode--syntax-table

  (unless (treesit-ready-p 'julia)
    (error "Tree-sitter for Julia is not available"))

  (set-electric! 'julia-ts-mode
    :words '("catch"
             "else"
             "elseif"
             "finally"
             "end"))

  (treesit-parser-create 'julia)
  (setq-local treesit-simple-indent-rules julia-ts-mode--treesit-indent-rules)
  (setq-local treesit-font-lock-settings julia-ts-mode--treesit-font-lock-settings)
  (setq-local treesit-font-lock-feature-list
              '((comment definition)
                (constant keyword string type)
                (literal macro_call)
                (operator)))

  (treesit-major-mode-setup))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.jl\\'" . julia-ts-mode))

(provide 'julia-ts-mode)

;; Local Variables:
;; coding: utf-8
;; byte-compile-warnings: (not obsolete)
;; End:
;;; julia-ts-mode.el ends here
