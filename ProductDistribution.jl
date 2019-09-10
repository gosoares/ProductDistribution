using JuMP, Cbc
include("DataReader.jl")
include("SubcycleChecker.jl")

function main()
    d, n, m = read_data()
    product_distribution(d, n, m)
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
    model = Model(with_optimizer(Cbc.Optimizer, logLevel = 0))
    @variable(model, x[1:m, 0:n, 1:n + 1], Bin)

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
    @constraint(model, stickCons[k = 1:m, i = 1:n, j = i+1:n], x[k, i, j] + x[k, j, i] <= 1)
    println("Resolvendo modelo...")


    while true
        optimize!(model)

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

    for k = 1:m
        println("Dia $k:")
        for i = 0:n, j = 1:n+1
            if i != j && value(x[k, i, j]) > 0.99
                print("($i -> $j) ")
            end
        end
        println("\n")
    end

end

main()