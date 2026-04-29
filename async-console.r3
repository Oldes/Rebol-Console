Rebol [
    Title:   "Async Console"
    Purpose: {
    	Asynchronous console using reusable line editor.
		Allows not blocking console input while having other async devices running.
	}
	issues: {
		* Using `wait` function inside another wait (like in this console) has strange results.
		* When using paste in this console, it processes all input as key presses, which is slow.
		* Doesn't catch CTRL+C.
	}
	Version: 0.1.0
    Needs:   3.21.16
]

;; Remove possible existing REPL components
try [system/modules/line-editor: none]
try [unset in lib 'line-editor!]
try [unset 'line-editor!]

;; Import the local one
import %repl-line-editor.reb

async-console: function [
	/with spec [block!]
][
	editor: make line-editor! spec
	editor/init

	port: system/ports/input
	port/data: make string! 32
	port/awake: function [event /local res][
		if find [key control] event/type [
			system/state/control?: did find event/flags 'control
			system/state/shift?:   did find event/flags 'shift
			editor/on-key event/key
		]
	]
	modify port 'line false
	unless find ports: system/state/wait-list port [
		append ports port
	]
	wait ports
	modify port 'line true
	exit
]

async-console/with [
	prompt: as-blue "A> "
	on-tab: does [
		emit skip pos: insert/dup pos SP 2 -2
		col: col + 2
		if tail? pos [prev-col: col]
	]
	on-quit: does [
		emit [clear-line as-purple"(adios)"]
		flush
		quit
	]
]