/*
 * $Id: fileinfo.c,v 1.1 2015/01/15 09:23:35 bnv Exp bnv $
 * $Log: fileinfo.c,v $
 * Revision 1.1  2015/01/15 09:23:35  bnv
 * Initial revision
 *
 */

#include <pwd.h>
#include <grp.h>
#include <ctype.h>
#include <errno.h>
#include <regex.h>
#include <stdio.h>
#include <dirent.h>
#include <getopt.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>

#define TRUE 1
#define FALSE 0

typedef unsigned int	dword;

#define __DEBUG	0
#define SKIPBLANKS(p)	while (*(p) && isspace(*(p))) (p)++;
#define SKIPWORD(p)	while (*(p) && !isspace(*(p))) (p)++;

enum operator_enum {
	Pattern_Add,
	Pattern_Sub
};

enum operation_enum {
	Mode_Local,
	Mode_Remote
};

typedef struct regexp_list_st {
	enum	operator_enum	op;
#if __DEBUG>0
	char	*exp;
#endif
	regex_t	regexp;
	struct	regexp_list_st	*next;
} RegexpList;

typedef struct leaf_st {
	char	*str;
	struct leaf_st *left, *right;
} Leaf;

/* --- Local Variables --- */
int	initpath_length;
char	initpath[FILENAME_MAX];
int	operation_mode =  -1;
char	*prgname;
RegexpList	*patternlist;
FILE	*fout;
char	output_filename[FILENAME_MAX];

/* --- Function Prototypes --- */
void scanDirectory(char *basedir);

/* --- usage --- */
void usage()
{
	printf("syntax: %s -[lr] -[-output name] <conf_file>\n",prgname);
	printf("desc:\n");
	printf("author:Vasilis.Vlachoudis@cern.ch\n");
	printf("date: "__DATE__"\n");
	exit(0);
} /* usage */

/* --- hashValue --- */
dword hashValue(char *s)
{
	dword hash = 0;
	while (*s) {
		hash = 31*hash + *s;
		s++;
	}
	return hash;
} /* hashValue */

/* --- binAdd--- */
Leaf *binAdd(Leaf *tree, char *str)
{
	int	leftTaken = FALSE;
	Leaf	*thisLeaf=tree, *lastLeaf;

	Leaf *leaf = (Leaf*)malloc(sizeof(Leaf));
	leaf->str = strdup(str);
	leaf->left = NULL;
	leaf->right = NULL;

	if (tree==NULL)
		return leaf;

	while (thisLeaf != NULL) {
		int cmp = strcmp(str,thisLeaf->str);
		lastLeaf = thisLeaf;
		if (cmp < 0) {
			thisLeaf = thisLeaf->left;
			leftTaken = TRUE;
		} else
		if (cmp > 0) {
			thisLeaf = thisLeaf->right;
			leftTaken = FALSE;
		} else {
			fprintf(stderr,"ERROR The file %s exists twice on the same directory\n",str);
			return NULL;
		}
	}

#if __DEBUG>0
		printf("+++ %s->%s = %s\n",lastLeaf->str,
			leftTaken?"left":"right",leaf->str);
#endif

	if (leftTaken)
		lastLeaf->left = leaf;
	else
		lastLeaf->right = leaf;

	return tree;
} /* binAdd*/

/* --- binDel --- */
void binDel(Leaf *tree)
{
	if (tree==NULL) return;
	if (tree->left) binDel(tree->left);
	if (tree->right) binDel(tree->right);
	free(tree->str);
	free(tree);
} /* binDel */

#if __DEBUG>0
/* --- binPrint --- */
void binPrint(Leaf *tree, int depth)
{
	int i;
	if (tree==NULL)
		return;
	binPrint(tree->left,depth+3);
	for (i=0; i<depth; i++)
		putchar('-');
	printf(" %s\n",tree->str);
	binPrint(tree->right,depth+3);
} /* binPrint */
#endif

