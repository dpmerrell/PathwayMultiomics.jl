

#######################################
# Termination conditions
#######################################
function iter_termination(model, iter)
    return iter >= 10
end

function precision_termination(model, iter; prec_threshold=0.3)
    pathway_av_precs = model_Y_average_precs(model)
    return minimum(pathway_av_precs) < prec_threshold
end

#######################################
# Callback structs
#######################################
mutable struct OuterCallback
    history::AbstractVector    
    history_json::String
end

function OuterCallback(; history_json="histories.json")
    return OuterCallback(Any[], history_json)
end

function (ocb::OuterCallback)(model::MultiomicModel, inner_callback)

    pathway_av_precs = model_Y_average_precs(model) 

    results = Dict("lambda_Y" => model.matfac.lambda_Y,
                   "history" => inner_callback.history,
                   "average_precisions" => pathway_av_precs)

    push!(ocb.history, results)

    open(ocb.history_json, "w") do f
        JSON.print(f, ocb.history)
    end

 
    #basename = join(split(ocb.history_json, ".")[1:end-1], ".")
    #save_model(string(basename, "_lambda_Y=", model.matfac.lambda_Y, ".bson"), model)

end

