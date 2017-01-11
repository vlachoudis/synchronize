#!/usr/local/bin/rexx
/* Compare two sync files and create a diff file with all files and a flag on the change
 * diff file format
 * <flag> <unixtime> <size> <user> <group> <filename>
 * flag:
 *   f - regular file no change since last time
 *   D - regular directory no change
 *   n - new file
 *   N - new directory
 *   c - file changed since last time
 *   e - erased(deleted) file
 *   E - erased(deleted) directory (with all subdirs and files)
 *   i - ignored file
 *   I - ignored directory
 *
 * return on stdout the location of the temporary file created
 */

parse arg host conffile filediff
if host="" | conffile="" then call usage

if host=='local' then
	mode = "l"
else
	mode = 'r'

/*>>>call load "/usr/local/lib/brexx/synclib.r"*/
call load "/home/bnv/prg/synchronize/synclib.r"
call SyncConfig

filenew = "/tmp/_sync."host
fileold = syncpath||host
/*filediff = "/tmp/_diff."time('s')*/
/*filediff = "/tmp/_diff."random()*/

FILEINFO "-"mode "-o "filenew conffile
if rc<>0 then do
	call lineout "<STDERR>","Error getting file information RC="RC
	exit rc
end

fc = open(conffile,"r")
fdiff = open(filediff,"w")
do forever
	line = strip(read(fc))
	if eof(fc) then leave
	start = left(line,1)
	if start=="#" | start=="@" | start=="-" | line=="" then iterate
	if abbrev(line,"local:") & mode=='l' then do
		parse var line . ":" base
		base = strip(base)
		if right(base,1)=="/" then base = left(base, length(base)-1)
		hash = CompareFiles(strip(base))
	end; else
	if abbrev(line,"remote:") & mode=='r' then do
		parse var line . ":" base
		base = strip(base)
		if right(base,1)=="/" then base = left(base, length(base)-1)
		hash = CompareFiles(base)
	end
end
call close fc
call close fdiff
"rm -f" filenew".*"
if mode=='R' then do
	GZIP filediff
	filediff = filediff".gz"
end
/*say filediff*/
return

/* --- Usage --- */
Usage:
	parse source . . prg .
	say "syntax:" prg "{local|host} <config-file>"
	exit

/* --- CompareFiles --- */
CompareFiles: procedure expose filenew fileold fdiff
	parse arg base
	hash = right(d2x(HashValue(base)),8,0)
	fnew = open(filenew"."hash,"r")
	fold = open(fileold"."hash,"r")

	if fnew<0 then do
		say "ERROR:" fnew "opening file new="filenew
		return
	end

	basenew = read(fnew)
	call lineout fdiff,basenew

	if fold>0 then do
		baseold = read(fold)

		if basenew ^= baseold then do
			say "Error reading new/old files"
			say "New="filenew"."hash "("fnew")" basenew
			say "Old="fileold"."hash "("fold")" baseold
			signal CMP_END
		end

		call ReadDir fnew,"new.","basenew"
		call ReadDir fold,"old.","baseold"
		do while new.0>0 & old.0>0
			if new.1 ^== old.1 then do
				if new.1<old.1 then do
					call PrintDirInfo 'n'
					call ReadDir fnew,"new.","basenew"
				end; else do
					call PrintDirInfo 'e'
					call ReadDir fold,"old.","baseold"
				end
			end; else  do
				if new.1.@TYPE ^== 'I' then
					call CheckDirectories
				call ReadDir fnew,"new.","basenew"
				call ReadDir fold,"old.","baseold"
			end
		end
		do while new.0>0
			call PrintDirInfo 'n'
			call ReadDir fnew,"new.","basenew"
		end
		do while old.0>0
			call PrintDirInfo 'e'
			call ReadDir fold,"old.","baseold"
		end
	end; else do
		call ReadDir fnew,"new.","basenew"
		do while new.0>0
			call PrintDirInfo 'f'
			call ReadDir fnew,"new.","basenew"
		end
	end

CMP_END:
	call close fnew
	if fold>0 then call close fold
return hash

/* --- CheckDirectories --- */
CheckDirectories:
	/* the directories names are the same */
	call lineout fdiff,'D' new.1.@INFO new.1
	n=2; o=2
	do while n<=new.0 & o<=old.0
		if new.n==old.o then do
			if new.n.@TYPE^=='i' then do
				if new.n.@INFO ^== old.o.@INFO then
					type = 'c' /* changed */
				else
					type = new.n.@TYPE
				call lineout fdiff,type new.n.@INFO new.n
			end
			n=n+1
			o=o+1
		end; else
		if new.n<old.o then do
			if new.n.@TYPE^=='i' then
				call lineout fdiff,'n' new.n.@INFO new.n /* new */
			n=n+1
		end; else do
			if old.o.@TYPE^=='i' then
				call lineout fdiff,'e' old.o.@INFO old.o /* deleted */
			o=o+1
		end
	end
	/* Check remaining files */
	if n<=new.0 then
		do n=n to new.0
			if new.n.@TYPE^=='i' then
				call lineout fdiff,'n' new.n.@INFO new.n /* new */
		end
	if o<=old.0 then
		do o=o to old.0
			if old.o.@TYPE^=='i' then
				call lineout fdiff,'e' old.o.@INFO old.o /* erased */
		end
return

/* --- PrintDirInfo --- */
PrintDirInfo:
	parse arg _action
	if _action=='n' | _action=='f' then do
		if _action=='n' then
			_diraction='N'
		else
			_diraction='D'
		if new.1.@TYPE=='I' then
			call lineout fdiff,'I' new.1.@INFO new.1 /* ignore */
		else do
			call lineout fdiff,_diraction new.1.@INFO new.1 /* new dir */
			do n=2 to new.0
				if new.n.@TYPE^='i' then
					call lineout fdiff,_action new.n.@INFO new.n /* new */
			end
		end
	end; else do
		if old.1.@TYPE=='I' then
			call lineout fdiff, 'I' old.1.@INFO old.1 /* ignore */
		else
			call lineout fdiff, 'E' old.1.@INFO old.1 /* erased with sub dirs */
	end
return