/* --- checkFile ---- */
int checkFile(char *fullpath)
{
	char	*filename;
	RegexpList *pat = patternlist;

	filename = fullpath + initpath_length;
	if (*filename==0)
		filename=fullpath;
#if __DEBUG>0
	printf("checkFile \"%s\"",fullpath);
#endif

	while (pat) {
		int match = !regexec(&(pat->regexp),filename,0,NULL,0);
#if __DEBUG>0
		printf(">C> %d %s %d %s\n",
				match, pat->exp, pat->op, filename);
#endif
		if (pat->op==Pattern_Add) {
			if (match)
				return TRUE;
		} else {
			if (match)
				return FALSE;
		}
		pat = pat->next;
	}
	return TRUE;
} /* checkFile */

/* --- splitPath --- */
void splitPath(char *fullpath, char *path, char *name)
{
	char *ptr = fullpath + strlen(fullpath)-1;

	while (ptr>fullpath && *ptr!='/')
		ptr--;

	if (ptr==fullpath) {
		*path = 0;
		strcpy(name,fullpath);
	} else {
		int n = (int)((long)ptr-(long)fullpath);
		if (n-initpath_length>=0) {
			memcpy(path,fullpath+initpath_length,
				n-initpath_length);
			path[n-initpath_length] = 0;
			strcpy(name,fullpath+n+1);
		} else {
			path[0] = 0;
			strcpy(name,fullpath);
		}
	}
} /* splitPath */

/* --- printInfo --- *
 * Mode: small letters refer to files, capital to directories
 *	D - directory
 *	l - link
 *	f - normal file
 *	i,I - ignore
 * Actions:
 *	n,N - new file/Directory
 *	c   - changed file
 *	e,E - erased file/Directory
 */
void printInfo(struct stat *filestat, char *filename)
{
	struct	passwd	*pwd;
	struct	group	*grp;
	char	path[FILENAME_MAX];
	char	name[FILENAME_MAX];
	char	type;
	char	*nametoprint;

	splitPath(filename,path,name);
	pwd = getpwuid(filestat->st_uid);
	grp = getgrgid(filestat->st_gid);

	nametoprint = name;

	if (S_ISLNK(filestat->st_mode))
		type = 'l';
	else
	if (S_ISDIR(filestat->st_mode)) {
		type = 'D';
		nametoprint = filename+initpath_length;
	} else
		type = 'f';

	if (!checkFile(filename)) {
		if (type=='D')
			type='I';	/* ignore */
		else
			type = 'i';
	}

	/*
	printf("pwd=%p pwd->pw_name=%s\n",pwd,pwd->pw_name);
	printf("grp=%p grp->gr_name=%s\n",grp,grp->gr_name);
	printf("filename=%s path=%s name=%s nametoprint=%s\n",
		filename, path, name, nametoprint);
	*/

	fprintf(fout,"%c %ld %ld %s %s %s\n",
		type,
#ifdef ANDROID
		filestat->st_mtime,
#else
		filestat->st_mtim.tv_sec,
#endif
		(long)filestat->st_size,
		"bnv", "dr",
//		((pwd==NULL)?"none":pwd->pw_name),
//		((grp==NULL)?"none":grp->gr_name),
		nametoprint);
} /* printInfo */

/* --- fileInfo --- */
void fileInfo(char *filename)
{
	struct	stat filestat;

	if (lstat(filename,&filestat)!=0) {
		fprintf(stderr,"Error %d on file: %s\n",errno,filename);
		return;
	}

//	if (S_ISLNK(filestat.st_mode) || (filestat.st_mode&S_IFLNK))
	if (S_ISLNK(filestat.st_mode))
		return;
	else
	if (S_ISDIR(filestat.st_mode)) {
		printInfo(&filestat,filename);
		scanDirectory(filename);
	} else
	if (S_ISREG(filestat.st_mode))
		printInfo(&filestat,filename);
} /* fileInfo */

