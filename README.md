# Passo a Passo para Reproduzir o Trabalho

Este documento descreve como executar a carga de dados e realizar os testes de desempenho utilizando os scripts disponíveis neste repositório.

## Requisitos

- R instalado com bibliotecas para integração com InfluxDB e MongoDB
- Python 3.8 ou superior com Jupyter Notebook e bibliotecas necessárias
- MongoDB e InfluxDB instalados e em execução (por padrão, em localhost ou docker)

## Etapa 1: Carga Inicial de Dados

1. Abra os scripts `carga_influx.R` e `carga_mongodb.R`.

2. No interior de ambos os scripts, configure os seguintes itens:
   - Defina o intervalo completo da série temporal a ser carregada.
   - Utilize o shapefile localizado em `shapefile/tres_pontas.shp`.
   - Ajuste a conexão com o banco de dados, se necessário (padrão: localhost ou docker).
   - As collections (MongoDB) e measurements (InfluxDB) podem ser nomeadas conforme preferência.

3. Execute os dois scripts para carregar os dados nos bancos de dados.

## Etapa 2: Testes de Carga

### Carga Inicial

- Nos scripts `carga_influx.R` e `carga_mongodb.R`, defina apenas um dia da série temporal.
- Execute os scripts.
- As métricas de desempenho serão exibidas no console.

### Carga de Atualização

- Altere os scripts para carregar o dia seguinte ao utilizado na carga inicial.
- Execute novamente.
- As métricas atualizadas serão exibidas.

## Etapa 3: Teste de Consulta

1. Abra o arquivo `teste_detalhado.ipynb` no Jupyter Notebook.
2. Execute todas as células do notebook.
3. As métricas de consulta serão exibidas ao final da execução.

## Observações

- Verifique se os serviços do MongoDB e InfluxDB estão ativos antes de iniciar os testes.
- Caso utilize conexões diferentes de localhost, altere os parâmetros nos scripts de carga.
- Mantenha consistência nos nomes de collections e measurements entre as etapas de carga e consulta.

## Resultado Esperado

Ao final das etapas, serão geradas métricas relacionadas a:
- Carga inicial de dados
- Atualizações de dados
- Consultas realizadas

Essas métricas permitirão avaliar o desempenho dos bancos de dados utilizados com base nos dados de bandas espectrais e indices de vegetação do Brazil Data Cube na região de Três Pontas.
