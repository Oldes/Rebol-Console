Rebol [
	Title:  "Rebol Console"
	Type:    module
	Name:    console
	Date:    1-Apr-2026
	Version: 0.1.3
	Author: [@Oldes @PCarlsson @Rebolek]
	Home:    https://github.com/Oldes/Rebol-Console
	License: MIT
	Purpose: {A lightweight, feature-complete interactive REPL with line editing, history, and tab completion, written in pure Rebol.}
	TODO: {
		* Better `complete-input`
		* Multiline input
		* Treat entire grapheme clusters as single units, e.g. 🏳️‍🌈
	}
	Needs: 3.21.12
	Exports: [new-console]
]

delimiters: charset { /%[({})];:"}
clear-line: "^[[G^[[K"
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
	col: 0
	tab-index: 0
	tab-col:   0
	tab-input: none
	tab-match: none
	tab-data:  none
]
;; Input completion function.
complete-input: function [
	input     [string!] "Current line to be completed"
	/with ctx [object!] "Optional context to search words instead of the user's context."
	return:   [block! ] "[start-part best-matches]"
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
			best-matches: copy []
			foreach file files [
				if parse file [part to end][
					append best-matches file
				]
			]
		]
		not empty? part [ ; Word completion
			;@@ all-words should not be created on each completion call!
			all-words: sort union words-of system/contexts/lib words-of any [ctx system/contexts/user]
			forall all-words [all-words/1: to string! all-words/1]

			best-matches: copy []
			foreach word all-words [
				if parse word [ part to end ] [
					append best-matches word
				]
			]
		]
	]
	reduce [part best-matches]
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
	]

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
		emit-ch: func[c [char!] num [integer!]][
			append/dup buffer c num
		]
		skip-back: does [
			unless head? pos [
				pos: back pos
				-- col
			]
		]
		skip-next: does [
			unless tail? pos [
				pos: next pos
				++ col
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
			while [ find delimiters pos/-1 ][ skip-back ]
			until [ skip-back any [head? pos  find delimiters pos/-1] ]
		]
		skip-to-next-delimiter: does [
			while [ find delimiters pos/1 ][ skip-next ]
			until [ skip-next any [tail? pos  find delimiters pos/1] ]
		]
		prompt-width: function/with [][
			either prev-prompt = prompt [ width ][
				tmp: sys/remove-ansi copy prev-prompt: prompt
				width: tmp/width ;; in columns
			]
		][  ;; cache previous prompt width
			prev-prompt: none width: 0
		]
		reset-tab: does [
			tab-match: tab-input: none
			tab-col: tab-index: 0
		]

		forever [
			time: stats/timer
			key: read-key
			;unless char? key [
			;    emit [clear-line mold key LF prompt line]
			;]
			clear buffer
			prev-col: col
			switch/default key [
				;- DEL/Backspace  
				#"^~"
				#"^H" [
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
							tmp: pos
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
					unless empty? line [
						prin LF
						unless same? line history/1 [
							insert history copy line
							history-pos: 0
						]
						code: try [transcode line]
						either error? code [
							;@@ TODO: handle multiline input here
							res: code
						][
							code: bind/new/set code eval-ctx
							code: bind code system/contexts/lib
							set/any 'res try/all code
						]
						pos: clear line
						col: prev-col: 0
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
					]
					emit [clear-line prompt]
					reset-tab
				]
				;- CTRL+C          
				#"^C" [
					prin clear-line
					break
				]
				;- escape          
				#"^[" [
					unless empty? line [
						emit [LF as-purple"(escape)" LF prompt]
						pos: clear line
						col: prev-col: 0
						reset-tab
					]
				]
				;- TAB             
				#"^-" [
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
								tab-input != line
							][
								tab-index: 0
								tab-match: none
								tab-input: line
								tab-col:   col
								tab-data: complete-input/with line eval-ctx
								
							]
							set [start-part: best-matches:] tab-data
							if empty? best-matches [ continue ]
							either all [system/state/shift? not single? best-matches] [
								;; SHIFT+TAB — show all matches
								emit [clear-line mold best-matches]
								emit [LF prompt line]
								skip-to-end
								;; Reset cycle on SHIFT+TAB
								tab-index: 0 tab-match: none
							][	;; TAB cycling through matches
								;; Strip previous cycled match if any
								if tab-col > 0 [
									skip-to tab-col
									emit "^[[K"
								]
								tab-index: 1 + mod tab-index length? best-matches
								tab-match: find/match/tail best-matches/:tab-index start-part
								append pos tab-match
								emit pos
								skip-to-end
							]
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
		]
	] :ctx
	unless prompt [prompt-counter: prompt-counter - 1]
	#(unset) ;; return unset on exit
] self