/* --- scanTree --- */
void scanTree(Leaf *tree, char *basedir, int dirs)
{
	char	filename[FILENAME_MAX];
	struct	stat filestat;

	if (tree==NULL)
		return;

	scanTree(tree->left,basedir,dirs);

	// prepare full path
	strcpy(filename,basedir);
	strcat(filename,tree->str);

	if (lstat(filename,&filestat)!=0)
		return;

	if (dirs) {
		if (S_ISDIR(filestat.st_mode)) {
			printInfo(&filestat,filename);
			scanDirectory(filename);
		}
	} else {
		if (!S_ISDIR(filestat.st_mode))
			fileInfo(filename);
	}

	scanTree(tree->right,basedir,dirs);
} /* scanTree */

/* --- scanDirectory --- */
void scanDirectory(char *basedir)
{
	DIR	*dir;
	struct	dirent	*dirinfo;
	int	len = strlen(basedir);
	Leaf	*tree = NULL;

	if (!checkFile(basedir))
		return;

//	fprintf(fout,"Dir: %s\n",basedir+initpath_length);

	dir = opendir(basedir);
	if (dir==NULL) {
		fprintf(stderr,"Error %d on dir: %s\n",errno,basedir);
		return;
	}

	while ((dirinfo=readdir(dir))!=NULL) {
		if (!strcmp(dirinfo->d_name,"."))
			continue;
		if (!strcmp(dirinfo->d_name,".."))
			continue;
		tree = binAdd(tree,dirinfo->d_name);
	}
	closedir(dir);

#if __DEBUG>0
	binPrint(tree,0);
#endif

	if (basedir[len-1]!='/') {
		basedir[len]='/';
		basedir[len+1]=0;
	}
	scanTree(tree,basedir,FALSE);	// only files
	scanTree(tree,basedir,TRUE);	// only directories

	binDel(tree);
} /* scanDirectory */

/* --- scanFile --- */
void scanFile(void)
{
	char basename[FILENAME_MAX];
	struct timezone tz;
	struct timeval  tv;
	long before;

	initpath_length = strlen(initpath);
	if (initpath[initpath_length] == '/') {
		// remove trailing /
		initpath[initpath_length] == 0;
		initpath_length--;
	}
	if (initpath_length>0) {
		if (output_filename[0]) {
			sprintf(basename,"%s.%08X",
				output_filename,
				hashValue(initpath));
			fout = fopen(basename,"w");
		} else
			fout = stdout;

		fprintf(fout,"Base: %s\n",initpath);
		fprintf(stderr,"Base: %s\t",initpath);
		gettimeofday(&tv, &tz);
		before = tv.tv_sec;
		fileInfo(initpath);
		gettimeofday(&tv, &tz);
		fprintf(stderr,"%lds\n",tv.tv_sec-before);
		if (fout != stdout)
			fclose(fout);
	}
} /* scanFile */

/* --- newPattern --- */
RegexpList *newPattern(char *expression, int caseRespect)
{
	RegexpList	*pat;

	pat = (RegexpList*)malloc(sizeof(RegexpList));

#if __DEBUG>0
	pat->exp= strdup(expression);
#endif
	if (expression[0]=='+')
		pat->op = Pattern_Add;
	else
	if (expression[0]=='-')
		pat->op = Pattern_Sub;
	else
		goto AP_ERROR;

	if (regcomp(&(pat->regexp),expression+1,caseRespect?0:REG_ICASE))
		goto AP_ERROR;

	/* establish the link */
	pat->next = NULL;
	return pat;

AP_ERROR:
	fprintf(stderr,"Error on regular expression: %s\n",expression);
	exit(-2);
	return NULL;
} /* newPattern */

/* --- freePatternList --- */
void freePatternList(RegexpList* list)
{
	RegexpList *next;

	while (list) {
		next = list->next;
		regfree(&(list->regexp));
#if __DEBUG>0
		free(list->exp);
#endif
		free(list);
		list = next;
	}
} /* freePatternList */

