setwd("C:\\Users\\dudud\\Desktop\\IC")
library(magrittr)
library(rstac)
library(terra)
library(sf)
library(tictoc)
library(influxdbclient)
library(s2)  

stac_obj <- stac("https://data.inpe.br/bdc/stac/v1/")
collections <- stac_obj %>%
  collections() %>%
  get_request()

print(collections, n = 31)


#Recuperando os itens
items <- stac_obj %>%
  collections("S2-16D-2") %>%
  items(datetime = "2017-01-17/2017-01-31",
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
#evi_url  <- assets_url(items, asset_names = "EVI", append_gdalvsi = TRUE)

red_rast <- terra::rast(red_url)
nir_rast <- terra::rast(nir_url)
green_rast <- terra::rast(green_url)
ndvi_rast <- terra::rast(ndvi_url)


# Carrega o shapefile
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
bands_tosave$red <- project(red_masked, "EPSG:4326", method = "near")
bands_tosave$nir <- project(nir_masked, "EPSG:4326", method = "near")
bands_tosave$green <- project(green_masked, "EPSG:4326", method = "near")
bands_tosave$ndvi <- project(ndvi_masked, "EPSG:4326", method = "near")


# Obtém as coordenadas dos pontos
allcoords <- terra::crds(bands_tosave$nir, df = TRUE, na.rm = FALSE)
rows <- dim(bands_tosave$red)[1]
columns <- dim(bands_tosave$red)[2]
dates <- length(items_datetime(items))  #### É NESSA PARTE QUE MUDAAA
total <- rows * columns

#Conexão com o influxDB
token = "0wpBV0X-w5NeJdrbJOp60Ur90oEokhGDw87zAOGUasamF2MWa1OQWU3rEkksWPBtlsusmDdkCjeZ3IBFLee9hw=="
org = "meu-org"
bucket = "sbbd"
client <- InfluxDBClient$new(url = "http://localhost:8086",
                             token = token,
                             org = org)
pixels_validos <- which(!is.na(values(bands_tosave$nir[[1]])))
latencias_insercao <- c()
registro_total <- 0
  
for (d in 1:(dates)) { # Para cada camada temporal
  print(items_datetime(items)[[d]])  # Debug para ver a data atual
  
  for (n in seq(1, rows * columns, by = 500)) { # Para cada pixel n
    
    if (n %% 10000 == 0) {
      print(paste(n / 10000, "of", total))
    }
    
    has_any_value <- FALSE
    values <- list()
    
    # Para cada banda espectral
    for (b in seq_along(bands_tosave)) {
      
      # Extrai o valor do pixel da banda na camada d
      valor_pixel <- bands_tosave[[b]][[d]][n][[1]]
      
      if (!is.na(valor_pixel)) {
        values[[names(bands_tosave)[b]]] <- valor_pixel  # Adiciona ao dicionário de valores
        has_any_value <- TRUE
      }
    }
    
    # Só salva no banco se houver pelo menos um valor válido
    if (has_any_value) {
      
      # Extrai as coordenadas do pixel apenas agora
      lon <- allcoords[n, 1]
      lat <- allcoords[n, 2]
      
      # Gera o S2 Cell ID
      s2_cell <- as.character(as_s2_cell(s2_lnglat(lon, lat)))
      
      # Converte o tempo para formato POSIXct
      date_posixct <- as.POSIXct(items_datetime(items)[[d]], format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC")
      
      # Criação do DataFrame com S2 Cell ID e bandas espectrais como campos
      data <- data.frame(
        name = "carga1",   # Measurement
        s2_cell_id = s2_cell,  # Tag (S2 Cell ID)
        time = date_posixct,  # Timestamp
        lon = lon,   # Campo Longitude
        lat = lat,   # Campo Latitude
        do.call(cbind, values)  # Adiciona bandas como campos
      )
      
      # Medir tempo de escrita no banco
      tic()
      
      # Escreve no banco InfluxDB
      client$write(
        data,
        bucket = "carga",
        precision = "ms",  # Precisão em milissegundos
        measurementCol = "name",
        tagCols = c("s2_cell_id"),  # Agora a tag é o S2 Cell ID
        fieldCols = c("lon", "lat", names(values)),  # Campos incluem lat/lon + bandas espectrais
        timeCol = "time"
      )
      
      # Para o cronômetro e armazena o tempo de inserção
      latencia <- toc(quiet = TRUE)
      latencias_insercao <- c(latencias_insercao, latencia$toc - latencia$tic)
    }
  }
}
print(paste("Total de registros escritos:", registro_total))
latencia_media <- mean(latencias_insercao, na.rm = TRUE)
desvio_padrao <- sd(latencias_insercao, na.rm = TRUE)
cat("📊 Desvio padrão da latência:", desvio_padrao, "segundos\n")
cat("\n✅ Latência média de inserção:", latencia_media, "segundos\n")