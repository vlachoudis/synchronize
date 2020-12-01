#!/usr/local/bin/rexx
#!/data/data/com.termux/files/home/bin/rexx
/*
 * sync.r - Synchronize files
 * Author  = "Vasilis.Vlachoudis@cern.ch"
 * Date: 13/01/2017
 */
signal on error

Version = "0.3"
Author  = "Vasilis.Vlachoudis@cern.ch"

nothing = 0	/* dont do nothing */
parse arg args
args = space(args)

if word(args,1)=="-h" then do
	/* display hash value just in case */
	say right(d2x(HashValue(subword(args,2))),8,0)
	exit
end

if word(args,1)=="-n" then do
	nothing = 1	/* do nothing */
	args = subword(args,2)
end

parse var args remoteHost conffile
if remoteHost="" | conffile = "" then do
	parse source . . prg .
	say "syntax:" prg "[-nrh] <remote-host> <config-file>"
	say "desc:  -n : do not execute anything"
	say "       -h : show the hash value of what follows"
	exit
end

libs = "files.r dates.r synclib.r"
do while libs<>""
	parse var libs lib libs
	if load(lib) then
		if load("/usr/local/lib/brexx/"lib) then
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
localdiff = TMP"/_diff."tempext
SYNCDIFF "local" conffile localdiff
if rc<>0 then call ERROR "RC="RC "running local syncdiff.r"
call Log ">>>     Elapsed" format(time('r'),,1)'s'

call Log ">>> Remote syncdiff..."
remotediff = "_remotediff."tempext
remoteconf = "_"localHost".conf."tempext
RCOPY conffile remoteHost":"remoteconf
RCMD SYNCDIFF localHost remoteconf RTMP"/"remotediff
if rc<>0 then call ERROR "RC="RC "running remote" remoteHost":syncdiff.r"
call Log ">>>     Elapsed" format(time('r'),,1)'s'

call Log ">>> Transfer remote syncdiff file..."
RCOPY remoteHost":"RTMP"/"remotediff TMP"/"remotediff
call Log ">>>     Elapsed" format(time('r'),,1)'s'

flocal  = open(localdiff, "r")
fremote = open(TMP"/"remotediff,"r")

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
/* remove diff files */
if ^nothing then do
	call Log ">>> Update directory structure"
	call time 'r'

	call Log ">>> Local host"
	FILEINFO "-l -o" SYNCPATH||"local" conffile
	if RC<>0 then call ERROR "RC="RC "Executing fileinfo command"

	call Log ">>> Remote host"
	RCMD FILEINFO "-r -o" RSYNCPATH"/"localHost remoteconf
	if RC<>0 then call ERROR "RC="RC "Executing remote fileinfo command"
	call Log ">>>     Elapsed" format(time('r'),,1)'s'

	call Log ">>> Cleanup"
	"rm -f" localdiff TMP"/"remotediff remoteconf
	RCMD "rm -f" remoteconf RTMP"/"remotediff".gz"
	call Log ">>>     Elapsed" format(time('r'),,1)'s'
