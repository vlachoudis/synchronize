#!/usr/local/bin/rexx
/*
 * sync.r - Synchronize files
 */
noexec = 0
noremove = 0
signal on error

Version = "0.2"
Author = "Vasilis.Vlachoudis@cern.ch"

parse arg args
args = space(args)

if word(args,1)=="-n" then do
	noexec=1
	noremove=1
	args = subword(args,2)
end

parse var args remoteHost conffile
if remoteHost="" | conffile = "" then do
	parse source . . prg .
	say "syntax:" prg "[-nr] <remote-host> <config-file>"
	say "desc:  -n : do not execute anything"
	exit
end

libs = "files.r dates.r synclib.r"
do while libs<>""
	parse var libs lib libs
	if load(lib) then
		call ERROR "Cannot load library:" lib". Please check RXLIB var"
end

call SyncConfig

flog = open(logfile,"a")
if flog<0 then
	call ERROR "Opening logfile '"logfile"'"

call Log "sync.r V"Version Author

/* local vars */
RCMD  = RSH remoteHost

/* Find the changes in the remote & local hosts */
call Log ">>> Local syncdiff..."
call time 'r'
tempext = time("s")
localdiff = "/tmp/_diff."tempext
SYNCDIFF "local" conffile localdiff
if rc<>0 then call ERROR "RC="RC "running local syncdiff.r"
call Log ">>>     Elapsed" format(time('r'),,1)'s'

call Log ">>> Remote syncdiff..."
remotediff = "/tmp/_remotediff."time("s")
remoteconf = "/tmp/_"localHost".conf."tempext
RCOPY conffile remoteHost":"remoteconf
RCMD SYNCDIFF localHost remoteconf remotediff
if rc<>0 then call ERROR "RC="RC "running remote" remoteHost":syncdiff.r"
call Log ">>>     Elapsed" format(time('r'),,1)'s'

call Log ">>> Transfer compressed remote syncdiff file..."
RCMD GZIP remotediff
RCOPY remoteHost":"remotediff".gz" remotediff".gz"
GZIP "-d" remotediff".gz"
call Log ">>>     Elapsed" format(time('r'),,1)'s'

flocal  = open(localdiff, "r")
fremote = open(remotediff,"r")

if flocal<0 | fremote<0 then
	call ERROR "Opening file Local="flocal "Remote="fremote

/* --- Prepare log file --- */
call Log ,"N"
call Log copies("-",50),"N"
call Log "+++ Start of" conffile "+++","N"
"cat" conffile "(stack"
do queued()	/* print only the rules */
	parse pull line
	line = strip(line)
	if line=="" | left(line,1)=="#" then iterate
	call Log " "line,"N"
end
call Log "+++ End of" conffile "+++","N"

/* Compare the directories and files */
ResolveDefault = "n"
call Compare

call close flocal
call close fremote

/* update fileinfos */
call Log ,"N"
call Log ">>> Update directory structure"
call time 'r'
FILEINFO "-l -o" syncpath||"local" conffile
if RC<>0 then call ERROR "RC="RC "Executing fileinfo command"
RCMD FILEINFO "-r -o" syncpath||localHost remoteconf
if RC<>0 then call ERROR "RC="RC "Executing remote fileinfo command"
call Log ">>>     Elapsed" format(time('r'),,1)'s'

/* remove diff files */
if ^noremove then do
	call Log ">>> Cleanup"
	"rm -f" localdiff remotediff remoteconf remotediff
	RCMD "rm -f" remoteconf remotediff".gz"
end
call Log ">>>     Elapsed" format(time('r'),,1)'s'

call close flog
return

/* --- Error --- */
Error:
	call lineout "<STDERR>","ERROR: "arg(1)
	pull .
exit 1