/* --- parseFile --- */
void parseFile(char *conf_filename)
{
	RegexpList *pat;
	FILE	*fin;
	int	caseRespect = TRUE;

	if (conf_filename==NULL)
		fin = stdin;
	else
		fin = fopen(conf_filename,"r");
	if (fin==NULL) {
		fprintf(stderr,"Error oppening configuration file %s\n",
				conf_filename);
		exit(-1);
	}

	patternlist = pat = NULL;
	while (1) {
		char	line[FILENAME_MAX];
		char	*pch;

		fgets(line,sizeof(line)-1,fin);
		if (feof(fin)) break;

		line[strlen(line)-1] = 0;
#if __DEBUG>0
		printf(">>> %s\n",line);
#endif
		pch = line;

		SKIPBLANKS(pch);
		if (*pch=='#' || *pch==0)
			continue;

		caseRespect = TRUE;
		if (*pch=='i' || *pch=='I' || *pch=='~') {
			caseRespect = FALSE;
			pch++;
		}

		if (!memcmp(pch,"local:",6)) {
			pch += 6;
			SKIPBLANKS(pch);

			scanFile();	// Execute pending command

			// Free resources
			freePatternList(patternlist);
			patternlist = pat = NULL;

			// New rule
			memset(initpath,0,sizeof(initpath));
			if (operation_mode==Mode_Local) {
				strcpy(initpath,pch);
#if __DEBUG>0
				printf("*-* Check local: %s\n",initpath);
#endif
			}
		} else
		if (*pch=='+' || *pch=='-') {
			RegexpList *newpat = newPattern(pch,caseRespect);
			if (patternlist==NULL)
				patternlist = newpat;
			else
				pat->next = newpat;
			pat = newpat;
		} else
		if (!memcmp(pch,"remote:",7)) {
			if (operation_mode==Mode_Remote) {
				pch += 7;
				SKIPBLANKS(pch);
				//pch = (char*)memchr(pch,':',strlen(pch))+1;
				strcpy(initpath,pch);
#if __DEBUG>0
				printf("*-* Check remote: %s\n",initpath);
#endif
			}
		} else {
			fprintf(stderr,"ERROR: Unknown command found \"%s\"\n",
					pch);
			exit(-3);
		}
	}
	scanFile();	// Execute pending command
	freePatternList(patternlist);

	if (fin!=stdin) fclose(fin);
} /* parseFile */

/* --- main --- */
int main(int argc, char *argv[])
{
	int	c;
	prgname = argv[0];
	output_filename[0] = 0;

	while (1) {
		int option_index = 0;
		static struct option long_options[] = {
			{"local",  0, 0, 'l'},
			{"remote", 0, 0, 'r'},
			{"output", 1, 0, 'o'},
			{0, 0, 0, 0}
		};

		c = getopt_long  (argc, argv, "lro:",
			long_options, &option_index);
		if (c == -1)
			break;

		switch (c) {
			case 0:
				printf ("option %s", long_options[option_index].name);
				if (optarg)
					printf (" with arg %s", optarg);
				printf ("\n");
				break;

			case 'l':
				if (operation_mode>=0) {
					fprintf(stderr,"Error on operation mode (local)\n");
					exit(-99);
				}
				operation_mode = Mode_Local;
				break;

			case 'r':
				if (operation_mode>=0) {
					fprintf(stderr,"Error on operation mode (local)\n");
					exit(-99);
				}
				operation_mode = Mode_Remote;
				break;

			case 'o':
				strcpy(output_filename,optarg);
				break;

			case '?':
				usage();

			default:
				printf ("?? getopt returned character code 0%o ??\n", c);
		}
	}
	if (operation_mode<0)
		usage();

	if (optind < argc) {
		while (optind < argc)
			parseFile(argv[optind++]);
	} else
		parseFile(NULL);

	return 0;
} /* main */
