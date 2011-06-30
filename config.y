%{

#define YYSTACK_USE_ALLOCA 0

#include <sys/types.h>

#include <grp.h>
#include <pwd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "dgamelaunch.h"

extern int yylex(void);
extern void yyerror(const char*);
extern char *yytext;
extern unsigned int line, col;

extern int num_games;
int ncnf = 0;
struct dg_cmdpart *curr_cmdqueue = NULL;
struct dg_menu *curr_menu = NULL;
int cmdqueue_num = -1;

static const char* lookup_token (int t);

%}

%union {
	char* s;
	int kt;
	unsigned long i;
}

%token TYPE_SUSER TYPE_SGROUP TYPE_SGID TYPE_SUID TYPE_MAX TYPE_MAXNICKLEN
%token TYPE_GAME_SHORT_NAME TYPE_WATCH_SORTMODE TYPE_SERVER_ID
%token TYPE_ALLOW_REGISTRATION
%token TYPE_PATH_GAME TYPE_NAME_GAME TYPE_PATH_DGLDIR TYPE_PATH_SPOOL
%token TYPE_PATH_BANNER TYPE_PATH_CANNED TYPE_PATH_CHROOT
%token TYPE_PATH_PASSWD TYPE_PATH_LOCKFILE TYPE_PATH_TTYREC
%token TYPE_MALSTRING TYPE_PATH_INPROGRESS TYPE_GAME_ARGS TYPE_RC_FMT
%token TYPE_CMDQUEUE TYPE_DEFINE_MENU TYPE_BANNER_FILE TYPE_CURSOR
%token TYPE_MAX_IDLE_TIME TYPE_MENU_MAX_IDLE_TIME
%token <s> TYPE_VALUE
%token <i> TYPE_NUMBER TYPE_CMDQUEUENAME
%type  <kt> KeyType
%token <i> TYPE_DGLCMD0 TYPE_DGLCMD1 TYPE_DGLCMD2
%token TYPE_DEFINE_GAME
%token <i> TYPE_BOOL

%%

Configuration: KeyPairs
	| { if (!silent) fprintf(stderr, "%s: no settings, proceeding with defaults\n", config); }
	;

KeyPairs: KeyPairs KeyPair
	| KeyPair
	;

