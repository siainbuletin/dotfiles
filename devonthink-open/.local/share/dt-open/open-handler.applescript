-- Source of "DT Open PDF.app", built by dt-open-install with osacompile.
-- It is the default viewer for PDFs, so the Finder and Alfred hand it every PDF
-- they open. A PDF that is a record in an open DEVONthink database is opened in
-- DEVONthink; any other PDF goes to the fallback viewer (Preview by default).
use AppleScript version "2.4"
use framework "Foundation"
use scripting additions

on open theFiles
	set cfg to readConfig()
	repeat with theFile in theFiles
		openOne(POSIX path of theFile, cfg)
	end repeat
end open

-- Settings: ~/.config/dt-open/config, one NAME=value per line.
on readConfig()
	set cfg to {cfgFallback:"Preview", cfgLaunch:true, cfgReveal:false}
	try
		set cfgFile to (POSIX path of (path to home folder)) & ".config/dt-open/config"
		set cfgText to read (POSIX file cfgFile) as «class utf8»
		repeat with aLine in paragraphs of cfgText
			set aLine to contents of aLine
			set eq to offset of "=" in aLine
			if aLine does not start with "#" and eq > 1 then
				set theKey to text 1 thru (eq - 1) of aLine
				set theValue to ""
				if eq < (count aLine) then set theValue to text (eq + 1) thru -1 of aLine
				if theValue starts with "\"" and theValue ends with "\"" and (count theValue) > 1 then set theValue to text 2 thru -2 of theValue
				if theKey is "DT_OPEN_FALLBACK" and theValue is not "" then set cfgFallback of cfg to theValue
				if theKey is "DT_OPEN_LAUNCH" then set cfgLaunch of cfg to (theValue is not "0")
				if theKey is "DT_OPEN_MODE" then set cfgReveal of cfg to (theValue is "reveal")
			end if
		end repeat
	end try
	-- This app is the default for PDFs: never fall back to ourselves.
	if cfgFallback of cfg starts with "DT Open PDF" then set cfgFallback of cfg to "Preview"
	return cfg
end readConfig

on openOne(thePath, cfg)
	if thePath does not end with ".pdf" then
		do shell script "/usr/bin/open " & quoted form of thePath
		return
	end if
	set itemLink to lookupLink(thePath, cfgLaunch of cfg)
	if itemLink is not "" then
		if cfgReveal of cfg then set itemLink to itemLink & "?reveal=1"
		open location itemLink
	else
		do shell script "/usr/bin/open -a " & quoted form of (cfgFallback of cfg) & " " & quoted form of thePath
	end if
end openOne

-- The item link of the record for the file, or "" if there is none. Any error
-- (for instance the Automation permission being refused) also gives "", so the
-- PDF still opens in the fallback viewer.
on lookupLink(thePath, mayLaunch)
	try
		-- DEVONthink stores the path it was given; try the path with symlinks
		-- resolved first, then the path as the Finder gave it.
		set resolved to ((current application's NSString's stringWithString:thePath)'s stringByResolvingSymlinksInPath()) as text
		return findLink({resolved, thePath}, mayLaunch)
	on error
		return ""
	end try
end lookupLink

on findLink(candidates, mayLaunch)
	if not (application id "DNtp" is running) then
		if not mayLaunch then return ""
		tell application id "DNtp" to launch
	end if
	tell application id "DNtp"
		-- Right after a start there are no databases yet: wait up to 60 s for one.
		repeat 120 times
			try
				if (count of databases) > 0 then exit repeat
			end try
			delay 0.5
		end repeat
		repeat with candidate in candidates
			repeat with theDatabase in databases
				set hits to lookup records with path (contents of candidate) in theDatabase
				if (count of hits) > 0 then return reference URL of (item 1 of hits)
			end repeat
		end repeat
	end tell
	return ""
end findLink
