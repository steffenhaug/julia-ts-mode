;;; julia-ts-mode.el --- Major mode for Julia source code using tree-sitter -*- lexical-binding: t; -*-

;; Copyright (C) 2022, 2023  Ronan Arraes Jardim Chagas
;;
;; Author           : Ronan Arraes Jardim Chagas
;; Created          : December 2022
;; Keywords         : julia languages tree-sitter
;; Package-Requires : ((emacs "29.1") (julia-mode "0.4"))
;; URL              : https://github.com/ronisbr/julia-ts-mode
;; Version          : 0.2.5
;;
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
;;
;;; Commentary:
;; This major modes uses tree-sitter for font-lock, indentation, imenu, and
;; navigation. It is derived from `julia-mode'.

;;;; Code:

(require 'treesit)
(eval-when-compile (require 'rx))
(require 'julia-mode)
(require 'julia-ts-misc)

(declare-function treesit-parser-create "treesit.c")

(defgroup julia-ts nil
  "Major mode for the julia programming language using tree-sitter."
  :group 'languages
  :prefix "julia-ts-")
;; Notice that all custom variables and faces are automatically added to the
;; most recent group.

(defcustom julia-ts-align-argument-list-to-first-sibling nil
  "Align the argument list to the first sibling.

If it is set to t, the following indentation is used:

    myfunc(a, b,
           c, d)

Otherwise, the indentation is:

    myfunc(a, b
        c, d)"
  :version "29.1"
  :type 'boolean)

(defcustom julia-ts-align-assignment-expressions-to-first-sibling nil
  "Align the expressions after an assignment to the first sibling.

If it is set to t, the following indentation is used:

    var = a + b + c +
          d + e +
          f

Otherwise, the indentation is:

    var = a + b + c +
        d + e +
        f"
  :version "29.1"
  :type 'boolean)

(defcustom julia-ts-align-parameter-list-to-first-sibling nil
  "Align the parameter list to the first sibling.

If it is set to t, the following indentation is used:

    function myfunc(a, b,
                    c, d)

Otherwise, the indentation is:

    function myfunc(a, b,
        c, d)"
  :version "29.1"
  :type 'boolean)

(defcustom julia-ts-align-curly-brace-expressions-to-first-sibling nil
  "Align curly brace expressions to the first sibling.

If it is set to t, the following indentation is used:

    MyType{A, B,
           C, D}

Otherwise, the indentation is:

    MyType{A, B
        C, D}"
  :version "29.1"
  :type 'boolean)

(defcustom julia-ts-align-type-parameter-list-to-first-sibling nil
  "Align type parameter lists to the first sibling.

If it is set to t, the following indentation is used:

    struct MyType{A, B
                  C, D}

Otherwise, the indentation is:

    struct MyType{A, B,
        C, D}"
  :version "29.1"
  :type 'boolean)

(defcustom julia-ts-indent-offset 4
  "Number of spaces for each indentation step in `julia-ts-mode'."
  :version "29.1"
  :type 'integer
  :safe 'intergerp)

(defface julia-ts-macro-face
  '((t :inherit font-lock-preprocessor-face))
  "Face for Julia macro invocations in `julia-ts-mode'.")

(defface julia-ts-quoted-symbol-face
  '((t :inherit font-lock-constant-face))
  "Face for quoted Julia symbols in `julia-ts-mode', e.g. :foo.")

(defface julia-ts-interpolation-expression-face
  '((t :inherit font-lock-constant-face))
  "Face for interpolation expressions in `julia-ts-mode', e.g. :foo.")

(defface julia-ts-string-interpolation-face
  '((t :inherit font-lock-constant-face :weight bold))
  "Face for string interpolations in `julia-ts-mode', e.g. :foo.")

(defface julia-ts-boolean-face
  '((t :inherit font-lock-builtin-face))
  "Face for boolean literals in `julia-ts-mode`.")

(defvar julia-ts--keywords
  '("baremodule" "begin" "catch" "const" "do" "else" "elseif" "end" "export"
    "finally" "for" "function" "global"
    "if" "let" "local" "macro" "module" "quote" "return" "try" "where" "while" "public"
    "abstract" "type" "mutable" "struct"
    "import" "using" "as"
    )
  "Keywords for `julia-ts-mode'.")

