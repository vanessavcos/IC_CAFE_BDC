# Testes para criar um dicionário
# não existem tuplas em json, então ele é salvo em um vetor mesmo

# Criação de uma lista/json
test_save <- list("foo" = "bar", "vector" = list(c("onep1", "onep2"), "two"))
print(test_save["vector"][[1]][1])
test_save

# Utilização da biblioteca para salvar e ler dados json
install.packages("rjson")
require("rjson")

# Salvar dados em arquivo json
json_data <- rjson::toJSON(test_save)
write(json_data, "output.json")

# Ler dados em arquivo json
retrieve <- rjson::fromJSON(file = "output.json")
retrieve

# Alterar ou adicionar dados na lista
retrieve["vector"][[1]][2] <- list(c("two1", "two2"))
retrieve

# Aumentar dados na lista
retrieve["vector"][[1]] <-
    append(retrieve["vector"][[1]], list(c("three1", "three2"))) # nolint
retrieve

retrieve["vector"][[1]][4] <- list(c("four1", "four2"))
retrieve

retrieve["vector"][[1]][6] <- list(c("six1", "six2"))
retrieve

# Apagar dados na lista
retrieve["vector"][[1]][7] <- NULL
json_data <- rjson::toJSON(retrieve)
write(json_data, "newoutput.json")