KeyPair: TYPE_CMDQUEUE '[' TYPE_CMDQUEUENAME ']'
	{
	    int qnum = $<i>3;

	    if (globalconfig.cmdqueue[qnum]) {
		fprintf(stderr, "%s:%d: command queue defined twice, bailing out\n",
			config, line);
		exit(1);
	    }
	    cmdqueue_num = qnum;
	}
	'=' cmdlist
	{
	    /*
	    struct dg_cmdpart *tmp = curr_cmdqueue;
	    while (tmp) {
		fprintf(stderr, "cmd=%i, p1=%s, p2=%s\n", tmp->cmd, tmp->param1, tmp->param2);
		tmp = tmp->next;
	    }
	    */
	    globalconfig.cmdqueue[cmdqueue_num] = curr_cmdqueue;
	    curr_cmdqueue = NULL;
	}
	| definemenu
	{
	    /* nothing */
	}
	| definegame
	{
	    /* nothing */
	}
	| KeyType '=' TYPE_VALUE {
  struct group* gr;
  struct passwd* usr;

  switch ($1)
  {
    case TYPE_SGROUP:
      if (globalconfig.shed_gid != (gid_t)-1)
        break;

      globalconfig.shed_group = strdup($3);
      if ((gr = getgrnam($3)) != NULL)
      {
	globalconfig.shed_gid = gr->gr_gid;
	if (!silent)
	  fprintf(stderr, "%s:%d: suggest replacing 'shed_group = \"%s\"' line with 'shed_gid = %d'\n",
	  config, line, $3, gr->gr_gid);
      }
      else
      {
        if (!silent)
          fprintf(stderr, "%s:%d: no such group '%s'\n", config, line, $3);
      }

      break;
    case TYPE_SUSER:
      if (globalconfig.shed_uid != (uid_t)-1)
        break;

      if (!strcmp($3, "root"))
      {
        fprintf(stderr, "%s:%d: I refuse to run as root! Aborting.\n", config, line);
	graceful_exit(1);
      }
      globalconfig.shed_user = strdup($3);
      if ((usr = getpwnam($3)) != NULL)
      {
        if (usr->pw_uid != 0)
	{
          globalconfig.shed_uid = usr->pw_uid;
	  if (!silent)
	    fprintf(stderr, "%s:%d: suggest replacing 'shed_user = \"%s\"' line with 'shed_uid = %d'\n",
	      config, line, $3, usr->pw_uid);
	}
	else
	{
	  fprintf(stderr, "%s:%d: I refuse to run as %s (uid 0!) Aborting.\n", config, line, $3);
	  graceful_exit(1);
	}
      }
      else
      {
        if (!silent)
          fprintf(stderr, "%s:%d: no such user '%s'\n", config, line, $3);
      }
      break;

    case TYPE_PATH_CHROOT:
      if (globalconfig.chroot) free(globalconfig.chroot);
      globalconfig.chroot = strdup ($3);
      break;

  case TYPE_WATCH_SORTMODE:
      {
	  int tmpi, okay = 0;

	  for (tmpi = (SORTMODE_NONE+1); tmpi < NUM_SORTMODES; tmpi++)
	      if (!strcasecmp(SORTMODE_NAME[tmpi], $3 )) {
		  globalconfig.sortmode = tmpi;
		  okay = 1;
		  break;
	      }
	  if (!okay)
	      fprintf(stderr, "%s:%d: unknown sortmode '%s'\n", config, line, $3);
      }
      break;

  case TYPE_SERVER_ID:
      if (globalconfig.server_id) free(globalconfig.server_id);
      globalconfig.server_id = strdup($3);
      break;

    case TYPE_PATH_DGLDIR:
      if (globalconfig.dglroot) free(globalconfig.dglroot);
      globalconfig.dglroot = strdup($3);
      break;

    case TYPE_PATH_BANNER:
      if (globalconfig.banner) free(globalconfig.banner);
      globalconfig.banner = strdup($3);
      break;

    case TYPE_PATH_LOCKFILE:
      if (globalconfig.lockfile) free (globalconfig.lockfile);
      globalconfig.lockfile = strdup($3);
      break;

    case TYPE_PATH_PASSWD:
      if (globalconfig.passwd) free(globalconfig.passwd);
      globalconfig.passwd = strdup($3);
      break;

    default:
      fprintf(stderr, "%s:%d: token %s does not take a string, bailing out\n",
        config, line, lookup_token($1));
      exit(1);

  }

  free($3);
}
	| KeyType '=' TYPE_MALSTRING {}
	| KeyType '=' TYPE_BOOL {
	    switch ($1) {
	    case TYPE_ALLOW_REGISTRATION:
		globalconfig.allow_registration = $<i>3;
		break;
	    default:
		fprintf(stderr, "%s:%d: token %s does not take a boolean, bailing out\n",
			config, line, lookup_token($1)); 
		exit(1);
	    }
  	}
	| KeyType '=' TYPE_NUMBER {

  switch ($1)
  {
    case TYPE_SUID:
      if (!silent && globalconfig.shed_uid != (uid_t)-1 && globalconfig.shed_uid != $3)
        fprintf(stderr, "%s:%d: 'shed_uid = %lu' entry overrides old setting %d\n",
	  config, line, $3, globalconfig.shed_uid);

      /* Naive user protection - do not allow running as user root */
      if ($3 == 0)
      {
        fprintf(stderr, "%s:%d: I refuse to run as uid 0 (root)! Aborting.\n", config, line);
        graceful_exit(1);
      }

      globalconfig.shed_uid = $3;
      break;

    case TYPE_SGID:
      if (!silent && globalconfig.shed_gid != (gid_t)-1 && globalconfig.shed_gid != $3)
        fprintf(stderr, "%s:%d: 'shed_gid = %lu' entry overrides old setting %d\n",
	  config, line, $3, globalconfig.shed_gid);

      globalconfig.shed_gid = $3;
      break;

    case TYPE_MAX:
      globalconfig.max = $3;
      break;

  case TYPE_MAXNICKLEN:
      globalconfig.max_newnick_len = $3;
      if (globalconfig.max_newnick_len > DGL_PLAYERNAMELEN) {
	  fprintf(stderr, "%s:%d: max_newnick_len > DGL_PLAYERNAMELEN\n", config, line);
	  globalconfig.max_newnick_len = DGL_PLAYERNAMELEN;
      }
      break;

  case TYPE_MENU_MAX_IDLE_TIME:
      globalconfig.menu_max_idle_time = $3;
      break;

    default:
      fprintf(stderr, "%s:%d: token %s does not take a number, bailing out\n",
        config, line, lookup_token($1)); 
      exit(1);
  }
};




