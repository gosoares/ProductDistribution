using JuMP, Cbc, Serialization
import CSV, HTTP, JSON

function main()
    d, n, m = read_data()
    product_distribution(d, n, m)
end

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

"""
    product_distribution(d, n, m)

# Arguments

- `d::Any`: distances matrix
- `n::Int`: number of clients
- `m::Int`: number of days of work
"""
function product_distribution(d, n, m)
    println("Criando modelo...")
    model = Model(with_optimizer(Cbc.Optimizer))
    @variable(model, x[1:m, 0:n, 1:n + 1], Bin)

    # Função objetivo - Minimizar distância percorrida na semana
    @objective(model, Min, sum(d[k, i, j] * x[k, i, j] for k in 1:m, i in 0:n, j in 1:n+1 if i != j))

    # Restrições (1) - o distribuidar deve visitar todo cliente, exatamente uma vez em algum dia
    @constraint(model, inEdgesCons[j = 1:n], sum(x[k, i, j] for k in 1:m, i in 0:n if i != j) == 1)

    # Restrições (2) - se o distribuidor visitar um cliente, ele deve partir dele naquele mesmo dia
    @constraint(model, outEdgesCons[k=1:m, v = 1:n], sum(x[k, i, v] for i in 0:n if i != v) == sum(x[k, v, j] for j in 1:n+1 if j != v))

    # Restrições (3) - O distribuidor deve sair do ponto 0 todos os dias
    @constraint(model, outOriginCons[k = 1:m], sum(x[k, 0, j] for j in 1:n) == 1)

    # Restrições (4) - O distribuidor deve encerrar o trajeto no ponto n+1 todos os dias
    @constraint(model, inFinalCons[k = 1:m], sum(x[k, i, n+1] for i in 1:n) == 1)

    # Restrições (5) - Proibir subciclos de tamanho 2
    @constraint(model, stickCons[k = 1:m, i = 1:n, j = i+1:n], x[k, i, j] + x[k, j, i] <= 1)

    println("Resolvendo modelo...")
    optimize!(model)

    println("status: $(termination_status(model))")

#     for k in 1:m
#         println("Dia $m")
#         print("0 -> ")
#         i = 0
#         while i != n+1
#             for j in 1:n+1
#                 if value(x[k, i, j]) > 0.99
#                     i = j;
#                     print("$j -> ")
#                     break
#                 end
#             end
#         end
#         println()
#     end

    for k = 1:m
        println("Dia $k:")
        for i = 0:n
            for j = 1:n+1
                if value(x[k, i, j]) > 0.99
                    print("x($k, $i, $j) = $(value(x[k, i, j]))  ")
                end
            end
        end
        println("\n")
    end

end

main()