Rebol [
    Title: "Rebol Console - Code validation"
    Home:  https://github.com/Oldes/Rebol-Console
]

acceptable-code: function/with [
    "Returns the currently open bracket if the code can be fixed with additional edits."
    ;; If it has a missing (but balanced) closing parenthesis.
    code [string!]
][
    stack: clear ""
    all [
        parse code [any code-rule ]
        last stack
    ]
][
    stack: ""
    raw: none
    code-char:    complement charset "[](){}^"%;^/"
    string1-char: complement charset {"^^^/}
    string2-char: complement charset "^^{}"
    code-rule: [
        some code-char
        | block-rule
        | paren-rule
        | string1-rule ;= single line
        | string2-rule ;= multiline
        | string3-rule ;= raw-string
        | comment-rule
        | lf | #"%"
    ]
    block-rule: [
         #"[" (append stack #"[") any code-rule
        [#"]" (take/last stack) | end]
    ]
    paren-rule: [
         #"(" (append stack #"(") any code-rule
        [#")" (take/last stack) | end]
    ]
    string1-rule: [
        #"^"" (append stack #"^"") some [
              #"^^" skip
            | #"^/" to end ;; failed!
            | any string1-char
        ] #"^"" (take/last stack)
    ]
    string2-rule: [
        #"{" (append stack #"{") some [
              #"^^" skip
            | string2-rule
            | any string2-char
        ]
        [#"}" (take/last stack) | end]
    ]
    string3-rule: [
        copy raw: some #"%" (append stack #"{" insert raw "}")
        thru raw (take/last stack)
    ]
    comment-rule: [#";" [to LF | to end] ]
]