menu_definition : TYPE_BANNER_FILE '=' TYPE_VALUE
         {
           if (curr_menu->banner_fn) {
               fprintf(stderr, "%s:%d: banner file already defined.\n", config, line);
               exit(1);
           }
           curr_menu->banner_fn = strdup( $3 );
         }
       | TYPE_CURSOR '=' '(' TYPE_NUMBER ',' TYPE_NUMBER ')'
         {
           if (curr_menu->cursor_x != -1) {
               fprintf(stderr, "%s:%d: cursor position already defined.\n", config, line);
               exit(1);
           }
           curr_menu->cursor_x = $4;
           curr_menu->cursor_y = $6;
         }
       | TYPE_CMDQUEUE '[' TYPE_VALUE ']'
         {
             struct dg_menuoption *tmp;
             struct dg_menuoption *tmpmenuopt;
             if (curr_cmdqueue) {
                 fprintf(stderr, "%s:%d: command queue already in use?\n", config, line);
                 exit(1);
             }
             tmp = malloc(sizeof(struct dg_menuoption));
             tmp->keys = strdup( $3 );
             tmp->cmdqueue = NULL;
             tmp->next = curr_menu->options;
	     curr_menu->options = tmp;
         }
       '=' cmdlist
         {
	     curr_menu->options->cmdqueue = curr_cmdqueue;
             curr_cmdqueue = NULL;
         }
       ;


menu_definitions : menu_definition
	| menu_definition menu_definitions
	;


definemenu : TYPE_DEFINE_MENU '[' TYPE_VALUE ']'
	{
	   struct dg_menulist *tmp_menulist = globalconfig.menulist;

	   while (tmp_menulist) {
	       if (!strcmp(tmp_menulist->menuname, $<s>3 )) {
                   fprintf(stderr, "%s:%d: menu \"%s\" already defined.\n", config, line, $<s>3 );
                   exit(1);
	       }
	       tmp_menulist = tmp_menulist->next;
	   }

           tmp_menulist = malloc(sizeof(struct dg_menulist));
           tmp_menulist->menuname = strdup( $<s>3 );
           tmp_menulist->next = globalconfig.menulist;

	   globalconfig.menulist = tmp_menulist;

           tmp_menulist->menu = malloc(sizeof(struct dg_menu));
	   curr_menu = tmp_menulist->menu;

	   curr_menu->options = NULL;
	   curr_menu->cursor_x = curr_menu->cursor_y = -1;
	   curr_menu->banner_fn = NULL;
	}
	'{' menu_definitions '}'
	{
	    curr_menu = NULL;
	}
	;



game_definition : TYPE_CMDQUEUE
	{
	    if (myconfig[ncnf]->cmdqueue) {
		fprintf(stderr, "%s:%d: command queue defined twice, bailing out\n",
			config, line);
		exit(1);
	    }
	}
	'=' cmdlist
	{
	    myconfig[ncnf]->cmdqueue = curr_cmdqueue;
	    curr_cmdqueue = NULL;
	}
	| TYPE_GAME_ARGS '=' game_args_list
	{
	    /* nothing */
	}
        | TYPE_MAX_IDLE_TIME '=' TYPE_NUMBER
        {
            myconfig[ncnf]->max_idle_time = $3;
        }
	| KeyType '=' TYPE_VALUE
	{
	    switch ( $1 ) {
	    case TYPE_PATH_CANNED:
		if (myconfig[ncnf]->rcfile) free(myconfig[ncnf]->rcfile);
		myconfig[ncnf]->rcfile = strdup($3);
		break;

	    case TYPE_PATH_SPOOL:
		if (myconfig[ncnf]->spool) free (myconfig[ncnf]->spool);
		myconfig[ncnf]->spool = strdup($3);
		break;

	    case TYPE_PATH_TTYREC:
		if (myconfig[ncnf]->ttyrecdir) free(myconfig[ncnf]->ttyrecdir);
		myconfig[ncnf]->ttyrecdir = strdup($3);
		break;

	    case TYPE_PATH_GAME:
		if (myconfig[ncnf]->game_path) free(myconfig[ncnf]->game_path);
		myconfig[ncnf]->game_path = strdup ($3);
		break;

	    case TYPE_NAME_GAME:
		if (myconfig[ncnf]->game_name) free (myconfig[ncnf]->game_name);
		myconfig[ncnf]->game_name = strdup($3);
		break;

	    case TYPE_GAME_SHORT_NAME:
		if (myconfig[ncnf]->shortname) free (myconfig[ncnf]->shortname);
		myconfig[ncnf]->shortname = strdup($3);
		break;

	    case TYPE_RC_FMT:
		if (myconfig[ncnf]->rc_fmt) free(myconfig[ncnf]->rc_fmt);
		myconfig[ncnf]->rc_fmt = strdup($3);
		break;

	    case TYPE_PATH_INPROGRESS:
		if (myconfig[ncnf]->inprogressdir) free(myconfig[ncnf]->inprogressdir);
		myconfig[ncnf]->inprogressdir = strdup($3);
		break;

	    default:
		fprintf(stderr, "%s:%d: token does not belong into game definition, bailing out\n",
			config, line);
		exit(1);
	    }
	}
	;

