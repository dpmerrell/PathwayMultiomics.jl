
using PathwayMultiomics
using HDF5
using JSON


DEFAULT_OMICS = ["cna",
                 "mutation",
                 "methylation",
                 "mrnaseq",
                 "rppa"]

tcga_omic_types = DEFAULT_OMICS

log_transformed_data_types = [] #"methylation"]
standardized_data_types = ["methylation", "cna", "mrnaseq", "rppa"]


function value_to_idx(values)
    return Dict(v => idx for (idx, v) in enumerate(values))
end


function keymatch(l_keys, r_keys)

    rkey_to_idx = value_to_idx(r_keys) 

    l_idx = []
    r_idx = []

    for (i, lk) in enumerate(l_keys)
        if lk in keys(rkey_to_idx)
            push!(l_idx, i)
            push!(r_idx, rkey_to_idx[lk])
        end
    end

    return l_idx, r_idx
end


"""
    Given an empty featuremap, populate it from the array 
    of features. 
"""
function populate_featuremap_tcga(featuremap, features)

    for (idx, feat) in enumerate(features)
        
        tok = split(feat, "_")
        # extract the protein names
        prot_names = split(tok[1], " ")
        
        omic_datatype = tok[end]
 
        # for each protein name
        for protein in prot_names
            k = string(protein, "_", omic_datatype)
            if k in keys(featuremap)
                push!(featuremap[k], idx)
            end
        end
    end

    return featuremap
end


function get_omic_feature_names(omic_hdf)

    idx = h5open(omic_hdf, "r") do file
        read(file, "features")
    end

    return idx 
end


function get_omic_patients(omic_hdf)

    patients = h5open(omic_hdf, "r") do file
        read(file, "instances")
    end

    return patients 
end


function get_omic_ctypes(omic_hdf)

    cancer_types = h5open(omic_hdf, "r") do file
        read(file, "cancer_types")
    end

    return cancer_types
end


function get_omic_data(omic_hdf)

    dataset = h5open(omic_hdf, "r") do file
        read(file, "data")
    end

    # Julia reads arrays from HDF files
    # in the (weird) FORTRAN order
    return permutedims(dataset)
end


function apply_mask!(dataset, instances, features, mask)

    inst_to_idx = value_to_idx(instances)
    feat_to_idx = value_to_idx(features)

    for coord in mask
        inst_idx = inst_to_idx[coord[1]]
        feat_idx = feat_to_idx[coord[2]]
        dataset[feat_idx, inst_idx] = NaN
    end 
end


function collect_masked_values(dataset, instances, features, mask)
    inst_to_idx = value_to_idx(instances)
    feat_to_idx = value_to_idx(features)
    result = fill(NaN, length(mask))
    for (i, coord) in enumerate(mask)
        if (coord[1] in keys(inst_to_idx)) & (coord[2] in keys(feat_to_idx))
            result[i] = dataset[feat_to_idx[coord[2]], inst_to_idx[coord[1]]]
        end
    end
    return result
end


function get_transformations(feature_vec)
    to_log = Int[]
    to_std = Int[]
    for (i, feat) in enumerate(feature_vec)
        tok = split(feat, "_")
        if tok[end] in standardized_data_types
            push!(to_std, i)
        end
        if tok[end] in log_transformed_data_types
            push!(to_log, i)
        end
    end
    return to_log, to_std
end


function save_factors(feature_factor, patient_factor, ext_features, ext_patients, pwy_sifs, output_hdf)

    h5open(output_hdf, "w") do file
        write(file, "feature_factor", feature_factor)
        write(file, "instance_factor", patient_factor)

        write(file, "features", convert(Vector{String}, ext_features))
        write(file, "instances", convert(Vector{String}, ext_patients))
        write(file, "pathways", convert(Vector{String}, pwy_sifs))
    end

end


function construct_glrm(A, feature_ids, feature_ugraphs, patient_ids, patient_ctypes)

    # Assign loss functions to features 
    feature_losses = Loss[feature_to_loss(feat) for feat in feature_ids]

    # Construct the GLRM problem instance
    rrglrm = RRGLRM(transpose(A), feature_losses, feature_ids, 
                                  feature_ugraphs, patient_ids, patient_ctypes;
                                  offset=true, scale=true)

end


function factorize_data(omic_data, data_features, data_patients,
                        data_ctypes, pathway_ls)
    
    println("LOADING PATHWAYS")
    # Read in the pathways; figure out the possible
    # ways we can map omic data on to the pathways. 
    pwys, empty_featuremap = load_pathways(pathway_ls, tcga_omic_types)

    println("POPULATING FEATURE MAP")
    # Populate the map, using our knowledge
    # of the TCGA data
    filled_featuremap = populate_featuremap_tcga(empty_featuremap, data_features) 

    # Translate the pathways into undirected graphs,
    # with data features mapped into the graph at 
    # appropriate locations 
    println("TRANSLATING PATHWAYS TO UGRAPHS")
    feature_ugraphs = pathways_to_ugraphs(pwys, filled_featuremap)

    println("CONSTRUCTING GLRM")
    # Construct the GLRM problem instance
    rrglrm = construct_glrm(omic_data, data_features, feature_ugraphs,
                                       data_patients, data_ctypes) 

    # Solve it!
    fit!(rrglrm)

    imputed_matrix = impute_missing(rrglrm)

    return imputed_matrix, rrglrm.Y, rrglrm.X, rrglrm.feature_ids, rrglrm.instance_ids

end


