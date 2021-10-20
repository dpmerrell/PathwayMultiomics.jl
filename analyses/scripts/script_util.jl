
using HDF5

function get_omic_feature_genes(omic_hdf)

    features = h5open(omic_hdf, "r") do file
        read(file, "features")
    end

    genes = [split(feat, "_")[1] for feat in features]

    return genes
end

function get_omic_feature_assays(omic_hdf)

    features = h5open(omic_hdf, "r") do file
        read(file, "features")
    end

    assays = [split(feat, "_")[2] for feat in features]

    return assays
end

function get_omic_instances(omic_hdf)

    patients = h5open(omic_hdf, "r") do file
        read(file, "instances")
    end

    return patients 
end


function get_omic_groups(omic_hdf)

    cancer_types = h5open(omic_hdf, "r") do file
        read(file, "groups")
    end

    return cancer_types
end


function get_omic_data(omic_hdf)

    dataset = h5open(omic_hdf, "r") do file
        read(file, "data")
    end

    return dataset
end



function save_omic_data(output_hdf, feature_names, instance_names, 
                    instance_groups, omic_matrix)

    @assert size(omic_matrix,2) == length(feature_names)
    @assert size(omic_matrix,1) == length(instance_names)
    @assert length(instance_names) == length(instance_groups)

    h5open(output_hdf, "w") do file
        write(file, "features", feature_names)
        write(file, "instances", instance_names)
        write(file, "groups", instance_groups)
        write(file, "data", omic_matrix)
    end

end

