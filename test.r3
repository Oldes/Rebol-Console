Rebol [
	Title: "Rebol Console Test"
	Needs: 3.21.13
]

import %console.reb

;; Debug output...
;echo %console-out.txt

;; Start new console
new-console/prompt/banner as-red "## " ajoin [
	LF as-yellow {Welcome to this simple console experiment.^/}
	{It's possible to start another console with its own context using } as-green "new-console" {.^/}
	{(use CTRL+C to exit)^/}
]