/* --- Compare --- */
Compare:
	local. = ""
	remote. = ""
	totalSize = 0

	delete_local_name  = "/tmp/_delete.local."tempext
	delete_remote_name = "/tmp/_delete.remote."tempext
	copy2local_name    = "/tmp/_copy2local."tempext
	copy2remote_name   = "/tmp/_copy2remote."tempext

	do forever
		localBase = ""
		remoteBase = ""

		call ReadDir flocal,"local.","localBase"
		call ReadDir fremote,"remote.","remoteBase"

		if localBase=="" & remoteBase=="" then leave

		call Log
		call Log "Base:" localBase "<->" remoteHost":"remoteBase

		delete_local  = open(delete_local_name, "w")	/* delete from local directory	*/
		delete_remote = open(delete_remote_name,"w")	/* delete from remote directory	*/
		copy2local    = open(copy2local_name,   "w")		/* copy from remote to local	*/
		copy2remote   = open(copy2remote_name,  "w")		/* copy from local to remote	*/

		call CompareDirectories

		call close delete_local
		call close delete_remote
		call close copy2local
		call close copy2remote

		/* Execute sync commands */
		/* delete local */
		if filesize(delete_local_name)>0 then do
			say "<<<" RMFILES localBase delete_local_name
			RMFILES localBase delete_local_name
		end

		/* delete remote */
		if filesize(delete_remote_name)>0 then do
			RCOPY delete_remote_name remoteHost":"delete_remote_name
			say ">>>" RCMD RMFILES remoteBase delete_remote_name
			RCMD RMFILES remoteBase delete_remote_name
			if ^noremove then
				RCMD "rm -f" delete_remote_name
		end

		/* copy from local to remote */
		if filesize(copy2remote_name)>0 then
			'rsync -avpP -e "ssh -C" --files-from='copy2remote_name localBase '"'ESC(remoteHost':'remoteBase)'"'

		/* copy from remote to local */
		if filesize(copy2local_name)>0 then
			'rsync -avpP -e "ssh -C" --files-from='copy2local_name '"'ESC(remoteHost':'remoteBase)'"' localBase

		if ^noremove then
			"rm -f" delete_local_name delete_remote_name copy2local_name copy2remote_name
	end

	call Log "Total" trunc(totalSize/1024)"kb transfered."
return

/* --- CompareDirectories --- */
CompareDirectories:
	do while local.0>0 & remote.0>0
		/* Check Directories */
		lt = local.1.@TYPE
		rt = remote.1.@TYPE
		dirReported = 0

		/* assume the base has not changed */
		if local.1 ^== remote.1 then select
			when lt=='I' then
				call ReadDir flocal,"local.","localBase"
			when lt=="N" | local.1<remote.1 then do
				call CopyLocalDir
				call ReadDir flocal,"local.","localBase"
			end
			when rt=='I' then
				call ReadDir fremote,"remote.","remoteBase"
			when rt=="N" | remote.1<local.1 then do
				call CopyRemoteDir
				call ReadDir fremote,"remote.","remoteBase"
			end
			when rt=="E" then
				call ReadDir fremote,"remote.","remoteBase"
			when lt=="E" then
				call ReadDir flocal,"local.","localBase"
			otherwise
				say "ERROR Compare: Unhandled condition"
				say "  local:" local.1 lt local.1.@info
				say "  remote:" remote.1 rt remote.1.@info
				pull
		end; else do
			/* Directory names are the same */
			/* Possible types D,N,E,I */
			select
				when lt=="E" then
					call RMDir "R",local.1
				when rt=="E" then
					call RMDir "L",remote.1
				when lt=="I" | rt=="I" then
					nop	/* just ignore them */
				otherwise
					call CheckDirectory
			end
			call ReadDir flocal,"local.","localBase"
			call ReadDir fremote,"remote.","remoteBase"
		end
	end
	do while local.0>0
		lt = local.1.@TYPE
		dirReported = 0
		if lt^=='I' then call CopyLocalDir
		call ReadDir flocal,"local.","localBase"
	end
	do while remote.0>0
		rt = remote.1.@TYPE
		dirReported = 0
		if rt^=='I' then call CopyRemoteDir
		call ReadDir fremote,"remote.","remoteBase"
	end
return

