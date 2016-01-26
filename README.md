# base-terminologia-controlada
Base de dados contendo terminologia controlada e material de apoio.

Terminologias controladas podem ter origem em normas, em tesauros, glossários, vocabulários ou ontologias. No presente projeto os termos podem ter também a sua origem e controle em um [corpus linguístico textual](https://en.wikipedia.org/wiki/Corpus_linguistics).

É suposto o uso de documentos XML marcados em padrões [JATS](https://en.wikipedia.org/wiki/Journal_Article_Tag_Suite), [AKN](http://www.akomantoso.org/) ou [LexML](http://projeto.lexml.gov.br/documentacao/Parte-3-XML-Schema.pdf), e identificados pelos padrões [DOI](https://en.wikipedia.org/wiki/Digital_object_identifier) ou [URN Lex](https://en.wikipedia.org/wiki/Lex_(URN)).

A ortografia de um  texto de um desses documentos, escrito em [português brasileiro](https://www.wikidata.org/wiki/Q750553),  requer os seguintes controles:

* *vocabulário ordinário*: [VOLP](http://www.academia.org.br/nossa-lingua/busca-no-vocabulario), palavras simples e algumas palavras compostas, contexto fixado por análise linguística (substantivo, verbo, preposição, etc.). 

* *vocabulário técnico*: ver dicionário de jargão complementando o VOLP. Contexto fixado por área científica e compromisso rigor/informalidade do documento. Uso de expressões não-textuais tais como equações e variáveis, bem como o uso de códigos e abreviações, também recaem nesse "vocabulário".

* [*entidades nomeadas*](https://en.wikipedia.org/wiki/Named-entity_recognition): contemplados pelo escopo do presente projeto.

  * *[Anáforas](https://www.wikidata.org/wiki/Q156751), links e citações* às entidades nomeadas também podem ser controlados, dentro do mesmo esquema de contextualização. O reconhecimento de padrões através de regular expressions e verificação de ocorrências na vizinhança, é a abordagem mais simples para marcação automática desse tipo de ocorrência.

* outros termos controlados: também contemplados pelo escopo do presente projeto. Sinônimos, suspeitas e grafia equivocada podem ser tratados.

## Objetivo ##
Infra-estrutura SQL PostgreSQL v9+ para a manter contextos, termos controlados e seus sinônimos localiados no corpus. As funcionalidades da base permitem tanto o marcação em contexto como a recuperação dos termos de um contexto.