(defvar julia-ts--treesit-font-lock-settings
  (treesit-font-lock-rules

   :language 'julia
   :feature 'variable
   '((identifier) @font-lock-variable-name-face)

   :language 'julia
   :feature  'comment
   '((line_comment) @font-lock-comment-face)

   :language 'julia
   :feature  'literal
   '((integer_literal) @font-lock-number-face
     (float_literal)   @font-lock-number-face
     (boolean_literal) @julia-ts-boolean-face)

   :language 'julia
   :feature  'string
   '((string_literal _ (content)) @font-lock-string-face)

   :language 'julia
   :override t
   :feature 'symbol
   '((quote_expression
      ":"
      [(identifier) (operator)])
     @font-lock-keyword-face)

   :language 'julia
   :feature  'function
   :override t
   '((call_expression
      (identifier) @font-lock-function-call-face))

   :language 'julia
   :feature  'function
   :override t
   '((broadcast_call_expression
      (identifier) @font-lock-function-call-face))

   :language 'julia
   :feature  'type
   :override t
   '((type_head (identifier) @font-lock-type-face))

   :language 'julia
   :feature  'type
   :override t
   '((typed_expression (_) "::" (identifier) @font-lock-type-face))

   :language 'julia
   :feature  'keyword
   :override t
   `([,@julia-ts--keywords] @font-lock-keyword-face
     (for_binding (_) (operator) @font-lock-keyword-face (_))) ; `in` in for loops

   :language 'julia
   :feature  'macro
   :override t
   '((macro_identifier "@" (identifier)) @font-lock-preprocessor-face)

   

   )
  "Tree-sitter font-lock settings for `julia-ts-mode'.")

(defvar julia-ts--treesit-indent-rules
  `((julia
     ((parent-is "abstract_definition") parent-bol 0)
     ((parent-is "module_definition") parent-bol 0)
     ((node-is "end") (and parent parent-bol) 0)
     ((node-is "elseif") parent-bol 0)
     ((node-is "else") parent-bol 0)
     ((node-is "catch") parent-bol 0)
     ((node-is "finally") parent-bol 0)
     ((node-is ")") parent-bol 0)
     ((node-is "]") parent-bol 0)
     ((node-is "}") parent-bol 0)

     ;; Alignment of parenthesized expressions.
     ((parent-is "parenthesized_expression") parent-bol julia-ts-indent-offset)

     ;; Alignment of tuples.
     ((julia-ts--parent-is-and-sibling-on-same-line "tuple_expression" 1) first-sibling 1)
     ((julia-ts--parent-is-and-sibling-not-on-same-line "tuple_expression" 1) parent-bol julia-ts-indent-offset)

     ;; Alignment of arrays.
     ((julia-ts--parent-is-and-sibling-on-same-line "vector_expression" 1) first-sibling 1)
     ((julia-ts--parent-is-and-sibling-not-on-same-line "vector_expression" 1) parent-bol julia-ts-indent-offset)
     ((julia-ts--parent-is-and-sibling-on-same-line "matrix_expression" 1) first-sibling 1)
     ((julia-ts--parent-is-and-sibling-not-on-same-line "matrix_expression" 1) parent-bol julia-ts-indent-offset)

     ;; Alignment of curly brace expressions.
     ,(if julia-ts-align-curly-brace-expressions-to-first-sibling
          `((julia-ts--parent-is-and-sibling-on-same-line "curly_expression" 1) first-sibling 1)
        `((julia-ts--parent-is-and-sibling-on-same-line "curly_expression" 1) parent-bol julia-ts-indent-offset))
     ((julia-ts--parent-is-and-sibling-not-on-same-line "curly_expression" 1) parent-bol julia-ts-indent-offset)

     ;; Align the expressions in the if statement conditions.
     ((julia-ts--ancestor-is "if_statement") parent-bol julia-ts-indent-offset)

     ;; For all other expressions, keep the indentation as the parent.
     ((parent-is "_expression") parent 0)

     ;; General indentation rules for blocks.
     ((parent-is "_statement") parent-bol julia-ts-indent-offset)
     ((parent-is "_definition") parent-bol julia-ts-indent-offset)
     ((parent-is "_clause") parent-bol julia-ts-indent-offset)

     ;; Alignment of argument lists.
     ,(if julia-ts-align-argument-list-to-first-sibling
          `((julia-ts--parent-is-and-sibling-on-same-line "argument_list" 1) first-sibling 1)
        `((julia-ts--parent-is-and-sibling-on-same-line "argument_list" 1) parent-bol julia-ts-indent-offset))
     ((julia-ts--parent-is-and-sibling-not-on-same-line "argument_list" 1) parent-bol julia-ts-indent-offset)

     ;; Alignment of parameter lists.
     ,(if julia-ts-align-parameter-list-to-first-sibling
          `((julia-ts--parent-is-and-sibling-on-same-line "parameter_list" 1) first-sibling 1)
        `((julia-ts--parent-is-and-sibling-on-same-line "parameter_list" 1) parent-bol julia-ts-indent-offset))
     ((julia-ts--parent-is-and-sibling-not-on-same-line "parameter_list" 1) parent-bol julia-ts-indent-offset)

     ;; Alignment of type parameter lists.
     ,(if julia-ts-align-argument-list-to-first-sibling
          `((julia-ts--parent-is-and-sibling-on-same-line "type_parameter_list" 1) first-sibling 1)
        `((julia-ts--parent-is-and-sibling-on-same-line "type_parameter_list" 1) parent-bol julia-ts-indent-offset))
     ((julia-ts--parent-is-and-sibling-not-on-same-line "type_parameter_list" 1) parent-bol julia-ts-indent-offset)

     ;; The keyword parameters is a child of parameter list. Hence, we need to
     ;; consider its grand parent to perform the alignment.
     ,@(if julia-ts-align-parameter-list-to-first-sibling
           (list '((n-p-gp nil "keyword_parameters" "parameter_list")
                   julia-ts--grand-parent-first-sibling
                   1))
         (list '((n-p-gp nil "keyword_parameters" "parameter_list")
                 julia-ts--grand-parent-bol
                 julia-ts-indent-offset)))

     ;; Match if the node is inside an assignment.
     ;; Note that if the user wants to align the assignment expressions on the
     ;; first sibling, we should only check if the first sibling is not on the
     ;; same line of its parent. The other rules already perform the correct
     ;; indentation.
     ,@(unless julia-ts-align-assignment-expressions-to-first-sibling
         (list `((julia-ts--ancestor-is-and-sibling-on-same-line "assignment" 2) (julia-ts--ancestor-bol "assignment") julia-ts-indent-offset)))
     ((julia-ts--ancestor-is-and-sibling-not-on-same-line "assignment" 2) (julia-ts--ancestor-bol "assignment") julia-ts-indent-offset)

     ;; This rule takes care of blank lines most of the time.
     (no-node parent-bol 0)))
  "Tree-sitter indent rules for `julia-ts-mode'.")