game_arg : TYPE_VALUE
	{
	    char **tmpargs;
	    if (myconfig[ncnf]->bin_args) {
		myconfig[ncnf]->num_args++;
		tmpargs = calloc((myconfig[ncnf]->num_args+1), sizeof(char *));
		memcpy(tmpargs, myconfig[ncnf]->bin_args, (myconfig[ncnf]->num_args * sizeof(char *)));
		free(myconfig[ncnf]->bin_args);
		myconfig[ncnf]->bin_args = tmpargs;
	    } else {
		myconfig[ncnf]->num_args = 1;
		myconfig[ncnf]->bin_args = calloc(2, sizeof(char *));
	    }
	    myconfig[ncnf]->bin_args[(myconfig[ncnf]->num_args)-1] = strdup($1);
	    myconfig[ncnf]->bin_args[(myconfig[ncnf]->num_args)] = 0;
	}
	;

game_args_list : game_arg
	| game_arg ',' game_args_list
	;

game_definitions : game_definition
	| game_definition game_definitions
	;

definegame : TYPE_DEFINE_GAME '{'
	{
	    struct dg_config **tmpconfig = NULL;

	    tmpconfig = calloc(ncnf + 1, sizeof(myconfig[0]));
	    if (!tmpconfig) {
		fprintf(stderr, "%s:%d: could not allocate memory for config, bailing out\n",
			config, line);
		exit(1);
	    }

	    if (myconfig) {
		int tmp;
		for (tmp = 0; tmp < ncnf; tmp++) {
		    tmpconfig[tmp] = myconfig[tmp];
		}
		free(myconfig);
	    }

	    tmpconfig[ncnf] = calloc(1, sizeof(struct dg_config));
	    myconfig = tmpconfig;
	}
	game_definitions '}'
	{
	    ncnf++;
	    num_games = ncnf;
	}
	;

cmdlist : cmdlist ',' dglcmd
	| dglcmd
	;

dglcmd	: TYPE_DGLCMD1 TYPE_VALUE
	  {
	      struct dg_cmdpart *tmp = malloc(sizeof(struct dg_cmdpart));
	      if (tmp) {
		  struct dg_cmdpart *foo = curr_cmdqueue;
		  if (foo) {
		      while (foo->next) foo = foo->next;
		      foo->next = tmp;
		  } else curr_cmdqueue = tmp;
		  tmp->next = NULL;
		  tmp->param1 = strdup( $2 );
		  tmp->param2 = NULL;
		  tmp->cmd = $<i>1;

	      }
	  }
	| TYPE_DGLCMD0
	  {
	      struct dg_cmdpart *tmp = malloc(sizeof(struct dg_cmdpart));
	      if (tmp) {
		  struct dg_cmdpart *foo = curr_cmdqueue;
		  if (foo) {
		      while (foo->next) foo = foo->next;
		      foo->next = tmp;
		  } else curr_cmdqueue = tmp;
		  tmp->next = NULL;
		  tmp->param1 = NULL;
		  tmp->param2 = NULL;
		  tmp->cmd = $<i>1;
	      }
	  }
	| TYPE_DGLCMD2 TYPE_VALUE TYPE_VALUE
	  {
	      struct dg_cmdpart *tmp = malloc(sizeof(struct dg_cmdpart));
	      if (tmp) {
		  struct dg_cmdpart *foo = curr_cmdqueue;
		  if (foo) {
		      while (foo->next) foo = foo->next;
		      foo->next = tmp;
		  } else curr_cmdqueue = tmp;
		  tmp->next = NULL;
		  tmp->param1 = strdup( $2 );
		  tmp->param2 = strdup( $3 );
		  tmp->cmd = $<i>1;
	      }
	  }
	;

