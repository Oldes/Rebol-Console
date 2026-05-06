Rebol [
    Title:   "Mini Console"
    Purpose: {Console without any features using reusable line editor}
    Version: 0.2.0
    Needs:   3.21.18
]

;; Remove possible existing REPL components
try [system/modules/line-editor: none]
try [unset in lib 'line-editor!]
try [unset 'line-editor!]

;; Import the local one
import %repl-line-editor.reb

mini-console: function [/with spec [block!]][
	unless tty? [exit] ;; start console only if input is available!
	editor: make line-editor! spec
	editor/init
	forever [
		editor/on-key read-key
	]
]

mini-console/with [
	prompt: as-red "[mini]> "
	eval-ctx: context []
]