end

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

	delete_local_name  = TMP"/_delete.local."tempext
	delete_remote_name = TMP"/_delete.remote."tempext
	copy2local_name    = TMP"/_copy2local."tempext
	copy2remote_name   = TMP"/_copy2remote."tempext

	do forever
		localBase = ""
		remoteBase = ""

		call ReadDir flocal, "local.", "localBase"
		call ReadDir fremote,"remote.","remoteBase"

		if localBase=="" & remoteBase=="" then leave

		call Log
		call Log "Base:" localBase "<->" remoteHost":"remoteBase

		delete_local  = open(delete_local_name, "w")	/* delete from local directory	*/
		delete_remote = open(delete_remote_name,"w")	/* delete from remote directory	*/
		copy2local    = open(copy2local_name,   "w")	/* copy from remote to local	*/
		copy2remote   = open(copy2remote_name,  "w")	/* copy from local to remote	*/

		call CompareDirectories

		call close delete_local
		call close delete_remote
		call close copy2local
		call close copy2remote

		/* If do nothing is activated then ignore all following commands */
		if nothing then iterate

		/* Execute sync commands */
		/* delete local */
		if filesize(delete_local_name)>0 then do
			call Log "Cmd:" RMFILES localBase delete_local_name
			call flush flog
			RMFILES localBase delete_local_name "|"TEE logfile "2>&1"
			call seek flog,0,"EOF"
		end

		/* delete remote */
		if filesize(delete_remote_name)>0 then do
			call Log "Cmd:" RCOPY delete_remote_name remoteHost":"delete_remote_name
			call Log "Cmd:" RCMD RMFILES remoteBase delete_remote_name
			call flush flog
			RCOPY delete_remote_name remoteHost":"delete_remote_name "|"TEE logfile "2>&1"

			RCMD RMFILES remoteBase delete_remote_name "|"TEE logfile "2>&1"

			if ^nothing then
				RCMD "rm -f" delete_remote_name
			call seek flog,0,"EOF"
		end

		/* copy from local to remote */
		if filesize(copy2remote_name)>0 then do
			call Log "Cmd:" RSYNC '--files-from='copy2remote_name localBase '"'ESC(remoteHost':'remoteBase)'"'
			call flush flog
			RSYNC '--files-from='copy2remote_name localBase '"'ESC(remoteHost':'remoteBase)'"' "|"TEE logfile "2>&1"

			call seek flog,0,"EOF"
		end

		/* copy from remote to local */
		if filesize(copy2local_name)>0 then do
			call Log "Cmd:" RSYNC '--files-from='copy2local_name '"'ESC(remoteHost':'remoteBase)'"' localBase
			call flush flog
			RSYNC '--files-from='copy2local_name '"'ESC(remoteHost':'remoteBase)'"' localBase "|"TEE logfile "2>&1"

			call seek flog,0,"EOF"
		end

		/* clean up */
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
				when lt=="E" then do
					call write ,"  +++ Delete REMOTE dir:" local.1 "(yes*|no)? "
					pull action
					if abbrev("NO",action,1) then
						local.1.@TYPE = "I"
					else
						call RMDir "R",local.1
				end
				when rt=="E" then do
					call write , "  +++ Delete LOCAL dir:" remote.1 "(yes*|no)? "
					pull action
					if abbrev("NO",action,1) then
						local.1.@TYPE = "I"
					else
						call RMDir "L",remote.1
				end
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
	end; else do
		call Log "-R: rm" arg(2)
		call lineout delete_remote, arg(2)
	end
return

/* --- CopyLocalDir --- */
CopyLocalDir:
	dir = local.1
	call CopyFrom "L",local.1
	do l=2 to local.0
		call CopyFrom "L",dir"/"local.l
	end
return

/* --- CopyRemoteDir --- */
CopyRemoteDir:
	dir = remote.1
	call CopyFrom "R",remote.1
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
	end; else do
		size = word(remote.r.@INFO,2)
		_logmsg = "  R->L:" basename(arg(2))
		call lineout copy2local,arg(2)
	end
	call Log overlay(right(size,10),_logmsg,40)
	if datatype(size,"NUM") then totalSize = totalSize + size
return

/* --- Delete --- */
Delete:
	call ReportDir
	if arg(1)=="L" then do
		call Log "    -L:" basename(arg(2))
		call lineout delete_local,arg(2)
	end; else do
		call Log "    -R:" basename(arg(2))
		call lineout delete_remote,arg(2)
	end
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
	if ^value("nothing",,0) then do
		address command cmd
		if RC<>0 then
			call Log "ERROR: RC="RC "Executing:" cmd
	end
return

/* --- Log --- */
Log: procedure expose flog
	parse arg text,option
	if option^=="N" then say text
	if ^value("nothing",,0) then
		call lineout(flog,date() time()":" text)
return
