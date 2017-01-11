/*
 * Remove files from stdin, on file per line
 * Directories are removed recursively
 * Author: Vasilis.Vlachoudis@cern.ch
 * Date: 11.01.2011
 */
#include <stdio.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

int remove_directory(const char *path)
{
	int r = -1;
	size_t path_len = strlen(path);
	DIR *d = opendir(path);
	printf("Removing directory: %s\n",path);
	if (d) {
		struct dirent *p;
		r = 0;
		while (!r && (p=readdir(d))) {
			int r2 = -1;
			char *filename;
			size_t len;
			/* Skip the names "." and ".." as we don't want to recurse on them. */
			if (!strcmp(p->d_name, ".") || !strcmp(p->d_name, "..")) continue;
			len = path_len + strlen(p->d_name) + 2;
			filename = malloc(len);
			if (filename) {
				struct stat statbuf;
				snprintf(filename, len, "%s/%s", path, p->d_name);
				if (!stat(filename, &statbuf))
					if (S_ISDIR(statbuf.st_mode))
						r2 = remove_directory(filename);
					else {
						printf("Removing: %s\n",filename);
						r2 = unlink(filename);
						if (r2)
							fprintf(stderr,"Error removing \"%s\"\n",filename);
					}
				free(filename);
			}
			r = r2;
		}
		closedir(d);
	}
	if (!r) r = rmdir(path);
	return r;
} // remove_directory

/* --- main --- */
int main(int ac, char *av[])
{
	size_t lenbase;
	char filename[1024];
	FILE* fin=stdin;

	if (ac==1) {
		fprintf(stderr,"syntax: %s <base> [<fromfile>]\n",av[0]);
		fprintf(stderr,"delete recursively sub-files and directories from base given in stdin\n");
		fprintf(stderr,"Author: Vasilis.Vlachoudis@cern.ch\n");
		fprintf(stderr,"Date: 11.01.2011\n");
		exit(0);
	}

	strcpy(filename, av[1]);
	lenbase = strlen(filename);
	/* add a trailing / if needed */
	if (filename[lenbase-1]!='/') {
		filename[lenbase++] = '/';
		filename[lenbase] = 0;
	}

	if (ac==3)
		fin = fopen(av[2],"r");
		if (!fin) {
			fprintf(stderr,"Cannot open file \"%s\"\n",av[2]);
			return -1;
			exit(-1);
		}

	while (fgets(filename+lenbase, sizeof(filename)-lenbase, fin)!=NULL) {
		struct stat statbuf;
		size_t len = strlen(filename);
		int r = -1;

		/* strip trailing CR, LF */
		while (filename[len-1]==0x0D || filename[len-1]==0x0A)
			filename[--len] = 0;

		if (len == lenbase) continue;	/* ignore empty lines */

		if (!stat(filename, &statbuf)) {
			if (S_ISDIR(statbuf.st_mode))
				r = remove_directory(filename);
			 else {
				printf("Removing: %s\n",filename);
				r = unlink(filename);
			}
		} else
			r = -1;

		if (r!=0)
			fprintf(stderr,"Error removing \"%s\"\n",filename);
	}
	if (fin != stdin) fclose(fin);
	return 0;
} // main
