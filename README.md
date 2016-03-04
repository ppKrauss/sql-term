This project illustrates the use of [PostgreSQL textsearch-dictionaries](http://www.postgresql.org/docs/9.1/static/textsearch-dictionaries.html), [dict-xsyn](http://www.postgresql.org/docs/current/static/dict-xsyn.html), metaphone, and a simple database for terminological storage.

# Term
... [Controlled terminologies](https://www.wikidata.org/wiki/Q1469824) ...

XML: terms into [JATS](https://en.wikipedia.org/wiki/Journal_Article_Tag_Suite), [AKN](http://www.akomantoso.org/) or [LexML](http://projeto.lexml.gov.br/documentacao/Parte-3-XML-Schema.pdf) documents... Each document must use a public standard ID, as  [DOI](https://www.wikidata.org/wiki/Q25670) or [URN Lex](https://en.wikipedia.org/wiki/Lex_(URN)).

... lexemes ...  illustring use of [português brasileiro](https://www.wikidata.org/wiki/Q750553)... 

## Objetive ##
...

## Modelagem ##

UML class diagram of [ini.sql](src/ini.sql):

```
...

```

### NOTES

* [Using metaphone as lexeme](http://stackoverflow.com/questions/4001579/postgresql-full-text-search-randomly-dropping-lexemes).

* PostreSQL guide, 
** [Text search dictionaries](http://www.postgresql.org/docs/9.1/static/textsearch-dictionaries.html#TEXTSEARCH-THESAURUS)
** [runtime-config-client](http://www.postgresql.org/docs/current/static/runtime-config-client.html#GUC-DEFAULT-TEXT-SEARCH-CONFIG)

