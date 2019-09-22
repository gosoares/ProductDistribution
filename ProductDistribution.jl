using JuMP, Cbc
include("DataReader.jl")
include("SubcycleChecker.jl")

function main()
    instance = "data10"
    n, m, d, op, cl, a, clientsData, daysData = readData(instance)
    routes = @time productDistribution(n, m, d, op, cl, a)
    printRoutes(instance, routes, clientsData, daysData)
end

"""
    product_distribution(d, n, m)

# Arguments

- `d::Any`: distances matrix
- `n::Int`: number of clients
- `m::Int`: number of days of work
"""
function productDistribution(n, m, d, op, cl, a)
    formulation = "with_time_windows"
    f = n + 1

    # conjuntos
    C = [i for i in 1:n]
    D = [i for i in 1:m]
    P0 = [i for i in 0:n]
    Pf = [i for i in 1:f]
    P = [i for i in 0:f]
    A = [(i, j) for i in P0, j in Pf if i != j]

    println("Criando modelo...")
    model = Model(with_optimizer(Cbc.Optimizer, logLevel = 0))
    @variable(model, x[k in D, i in P0, j in Pf; i != j], Bin)

    # Função objetivo - Minimizar distância percorrida na semana
    @objective(model, Min, sum(d[k, i, j] * x[k, i, j] for k in D, (i, j) in A))

    # Restrições (1) - o distribuidar deve visitar todo cliente, exatamente uma vez em algum dia
    @constraint(model, inArcsCons[j in C], sum(x[k, i, j] for k in D, i in P0 if i != j) == 1)

    # Restrições (2) - se o distribuidor visitar um cliente, ele deve partir dele naquele mesmo dia
    @constraint(model, outArcsCons[k in D, v in C], sum(x[k, i, v] for i in P0 if i != v) == sum(x[k, v, j] for j in Pf if j != v))

    # Restrições (3) - O distribuidor deve sair do ponto 0 todos os dias
    @constraint(model, outOriginCons[k in D], sum(x[k, 0, j] for j in C) == 1)

    # Restrições (4) - O distribuidor deve encerrar o trajeto no ponto f todos os dias
    @constraint(model, inFinalCons[k in D], sum(x[k, i, f] for i in C) == 1)

    # Restrições (5) - não pode atender mais que (135/m)% dos clientes em um dia
    @constraint(model, dayLimit[k in D], sum(x[k, i, j] for (i, j) in A) - 1 <= round((1.2/m)*n))

    # Restrições (6) - Proibir subciclos de tamanho 2
    @constraint(model, stickCons[k in D, i in C, j in C; j > i], x[k, i, j] + x[k, j, i] <= 1)

    # @constraint(model, balacing[k1 in D, k2 in D; k1 != k2], 2*sum(d[k1, i, j]*x[k1, i, j] for (i, j) in A) >= sum(d[k2, i, j]*x[k2, i, j] for (i, j) in A)) 

    println("Resolvendo modelo...")

    if formulation == "with_time_windows"
        # Restrições de janelas de tempo
        @variable(model, op[k, i] <= s[k in D, i in P] <= cl[k, i] - a[i])
        @constraint(model, timeRel[k in D, (i, j) in A], s[k, i] + a[i] + d[k, i, j] - 1440*(1 - x[k, i, j]) <= s[k, j])
 
        optimize!(model)

        status = termination_status(model)
        if status != MOI.OPTIMAL
            println("status: $status")
            exit()
        end
    elseif formulation == "mtz"
        # mtz constraints
        @variable(model, 1 <= u[1:n] <= n)
        @constraint(model, u[1] == 1)
        @constraint(model, mtz[i = 1:n, j = 1:n; i != j], u[i] - u[j] + n*sum(x[k, i, j] for k in 1:m) <= (n-1))

        optimize!(model)
    elseif formulation == "exponencial"
        # subcycles cut (exponencial formulation)
        while true
            optimize!(model)
            status = termination_status(model)

            if status != MOI.OPTIMAL
                println("status: $status")
                break
            end

            subcycles = checkForSubcycles(value.(x))

            if length(subcycles) > 0
                println("Subcycles found: $(subcycles)")

                for t in subcycles
                    S = t[2]
                    sumArcs = AffExpr()
                    for k = 1:m, i in S, j in S
                        if i != j
                            add_to_expression!(sumArcs, 1.0, x[k, i, j])
                        end
                    end
                    @constraint(model, sumArcs <= length(S) - 1)
                end
            else
                break
            end

        end
    else
        println("Invalid Formulation")
    end

    # recupera solucao
    routes = []
    for k = 1:m
        r = [0]
        while r[end] != f
            for j = 1:f
                if r[end] != j && value(x[k, r[end], j]) > 0.99
                    push!(r, j)
                end
            end
        end
        push!(routes, r)
    end

    return routes

end

function printRoutes(instance, routes, clientsData, daysData)
    m = length(routes)

    for k in 1:m
        route = routes[k]
        print("Dia $k: $(route[1])")
        for i in 2:length(route)
            print(" -> $(route[i])")
        end
        println()
    end
    println()

    rm("$(instance)_out", force = true, recursive = true)
    mkdir("$(instance)_out")
    for k in 1:m
        open("$(instance)_out/day$k.csv", "w") do f
            dayData = daysData[k]
            startCoordinates = split(dayData["startCoordinates"], ',')
            startCoordinates = [parse(Float64, s) for s in startCoordinates]
            destCoordinates = split(dayData["destCoordinates"], ',')
            destCoordinates = [parse(Float64, s) for s in destCoordinates]
            color = dayData["color"]
            route = routes[k]

            write(f, "latitude,longitude,name,color,note\n") # headers
            write(f, "$(startCoordinates[1]),$(startCoordinates[2]),\"$(dayData["startName"])\",$color,\"$(dayData["startAddress"])\"\n")

            for i in 2:length(route)-1
                c = clientsData[route[i]]
                coords = [parse(Float64, s) for s in split(c["coordinates"], ',')]
                write(f, "$(coords[1]),$(coords[2]),\"$(c["name"])\",$color,\"$(c["address"])\"\n")
            end

            write(f, "$(destCoordinates[1]),$(destCoordinates[2]),\"$(dayData["destName"])\",$color,\"$(dayData["destAddress"])\"\n")
        end
    end
    
end

main()