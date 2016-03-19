This project offers a simple database for terminological storage, and illustrates the use of [PostgreSQL textsearch-dictionaries](http://www.postgresql.org/docs/9.1/static/textsearch-dictionaries.html), [dict-xsyn](http://www.postgresql.org/docs/current/static/dict-xsyn.html), [metaphone and levenshtein](http://www.postgresql.org/docs/current/static/fuzzystrmatch.html), in a context of terminological applications (search and admin).  Is supposed that, when all logic is at the (SQL) database, the algorithms can be simpler and faster.

## Objetive ##
To present *reference database structure* for "terminology by demand", and offer [requirements](https://en.wikipedia.org/wiki/Software_requirements_specification) and implemantation of a *framework* for manage, search and resolve controled terminologies. Also, as secondary aim, to illustrate a full-SQL implementation.

## PREPARE ##
```
git clone https://github.com/ppKrauss/sql-term.git
cd sql-term
nano src/omLib.php # edit variables $PG_USER and $PG_PW
php src/prepare.php
```
The default is to prepare `term1`, edit *$modeVers* (at `prepare.php`) to prepare term0 Project.

### Examples and case uses
The functions can be used as webservice or in SQL  queries. About webservice applications, see [Wayta](http://wayta.scielo.org/), the main reference-example.  For other uses and details, the [examples folder](examples) are didactic (for "learling by examples") and plays role of tesing module, as [diff asserts](https://en.wikipedia.org/wiki/Assertion_(software_development)).

Typical usage on terminal:
```
cd sql-term
psql -h localhost -U postgres postgres < examples/basic1.sql | more
# or
psql -h localhost -U postgres postgres < examples/basic1.sql >  test.txt
diff test.txt examples/basic1.dump.txt
```
the database user (`-U postgres`)  must be conform edited `$PG_USER`. If database name also changed, the `psql` commands also must be changed.

## Modeling ##

The *Term* table is so simple: each term, canonic or not, is a row in the main table. A secondary table for namespaces, *ns*, split terms in "base" group (theme, corpus or project) and  its "auxiliary" groups, for translations (one namespace for each language) and other dependent namespaces.

UML class diagram of *SCHEMA term1* tables and views, at [ini1.sql](src/ini1.sql):

![uml class diagram](http://yuml.me/fe36a8da)

### Conventions ###
The  public functions runs in a set of namespaces defined by the base-namespace, never in "all namespaces".
Some functions can be config to target a specific namespace or  to specific languages.

For each namespace the "canonic term" concept can change, from standardized to "most-popular" statistics. Semantic conflict or compromise between canonic term and its synonymous, are both valid, semantic analyses is out of scope of this project. The is_cult flag is an option to 

For searching and resolving, use a base-namespace as target and adopt its mask with `term1.get_basemask(label)` for all searches and resolutions. To offer more specific language-target options in the interface, use `term1.get_baselangs(label)`.

## Populating with other data
... CSV import , SQL import ... Namespaces... 

## Fast Guide

Use of SQL functions, or microservices with same *method name* (SEARCH, FIND, N2C, N2Ns, etc.). For function details and description, see [ini1.sql](src/ini1.sql), or examples [basic1](https://github.com/ppKrauss/sql-term/blob/master/examples/basic1.sql) (b1) and [basic2](https://github.com/ppKrauss/sql-term/blob/master/examples/basic2.sql) (b2).


* `term1`:
   * Main functions:
      * `n2c()`: normal to canonic, retrieves de canonic term from a valid term of a namespace. See b1.
      * `n2ns()`: normal to normals, retrieves de all synonyms of a valid term (of a namespace). See b1.
      * `search_tab()`: search by terms with specified option, returning nearst (similar) terms. See b2.
      * `search2c()`: as `search_tab()` but reducing to only corresponding canonical terms. See b2.
      * `find()`: complete algorithm to "best search choice"...
      * `find2c()`: ...
   * Utilities:
      * `term1.basemask()` see b1.
      * `nsget_nsopt2int()` see b2.
* `term_lib`, main functions: 
   * `term_lib.normalizeterm()`: see b1. 
   * `term_lib.score()`: see b1.
   * `term_lib.score_pairs()`: see b1.

## NOTES

* [Using metaphone as lexeme](http://stackoverflow.com/questions/4001579/postgresql-full-text-search-randomly-dropping-lexemes).

* PostreSQL guide,
  * [Text search dictionaries](http://www.postgresql.org/docs/9.1/static/textsearch-dictionaries.html#TEXTSEARCH-THESAURUS)
  * [runtime-config-client](http://www.postgresql.org/docs/current/static/runtime-config-client.html#GUC-DEFAULT-TEXT-SEARCH-CONFIG)

* Testing dataset: [Wayta site](http://wayta.scielo.org/) and [Wayta dataset](https://github.com/scieloorg/wayta).

### Context and concepts

* ... [Controlled terminologies](https://www.wikidata.org/wiki/Q1469824) ... [Named-entity recognition](https://en.wikipedia.org/wiki/Named-entity_recognition), ...  URNs, URN-resolution (ex. [ISSN-L resolution](https://github.com/okfn-brasil/ISSN-L-Resolver)) and operators N2C, N2Ns, etc.

* ... lexemes ...  this project is illustring use of [português brasileiro](https://www.wikidata.org/wiki/Q750553)... 

* XML and precise markup of terms: terms into [JATS](https://en.wikipedia.org/wiki/Journal_Article_Tag_Suite), [AKN](http://www.akomantoso.org/) or [LexML](http://projeto.lexml.gov.br/documentacao/Parte-3-XML-Schema.pdf) documents... Each document must use a public standard ID, as  [DOI](https://www.wikidata.org/wiki/Q25670) or [URN Lex](https://en.wikipedia.org/wiki/Lex_(URN)).

* [MADLib filosofy](http://doc.madlib.net/latest/), an "open-source library for scalable in-database analytics", as we need here. See also simple lib examples at [pgxn.org](http://pgxn.org/).

### Future implementations

The automatic choice of language needs "dynamic *tsquery*" and in-loop change of *regconfig*, so, some caching or some fast ID2regconfig convertion.


