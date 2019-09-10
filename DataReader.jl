using Serialization
import CSV, HTTP, JSON

function read_data()
    println("Lendo dados... ")

    if isfile("data.srl")
        println("data.srl encontrado!")
        data = deserialize("data.srl")
        return data['d'], data['n'], data['m']
    end

    file = CSV.file("data.csv")

    # le as coordenadas e transforma no formato aceito pelo OSRM
    coordinates = [join(reverse(split(row.coordinates, ',')), ',') for row in file]
    push!(coordinates, coordinates[1]) # a principio, inicio e fim das rotas são no deposito
    coordsString = join(coordinates, ';')

    # obtem a matriz de 'distancias' pelo osrm
    r = HTTP.get("http://router.project-osrm.org/table/v1/driving/$coordsString")
    responseBody = JSON.parse(String(r.body))
    durations = responseBody["durations"]

    # cria a matriz d
    n = length(durations) - 2 # numero de clientes
    m = 5 # numero de dias de trabalho
    d = Dict([(k, i, j)=> durations[i+1][j+1] for k in 1:m, i in 0:n+1, j in 0:n+1])

    data = Dict(['d' => d, 'n' => n, 'm' => m])

    serialize("data.srl", data)

    return d, n, m
end