/* --- RMDir --- */
RMDir:
	if arg(1)=="L" then do
		call Log "-L: rm" arg(2)
		call lineout delete_local, arg(2)
		/*cmd = "rm -Rf" ESC(localBase||arg(2))*/
	end; else do
		call Log "-R: rm" arg(2)
		call lineout delete_remote, arg(2)
		/*cmd = RCMD 'rm -Rf "'ESC(remoteBase||arg(2))'"'*/
	end
	/*call Exec cmd*/
return

/* --- CopyLocalDir --- */
CopyLocalDir:
	/*call MKDir "R",local.1*/
	dir = local.1
	do l=2 to local.0
		call CopyFrom "L",dir"/"local.l
	end
return

/* --- CopyRemoteDir --- */
CopyRemoteDir:
	/*call MKDir "L",remote.1*/
	dir = remote.1
	do r=2 to remote.0
		call CopyFrom "R",dir"/"remote.r
	end
return

/* --- CheckDirectory --- */
CheckDirectory:
	l = 2	/* local index */
	r = 2	/* remote index */
	dir = local.1
	do while l<=local.0 & r<=remote.0
		lt = local.l.@TYPE
		rt = remote.r.@TYPE
		if local.l==remote.r then do
			/* possible flags f,e,n,c,i */
			if lt^=='i' | rt^=='i' then select
				when lt=='e' & rt=='e' then nop
				when lt=='f' & rt=='f' then do
					if local.l.@INFO^==remote.r.@INFO then
						/* check the dates!!! */
						call Resolve
				end
				when lt=='e' & rt=='f' then
					call Delete 'R',dir"/"remote.r
				when lt=='f' & rt=='e' then
					call Delete 'L',dir"/"local.l
				when lt=='c' & rt=='f' then
					call CopyFrom 'L',dir"/"local.l
				when lt=='f' & rt=='c' then
					call CopyFrom 'R',dir"/"remote.r
				otherwise
					call Resolve
			end
			l=l+1
			r=r+1
		end; else
		if local.l<remote.r then do /* new local */
			if lt^=='i' & lt^=='e' then
				call CopyFrom 'L',dir"/"local.l
			l=l+1
		end; else do
			if rt^=='i' & rt^=='e' then
				call CopyFrom 'R',dir"/"remote.r
			r=r+1
		end
	end

	/* Check remaining files */
	do l=l to local.0
		lt = local.l.@TYPE
		if lt^=='i' & lt^=='e' then
			call CopyFrom 'L',dir"/"local.l
	end
	do r=r to remote.0
		rt = remote.r.@TYPE
		if rt^=='i' & rt^=='e' then
			call CopyFrom 'R',dir"/"remote.r
	end
return

/* --- Resolve --- */
Resolve:
	timeLocal = word(local.l.@INFO,1)
	timeRemote = word(remote.r.@INFO,1)

	/* Check for a false alarm if time is within the jitter value */
	if abs(timeLocal-timeRemote) <= timeJitter then
		if subword(local.l.@INFO,2) = subword(remote.r.@INFO,2) then do
			/* Do nothing... */
			return
		end

	say
	if dir="" then
		say "Subdir: /"
	else
		say "Subdir:" dir

	say "  L:" local.l "	"lt GMTime(timeLocal) subword(local.l.@INFO,2)
	say "  R:" remote.r "	"rt GMTime(timeRemote) subword(remote.r.@INFO,2)
	say "  Actions:"

	/* Capital = default for all subsequest requestes */
	/* Small = let the program choose the default action */
	if ResolveDefault>='a' & ResolveDefault<='z' then do
		/* find the best action */
		ResolveDefault = 'n'
		if timeLocal>timeRemote then ResolveDefault='l'
		else
		if timeLocal<timeRemote then ResolveDefault='r'
	end
	_def = translate(ResolveDefault)

	if _def='N' then _D="*"; else _D=" "
	say "	"_D "n/N: Do nothing"

	if _def='L' then _D="*"; else _D=" "
	say "	"_D "l/L: Local -> Remote"
	if _def='C' then _D="*"; else _D=" "
	say "	"_D "c/C: Local(client) -> Remote + backup"

	if _def='R' then _D="*"; else _D=" "
	say "	"_D "r/R: Remote -> Local"
	if _def='S' then _D="*"; else _D=" "
	say "	"_D "s/S: Remote(server) -> Local + backup"

	if _def='D' then _D="*"; else _D=" "
	say "	"_D "d/D: Delete both"