(defun julia-ts--defun-name (node)
  "Return the defun name of NODE.
Return nil if there is no name or if NODE is not a defun node."
  (pcase (treesit-node-type node)
    ((or "abstract_definition"
         "function_definition"
         "short_function_definition"
         "struct_definition")
     (treesit-node-text
      (treesit-node-child-by-field-name node "name")
      t))))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.jl\\'" . julia-ts-mode))

;;;###autoload
(define-derived-mode julia-ts-mode julia-mode "Julia (TS)"
  "Major mode for Julia files using tree-sitter."
  :group 'julia

  (unless (treesit-ready-p 'julia)
    (error "Tree-sitter for Julia is not available"))

  ;; Override the functions in `julia-mode' that are not needed when using
  ;; tree-sitter.
  (setq-local syntax-propertize-function nil)
  (setq-local indent-line-function nil)
  (setq-local font-lock-defaults nil)

  (treesit-parser-create 'julia)

  ;; Comments.
  (setq-local comment-start "# ")
  (setq-local comment-end "")
  (setq-local comment-start-skip (rx "#" (* (syntax whitespace))))

  ;; Indent.
  (setq-local treesit-simple-indent-rules julia-ts--treesit-indent-rules)

  ;; Navigation.
  (setq-local treesit-defun-type-regexp
              (rx (or "function_definition"
                      "struct_definition")))
  (setq-local treesit-defun-name-function #'julia-ts--defun-name)

  ;; Imenu.
  (setq-local treesit-simple-imenu-settings
              `(("Function" "\\`function_definition\\|short_function_definition\\'" nil nil)
                ("Struct" "\\`struct_definition\\'" nil nil)))

  ;; Fontification
  (setq-local treesit-font-lock-settings julia-ts--treesit-font-lock-settings)
  (setq-local treesit-font-lock-feature-list
              '((comment definition)
                (constant keyword string type)
                (assignment literal variable symbol function interpolation macro)
                (error operator)))

  (treesit-major-mode-setup))

(provide 'julia-ts-mode)

;; Local Variables:
;; coding: utf-8
;; byte-compile-warnings: (not obsolete)
;; End:
;;; julia-ts-mode.el ends here
