Rebol [
    Title:   "Mini Console"
    Purpose: {Console without any features using reusable line editor}
    Version: 0.1.0
    Needs:   3.21.16
]

import %line-editor.reb

mini-console: function [/with spec [block!]][
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