/*	if _def='D' then _D="*"; else _D=" "
	say "	"_D "k/K: Keep both" */

	do forever
		parse pull action
		if action=="" then action=ResolveDefault
		action = left(action,1)
		_act = translate(action)
		select
			when _act=="N" then leave
			when _act=="L" then call CopyFrom 'L',dir"/"local.l
			when _act=="R" then call CopyFrom 'R',dir"/"remote.r
			when _act=="C" then do
				fn = remoteBase"/"dir"/"remote.r
				call Log "Backup:" fn"~"
				RCMD "mv '"fn"' '"fn"~'"
				call CopyFrom 'L',dir"/"local.l
			end
			when _act=="S" then do
				fn = localBase"/"dir"/"local.l
				call Log "Backup:" fn"~"
				"mv '"fn"' '"fn"~'"
				call CopyFrom 'R',dir"/"remote.r
			end
			when _act=="D" then do
				call Delete 'L',dir"/"local.l
				call Delete 'R',dir"/"remote.r
			end
			otherwise
				say "Invalid action"
				iterate
		end
		leave
	end
	ResolveDefault = action
return

/* --- CopyFrom --- */
CopyFrom:
	call ReportDir
	if arg(1)=="L" then do
		size = word(local.l.@INFO,2)
		_logmsg = "  L->R:" basename(arg(2))
		call lineout copy2remote,arg(2)
		/*cmd = RCOPY ESC(localBase||arg(2)) '"'ESC(remoteHost':'remoteBase||arg(2))'"'*/
	end; else do
		size = word(remote.r.@INFO,2)
		_logmsg = "  R->L:" basename(arg(2))
		call lineout copy2local,arg(2)
		/*cmd = RCOPY '"'ESC(remoteHost':'remoteBase||arg(2))'"' ESC(localBase||arg(2))*/
	end
	call Log overlay(right(size,10),_logmsg,40)
	totalSize = totalSize + size
	/*call Exec cmd*/
return

/* --- Delete --- */
Delete:
	call ReportDir
	if arg(1)=="L" then do
		call Log "    -L:" basename(arg(2))
		call lineout delete_local,arg(2)
		/*cmd = "rm -f" ESC(localBase||arg(2))*/
	end; else do
		call Log "    -R:" basename(arg(2))
		call lineout delete_remote,arg(2)
		/*cmd = RCMD 'rm -f "'ESC(remoteBase||arg(2))'"'*/
	end
	/*call Exec cmd*/
return

/* --- ReportDir --- */
ReportDir: procedure expose dir dirReported flog
	if ^dirReported then do
		if dir^=="" then
			call Log "Dir:" dir
		else
			call Log "Dir: /"

		dirReported = 1
	end
return

/* --- ESC --- *
 * escape metacharacters
 */
ESC: procedure
	parse arg s
	out = ""
	valid = xrange("A","Z")||xrange("a","z")||"1234567890-+=_.~!@#%/:"
	do i=1 to length(s)
		c = substr(s,i,1)
		if pos(c,valid)>0 then
			out=out||c
		else
			out=out"\"c
	end
return out

/* --- Exec --- */
Exec: procedure expose flog
	trace o
	parse arg cmd
	if ^value("noexec",,0) then do
		address command cmd
		if RC<>0 then
			call Log "ERROR: RC="RC "Executing:" cmd
	end
return

/* --- Log --- */
Log: procedure expose flog
	parse arg text,option
	if option^=="N" then say text
	if ^value("noexec",,0) then
		call lineout(flog,date() time()":" text)
return
