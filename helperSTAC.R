#install.packages("rstac") # nolint
#install.packages(c("magrittr", "tibble", "dplyr", "raster"), dependencies = FALSE) # nolint

library(rstac)    # package rstac
library(terra)    # package to manipulate rasters
library(magrittr) # Package to use pipe operator %>%


# Esse arquivo de utilidades funciona com a idea de closures.
# No programa principal, faça "variavel = closureSTAC("sua_bdc_api_key")
# Em seguida utilize as funções com variavel$funcao(param)
# Exemplo:
# ```
# stacApp = closureSTAC("key") # nolint
# items = stacApp$getInterval(startDate = "2022-01-01", endDate = "2022-12-31") # nolint
# ```
closureSTAC <- function(api_key) { # nolint
  API_KEY <- api_key # nolint

  # Recebe duas strings no formato AAAA-MM-DD
  # Também pode receber um limite de quantos dados retornar,
  # se não receber então ele deixa no default (12)
  #Retorna os objetos com as urls dos itens
  GETINTERVAL <- function(start_date, end_date, limit = NULL) { # nolint

    if (missing(start_date) || missing(end_date)) {
      warning("startDate or endDate missing")
      stop("startDate or endDate missing")
    }

    if (is.null(limit)) {
      print("Defaulting retrieve limit to 10000")
      retrieve_limit <- 10000
    } else {
      retrieve_limit <- limit
    }

    # Obtém os itens da coleção do sentinel
    # o local está travado para Três Pontas mas pode ser editado
    items <- stac("https://brazildatacube.dpi.inpe.br/stac/") %>%
      collections("S2-16D-2") %>%
      # Intervalo de tempo
      items(datetime = paste(start_date, end_date, sep = "/"),
            bbox  = c(-45.6444, -21.4409, -45.4755, -21.3233), # Limites no mapa
            limit = retrieve_limit)

    # realização da consulta, retorna objetos com as urls dos itens
    items <- get_request(items) %>% items_sign(sign_bdc(API_KEY))

    return(items)
  }


  # Função que recebe uma lista de itens e filtra para apenas uma data
  # Recebe a lista de itens e a data desejada
  FILTERDATE <- function(item_list, date) { # nolint: object_name_linter.
    concat_filter <- paste(date, "T00:00:00", sep = "")

    filtered_items <- items_filter(
      items = item_list,
      filter_fn = function(item) item$properties[["datetime"]] == concat_filter
    )

    return(filtered_items)
  }

  # Função para retornar apenas uma banda
  # @param items: STACItemCollection
  # @param bandName: string
  # retorna a url da banda selecionada
  GETBANDURL <- function( # nolint: object_name_linter.
    items,
    band_name
  ) {
    if (band_name %in% items_assets(items)) {
      band_url <- assets_url(items, asset_names = band_name, append_gdalvsi = TRUE) # nolint
      return(band_url)
    } else {
      message = paste("Band name ", band_name, " does not exist in item collection") # nolint
      warning(message)
    }
  }

  # Função para cortar os assets usando latitude e longitude
  # É possível selecionar a projeção desejada, mas não é necessário
  # se ela não for passada vai para o padrão que funciona com o sentinel-2
  GETPROJECTEDBBOX <- function( # nolint: object_name_linter.
    min_lat,
    min_lng,
    max_lat,
    max_lng,
    proj_orig_overwrite = NULL,
    proj_dest_overwrite = NULL
  ) {
    if (is.null(proj_orig_overwrite)) {
      proj_orig <- sf::st_crs("+proj=longlat +datum=WGS84")
    } else {
      proj_orig <- sf::st_crs(proj_orig_overwrite)
    }
    ?sf::st_crs
    ?terra::ext

    if (is.null(proj_dest_overwrite)) {
      proj_dest <- sf::st_crs(
        "+proj=aea +lat_0=-12 +lon_0=-54 +lat_1=-2 +lat_2=-22 +x_0=5000000 +y_0=10000000 +ellps=GRS80 +units=m +no_defs") # nolint
    } else {
      proj_dest <- sf::st_crs(proj_dest_overwrite)
    }

    pts <- tibble::tibble(
      lon = c(min_lng, max_lng),
      lat = c(min_lat, max_lat)
    )
    pts_sf <- sf::st_as_sf(pts, coords = c("lon", "lat"), crs = proj_orig)
    pts_transf <- sf::st_transform(pts_sf, crs = proj_dest)

    lat_dest <- sf::st_coordinates(pts_transf)[, 2]
    lon_dest <- sf::st_coordinates(pts_transf)[, 1]
    print(lat_dest[1])
    print(lat_dest[2])

    # Define a bounding box para a região
    # long_min, long_max, lat_min, lat_max
    transformed_bbox <- terra::ext(lon_dest[1] , lon_dest[2] , lat_dest[1] , lat_dest[2]) # nolint

    return(transformed_bbox)
  }


  return(list(
    getInterval = GETINTERVAL,
    filterDate = FILTERDATE,
    getBandUrl = GETBANDURL,
    getProjectedBbox = GETPROJECTEDBBOX
  ))
}