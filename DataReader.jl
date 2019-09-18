using Serialization
import CSV, HTTP, JSON

function read_data(name)
    println("Lendo dados... ")

    if isfile("$name.srl")
        println("$name.srl encontrado!")
        data = deserialize("$name.srl")
        return data['n'], data['m'], data['d'], data["op"], data["cl"]
    end

    file = CSV.file("$name.csv")

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
    d = Dict([(k, i, j)=> durations[i+1][j+1] / 60 for k in 1:m, i in 0:n+1, j in 0:n+1 if i != j])

    # obtem horarios de abertura
    op = [split(t, ":") for t in file.opening_time]
    push!(op, op[1]) # inicio e fim no deposito
    op = [parse(Int, t[1]) * 60 + parse(Int, t[2]) for t in op] # transforma hora em minutos a partir das 00:00
    zeroTime = op[1] # tempo 0 eh o tempo de abertura do deposito
    op = [max(0, t - zeroTime) for t in op] # tempo de abertura em relação ao tempo de abertura do deposito
    op = Dict([i => op[i+1] for i in 0:n+1]) # indexado do 0

    # obtem horarios de fechamento
    cl = [split(t, ":") for t in file.closing_time]
    push!(cl, cl[1]) # inicio e fim no deposito
    cl = [parse(Int, t[1]) * 60 + parse(Int, t[2]) for t in cl] # transforma hora em minutos a partir das 00:00
    cl = [min(cl[1] - zeroTime, t - zeroTime) for t in cl] # tempo de fechamento em relação ao tempo de abertura do deposito
    cl = Dict([i => cl[i+1] for i in 0:n+1]) # indexicado do 0

    data = Dict(['n' => n, 'm' => m, 'd' => d, "op" => op, "cl" => cl])
    serialize("$name.srl", data)

    return n, m, d, op, cl
end