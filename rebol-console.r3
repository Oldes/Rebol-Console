Rebol [
    Title:   "Rebol Console"
    Purpose: {Rebol Console using reusable line editor}
    Version: 0.0.1
    Needs:   3.21.13
]

do %line-editor.reb
do %validate.reb

rebol-console: function [/with spec [block!]][
	editor: make line-editor spec
	editor/init
	forever [
		editor/on-key read-key
	]
]

rebol-console/with [
	banner: :sys/boot-banner
	prompt: func[/local dir] [
		dir: what-dir
		parse dir [change system/options/home "~/" to end]
		ajoin [as-purple dir "^[[1;31m> ^[[1;33m"]
	]
	on-tab: does [
		emit skip pos: insert/dup pos SP 2 -2
		col: col + 2
		if tail? pos [prev-col: col]
	]
	on-line: does [
		either multiline [
			result: try [transcode code: ajoin [ajoin/with multiline LF LF line]]
		][	result: try [transcode code: line]]
		either error? result [
			if ml-type: acceptable-code code [
				unless multiline [
					multiline: clear []
					ml-prompt: :prompt  ;; store original prompt
					prompt: as-purple append/dup clear "" SP max 2 prompt-width
				]
				change back find/last prompt " "  ml-type
				append multiline copy line
				pos: clear line
				emit [LF prompt]
				exit
			]
			prin clear-newline
			reset-multiline
		][
			prin clear-newline
			if multiline [ reset-multiline ]
			code: bind/new/set result eval-ctx
			code: bind code system/contexts/lib
			set/any 'result try/all [
				catch/quit code
			]
			if system/state/quit? [
				system/state/quit?: false ;; quit only from this console
				on-quit
				break
			]
		]
		on-result
	]
	eval-ctx: system/contexts/user
]