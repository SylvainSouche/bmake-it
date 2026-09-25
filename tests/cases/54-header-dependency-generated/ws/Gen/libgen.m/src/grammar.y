%{
int yylex(void);
int yyerror(const char *s);
%}
%token TOKEN_A
%%
start: TOKEN_A ;
%%
int yyerror(const char *s) { return 0; }
int yylex(void) { return 0; }
