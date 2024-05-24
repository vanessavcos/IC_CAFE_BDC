# Bibliotecas locais
source(".env")
setwd(CUR_WD)
source("helperSTAC.R")

library(rstac)      # biblioteca para o stac
library(sf)         # biblioteca para tratar o shapefile
library(mongolite)  # biblioteca para o mongodb
# A chave API será passada pelo usuário ou será utilizada uma chave qualquer?
# No momento ela está aqui como se fosse informada pelo usuário
#
stac_app <- closureSTAC(API_KEY)
items <- stac_app$getInterval(start_date = "2022-01-01", end_date = "2022-12-31") # nolint

# debug, comandos para ver os nomes, bbox e datas dos itens
#
#names(items) # nolint
#items_bbox(items) # nolint
#items_datetime(items) # nolint

# Filtra os itens para uma data específica
# Seria possível filtrar também para a última data usando a função anterior
items_filtered <- stac_app$filterDate(item_list = items, date <- "2022-06-10")
items_filtered
# Recebe a url da banda desejada
red_url <- stac_app$getBandUrl(items_filtered, "B04")
nir_url <- stac_app$getBandUrl(items_filtered, "B08")
green_url <- stac_app$getBandUrl(items_filtered, "B03")
ndvi_url <- stac_app$getBandUrl(items_filtered, "NDVI")

# Cria o raster/imagem/asset a partir da url

red_rast <- terra::rast(red_url)
nir_rast <- terra::rast(nir_url)
green_rast <- terra::rast(green_url)
ndvi_rast <- terra::rast(ndvi_url)

# Criando uma bbox a partir de coordenadas
# Isso não é necessário já que será feita uma
# reprojeção por conta do shapefile
#
#transformed_bbox <- stacApp$getProjectedBbox(-21.4409, -45.6444, -21.3233, -45.4755) # nolint
#transformed_bbox <- stac_app$getProjectedBbox(-21.4409, -45.6444, -21.4400, -45.6440) # nolint

# Open shapefile
myshp <- read_sf(dsn="shapefile/tresPontas.shp", layer="tresPontas") # nolint
shp_extension <- terra::ext(myshp) # obtém a extensão/bbox do shapefile

# CRS - Coordinate Reference System;
# Raster aqui é o asset, a imagem vinda do BDC
#
# Obtém o crs do raster
crs_rast <- sf::st_crs(red_rast)
# Reprojeta o shapefile para o crs do raster
shp_transformed <- sf::st_transform(myshp, crs = crs_rast)
# debug, observa a diferença de extensão entre o shapefile e o asset
#
#terra::ext(shp_transformed)
#terra::ext(red_rast)

# Corta os rasters pela extensão (praticamente bbox) do shapefile
# A partir daqui várias variáveis terão já sua memória liberada,
# sendo descartadas após serem usadas. Isso é feito principalmente
# para casos onde não é usada uma máscara ou há uma quantidade
# muito grande de bandas ou pixels, de forma que deve haver
# mais memória disponível
#
red_cropped <- terra::crop(red_rast, shp_transformed)
red_rast <- NULL
nir_cropped <- terra::crop(nir_rast, shp_transformed)
nir_rast <- NULL
green_cropped <- terra::crop(green_rast, shp_transformed)
green_rast <- NULL
ndvi_cropped <- terra::crop(ndvi_rast, shp_transformed)
ndvi_rast <- NULL

# Aplica a máscara aos rasters usando o shapefile
red_masked <- terra::mask(red_cropped, shp_transformed)
red_cropped <- NULL
nir_masked <- terra::mask(nir_cropped, shp_transformed)
nir_cropped <- NULL
green_masked <- terra::mask(green_cropped, shp_transformed)
green_cropped <- NULL
ndvi_masked <- terra::mask(ndvi_cropped, shp_transformed)
ndvi_cropped <- NULL

# Reprojeta os rasters para latitude e longitude para realizar o armazenamento
######### Existe uma pequena modificação dos dados, além de que
# existe uma distorção na imagem por conta da projeção original
#
# Essas variáveis são as que serão usadas para guardar os dados,
# sendo assim, elas já serão guardadas em uma lista para uma
# iteração mais fácil
#
bands_tosave <- list()
bands_tosave$red <- project(red_masked, "+proj=longlat", method = "near")
red_masked <- NULL
bands_tosave$nir <- project(nir_masked, "+proj=longlat", method = "near")
nir_masked <- NULL
bands_tosave$green <- project(green_masked, "+proj=longlat", method = "near")
green_masked <- NULL
bands_tosave$ndvi <- project(ndvi_masked, "+proj=longlat", method = "near")
ndvi_masked <- NULL

