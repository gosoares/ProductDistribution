function checkForSubcycles(x)
    sizes = size(x)
    n = sizes[2] - 1
    m = sizes[1]

    subcycles = Array{Tuple{Int, Set{Int64}}, 1}()

    for k = 1:m

        # create adjacency list of the day k
        adjList = Containers.DenseAxisArray([-1 for i = 0:n], 0:n)
        for i = 0:n
            for j = 1:n+1
                if i != j && x[k, i, j] > 0.99
                   adjList[i] = j
                end
            end
        end

#         println("adjList:")
#         for i = 0:n
#             println("$i -> $(adjList[i])")
#         end

        visited = Containers.DenseAxisArray([false for i = 0:n], 0:n)
        # visit path from 0 to n+1
        v = 0
        while v != n+1
            visited[v] = true
            v = adjList[v]
        end

        # is some not visited vertex has a arc, it is from a subcycle
        for i in 1:n
            if !visited[i] && adjList[i] != -1
                # found a subcycle starting with i
                subcycle = Set{Int}([i])
                v = adjList[i]
                while v != i
                    visited[v] = true
                    push!(subcycle, v)
                    v = adjList[v]
                end
                push!(subcycles, (k, subcycle))
            end
        end

    end

    return subcycles
end