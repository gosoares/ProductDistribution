using Serialization
import CSV, HTTP, JSON

function readData(name)
    println("Lendo dados... ")

    if isfile("$name.srl")
        println("$name.srl encontrado!")
        data = deserialize("$name.srl")
        return data['n'], data['m'], data['d'], data["op"], data["cl"], data['a'], data["clientsData"], data["daysData"]
    end

    clients_file = CSV.file("$(name)_clients.csv")
    clientsData = [
        Dict([
            "name" => row.name,
            "address" => row.address,
            "coordinates" => row.coordinates,
        ]) for row in clients_file
    ]

    # le as coordenadas e transforma no formato aceito pelo OSRM
    clients_coordinates = clients_file.coordinates
    n = length(clients_coordinates) # numero de clientes
    clients_op = getTimes(clients_file.opening_time)
    clients_cl = getTimes(clients_file.closing_time)
    clients_a = clients_file.service_time
    a = Dict([i => clients_a[i] for i = 1:length(clients_a)])
    a[0] = 0 # origem não tem tempo de atendimento
    a[n+1] = 0 # nem destino
    

    days_file = CSV.file("$(name)_days.csv")
    daysData = [
        Dict([
            "startName" => row.start_name,
            "startAddress" => row.start_address,
            "startCoordinates" => row.start_coordinates,
            "destName" => row.dest_name,
            "destAddress" =>  row.dest_address,
            "destCoordinates" => row.dest_coordinates,
            "color" => row.color,
        ]) for row in days_file
    ]

    start_coordinates = days_file.start_coordinates
    dest_coordinates = days_file.dest_coordinates
    m = length(start_coordinates) # numero de dias
    start_op = getTimes(days_file.start_opening_time)
    start_cl = getTimes(days_file.start_closing_time)
    dest_op = getTimes(days_file.dest_opening_time)
    dest_cl = getTimes(days_file.dest_closing_time)
    zeroTime = minimum(start_op)

    d = Dict{Tuple{Int, Int, Int}, Float64}()
    op = Dict{Tuple{Int, Int}, Int}()
    cl = Dict{Tuple{Int, Int}, Int}()
    for k = 1:m
        day_coordinates = vcat([start_coordinates[k]], clients_coordinates, [dest_coordinates[k]])
        durations = getDurations(day_coordinates)
        d = merge(d, Dict([(k, i, j) => durations[i+1][j+1] / 60 for i = 0:n, j = 1:n+1 if i != j ]))
        
        op_times = vcat([start_op[k]], clients_op, [dest_op[k]])
        op = merge(op, Dict([(k, i) => op_times[i+1] - zeroTime for i in 0:n+1]))

        cl_times = vcat([start_cl[k]], clients_cl, [dest_cl[k]])
        cl = merge(cl, Dict([(k, i) => cl_times[i+1] - zeroTime for i in 0:n+1]))
    end


    data = Dict(['n' => n, 'm' => m, 'd' => d, "op" => op, "cl" => cl, 'a' => a, "clientsData" => clientsData, "daysData" => daysData])
    serialize("$name.srl", data)

    return n, m, d, op, cl, a, clientsData, daysData
end

function getDurations(coordinates)
    coordinates = [join(reverse(split(c, ',')), ',') for c in coordinates]
    coordsString = join(coordinates, ';')

    # obtem a matriz de tempos pelo osrm
    r = HTTP.get("http://router.project-osrm.org/table/v1/driving/$coordsString")
    responseBody = JSON.parse(String(r.body))
    durations = responseBody["durations"]
    return durations
end

function getTimes(timesColumn)
    op = [split(t, ":") for t in timesColumn]
    op = [parse(Int, t[1]) * 60 + parse(Int, t[2]) for t in op] # transforma hora em minutos a partir das 00:00
    return op
end