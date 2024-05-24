# Extração de Séries Espaço-Temporais a partir de um Cubo de Dados Geoespacial em Benefício da Cafeicultura Mineira

Esse repositório contém os códigos parciais do Projeto Café para Todos escritos por Marcelo Robert Santos. O desenvolvimento foi feito utilizando R 4.3.1 no editor Visual Studio Code no sistema operacional Windows 11.

## Dependências

São necessárias duas variáveis externas (definidas num arquivo .env ou localmente no arquivo "mainSTAC.R"):

- ``CUR_WD``: Define o "*current working directory*", utilizado para poder acessar o arquivo auxiliar "helperSTAC.R" e também para definir o diretório padrão para salvar arquivos.

- ``API_KEY``: Define a chave de API do BDC (*Brazil Data Cube*), utilizada para acessar os dados através da biblioteca RSTAC.

Caso sejam inseridas no arquivo .env, essas variáveis devem ser definidas no formato ``VAR = "valor"``.

É necessária a inclusão do arquivo "helperSTAC.R", ele define uma **closure** para o acesso de funções mais comuns e para maior abstração no arquivo principal.

É necessário o shapefile de Três Pontas para a execução do programa na versão atual. **Caso seja desejado o trabalho em outra área, será preciso não só o shapefile, mas também primeiramente alterar a tile que é recebida do BDC**. O shapefile de Três Pontas foi providenciado para esse projeto por [Vanessa Souza](https://github.com/vanessavcos).

O programa realiza a conexão com um banco de dados MongoDB, é necessária a instalação do mesmo para as funções de armazenamento dos dados.

## Execução

Considerando que todas as dependências estão presentes, o arquivo ***mainStac.R*** pode ser executado sequencialmente. Uma breve explicação do código:

1. São obtidos os itens da coleção do Sentinel, nas datas desejadas e da tile desejada através da closureSTAC, que em si utiliza a biblioteca RSTAC.

2. Dos itens são retiradas as urls das bandas desejadas. Tanto os itens quanto as urls não são as imagens em si, mas referenciam à elas.

3. As urls são utilizadas como referência para criar os **rasters** (classe utilizada pela biblioteca **terra** para a manipulação dos dados). Esses rasters podem ser plotados como imagem utilizando a função plot().

4. O shapefile é aberto e obtida a extensão (que também pode ser chamada de bbox ou *bounding box*) para inicialmente realizar o recorte dos **assets** (que são as bandas, armazenadas como variáveis da classe raster) e em seguida realizar o mascaramento dos pixels dentro e fora da região desejada. O shapefile utilizado está em uma projeção diferente da projeção dos assets, portanto o shapefile deve ser reprojetado para ficar na mesma escala dos assets.

5. A variável ``bands_tosave`` é criada como uma lista contendo todas as bandas que serão salvas com seus devidos nomes. Dentro dela é armazenada diretamente o asset já reprojetado para exibir os dados de longitude e latitude crus, que são necessários para as consultas georreferenciadas no MongoDB.

6. Outros índices de vegetação podem ser calculados a partir das bandas já reprojetadas e armazenados diretamente na ``bands_tosave``.

7. É iniciada a conexão com o MongoDB e obtidas as variáveis de controle para realizar o laço em que serão processados os dados.

8. Dentro do laço é criada a variável que irá armazenar o documento para o armazenamento no MongoDB. Devido à restrições de nome, tipo e formato de dados tanto do R quanto do MongoDB, alguns placeholders são necessários para a criação dos dados e outros dados devem ser inseridos manualmente no json para inserção no banco de dados em formato de string.

Já no arquivo "helperSTAC.R", há apenas uma variável que atua como [closure](https://rstudio-education.github.io/hopr/environments.html#closures), contendo funções retiradas do [treinamento prodes 2023](https://www.kaggle.com/code/brazildatacube/treinamento-prodes-2023-stac-introduction).

PS.: O desenvolvimento no VSCode incluiu um linter automático para a linguagem R, porém alguns dos "*warnings*" são apenas recomendações e não erros, por isso existem alguns comentários ``#nolint`` que indicam à extensão para não considerar aquela linha de código.