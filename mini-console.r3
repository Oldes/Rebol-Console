Rebol [
    Title:   "Mini Console"
    Purpose: {Console using reusable line editor}
    Version: 0.0.1
    Needs:   3.21.13
]

import %line-editor.reb

mini-console: function [/with spec [block!]][
	editor: make line-editor spec
	editor/init
	forever [
		editor/on-key read-key
	]
]

mini-console/with [
	prompt: does [ajoin [as-purple what-dir "^[[1;31m> ^[[1;33m"]]
	on-tab: does [
		emit skip pos: insert/dup pos SP 2 -2
		col: col + 2
		if tail? pos [prev-col: col]
	]
	eval-ctx: system/contexts/user
]