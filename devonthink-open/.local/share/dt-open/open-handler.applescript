-- Source of "DT Open PDF.app", built by dt-open-install with osacompile.
-- It is the default viewer for PDFs, so the Finder and Alfred hand it every PDF
-- they open. A PDF that is a record in an open DEVONthink database is opened in
-- DEVONthink; any other PDF goes to the fallback viewer (Preview by default).
use AppleScript version "2.4"
use framework "Foundation"
use scripting additions

on open theFiles
	set cfg to readConfig()
	if cfgError of cfg is not "" then logLine(cfg, "settings could not be read: " & cfgError of cfg)
	repeat with theFile in theFiles
		openOne(POSIX path of theFile, cfg)
	end repeat
end open
-- Settings: ~/.config/dt-open/config, one NAME=value per line.
on readConfig()
	set cfg to {cfgFallback:"", cfgLaunch:true, cfgRaise:"window", cfgDebug:false, cfgError:""}
	try
		set cfgFile to (POSIX path of (path to home folder)) & ".config/dt-open/config"
		set cfgText to read (POSIX file cfgFile) as «class utf8»
		repeat with aLine in paragraphs of cfgText
			set aLine to contents of aLine
			set eqPos to offset of "=" in aLine
			if aLine does not start with "#" and eqPos > 1 then
				set theKey to text 1 thru (eqPos - 1) of aLine
				set theValue to ""
				if eqPos < (count aLine) then set theValue to text (eqPos + 1) thru -1 of aLine
				if theValue starts with "\"" and theValue ends with "\"" and (count theValue) > 1 then set theValue to text 2 thru -2 of theValue
				if theKey is "DT_OPEN_FALLBACK" then set cfgFallback of cfg to theValue
				if theKey is "DT_OPEN_LAUNCH" then set cfgLaunch of cfg to (theValue is not "0")
				if theKey is "DT_OPEN_RAISE" and theValue is in {"window", "app", "none"} then set cfgRaise of cfg to theValue
				if theKey is "DT_OPEN_DEBUG" then set cfgDebug of cfg to (theValue is "1")
			end if
		end repeat
	on error errMsg number errNum
		if errNum is not -43 then set cfgError of cfg to errMsg & " (" & errNum & ")"
	end try
	if cfgFallback of cfg starts with "DT Open PDF" then set cfgFallback of cfg to ""
	return cfg
end readConfig
on openOne(thePath, cfg)
	if thePath does not end with ".pdf" then
		do shell script "/usr/bin/open " & quoted form of thePath
		return
	end if
	if openInDEVONthink(thePath, cfg) then
		logLine(cfg, thePath & " -> opened in a DEVONthink window")
	else
		set theCommand to fallbackCommand(thePath, cfg)
		logLine(cfg, thePath & " -> not opened in DEVONthink, running: " & theCommand)
		do shell script theCommand
	end if
end openOne
on fallbackCommand(thePath, cfg)
	set theFile to quoted form of thePath
	if cfgFallback of cfg is not "" then return "/usr/bin/open -a " & quoted form of (cfgFallback of cfg) & " " & theFile
	try
		set stateFile to (POSIX path of (path to home folder)) & ".local/state/dt-open/previous-handler"
		set bundleID to paragraph 1 of (read (POSIX file stateFile) as «class utf8»)
		if bundleID is not "" then return "/usr/bin/open -b " & quoted form of bundleID & " " & theFile
	end try
	return "/usr/bin/open -a Preview " & theFile
end fallbackCommand
on openInDEVONthink(thePath, cfg)
	try
		set resolved to ((current application's NSString's stringWithString:thePath)'s stringByResolvingSymlinksInPath()) as text
		return findAndOpen({resolved, thePath}, cfg)
	on error errMsg number errNum
		logLine(cfg, "opening in DEVONthink failed (" & errNum & "): " & errMsg)
		if errNum is -1743 then
			try
				display alert "DT Open PDF may not control DEVONthink" message "Allow it in System Settings > Privacy & Security > Automation, then open the PDF again. This time it was opened in the fallback viewer." giving up after 8
			end try
		end if
		return false
	end try
end openInDEVONthink
on findAndOpen(candidates, cfg)
	if not (application id "DNtp" is running) then
		if not (cfgLaunch of cfg) then
			logLine(cfg, "DEVONthink is not running and DT_OPEN_LAUNCH is 0")
			return false
		end if
		tell application id "DNtp" to launch
	end if
	waitForDatabases(cfg)
	repeat with candidate in candidates
		if openInDatabases(contents of candidate, cfg) then return true
	end repeat
	return false
end findAndOpen

-- Right after a start there are no databases yet: wait up to 60 s for one.
on waitForDatabases(cfg)
	tell application id "DNtp"
		repeat 120 times
			try
				if (count of databases) > 0 then exit repeat
			end try
			delay 0.5
		end repeat
		set dbCount to count of databases
	end tell
	logLine(cfg, "DEVONthink has " & dbCount & " database(s) open")
end waitForDatabases

on openInDatabases(aPath, cfg)
	tell application id "DNtp"
		repeat with theDatabase in databases
			set hits to lookup records with path aPath in theDatabase
			if cfgDebug of cfg then my logLine(cfg, "  " & aPath & " in " & (name of theDatabase) & ": " & (count of hits))
			if class of hits is list and (count of hits) > 0 then
				set theWindow to open window for record (item 1 of hits)
				set theTitle to ""
				try
					set theTitle to name of theWindow
				end try
				if cfgRaise of cfg is "app" then activate
				if cfgRaise of cfg is "window" then my raiseWindow(theTitle, cfg)
				return true
			end if
		end repeat
	end tell
	return false
end openInDatabases

-- Brings only the PDF's window forward, not DEVONthink's other windows.
on raiseWindow(theTitle, cfg)
	try
		tell application "System Events"
			set theProcess to first application process whose bundle identifier starts with "com.devon-technologies.think"
			tell theProcess
				if theTitle is "" then
					set theWindow to window 1
				else
					set theWindow to first window whose name is theTitle
				end if
				perform action "AXRaise" of theWindow
				if not frontmost then set frontmost to true
			end tell
		end tell
	on error errMsg number errNum
		logLine(cfg, "raising only the PDF window failed (" & errNum & "): " & errMsg & "; using activate")
		tell application id "DNtp" to activate
	end try
end raiseWindow
on logLine(cfg, msg)
	if not (cfgDebug of cfg) and cfgError of cfg is "" then return
	try
		set logFile to (POSIX path of (path to home folder)) & "Library/Logs/DT Open PDF.log"
		do shell script "/usr/bin/printf '%s %s\\n' \"$(/bin/date '+%F %T')\" " & quoted form of msg & " >> " & quoted form of logFile
	end try
end logLine
