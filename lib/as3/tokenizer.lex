/* tokenizer.lex

   Routines for compiling Flash2 AVM2 ABC Actionscript

   Extension module for the rfxswf library.
   Part of the swftools package.

   Copyright (c) 2008 Matthias Kramm <kramm@quiss.org>
 
   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA */
%{


#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include "../utf8.h"
#include "tokenizer.h"
#include "files.h"

static void countlines(char*text, int len) {
    int t;
    for(t=0;t<len;t++) {
	if(text[t]=='\n') {
	    current_line++;
	    current_column=0;
	} else {
	    current_column++;
	}
    }
}

static int verbose = 1;
static void dbg(const char*format, ...)
{
    char buf[1024];
    int l;
    va_list arglist;
    if(!verbose)
	return;
    va_start(arglist, format);
    vsprintf(buf, format, arglist);
    va_end(arglist);
    l = strlen(buf);
    while(l && buf[l-1]=='\n') {
	buf[l-1] = 0;
	l--;
    }
    printf("(tokenizer) ");
    printf("%s\n", buf);
    fflush(stdout);
}

void syntaxerror(const char*format, ...)
{
    char buf[1024];
    int l;
    va_list arglist;
    if(!verbose)
	return;
    va_start(arglist, format);
    vsprintf(buf, format, arglist);
    va_end(arglist);
    fprintf(stderr, "%s:%d:%d: error: %s\n", current_filename_short, current_line, current_column, buf);
    fflush(stderr);
    exit(1);
}
void warning(const char*format, ...)
{
    char buf[1024];
    int l;
    va_list arglist;
    if(!verbose)
	return;
    va_start(arglist, format);
    vsprintf(buf, format, arglist);
    va_end(arglist);
    fprintf(stderr, "%s:%d:%d: warning: %s\n", current_filename_short, current_line, current_column, buf);
    fflush(stderr);
}


#ifndef YY_CURRENT_BUFFER
#define YY_CURRENT_BUFFER yy_current_buffer
#endif

void handleInclude(char*text, int len, char quotes)
{
    char*filename = 0;
    if(quotes) {
        char*p1 = strchr(text, '"');
        char*p2 = strrchr(text, '"');
        if(!p1 || !p2 || p1==p2) {
            syntaxerror("Invalid include in line %d\n", current_line);
        }
        *p2 = 0;
        filename = strdup(p1+1);
    } else {
        int i1=0,i2=len;
        // find start
        while(!strchr(" \n\r\t", text[i1])) i1++;
        // strip
        while(strchr(" \n\r\t", text[i1])) i1++;
        while(strchr(" \n\r\t", text[i2-1])) i2--;
        if(i2!=len) text[i2]=0;
        filename = strdup(&text[i1]);
    }
    
    char*fullfilename = enter_file(filename, YY_CURRENT_BUFFER);
    yyin = fopen(fullfilename, "rb");
    if (!yyin) {
	syntaxerror("Couldn't open include file \"%s\"\n", fullfilename);
    }

    yy_switch_to_buffer(yy_create_buffer( yyin, YY_BUF_SIZE ) );
    //BEGIN(INITIAL); keep context
}

string_t string_unescape(const char*in, int l)
{
    int len=0;
    const char*s = in;
    const char*end = &in[l];
    char*n = (char*)malloc(l);
    char*o = n;
    while(s<end) {
        if(*s!='\\') {
            o[len++] = *s;
            s++;
            continue;
        }
        s++; //skip past '\'
        if(s==end) syntaxerror("invalid \\ at end of string");

        /* handle the various line endings (mac, dos, unix) */
        if(*s=='\r') { 
            s++; 
            if(s==end) break;
            if(*s=='\n') 
                s++;
            continue;
        }
        if(*s=='\n')  {
            s++;
            continue;
        }
        switch(*s) {
	    case '\\': o[len++] = '\\';s++; break;
	    case '"': o[len++] = '"';s++; break;
	    case 'b': o[len++] = '\b';s++; break;
	    case 'f': o[len++] = '\f';s++; break;
	    case 'n': o[len++] = '\n';s++; break;
	    case 'r': o[len++] = '\r';s++; break;
	    case 't': o[len++] = '\t';s++; break;
            case '0': case '1': case '2': case '3': case '4': case '5': case '6': case '7': {
                unsigned int num=0;
                int nr = 0;
		while(strchr("01234567", *s) && nr<3 && s<end) {
                    num <<= 3;
                    num |= *s-'0';
                    nr++;
                    s++;
                }
                if(num>256) 
                    syntaxerror("octal number out of range (0-255): %d", num);
                o[len++] = num;
                continue;
            }
	    case 'x': case 'u': {
		int max=2;
		char bracket = 0;
                char unicode = 0;
		if(*s == 'u') {
		    max = 6;
                    unicode = 1;
                }
                s++;
                if(s==end) syntaxerror("invalid \\u or \\x at end of string");
		if(*s == '{')  {
                    s++;
                    if(s==end) syntaxerror("invalid \\u{ at end of string");
		    bracket=1;
		}
		unsigned int num=0;
                int nr = 0;
		while(strchr("0123456789abcdefABCDEF", *s) && (bracket || nr < max) && s<end) {
		    num <<= 4;
		    if(*s>='0' && *s<='9') num |= *s - '0';
		    if(*s>='a' && *s<='f') num |= *s - 'a' + 10;
		    if(*s>='A' && *s<='F') num |= *s - 'A' + 10;
                    nr++;
		    s++;
		}
		if(bracket) {
                    if(*s=='}' && s<end) {
                        s++;
                    } else {
                        syntaxerror("missing terminating '}'");
                    }
		}
                if(unicode) {
                    char*utf8 = getUTF8(num);
                    while(*utf8) {
                        o[len++] = *utf8++;
                    }
                } else {
                    if(num>256) 
                        syntaxerror("byte out of range (0-255): %d", num);
                    o[len++] = num;
                }
		break;
	    }
            default:
                syntaxerror("unknown escape sequence: \"\\%c\"", *s);
        }
    }
    string_t out = string_new(n, len);
    o[len]=0;
    return out; 
}

static void handleString(char*s, int len)
{
    if(s[0]=='"') {
        if(s[len-1]!='"') syntaxerror("String doesn't end with '\"'");
        s++;len-=2;
    }
    else if(s[0]=='\'') {
        if(s[len-1]!='\'') syntaxerror("String doesn't end with '\"'");
        s++;len-=2;
    }
    else syntaxerror("String incorrectly terminated");

    
    avm2_lval.str = string_unescape(s, len);
}


char start_of_expression;

static inline int mkid(int type)
{
    char*s = malloc(yyleng+1);
    memcpy(s, yytext, yyleng);
    s[yyleng]=0;
    avm2_lval.id = s;
    return type;
}

static inline int m(int type)
{
    avm2_lval.token = type;
    return type;
}


static char numberbuf[64];
static inline int handlenumber()
{
    if(yyleng>sizeof(numberbuf)-1)
        syntaxerror("decimal number overflow");

    char*s = numberbuf;
    memcpy(s, yytext, yyleng);
    s[yyleng]=0;

    int t;
    char is_float=0;
    for(t=0;t<yyleng;t++) {
        if(yytext[t]=='.') {
            if(is_float)
                syntaxerror("Invalid number");
            is_float=1;
        } else if(!strchr("-0123456789", yytext[t])) {
            syntaxerror("Invalid number");
        }
    }
    if(is_float) {
        avm2_lval.number_float = atof(s);
        return T_FLOAT;
    } 
    char l = (yytext[0]=='-');

    char*max = l?"1073741824":"2147483647";
    if(yyleng-l>10)
        syntaxerror("integer overflow");
    if(yyleng-l==10) {
        int t;
        for(t=0;t<yyleng-l;t++) {
            if(yytext[l+t]>max[t])
                syntaxerror("integer overflow %s > %s", s+l,max);
            else if(yytext[l+t]<max[t])
                break;
        }
    }
    if(yytext[0]=='-') {
        int v = atoi(s);
        avm2_lval.number_int = v;
        if(v>-128)
            return T_BYTE;
        else if(v>=-32768)
            return T_SHORT;
        else
            return T_INT;
    } else {
        unsigned int v = 0;
        for(t=0;t<yyleng;t++) {
            v*=10;
            v+=yytext[t]-'0';
        }
        avm2_lval.number_uint = v;
        if(v<128)
            return T_BYTE;
        else if(v<32768)
            return T_SHORT;
        else
            return T_UINT;
    }
}

void initialize_scanner();
#define YY_USER_INIT initialize_scanner();

#define c() {countlines(yytext, yyleng);}

%}

