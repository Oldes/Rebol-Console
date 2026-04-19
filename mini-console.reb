Rebol [
    Title:   "Mini Console"
    Purpose: {Console using reusable line editor}
    Version: 0.0.1
    Needs:   3.21.13
]

line-editor: context [
	prompt: "^[[1;31m## ^[[1;33m"
	buffer: copy ""
	line: pos: result: code: eval-ctx: _
	prev-col: col: history-pos: 0
	multiline: none
	history: system/console/history

	init: func [][
		clear buffer
		line: pos: clear ""
		prev-col: col: 0
		eval-ctx: context []
		prin prompt
	]

	;-- Main callbacks ---
	on-key: func[key][
		prev-col: col
		clear buffer
		switch/default key [
			#"^M" [on-enter]
			;- DEL/Backspace  
			backspace #"^~" #"^H" #"^(7F)" [
				unless head? pos [
					either system/state/control? [
						;; delete to the previous delimiter
						tmp: pos
						skip-to-prev-delimiter
						remove/part pos tmp
					][	;; delete previous char
						col: col - pos/-1/width
						pos: remove back pos
					]
					skip-to col
					emit ["^[[K" pos]
					if tail? pos [prev-col: col]
				]
				;reset-tab
			]
			delete [
				unless tail? pos [
					either system/state/control? [
						tmp: pos prev-col: col
						skip-to-next-delimiter
						pos: remove/part tmp pos
						col: prev-col
					][	;; delete following char
						pos: remove pos
					]
					emit ["^[[K" pos]
					prev-col: none ;; force cursor position refresh
				]
				;reset-tab
			]
			#"^C" [
				print ajoin [clear-newline as-purple "(CTRL+C)"]
				break
			]
			;- CTRL+A - move to start
			#"^A" [
				emit "^[[4G"
				pos: head line
				col: 0
			]
			;- CTRL+E - move to end
			#"^E" [
				skip-to-end
				skip-to col
			]
			;- CTRL+U - clear line
			#"^U" [
				pos: clear line
				col: prev-col: 0
				emit "^[[4G"
				emit "^[[K"
			]
			;- escape          
			escape #"^[" [ on-escape ]
			;- TAB             
			#"^-" backtab [ on-tab ]
			;- Navigation      
			up [
				if history-pos < length? history [
					++ history-pos
					emit [clear-line prompt ]
					append clear line history/:history-pos
					emit line
					skip-to-end
					prev-col: col
					;reset-tab
				]
			]
			down [
				if history-pos > 1 [
					-- history-pos
					emit [clear-line prompt ]
					append clear line history/:history-pos
					emit line
					skip-to-end
					prev-col: col
					;reset-tab
				]
			]
			left [
				unless head? pos [
					either system/state/control? [
						;; Skip all delimiters backwards.
						skip-to-prev-delimiter
					][	skip-back ]
				]
			]
			right [
				unless tail? pos [
					either system/state/control? [
						;; Skip all delimiters forward
						skip-to-next-delimiter
					][	skip-next ]
				]
			]
			home [
				pos: head pos
				col: 0
			]
			end [
				pos: tail pos
				col: line/width
			]
		][
			if all [char? key key > 0#1F][
				emit back pos: insert pos key
				col: col + key/width
				if tail? pos [prev-col: col]
			]
		]
		flush
	]
	on-enter: function [][
		if empty? line [
			prin ajoin [unless multiline [clear-line] clear-newline prompt]
			exit
		]
		unless same? line history/1 [
			insert history copy line
			history-pos: 0
		]
		prin LF
		on-eval line
	]
	on-eval: func [line][
		result: try [transcode code: line]
		prin clear-newline
		;if multiline [ reset-multiline ]
		code: bind/new/set result eval-ctx
		code: bind code system/contexts/lib
		set/any 'result try/all [
			catch/quit code
		]
		if system/state/quit? [
			system/state/quit?: false ;; quit only from this console
			break
		]
		on-result :result
	]
	on-result: func [result [any-type!]][
		pos: clear line
		col: prev-col: 0
		case [
			unset? :result [] ;; ignore
			error? :result [
				foreach line split-lines form :result [
					emit as-purple line
					emit LF
				]
				emit LF
			]
			'else [emit [as-green "== " mold :result LF]]
		]
		emit [clear-line prompt]
		flush
	]
	on-escape: does [
		;if multiline [ reset-multiline append line " " ]
		unless empty? line [
			emit [clear-newline as-purple"(escape)" LF prompt]
			on-result #(unset)
			;reset-tab
		]
	]
	on-tab: does [
		emit skip pos: insert/dup pos SP 4 -4
		col: col + 4
		if tail? pos [prev-col: col]
	]

	;-- Private editor functions ---

	emit: func[s][append buffer either block? s [ajoin s][s]]

	prompt-width: function/with [][
		either prev-prompt == prompt [ width ][
			tmp: sys/remove-ansi copy prev-prompt: prompt
			width: tmp/width ;; in columns
		]
	][  ;; cache previous prompt width
		prev-prompt: none width: 0
	]
	
	skip-to: func[col][emit ["^[[" prompt-width + col + 1 #"G"]]
	skip-to-end: does [ pos: tail line  col: line/width	]
	skip-to-prev-delimiter: does [
		;; skip any delimiters immediately to the left of `pos`
		while [ all [not head? pos find delimiters pos/-1 ]][ skip-back ]
		;; then keep going left until we hit the head or another delimiter
		unless head? pos [
			until [ skip-back any [head? pos  find delimiters pos/-1] ]
		]
	]
	skip-to-next-delimiter: does [
		;; skip any delimiters immediately to the right of `pos`
		while [ all [not tail? pos find delimiters pos/1 ]][ skip-next ]
		;; then keep going right until we hit the tail or another delimiter
		unless tail? pos [
			until [ skip-next any [tail? pos  find delimiters pos/1] ]
		]
	]
	skip-back: does [
		unless head? pos [
			pos: back pos
			col: col - pos/1/width
		]
	]
	skip-next: does [
		unless tail? pos [
			col: col + pos/1/width
			pos: next pos
		]
	]
	flush: does [
		;; Move cursor only if really changed its position.
		if prev-col != col [skip-to col]
		prin take/all buffer
	]

	;---- Constants ----
	clear-line:      "^M^[[K"            ;; go to line start, clear to its end
	clear-newline:   "^/^[[K"            ;; go to new line and clear it (removes optional status line)
	clear-next-line: "^[[1B^[[2K^[[1A"
	save-cur:        "^[[s"              ;= tui [save]
	restore-cur:     "^[[u"              ;= tui [restore]
	move-up:         "^[[1A"             ;= tui [up]
	move-down:       "^[[1B"             ;= tui [down]
	move-start:      "^M"                ;= tui [col 0]  
	highlight:       "^[[7m"             ;= tui [invert]
	reset-style:     "^[[0m"             ;= tui [reset]

	delimiters: charset { /%[({})];:"}
]

mini-console: func [/with spec [block!] /local editor][
	editor: make line-editor spec
	editor/init
	forever [
		editor/on-key read-key
	]
]

mini-console/with [
	prompt: as-red ">> "
	on-tab: does [
		emit skip pos: insert/dup pos SP 2 -2
		col: col + 2
		if tail? pos [prev-col: col]
	]
]