setwd("C:\\Users\\dudud\\OneDrive\\Área de Trabalho\\IC\\R Scripts\\STAC") # nolint
library(rstac)      # biblioteca para o stac
library(sf)         # biblioteca para tratar o shapefile
library(mongolite)  # biblioteca para o mongodb
library(terra)      # biblioteca para o processamento raster
library(tictoc)     # biblioteca para medir o tempo de execução
source("helperSTAC.R")

print("Iniciando script...")

stac_app <- closureSTAC("VlNY62maqgBK60Li0Rah9AnPLsPwz6DW5iPITgyMx3")
items <- stac_app$getInterval(start_date = "2022-01-01", end_date = "2022-12-31")
print("Itens obtidos do STAC:")
items_datetime(items)
#items_filtered <- stac_app$filterDate(item_list = items, date <- "2022-06-10")
#print("Itens filtrados para a data específica:")

red_url <- stac_app$getBandUrl(items, "B04")
nir_url <- stac_app$getBandUrl(items, "B08")
green_url <- stac_app$getBandUrl(items, "B03")
ndvi_url <- stac_app$getBandUrl(items, "NDVI")

red_rast <- terra::rast(red_url)
nir_rast <- terra::rast(nir_url)
green_rast <- terra::rast(green_url)
ndvi_rast <- terra::rast(ndvi_url)

# Verificar as dimensões
print("Dimensões dos rasters:")
print(dim(red_rast))
print(dim(nir_rast))
print(dim(green_rast))
print(dim(ndvi_rast))

myshp <- read_sf(dsn="shapefile/tresPontas.shp", layer="tresPontas")
shp_extension <- terra::ext(myshp)

crs_rast <- sf::st_crs(ndvi_rast)
shp_transformed <- sf::st_transform(myshp, crs = crs_rast)

red_cropped <- terra::crop(red_rast, shp_transformed)
nir_cropped <- terra::crop(nir_rast, shp_transformed)
green_cropped <- terra::crop(green_rast, shp_transformed)
ndvi_cropped <- terra::crop(ndvi_rast, shp_transformed)

red_masked <- terra::mask(red_cropped, shp_transformed)
nir_masked <- terra::mask(nir_cropped, shp_transformed)
green_masked <- terra::mask(green_cropped, shp_transformed)
ndvi_masked <- terra::mask(ndvi_cropped, shp_transformed)

bands_tosave <- list(
  red = project(red_masked, "+proj=longlat", method = "near"),
  nir = project(nir_masked, "+proj=longlat", method = "near"),
  green = project(green_masked, "+proj=longlat", method = "near"),
  ndvi = project(ndvi_masked, "+proj=longlat", method = "near")
)


# Loop para imprimir cada elemento da lista bands_tosave
for (band_name in names(bands_tosave)) {
  cat("\nConteúdo da banda:", band_name, "\n")
  print(bands_tosave[[band_name]])
}


collection <- mongo(
  db = "projetoCafe-dev",
  collection = "modelagem-normal",
  url = "mongodb://localhost:27017"
)

allcoords <- terra::crds(bands_tosave$nir, df = TRUE, na.rm = FALSE)

rows <- dim(bands_tosave$red)[1]
columns <- dim(bands_tosave$red)[2]
dates <- length(items_datetime(items))

total <- (rows * columns)

print(paste("Total de pixels:", total))
print(paste("Total de datas:", dates))

# Loop para cada pixel
for (n in 1:(total)) {
  
  for (n in (1:(total / 10000) * 10000)) {
    tic()
    if(n %% 10000 == 0){
      print(paste(n/10000, "of", total))
    }
    
    
    # Inicializa o DataFrame para armazenar todas as datas
    px_tosave <- list()
    has_any_value <- FALSE
    
    # Loop para cada camada (data)
    for (d in 1:dates) {
      date_str <- items_datetime(items)[[d]]
      date_band_values <- list()
      print(items_datetime(items)[[d]])
      
      # Loop para cada banda
      for (b in seq_along(bands_tosave)) {
        band_name <- names(bands_tosave)[b]
        valor_pixel <- bands_tosave[[b]][[d]][n][[1]]
        print(valor_pixel)
        if (!is.na(valor_pixel)) {
          date_band_values[[band_name]] <- valor_pixel
          has_any_value <- TRUE
        }
      }
      
      if (has_any_value) {
        px_tosave[[date_str]] <- date_band_values
      }
    }
    
    # Se não houver nenhum dado das bandas desejadas, não salva no banco
 
      if (has_any_value) {
        # Adiciona metadados à lista
        px_tosave$metadata <- list(
          location = list(
            type = "Point",
            coordinates = c(allcoords[n, 1], allcoords[n, 2])
          )
        )
        
        # Converte a lista para JSON
        px_json <- jsonlite::toJSON(px_tosave, auto_unbox = TRUE)
        
      
      # Insere no MongoDB
      collection$insert(data = px_json)
    }
    
    toc()
  }
}