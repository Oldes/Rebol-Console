Rebol [
	Title:  "Rebol Console"
	Type:    module
	Name:    console
	Date:    11-Apr-2026
	Version: 0.3.1
	Author: [@Oldes @PCarlsson @Rebolek]
	Home:    https://github.com/Oldes/Rebol-Console
	License: MIT
	Purpose: {A lightweight, feature-complete interactive REPL with line editing, history, and tab completion, written in pure Rebol.}
	TODO: {
		* Treat entire grapheme clusters as single units, e.g. 🏳️‍🌈
	}
	Needs: 3.21.13
	Exports: [new-console]
]

tui: function [dialect [block!] /local value] [
	csi: "^[["
	out: clear ""
	value: 1
	size: as-pair
		query system/ports/output 'window-cols
		query system/ports/output 'window-rows
	colors: [black red green yellow blue magenta cyan white]
	get-color: func [value] [
		if word? value [value: -1 + index? find colors value]
		value
	]
	emit: func [value /csi] [
		value: head insert clear [] value
		if csi [insert value "^[["] 
		repend out value
	]
	movement: [
		(value: 1)
		'up opt [set value integer!] (emit/csi [value #"A"])
	|	'down opt [set value integer!] (emit/csi [value #"B"])
	|	'right opt [set value integer!] (emit/csi [value #"C"])
	|	'left opt [set value integer!] (emit/csi [value #"D"])
	|	'col opt [set value integer!] (emit/csi [value #"G"])
	]
	cursor: [
		'save (emit/csi #"s")
	|	'restore (emit/csi #"u")
	]
	colors-rule: ['black | 'red | 'green | 'yellow | 'blue | 'magenta | 'cyan | 'white]
	styling: [
		'reset  (emit/csi "0m")
	|	'bold   (emit/csi "1m")
	|	'invert (emit/csi "7m")
	|	opt 'fg set value [integer! | colors-rule] (emit/csi ["38;5;" get-color value "m"])
	|	'bg set value [integer! | colors-rule] (emit/csi ["48;5;" get-color value "m"])
	]
	lines: [
		'hline set value integer! (emit array/initial value #"-")
	|	'vline set value integer! (loop value [emit #"|" emit/csi #"B" emit/csi #"D"])
	]
	boxes: [
		'box set value pair! (
			emit/csi #"s" ; save
			emit #"+"
			emit array/initial (to integer! value/x) - 2 #"-"
			emit #"+"
			loop value/y - 2 [
				emit/csi #"B"
				emit/csi [to integer! value/x #"D"]
				emit #"|" 
				emit array/initial (to integer! value/x) - 2 #" "
				emit #"|"
			]
			emit/csi #"B"
			emit/csi [to integer! value #"D"]
			emit #"+"
			emit array/initial (to integer! value/x) - 2 #"-"
			emit #"+"
			emit/csi "0m" ; reset style
		)
	]
	scrolling: [
		'scroll [
			(value: 1)
			'up opt [set value integer!] (emit/csi [value #"S"])
		|	'down opt [set value integer!] (emit/csi [value #"T"])
		]
	]
	clearing: [
			['cls  | 'clear 'screen] (emit/csi "2J")
		|	'clear 'line (emit/csi "2K")
		|	'clear 'to 'end (emit/csi #"K")
	]
	parse dialect [
		some [
			set value pair! (emit/csi [to integer! value/y #";" to integer! value/x #"H"])
		|	movement
		|	cursor
		|	styling
		|	lines
		|	boxes
		|	scrolling
		|	clearing
		|	'newline (emit #"^/")
		|	set value string! (emit value)
		]
	]
	out
]
delimiters: charset { /%[({})];:"}
clear-line:  "^[[G^[[K"  ;; go to line start, clear to its end
save-cur:    "^[[s"
rest-cur:    "^[[u"
move-up:     "^[[1A"
move-down:   "^[[1B"
move-start:  "^[[G"
highlight:   "^[[7m"
reset-style: "^[[m"
prompt-counter: #"0"

move-left-by: func [n] [rejoin ["^[[" n #"D"]]

delimiters: charset { /%[({})];:"}
clear-line:    "^M^[[K"  ;; go to line start, clear to its end
clear-newline: "^/^[[K"  ;; go to new line and clear it (removes optional status line)

prompt-counter: #"0"

;; Console's state template.
state: context [
	prompt: as-red "## "
	history: system/console/history
	;; Private values...
	line: pos:  copy ""  ;; edited line
	buffer:     copy ""  ;; stdout buffer
	time:       none     ;; used to detect TAB while PASTE
	key:        none     ;; current key
	eval-ctx:   none     ;; used to hold per/session evaluation context
	col:        0        ;; current cursor position
	tab-index:  0        ;; current position in the cycling list
	tab-col:    0        ;; column position before tab-match was inserted
	tab-line:   none     ;; line content at the time TAB was pressed, used to detect changes
	tab-match:  none     ;; currently inserted completion
	tab-result: none     ;; cached result of complete-input [start matches]
	multiline:  none     ;; block of lines
	ml-prompt:  none     ;; stored original prompt while inside multiline mode
	ml-type:    none     ;; current bracket type
]

;; Word completion support

words-cache: none
lib-size: none
user-size: none

cache-words: func [ ctx [object!] ] [
	lib-size: length? system/contexts/lib
	user-size: length? any [ctx system/contexts/user]
	words-cache: sort union words-of system/contexts/lib words-of any [ctx system/contexts/user]
]

;; Object/function completion support

collect-refs: func [fn [any-function!] /local ref] [
	parse spec-of :fn [
		collect any [set ref refinement! keep (form ref) | skip]
	]
]

form-all: func [
	"Convert block of words to block of strings"
	block [block!]
] [
	split form block space
]

filter-matches: function [
	"From block of strings, return only those matching pattern"
	block [block!]
	pattern [string!]
] [
	remove-each value block [ not find/match value pattern ]
]

scan-context: function [
	ctx [object!]
	part [string!]
] [
	path: split part #"/"
	foreach [key val] ctx [
		switch type? :val [
			#(native!) #(action!) #(function!) #(closure!) [
				if equal? path/1 form key [
					matches: either empty? last path [ ; part is `word/` -> ["word" ""]
						collect-refs :val
					] [
						; possible optimization:
						; if refinement is already present, do not offer it
						filter-matches collect-refs :val last path
					]
				]
			]
			#(object!) #(module!) #(error!) #(port!) #(block!) [
				if equal? path/1 form key [
					matches: case [
						; top level object
						all [ empty? last path 2 = length? path ] [
							form-all words-of :val
						]
						; subobject
						empty? last path [
							take/last path
							result: get to path! load path
							case [
								any-object? result [ form-all words-of result ]
							;	block? result [ rejoin ["1 - " length? result ] ]
								'else ["???"]
							]
						]
						'else [
							either attempt [ get to path! load path ] [
								; fully resolved path, nothing to add
								[]
							] [
								; partial word from subobject
								partial: take/last path
								result: either single? path [
									form-all words-of get load path/1
								] [
									form-all words-of get to path! load path
								]
								filter-matches result partial
							]
						]
					]
				]
			]
		]
	]
	either block? matches [
		prefix: combine/with path #"/"
		unless equal? #"/" last prefix [append prefix #"/"]
		forall matches [matches/1: join prefix matches/1]
		head matches
	] [ none ]
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

;; Input completion function.
complete-input: function [
	input     [string!] "Current line to be completed"
	/with ctx [object!] "Optional context to search words instead of the user's context."
	return:   [block! ] "[start matches]"
][
	part: any [
		find/last/tail input SP
		input
	]
	case [
		part/1 == #"%" [ ; File completion
			part: as file! next part
			path-parts: split-path part
			files: sort read path-parts/1
			matches: copy []
			foreach file files [
				if parse file [part to end][
					append matches to string! file
				]
			]
		]
		find part #"/" [ ; Path completion
			matches: any [
				scan-context system/contexts/sys part
				scan-context system/contexts/lib part
				scan-context any [ctx system/contexts/user] part
			]
		]
		not empty? part [ ; Word completion
			all-words: form-all either any [
				(length? system/contexts/lib) <> lib-size
				(length? any [ctx system/contexts/user]) <> user-size
			] [
				cache-words ctx
			] [
				words-cache
			]

			matches: copy []
			foreach word all-words [
				if parse word [ part to end ] [
					append matches word
				]
			]
		]
	]
	reduce [as string! part matches]
]

;; Main function.
new-console: function/with [
	"Start new REPL (Read Edit Print Loop)"
	/prompt prom [string!]
	/banner text [string!]
][
	if banner [print text]
	ctx: make state []
	ctx/prompt: either prompt [prom][
		;; Using numbered prompt to test nested consoles
		prompt-counter: prompt-counter + 1
		ajoin [ as-yellow prompt-counter as-red "] " ]
	]
	ctx/eval-ctx: context [
		new-console: :system/modules/console/new-console
		debug?: on ;; console debugging output
	]

	system/state/quit?: false

	;; Using bind/copy to be able start a console from another console
	do bind/copy [
		clear history
		history-pos: 0
		prin prompt

		pos: head line

		;; Helper functions
		emit: func[s][
			if block? s [s: ajoin s]
			append buffer s
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
		skip-to: func[pos][
			emit ["^[[" prompt-width + pos + 1 #"G"]
		]
		skip-to-end: does [
			pos: tail line
			col: line/width
		]
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
		prompt-width: function/with [][
			either prev-prompt = prompt [ width ][
				tmp: sys/remove-ansi copy prev-prompt: prompt
				width: tmp/width ;; in columns
			]
		][  ;; cache previous prompt width
			prev-prompt: none width: 0
		]
		get-suggestions: function [matches] [
			match-lines: clear []
			line: clear ""
			foreach match matches [
				repend line [match space]
				if (length? line) > term-width [
					clear skip tail line negate 1 + length? match
					append match-lines copy line
					clear line
					repend line [match space]
				]
			]
			append match-lines copy line
			match-lines
		]
		reset-tab: does [
			tab-match: tab-line: none
			tab-col: tab-index: 0
		]
		tab-help-line?: false ; is tab help line added?
		tab-help?: false      ; is tab help shown?
		tab-offset: 0         ; how much is tab help shifted
		max-tab: 0
		tab-dirty?: false
		clear-tab-help: does [
			if tab-help? [
				emit tui [
					save
					down
					clear line
					restore
				]
				tab-help?: false
			]
		]
		reset-multiline: does [
			multiline: none
			prompt: ml-prompt
		]

		show-status: function [txt][
			;; limit output to max line width...
			max-cols: query system/ports/output 'window-cols 
			txt: reform txt
			if txt/length >= max-cols [ 
				clear skip txt max-cols - 1
				append txt "…"
			]

			prin tui compose [
				newline
				clear line
				(txt)
				up
				col (prompt-width + col + 1)
			]
		]

		catch/quit [ forever [
			clear buffer
			prev-col: col
			term-width: query system/ports/output 'window-cols ; it's in loop, so it's resizing aware
			time: stats/timer
			key: read-key
			if eval-ctx/debug? [
				show-status ["key:" mold key "ctrl:" system/state/control? "shift:" system/state/shift?]
			]
			switch/default key [
				;- DEL/Backspace  
				backspace
				#"^~" #"^H" #"^(7F)" [
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
						reset-tab
					]
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
						reset-tab
					]
				]
				;- ENTER          
				#"^M" [
					if empty? line [
						prin ajoin [unless multiline [clear-line] clear-newline prompt]
						continue
					]
					unless same? line history/1 [
						insert history copy line
						history-pos: 0
					]
					either multiline [
						res: try [transcode code: ajoin [ajoin/with multiline LF LF line]]
					][	res: try [transcode code: line]]

					either error? res [
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
							col: prev-col: 0
							prin buffer
							continue
						]
						prin clear-newline
						reset-multiline
					][
						prin clear-newline
						if multiline [ reset-multiline ]
						code: bind/new/set res eval-ctx
						code: bind code system/contexts/lib
						set/any 'res try/all [
							catch/quit code
						]
						if system/state/quit? [
							system/state/quit?: false ;; quit only from this console
							break
						]
					]

					pos: clear line
					col: prev-col: 0
					clear-tab-help
					tab-help-line?: false
					case [
						unset? :res [] ;; ignore
						error? :res [
							foreach line split-lines form :res [
								emit as-purple line
								emit LF
							]
							emit LF
						]
						'else [emit [as-green "== " mold res LF]]
					]
					emit [clear-line prompt]
					reset-tab
				]
				;- CTRL+C          
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
				escape #"^[" [
					if multiline [ reset-multiline append line " " ]
					unless empty? line [
						emit [clear-newline as-purple"(escape)" LF prompt]
						pos: clear line
						col: prev-col: 0
						reset-tab
					]
				]
				;- TAB             
				#"^-" backtab [
					;; completion only if key-time is high
					either 0:0:0.01 > (stats/timer - time) [
						pos: insert pos "  "
						emit at pos -2
						col: col + 2
					][
						if tail? pos [
							if tab-match [
								loop tab-match/length [
									col: col - pos/-1/width
									pos: remove back pos
								]
							]
							if any [
								not tab-match
								tab-line != line
							][
								tab-index: 0
								tab-match: none
								tab-line:  line
								tab-col:   col
								tab-result: complete-input/with line eval-ctx
								;; prepare suggestions
								match-lines: get-suggestions second tab-result
							]
							set [start: matches:] tab-result
							if empty? matches [ continue ]
							;; TAB cycles forward, SHIFT+TAB (backtab) cycles backward
							;; Strip previous cycled match if any
							if tab-col > 0 [
								skip-to tab-col
								emit "^[[K"
							]
							; rotate left/right
							either key = 'backtab [
								if zero? tab-index: tab-index - 1 [
									tab-index: length? matches
								]
							][
								tab-index: 1 + mod tab-index length? matches
							]
							tab-match: either find start #"/" [
								remove next find/last start #"/"
								matches/:tab-index
							][	find/match/tail matches/:tab-index start ]

							; on first tab/backtab press, add help line
							if not tab-help-line? [
								tab-help?: true
								tab-help-line?: true
								emit tui [scroll up up]
							]

							; prepare matches with highlighted current match
							current-line: none
							foreach line match-lines [
								if mark: find line join tab-match space [
									current-line: copy line
									break
								]
							]
							; go back to space or start so whole word is highlighted
							either start-mark: find/reverse mark space [
								start-mark: next start-mark
							] [
								start-mark: head mark
							]
							mark: start-mark
							; insert highlight
							insert mark: at current-line index? mark tui [invert]
							insert find mark space tui [reset]
							show-status head current-line
							tab-match: find/match/tail matches/:tab-index start
							append pos tab-match
							emit pos
							skip-to-end
						]
					]
				]
				;- Navigation      
				up [
					if history-pos < length? history [
						++ history-pos
						emit [clear-line prompt ]
						append clear line history/:history-pos
						emit line
						skip-to-end
						prev-col: col
						reset-tab
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
						reset-tab
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
				if #" " = key [clear-tab-help]
				if all [
					char? key
					key > 0#1F
				][
					emit back pos: insert pos key
					col: col + key/width
					if tail? pos [prev-col: col]
					reset-tab
				]
			]
			;; Move cursor only if really changed its position.
			if prev-col != col [skip-to col]
			prin buffer
		]] ;=catch/quit
	] :ctx
	unless prompt [prompt-counter: prompt-counter - 1]
	#(unset) ;; return unset on exit
] self
