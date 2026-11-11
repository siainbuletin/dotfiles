-- Source of "DT Open PDF.app", built by dt-open-install with osacompile.
-- Finder and Alfred hand the PDFs they open to this app (it is the default
-- viewer for PDFs); dt-open decides between DEVONthink and the fallback viewer.
on open theFiles
	set helper to (POSIX path of (path to home folder)) & ".local/bin/dt-open"
	set args to ""
	repeat with theFile in theFiles
		set args to args & " " & quoted form of POSIX path of theFile
	end repeat
	do shell script quoted form of helper & args
end open
