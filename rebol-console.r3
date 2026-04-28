Rebol [
	Title:   "Rebol Console"
	Purpose: {Rebol Console with multiline input and TAB completion}
	Version: 0.1.0
	Date:    27-Apr-2026
	Needs:   3.21.16
]

;; Remove possible existing REPL components
try [system/modules/rebol-completion: none]
try [system/modules/rebol-console: none]
try [system/modules/line-editor: none]
try [unset in lib 'rebol-console]
try [unset in lib 'line-editor!]
try [unset in lib 'completion!]

;; Import new one
import %repl-line-editor.reb
import %repl-completion.reb
import %repl-rebol-console.reb

rebol-console

