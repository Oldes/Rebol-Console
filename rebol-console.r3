Rebol [
	Title:   "Rebol Console"
	Purpose: {Rebol Console with multiline input and TAB completion}
	Version: 0.1.0
	Date:    27-Apr-2026
	Needs:   3.21.16
]

do %line-editor.reb
do %validate.reb
do %completion.reb

rebol-console: function [
	"Start an interactive REPL using the line editor."
	/with "Customize the console by overriding line-editor! defaults."
	 spec [block!]
][
	editor: make line-editor! spec
	editor/init

	forever [
		editor/on-key read-key
	]
]

rebol-console/with [
	banner: :sys/boot-banner
	history: system/console/history
	prompt: function [][
		dir: what-dir
		parse dir [change system/options/home "~/" to end]
		ajoin [ansi/magenta dir "^[[1;31m>^[[m "]
	]
	completion: make completion! []
	eval-ctx: completion/user-context

	on-edit-key:    :on-key
	on-edit-escape: :on-escape
	on-key: func[key][
		try/with [
			on-edit-key key
			unless find [tab backtab #"^-"] key [
				if status? == 'tab [
					hide-status
					completion/reset
				]
			]
		][
			prin next-line
			result: system/state/last-error
			on-result
		]
	]
	on-tab: does [
		;; completion only if key-time is high
		either 0:0:0.001 > (stats/timer - time) [
		;@@ this is not reliable! When user holds TAB key, the time would be also low
		;	pos: insert pos "   "
		;	emit at pos -2
		;	col: col + 2
		;	if tail? pos [prev-col: col]
		][
			if all [tail? pos not empty? line] [
				;; remove existing tab completion
				if completion/suffix [
					remove-back completion/suffix/length
					completion/suffix: _
					emit "^[[K"
				]
				completion/complete line
				if zero? completion/count [continue]
				;; TAB cycles forward, SHIFT+TAB (backtab) cycles backward
				completion/get-match (did any [current-key = 'backtab system/state/shift?])
				either completion/count == 1 [
					;; direct hit - append and forget
					append append pos completion/suffix SP
					completion/reset
				][	;; display multiple posibilities in the status line
					show-status 'tab completion/status-line
					append pos completion/suffix
				]
				emit pos
				skip-to-end
			]
		]
	]
	on-line: does [
		completion/reset
		if status? [hide-status]

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
			;; It's an error from transcode, no need to show the stack!
			unset in :result 'where
			prin next-line
			reset-multiline
		][
			prin next-line
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
	on-escape: does [
		either status? = 'tab [
			;; Remove existing TAB completion suffix.
			if completion/suffix [
				remove-back completion/suffix/length
				completion/suffix: _
				skip-to col
				emit "^[[K"
			]
			;; And hide the completion status line.
			hide-status
			completion/reset
		][	;; Or call default escape handler.
			on-edit-escape
		]
	]
]