KeyType : TYPE_SUSER	{ $$ = TYPE_SUSER; }
	| TYPE_SGROUP	{ $$ = TYPE_SGROUP; }
	| TYPE_SUID	{ $$ = TYPE_SUID; }
	| TYPE_SGID	{ $$ = TYPE_SGID; }
	| TYPE_MAX	{ $$ = TYPE_MAX; }
	| TYPE_MAXNICKLEN	{ $$ = TYPE_MAXNICKLEN; }
        | TYPE_MENU_MAX_IDLE_TIME	{ $$ = TYPE_MENU_MAX_IDLE_TIME; }
	| TYPE_PATH_CHROOT	{ $$ = TYPE_PATH_CHROOT; }
	| TYPE_ALLOW_REGISTRATION	{ $$ = TYPE_ALLOW_REGISTRATION; }
	| TYPE_PATH_GAME	{ $$ = TYPE_PATH_GAME; }
        | TYPE_NAME_GAME        { $$ = TYPE_NAME_GAME; }
	| TYPE_GAME_SHORT_NAME	{ $$ = TYPE_GAME_SHORT_NAME; }
	| TYPE_PATH_DGLDIR	{ $$ = TYPE_PATH_DGLDIR; }
	| TYPE_PATH_SPOOL	{ $$ = TYPE_PATH_SPOOL; }
	| TYPE_PATH_BANNER	{ $$ = TYPE_PATH_BANNER; }
	| TYPE_PATH_CANNED	{ $$ = TYPE_PATH_CANNED; }
	| TYPE_PATH_TTYREC	{ $$ = TYPE_PATH_TTYREC; }
	| TYPE_PATH_PASSWD	{ $$ = TYPE_PATH_PASSWD; }
	| TYPE_PATH_LOCKFILE	{ $$ = TYPE_PATH_LOCKFILE; }
	| TYPE_PATH_INPROGRESS	{ $$ = TYPE_PATH_INPROGRESS; }
	| TYPE_RC_FMT		{ $$ = TYPE_RC_FMT; }
	| TYPE_WATCH_SORTMODE	{ $$ = TYPE_WATCH_SORTMODE; }
	| TYPE_SERVER_ID	{ $$ = TYPE_SERVER_ID; }
	;

%%

const char* lookup_token (int t)
{
  switch (t)
  {
    case TYPE_SUSER: return "shed_user";
    case TYPE_SGROUP: return "shed_group";
    case TYPE_SUID: return "shed_uid";
    case TYPE_SGID: return "shed_gid";
    case TYPE_MAX: return "maxusers";
    case TYPE_MAXNICKLEN: return "maxnicklen";
    case TYPE_MENU_MAX_IDLE_TIME: return "menu_max_idle_time";
    case TYPE_PATH_CHROOT: return "chroot_path";
    case TYPE_PATH_GAME: return "game_path";
    case TYPE_NAME_GAME: return "game_name";
    case TYPE_ALLOW_REGISTRATION: return "allow_new_nicks";
    case TYPE_GAME_SHORT_NAME: return "short_name";
    case TYPE_PATH_DGLDIR: return "dglroot";
    case TYPE_PATH_SPOOL: return "spooldir";
    case TYPE_PATH_BANNER: return "banner";
    case TYPE_PATH_CANNED: return "rc_template";
    case TYPE_PATH_TTYREC: return "ttyrecdir";
    case TYPE_PATH_INPROGRESS: return "inprogressdir";
    case TYPE_GAME_ARGS: return "game_args";
    case TYPE_MAX_IDLE_TIME: return "max_idle_time";
    case TYPE_RC_FMT: return "rc_fmt";
    case TYPE_WATCH_SORTMODE: return "sortmode";
    case TYPE_SERVER_ID: return "server_id";
    default: abort();
  }
}

void yyerror(char const* s)
{
  if (!silent)
    fprintf(stderr, "%s:%d:%d: couldn't parse \"%s\": %s\n", config, line, col, yytext, s);
}
