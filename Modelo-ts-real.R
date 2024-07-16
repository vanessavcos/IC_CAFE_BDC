gitsetwd("C:\\Users\\dudud\\OneDrive\\Área de Trabalho\\IC\\R Scripts\\STAC")
library(rstac)
library(sf)
library(mongolite)
library(terra)
library(tictoc)
source("helperSTAC.R")

# Inicializa a aplicação STAC
stac_app <- closureSTAC("VlNY62maqgBK60Li0Rah9AnPLsPwz6DW5iPITgyMx3")
items <- stac_app$getInterval(start_date = "2022-01-01", end_date = "2022-12-31")
#items_filtered <- stac_app$filterDate(item_list = items, date <- "2022-06-10")
items_datetime(items)

# Obtém as URLs das bandas desejadas
red_url <- stac_app$getBandUrl(items, "B04")
nir_url <- stac_app$getBandUrl(items, "B08")
green_url <- stac_app$getBandUrl(items, "B03")
ndvi_url <- stac_app$getBandUrl(items, "NDVI")

# Cria os raster a partir das URLs
red_rast <- terra::rast(red_url)
nir_rast <- terra::rast(nir_url)
green_rast <- terra::rast(green_url)
ndvi_rast <- terra::rast(ndvi_url)

# Abre o shapefile
myshp <- read_sf(dsn="shapefile/tresPontas.shp", layer="tresPontas")
shp_extension <- terra::ext(myshp)
crs_rast <- sf::st_crs(ndvi_rast)
shp_transformed <- sf::st_transform(myshp, crs = crs_rast)

# Corta os rasters pela extensão do shapefile
red_cropped <- terra::crop(red_rast, shp_transformed)
nir_cropped <- terra::crop(nir_rast, shp_transformed)
green_cropped <- terra::crop(green_rast, shp_transformed)
ndvi_cropped <- terra::crop(ndvi_rast, shp_transformed)

# Aplica a máscara aos rasters usando o shapefile
red_masked <- terra::mask(red_cropped, shp_transformed)
nir_masked <- terra::mask(nir_cropped, shp_transformed)
green_masked <- terra::mask(green_cropped, shp_transformed)
ndvi_masked <- terra::mask(ndvi_cropped, shp_transformed)

# Reprojeta os rasters para latitude e longitude
bands_tosave <- list()
bands_tosave$red <- project(red_masked, "+proj=longlat", method = "near")
bands_tosave$nir <- project(nir_masked, "+proj=longlat", method = "near")
bands_tosave$green <- project(green_masked, "+proj=longlat", method = "near")
bands_tosave$ndvi <- project(ndvi_masked, "+proj=longlat", method = "near")

# Inicializa a conexão com o banco de dados
collection <- mongo(
  db = "projetoCafe-dev",
  collection = "ts",
  url = "mongodb://localhost:27017"
)

# Obtém as coordenadas dos pontos
allcoords <- terra::crds(bands_tosave$nir, df = TRUE, na.rm = FALSE)
rows <- dim(bands_tosave$red)[1]
columns <- dim(bands_tosave$red)[2]
dates <- length(items_datetime(items))  #### É NESSA PARTE QUE MUDAAA

total <- rows * columns

for (d in 1:(dates)) { # para cada camada
  # print(paste0("d = ", d))
  print(items_datetime(items)[[d]])
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
    for (b in seq_along(bands_tosave)) { # para cada banda a salvar
      # pega os valores dessas bandas e coloca no dataframe
      has_any_value <- FALSE
      # Parte lenta
      valor_pixel <- bands_tosave[[b]][[d]][n][[1]]
      print(valor_pixel)
      if (!is.na(valor_pixel)) {
        px_tosave[[names(bands_tosave)[b]]] <- valor_pixel
        has_any_value <- TRUE
      }
    }
    
    
    
    # Se não houver nenhum dado das bandas desejadas então nem salva no banco #nolint
    if (has_any_value) {
      # O metadado tem que ser adicionado depois da criação do dataframe senão ele será "achatado" (ao invés de metadata: {x, y} ficará metadata.x e metadata.y) #nolint
      px_tosave$metadata <- data.frame(
        "placeholder" = NA
      )
      px_tosave$metadata$location <- data.frame(
        "type" = "Point"
      )
      coordstext <- jsonlite::toJSON(
        c(allcoords[n, 1], allcoords[n, 2])
      )
      
      # O timestamp deve ser colocado como string porque ele deve ser do tipo específico de data, porém esse tipo não é considerado na conversão de dataframe para json #nolint
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