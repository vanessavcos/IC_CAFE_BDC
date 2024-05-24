# Notebook original: https://www.kaggle.com/code/marcelorobertsantos/introducao-stac/edit

#install.packages("rstac")
#install.packages(c("magrittr", "tibble", "dplyr", "raster"), dependencies = FALSE)

source(.env)
library(rstac)    # package rstac
library(terra)    # package to manipulate rasters
library(magrittr) # Package to use pipe operator %>%

setwd(CUR_WD)
access_token <- API_KEY # API token do BDC


# Obtém o objeto do BDC
stac_obj <- stac("https://brazildatacube.dpi.inpe.br/stac/")

# Obtém a lista de coleções do objeto do BDC
collections <- stac_obj %>%
  collections() %>%
  get_request()

print(collections, n = 35)


# Informação da coleção do sentinel
collection_info <- stac_obj %>% 
  collections("S2-16D-2") %>% 
  get_request()

print(collection_info)


# Obtém os itens da coleção do sentinel
items <- stac_obj %>% 
  collections("S2-16D-2") %>% 
  items(datetime = "2022-01-01/2022-12-31",             # Intervalo de tempo
        bbox  = c(-45.6444,-21.4409,-45.4755,-21.3233), # Limites no mapa
        limit = 24)

# realização da consulta, retorna objetos com as urls dos itens
items <- get_request(items) %>% items_sign(sign_bdc(access_token))

print(items)


# Quais assets (bandas) há nos itens
items_assets(items)

# Quais são as urls desses assets, retorna um url para cada asset para cada item (data)
assets_url(items, asset_names = c("B04", "B08"))



# Exibe as datas dos itens retornados
items_datetime(items)

# É possível filtrar por uma data específica dessas que foram trazidas
item_filtered <- items_filter(items, filter_fn = function(item) item$properties[["datetime"]] == "2022-06-10T00:00:00")


# Separa a URL de cada banda
red_url   <- assets_url(item_filtered, asset_names = "B12", append_gdalvsi = TRUE)
green_url <- assets_url(item_filtered, asset_names = "B8A", append_gdalvsi = TRUE)
blue_url  <- assets_url(item_filtered, asset_names = "B04", append_gdalvsi = TRUE)


# Lê a imagem de cada url
red_rast   <- terra::rast(red_url)
green_rast <- terra::rast(green_url)
blue_rast  <- terra::rast(blue_url)

saveRDS(red_rast, file = "red_rast.rds")
load(file = "red_rast.rds")
plot(red_rast)

# Reprojeta a latitude e longitude para o formato necessário
proj_orig <- sf::st_crs("+proj=longlat +datum=WGS84")
#BDC proj4 string
proj_dest <- sf::st_crs("+proj=aea +lat_0=-12 +lon_0=-54 +lat_1=-2 +lat_2=-22 +x_0=5000000 +y_0=10000000 +ellps=GRS80 +units=m +no_defs")

pts <- tibble::tibble(
  lon = c(-45.6444, -45.4755),
  lat = c(-21.4409, -21.3233)
)
pts_sf <- sf::st_as_sf(pts, coords = c("lon", "lat"), crs = proj_orig)
pts_transf <- sf::st_transform(pts_sf, crs = proj_dest)

lat_dest <- sf::st_coordinates(pts_transf)[, 2]
lon_dest <- sf::st_coordinates(pts_transf)[, 1]

cat("Reprojected longitude:", lon_dest, "\nReprojected latitude:", lat_dest)


# Define a bounding box para a região
# long_min, long_max, lat_min, lat_max
transformed_bbox <- terra::ext(5864539 , 5882407 , 8930871 , 8943383)


# Corta as imagens
red_rast_cropped   <- terra::crop(red_rast, transformed_bbox)
green_rast_cropped <- terra::crop(green_rast, transformed_bbox)
blue_rast_cropped  <- terra::crop(blue_rast, transformed_bbox)


# Plota as bandas cortadas
options(repr.plot.width = 16, repr.plot.height = 5)
par(mfrow = c(1, 3))

plot(red_rast_cropped,   main = "Red Band")
plot(green_rast_cropped, main = "Green Band")
plot(blue_rast_cropped,  main = "Blue Band")


# Plotagem única com a composição rgb
rgb <- c(red_rast_cropped, green_rast_cropped, blue_rast_cropped)
plotRGB(rgb, r = 1, g = 2, b = 3, stretch="lin")



# Cálculo de índices
red <- assets_url(item_filtered, asset_names = "B04", append_gdalvsi = TRUE)
nir <- assets_url(item_filtered, asset_names = "B8A", append_gdalvsi = TRUE)

red_rast <- terra::crop(terra::rast(red), transformed_bbox)
red_rast

nir_rast <- terra::crop(terra::rast(nir), transformed_bbox)
nir_rast

ndvi <- (nir_rast - red_rast) / (nir_rast + red_rast)
ndvi

plot(ndvi)



# Image thresholding