%s REGEXPOK
%s BEGINNING

NAME	 [a-zA-Z_][a-zA-Z0-9_\\]*

NUMBER	 -?[0-9]+(\.[0-9]*)?

STRING   ["](\\[\x00-\xff]|[^\\"\n])*["]|['](\\[\x00-\xff]|[^\\'\n])*[']
S 	 [ \n\r\t]
MULTILINE_COMMENT [/][*]+([*][^/]|[^/*]|[^*][/]|[\x00-\x1f])*[*]+[/]
SINGLELINE_COMMENT \/\/[^\n]*\n
REGEXP   [/]([^/\n]|\\[/])*[/][a-zA-Z]*
%%


{SINGLELINE_COMMENT}         {c(); /* single line comment */}
{MULTILINE_COMMENT}          {c(); /* multi line comment */}
[/][*]                       {syntaxerror("syntax error: unterminated comment", yytext);}

^include{S}+{STRING}{S}*/\n    {c();handleInclude(yytext, yyleng, 1);}
^include{S}+[^" \t\r\n][\x20-\xff]*{S}*/\n    {c();handleInclude(yytext, yyleng, 0);}
{STRING}                     {c(); BEGIN(INITIAL);handleString(yytext, yyleng);return T_STRING;}

<BEGINNING,REGEXPOK>{
{REGEXP}                     {c(); BEGIN(INITIAL);return m(T_REGEXP);} 
}

\xef\xbb\xbf                 {/* utf 8 bom */}
{S}                          {c();}

{NUMBER}                     {c(); BEGIN(INITIAL);return handlenumber();}

3rr0r                        {/* for debugging: generates a tokenizer-level error */
                              syntaxerror("3rr0r");}

[&][&]                       {c();BEGIN(REGEXPOK);return m(T_ANDAND);}
[|][|]                       {c();BEGIN(REGEXPOK);return m(T_OROR);}
[!][=]                       {c();BEGIN(REGEXPOK);return m(T_NE);}
[=][=][=]                    {c();BEGIN(REGEXPOK);return m(T_EQEQEQ);}
[=][=]                       {c();BEGIN(REGEXPOK);return m(T_EQEQ);}
[>][=]                       {c();return m(T_GE);}
[<][=]                       {c();return m(T_LE);}
[-][-]                       {c();BEGIN(INITIAL);return m(T_MINUSMINUS);}
[+][+]                       {c();BEGIN(INITIAL);return m(T_PLUSPLUS);}
[+][=]                       {c();return m(T_PLUSBY);}
[-][=]                       {c();return m(T_MINUSBY);}
[/][=]                       {c();return m(T_DIVBY);}
[%][=]                       {c();return m(T_MODBY);}
[*][=]                       {c();return m(T_MULBY);}
[>][>][=]                    {c();return m(T_SHRBY);}
[<][<][=]                    {c();return m(T_SHLBY);}
[>][>][>][=]                 {c();return m(T_USHRBY);}
[<][<]                       {c();return m(T_SHL);}
[>][>][>]                    {c();return m(T_USHR);}
[>][>]                       {c();return m(T_SHR);}
\.\.\.                       {c();return m(T_DOTDOTDOT);}
\.\.                         {c();return m(T_DOTDOT);}
\.                           {c();return m('.');}
::                           {c();return m(T_COLONCOLON);}
:                            {c();return m(':');}
implements                   {c();return m(KW_IMPLEMENTS);}
interface                    {c();return m(KW_INTERFACE);}
namespace                    {c();return m(KW_NAMESPACE);}
protected                    {c();return m(KW_PROTECTED);}
override                     {c();return m(KW_OVERRIDE);}
internal                     {c();return m(KW_INTERNAL);}
function                     {c();return m(KW_FUNCTION);}
package                      {c();return m(KW_PACKAGE);}
private                      {c();return m(KW_PRIVATE);}
Boolean                      {c();return m(KW_BOOLEAN);}
dynamic                      {c();return m(KW_DYNAMIC);}
extends                      {c();return m(KW_EXTENDS);}
return                       {c();return m(KW_RETURN);}
public                       {c();return m(KW_PUBLIC);}
native                       {c();return m(KW_NATIVE);}
static                       {c();return m(KW_STATIC);}
import                       {c();return m(KW_IMPORT);}
Number                       {c();return m(KW_NUMBER);}
while                        {c();return m(KW_WHILE);}
class                        {c();return m(KW_CLASS);}
const                        {c();return m(KW_CONST);}
final                        {c();return m(KW_FINAL);}
false                        {c();return m(KW_FALSE);}
break                        {c();return m(KW_BREAK);}
true                         {c();return m(KW_TRUE);}
uint                         {c();return m(KW_UINT);}
null                         {c();return m(KW_NULL);}
else                         {c();return m(KW_ELSE);}
use                          {c();return m(KW_USE);}
int                          {c();return m(KW_INT);}
new                          {c();return m(KW_NEW);}
get                          {c();return m(KW_GET);}
for                          {c();return m(KW_FOR);}
set                          {c();return m(KW_SET);}
var                          {c();return m(KW_VAR);}
is                           {c();return m(KW_IS) ;}
if                           {c();return m(KW_IF) ;}
as                           {c();return m(KW_AS);}
{NAME}                       {c();BEGIN(INITIAL);return mkid(T_IDENTIFIER);}

[+-\/*^~@$!%&\(=\[\]\{\}|?:;,.<>] {c();BEGIN(REGEXPOK);return m(yytext[0]);}
[\)\]]                            {c();BEGIN(INITIAL);return m(yytext[0]);}

.		             {char c1=yytext[0];
                              char buf[128];
                              buf[0] = yytext[0];
                              int t;
                              for(t=1;t<128;t++) {
		                  char c = buf[t]=input();
		                  if(c=='\n' || c==EOF)  {
                                      buf[t] = 0;
		                      break;
                                  }
		              }
			      if(c1>='0' && c1<='9')
			          syntaxerror("syntax error: %s (identifiers must not start with a digit)");
                              else
		                  syntaxerror("syntax error: %s", buf);
		              printf("\n");
			      exit(1);
		              yyterminate();
		             }
<<EOF>>		             {c();
                              void*b = leave_file();
			      if (!b) {
			         yyterminate();
                                 yy_delete_buffer(YY_CURRENT_BUFFER);
                                 return m(T_EOF);
			      } else {
			          yy_delete_buffer(YY_CURRENT_BUFFER);
			          yy_switch_to_buffer(b);
			      }
			     }

%%

int yywrap()
{
    return 1;
}

static char mbuf[256];
char*token2string(enum yytokentype nr)
{
    if(nr==T_STRING)     return "<string>";
    else if(nr==T_INT)     return "<int>";
    else if(nr==T_UINT)     return "<uint>";
    else if(nr==T_FLOAT)     return "<float>";
    else if(nr==T_REGEXP)     return "REGEXP";
    else if(nr==T_EOF)        return "***END***";
    else if(nr==T_GE)         return ">=";
    else if(nr==T_LE)         return "<=";
    else if(nr==T_MINUSMINUS) return "--";
    else if(nr==T_PLUSPLUS)   return "++";
    else if(nr==KW_IMPLEMENTS) return "implements";
    else if(nr==KW_INTERFACE)  return "interface";
    else if(nr==KW_NAMESPACE)  return "namespace";
    else if(nr==KW_PROTECTED)  return "protected";
    else if(nr==KW_OVERRIDE)   return "override";
    else if(nr==KW_INTERNAL)   return "internal";
    else if(nr==KW_FUNCTION)   return "function";
    else if(nr==KW_PACKAGE)    return "package";
    else if(nr==KW_PRIVATE)    return "private";
    else if(nr==KW_BOOLEAN)    return "Boolean";
    else if(nr==KW_DYNAMIC)    return "dynamic";
    else if(nr==KW_EXTENDS)    return "extends";
    else if(nr==KW_PUBLIC)     return "public";
    else if(nr==KW_NATIVE)     return "native";
    else if(nr==KW_STATIC)     return "static";
    else if(nr==KW_IMPORT)     return "import";
    else if(nr==KW_NUMBER)     return "number";
    else if(nr==KW_CLASS)      return "class";
    else if(nr==KW_CONST)      return "const";
    else if(nr==KW_FINAL)      return "final";
    else if(nr==KW_FALSE)      return "False";
    else if(nr==KW_TRUE)       return "True";
    else if(nr==KW_UINT)       return "uint";
    else if(nr==KW_NULL)       return "null";
    else if(nr==KW_ELSE)       return "else";
    else if(nr==KW_USE)        return "use";
    else if(nr==KW_INT)        return "int";
    else if(nr==KW_NEW)        return "new";
    else if(nr==KW_GET)        return "get";
    else if(nr==KW_FOR)        return "for";
    else if(nr==KW_SET)        return "set";
    else if(nr==KW_VAR)        return "var";
    else if(nr==KW_IS)         return "is";
    else if(nr==KW_AS)         return "as";
    else if(nr==T_IDENTIFIER)  return "ID";
    else {
        sprintf(mbuf, "%d", nr);
        return mbuf;
    }
}

void initialize_scanner()
{
    BEGIN(BEGINNING);
}

