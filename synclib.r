/* Sync library & configuration */
exit

/* --- SyncConfig --- */
SyncConfig:
	parse source . . prg .
	PRGDIR = left(prg, lastpos("/",prg)-1)
	PRGDIR = "/usr/local/bin"
	/*PRGDIR = "/home/bnv/prg/synchronize"*/

	SYNCPATH = "/var/spool/sync"
	LOGFILE = "sync.log"

	RSH   = "ssh"
	RCOPY = "scp -pC"
	GZIP  = "gzip"
	RSYNC = 'rsync -avpP -e "ssh -C"'
	TEE   = "tee -a"

	SYNCDIFF = PRGDIR"/syncdiff.r"
	FILEINFO = PRGDIR"/fileinfo"
	RMFILES  = PRGDIR"/rmfiles"
	LOCALHOST = "hostname"()

	/* Allow time jitter of few sec */
	timeJitter = 1	/* sec */

	/* correct variables */
	if right(syncpath,1)^='/' then syncpath=syncpath'/'
	logfile = syncpath||logfile
return

/* --- ReadDir --- */
ReadDir: procedure
	trace o
	parse arg f,array,base

	call value array"0","0",-1
	n = 0

	pos = seek(f)
	line = read(f)

	/* Check if the base has changed */
	if word(line,1)=="Base:" then do
		if value(base,,-1)^=="" then do
			call seek f,pos
			return 0
		end
		call value base,subword(line,2),-1
		pos = seek(f)
		line = read(f)
	end
	if eof(f) | word(line,1)=="Base:" then do
		call seek f,pos
		return 0
	end

	/* Must be a directory entry */
	parse var line type date size user group file
	if type<'A' | type>'Z' then do
		say "ERROR:" line
		return 0
	end
	n = 1
	call value array||n,file,-1
	call value array||n".@INFO",date size user group,-1
	call value array||n".@TYPE",type,-1

	do forever
		pos = seek(f)
		line = read(f)
		if eof(f) then leave
		parse var line type date size user group file
		if type>='A' & type<='Z' then do
			call seek f,pos
			leave
		end
		n = n + 1
		call value array||n,file,-1
		call value array||n".@INFO",date size user group,-1
		call value array||n".@TYPE",type,-1
	end
	call value array"0",n,-1
return n