# # debug, salvando as bandas finais em formato png
#
# png("plot_ndvi_project.png",
#   width = 480 * 2,
#   height = 300 * 2
# )
# plot(bands_tosave$ndvi,
#   col = gray.colors(10000, start = 1, end = 0)
# )
# dev.off()

# Cálculo dos índices, o nome também deve ser final
## Chlorophyte index green = (NIR / Green) - 1
# bands_tosave$cig <- (bands_tosave$nir / 10000) /
#   (bands_tosave$green / 10000) - 1

# Inicializa a conexão com o banco de dados para salvar
collection <- mongo(
  db = "projetoCafe-dev",
  collection = "all",
  url = "mongodb://localhost:27017"
)

# Comando para pegar as coordenadas do ponto. Os pontos estão na projeção
# passada até aqui, isto é, como a shapefile foi convertido para
# a projeção original do asset então a máscara e o índice calculado
# também estão nessa projeção original
#
allcoords <- terra::crds(bands_tosave$ndvi, df = TRUE, na.rm = FALSE)

# O número de linhas e colunas deve ser o mesmo entre bandas
# assim como o número de datas
rows <- dim(bands_tosave$red)[1]
columns <- dim(bands_tosave$red)[2]
dates <- dim(bands_tosave$red)[3]

# biblioteca para medir o tempo de execução
library(tictoc)

# # Raster com todas as bandas
# bands_tosave
# # Raster com a primeira banda, todas as datas e todos os pixels
# bands_tosave[[1]]
# # Raster com a primeira banda, primeira data e todos os pixels
# bands_tosave[[1]][[1]]
# # Lista da primeira banda com a primeira data e o valor do pixel n
# bands_tosave[[1]][[1]][n]
# # Valor da lista do pixel n da primeira data na primeira banda
# bands_tosave[[1]][[1]][n][[1]]
total <- (rows * columns / 10000)

for (d in 1:(dates)) { # para cada camada
  for (n in (1:(rows * columns / 10000) * 10000)) { # para cada pixel n
    # Inicializa o dataframe com um placeholder para poder inserir novos dados
    # É necessário que haja alguma linha no dataframe para poder inserir novos
    # dados, e colocar um valor de NA não irá fazer diferença na inserção no
    # banco pois ele não será considerado durante o parse para json
    #
    tic()
    if(n %% 10000 == 0){
      print(paste(n/10000, "of", total))
    }
    px_tosave <- data.frame(
      "placeholder" = NA
    )

    # pega os valores dessas bandas e coloca no dataframe
    has_any_value <- FALSE
    for (b in seq_along(bands_tosave)) { # para cada banda a salvar
      # Parte lenta
      valor_pixel <- bands_tosave[[b]][[d]][n][[1]]
      if (!is.na(valor_pixel)) {
        px_tosave[[names(bands_tosave)[b]]] <- valor_pixel
        has_any_value <- TRUE
      }
    }

    # Se não houver nenhum dado das bandas desejadas então nem salva no banco
    if (has_any_value) {
      # O metadado tem que ser adicionado depois da criação do dataframe senão ele será "achatado" (ao invés de metadata: {x, y} ficará metadata.x e metadata.y)
      px_tosave$metadata <- data.frame(
        "placeholder" = NA
      )
      px_tosave$metadata$location <- data.frame(
        "type" = "Point"
      )
      coordstext <- jsonlite::toJSON(
        c(allcoords[n, 1], allcoords[n, 2])
      )

      # O timestamp deve ser colocado como string porque ele deve ser do tipo específico de data, porém esse tipo não é considerado na conversão de dataframe para json
      px_json <- jsonlite::toJSON(px_tosave)

      px_json <- paste0(
        '{"timestamp": {"$date": "',
        items_datetime(items)[[d]],
        'Z"},',
        substring(px_json, 3, nchar(px_json) - 4),
        ', "coordinates": ',
        coordstext,
        "}}}"
      )
      collection$insert(data = px_json)
    }
    toc()
  }
}