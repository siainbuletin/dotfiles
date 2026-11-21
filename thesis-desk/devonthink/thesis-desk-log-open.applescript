-- thesis-desk: log every record a smart rule sees opened.
--
-- Use it in a DEVONthink smart rule with the event "On Opening" and the action
-- "Execute Script" (external).  M-x thesis-desk-install-smart-rule-script
-- compiles it into DEVONthink's Smart Rules script folder.
--
-- Each opening appends one line to ~/.local/state/thesis-desk/opens.tsv:
--   ISO time <TAB> UUID <TAB> name
-- Emacs watches that file (thesis-desk-watch-mode); nothing runs between opens.

on performSmartRule(theRecords)
	set stateDir to (POSIX path of (path to home folder)) & ".local/state/thesis-desk"
	set logFile to stateDir & "/opens.tsv"
	do shell script "mkdir -p " & quoted form of stateDir
	tell application id "DNtp"
		repeat with theRecord in theRecords
			set theUUID to uuid of theRecord
			set theName to name of theRecord
			do shell script "printf '%s\\t%s\\t%s\\n' \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\" " & quoted form of theUUID & " " & quoted form of theName & " >> " & quoted form of logFile
		end repeat
	end tell
end performSmartRule
