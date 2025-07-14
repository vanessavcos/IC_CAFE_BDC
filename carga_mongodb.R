setwd("C:\\Users\\dudud\\Desktop\\IC")
library(rstac)
library(sf)
library(mongolite)
library(terra)
library(tictoc)
source("helperSTAC.R")


stac_obj <- stac("https://data.inpe.br/bdc/stac/v1/")

#Recuperando os itens
items <- stac_obj %>%
  collections("S2-16D-2") %>%
  items(datetime = "2017-01-17/2017-01-20",
        bbox  = c(-45.6444, -21.4409, -45.4755, -21.3233),
        limit = 10000) %>%
  get_request()
items_datetime(items)
items_assets(items)
print(items)

#Resgatando os urls das bandas
red_url  <- assets_url(items, asset_names = "B04", append_gdalvsi = TRUE)
green_url  <- assets_url(items, asset_names = "B03", append_gdalvsi = TRUE)
nir_url  <- assets_url(items, asset_names = "B08", append_gdalvsi = TRUE)
ndvi_url  <- assets_url(items, asset_names = "NDVI", append_gdalvsi = TRUE)

# Cria os raster a partir das URLs
red_rast <- terra::rast(red_url)
nir_rast <- terra::rast(nir_url)
green_rast <- terra::rast(green_url)
ndvi_rast <- terra::rast(ndvi_url)

myshp <- read_sf(dsn="shapefile/tresPontas.shp", layer="tresPontas")
shp_extension <- terra::ext(myshp)
crs_rast <- sf::st_crs(ndvi_rast)
shp_transformed <- sf::st_transform(myshp, crs = crs_rast)
cityname <- myshp$nome[1]

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
masked_pixel_count <- sum(!is.na(values(red_masked)))
# Inicializa a conexão com o banco de dados
collection <- mongo(
  db = "geo",
  collection = "serie",
  url = "mongodb://localhost:27017"
)

# Obtém as coordenadas dos pontos
allcoords <- terra::crds(bands_tosave$nir, df = TRUE, na.rm = FALSE)
rows <- dim(bands_tosave$red)[1]
columns <- dim(bands_tosave$red)[2]
dates <- length(items_datetime(items))  

total <- rows * columns
pixels_validos <- which(!is.na(values(bands_tosave$nir[[1]])))

# Lista para armazenar tempos de inserção
latencias_insercao <- c()

for (d in 1:dates) {
  # print(paste0("d = ", d))
  print(items_datetime(items)[[d]])
  for (n in seq(1, rows * columns, by = 500)) { # para cada pixel n
    # Inicializa o dataframe com um placeholder para poder inserir novos dados
    # É necessário que haja alguma linha no dataframe para poder inserir novos
    # dados, e colocar um valor de NA não irá fazer diferença na inserção no
    # banco pois ele não será considerado durante o parse para json
    #
    
    if(n %% 10000 == 0){
      print(paste(n/10000, "of", total))
    }
    px_tosave <- data.frame(
      "placeholder" = NA
    )
    for (b in seq_along(bands_tosave)) {
      has_any_value <- FALSE
      valor_pixel <- bands_tosave[[b]][[d]][n][[1]]
      print(valor_pixel)
      
      if (!is.na(valor_pixel)) {
        px_tosave[[names(bands_tosave)[b]]] <- valor_pixel
        has_any_value <- TRUE
      }
    }

    
    if (has_any_value) {
      px_tosave$metadata <- data.frame("placeholder" = NA)
      px_tosave$metadata$location <- data.frame("type" = "Point")
      
      coordstext <- jsonlite::toJSON(
        c(allcoords[n, 1], allcoords[n, 2]),
        digits = NA,
        auto_unbox = TRUE
      )
      
      px_json <- jsonlite::toJSON(px_tosave)
      px_json <- paste0(
        '{"timestamp": {"$date": "',
        format(as.POSIXct(items_datetime(items)[[d]], tz = "UTC"), "%Y-%m-%dT%H:%M:%OS3Z"),
        '"},',
        substring(px_json, 3, nchar(px_json) - 4),
        ', "coordinates": ',
        coordstext,
        "}}}"
      )
      
      tic()
      collection$insert(data = px_json)
      latencia <- toc(quiet = TRUE)
      latencias_insercao <- c(latencias_insercao, latencia$toc - latencia$tic)
    }
  }
}

# Cálculo da latência média
latencia_media <- mean(latencias_insercao, na.rm = TRUE)
cat("\n✅ Latência média de inserção:", latencia_media, "segundos\n")