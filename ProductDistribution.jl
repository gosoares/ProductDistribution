using JuMP, Cbc
include("DataReader.jl")
include("SubcycleChecker.jl")

function main()
    n, m, d, op, cl, a = readData("data10")
    routes = @time productDistribution(n, m, d, op, cl, a)
    printRoutes(routes)
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

    println("Criando modelo...")
    model = Model(with_optimizer(Cbc.Optimizer, logLevel = 0))
    @variable(model, x[k = 1:m, i = 0:n, j = 1:n + 1], Bin)

    # Função objetivo - Minimizar distância percorrida na semana
    @objective(model, Min, sum(d[k, i, j] * x[k, i, j] for k in 1:m, i in 0:n, j in 1:n+1 if i != j))

    # Restrições (1) - o distribuidar deve visitar todo cliente, exatamente uma vez em algum dia
    @constraint(model, inArcsCons[j = 1:n], sum(x[k, i, j] for k in 1:m, i in 0:n if i != j) == 1)

    # Restrições (2) - se o distribuidor visitar um cliente, ele deve partir dele naquele mesmo dia
    @constraint(model, outArcsCons[k=1:m, v = 1:n], sum(x[k, i, v] for i in 0:n if i != v) == sum(x[k, v, j] for j in 1:n+1 if j != v))

    # Restrições (3) - O distribuidor deve sair do ponto 0 todos os dias
    @constraint(model, outOriginCons[k = 1:m], sum(x[k, 0, j] for j in 1:n) == 1)

    # Restrições (4) - O distribuidor deve encerrar o trajeto no ponto n+1 todos os dias
    @constraint(model, inFinalCons[k = 1:m], sum(x[k, i, n+1] for i in 1:n) == 1)

    # Restrições (5) - Proibir subciclos de tamanho 2
    @constraint(model, stickCons[k = 1:m, i = 1:n, j = i+1:n; i != j], x[k, i, j] + x[k, j, i] <= 1)
    println("Resolvendo modelo...")

    if formulation == "with_time_windows"
        # Restrições de janelas de tempo
        @variable(model, op[k, i] <= s[k = 1:m, i = 0:n+1] <= cl[k, i] - a[i])
        @constraint(model, timeRel[k = 1:m, i=0:n, j=1:n+1; i != j], s[k, i] + a[i] + d[k, i, j] - 1440*(1 - x[k, i, j]) <= s[k, j])

        optimize!(model)

        status = termination_status(model)
        if status != MOI.OPTIMAL
            println("status: $status")
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
        while r[end] != n+1
            for j = 1:n+1
                if r[end] != j && value(x[k, r[end], j]) > 0.99
                    push!(r, j)
                end
            end
        end
        push!(routes, r)
    end

    return routes

end

function printRoutes(routes)
    for k in 1:length(routes)
        route = routes[k]
        print("Dia $k: $(route[1])")
        for i in 2:length(route)
            print(" -> $(route[i])")
        end
        println()
    end
end

main()