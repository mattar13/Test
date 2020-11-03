


########################### These are some functions that will make parsing folder names easier ##############
"""
This function pulls out all adjacent numbers from a string and returns a list of numbers and letters
"""
function number_seperator(str)
    #First we want to split the string into characters
    char_str = split(str, "")
    #We can dilate numbers next to each other
    numerical = String[]
    text = String[]
    place_number = ""
    place_text = ""
    for c in char_str
        if tryparse(Int, c) !== nothing
            if place_text != ""
                push!(text, place_text)
                place_text = ""
            end
            place_number *= c
        else
            if place_number != ""
                push!(numerical, place_number)
                place_number = ""
            end
            place_text *= c
        end
    end
    #Clear any remaining numbers or texts
    if place_number != ""
        push!(numerical, place_number)
    end
    if place_text != ""
        push!(text, place_text)
    end
    #Finally we want to convert all numbers within the numerical array into numbers
    numerical = map(c -> parse(Int, c), numerical)
    return numerical, text
end

"""
This function takes all the data from the file/folder name and returns only the numbers
"""
function extract_numbers(str) 
    number_field = number_seperator(str)[1]
    if number_field |> length == 1
        #If it is only one number return only that number
        return number_field[1]
    else
        #If the datafield is multiple numbers return all of them
        return number_field
    end
end
#These functions open and load ABF data

"""
This function walks through the directory and locates any .abf file. 
The extension can be changed with the keyword argument extension
"""
function parse_abf(super_folder::String; extension::String = ".abf", verbose = false)
    file_list = []
    for (root, dirs, files) in walkdir(super_folder)
        for file in files
            if file[end-3:end] == extension
                path = joinpath(root, file)
                if verbose 
                    println(path) # path to files
                end
                push!(file_list, path)
            end
        end
    end
    file_list
end

"""
This function walks through the directory and locates any .abf file. 
The extension can be changed with the keyword argument extension
"""
function extract_abf(abf_path; swps = -1, chs = ["Vm_prime","Vm_prime4", "IN 7"], verbose = false, v_offset = -25.0, sweep_sort = false)
    if length(abf_path |> splitpath) > 1
        full_path = abf_path
    else
        full_path = joinpath(pwd(), abf_path)   
    end
    
    pyABF = pyimport("pyabf")
    #extract the abf file by using pyABF
    exp_data = pyABF.ABF(full_path)
    n_data_sweeps = n_sweeps = length(exp_data.sweepList)
    n_data_channels = n_channels = length(exp_data.channelList)
    n_data_points = n_points = length(exp_data.sweepX)
    
    if isa(swps, Int) && swps != -1
        data_sweeps = [swps-1]
        n_data_sweeps = 1
    elseif isa(swps, AbstractArray)
        data_sweeps = swps.-1
        n_data_sweeps = length(swps)
    else
        data_sweeps = exp_data.sweepList
    end
        
    if isa(chs, Int) && chs != -1
        data_channels = [chs-1]
        n_data_channels = 1
    elseif isa(chs, Array{Int64,1})
        data_channels = chs.-1
        n_data_channels = length(chs)
    elseif isa(chs, Array{String, 1})
        data_channels = map(ch_name -> findall(x -> x == ch_name, exp_data.adcNames)[1], chs) .- 1
        n_data_channels = length(chs)
    else
        data_channels = exp_data.channelList
    end 
    
    data_array = zeros(n_data_sweeps, n_data_points, n_data_channels)
    
    if verbose 
        print("Data output size will be:")
        println(size(data_array))
        println("$n_sweeps Sweeps available: $(exp_data.sweepList)")
        println("$n_channels Channels available: $(exp_data.channelList)")
    end
    t = Float64.(exp_data.sweepX);
    dt = t[2]
    for (swp_idx, swp) in enumerate(data_sweeps), (ch_idx, ch) in enumerate(data_channels)
        exp_data.setSweep(sweepNumber = swp, channel = ch);
        data = Float64.(exp_data.sweepY);
        t = Float64.(exp_data.sweepX);
        dt = t[2]
        if verbose
            println("Data extracted from $full_path")
            println("Data from Channel $(ch) Sweep $(swp)")
            println("Data from time stamp $(t[1]) s to $(t[end]+dt) s with dt = $dt ms")
            println("Data was acquired at $(1/dt/1000) Hz")
            println("$n_data_points data points")
        end
        data_array[swp_idx, :, ch_idx] = data
    end
    t, data_array, dt
end

"""
This extracts the stimulus intensities from a light calibration trial
"""
function stim_intensity(filename; kwargs...)
    t, data_array, dt = extract_abf(filename; kwargs...);
    stim_t = sum(data_array[:,:,2] .> 1.0, dims = 2) .* dt*1000
    stim_i = sum(data_array[:,:,1], dims = 2) .* dt
    stim_t = reshape(stim_t,  (length(stim_t)));
    stim_i = reshape(stim_i,  (length(stim_i)));
    return stim_t, stim_i
end

"""
This function opens the .abf file in clampfit if it is installed
"""
function openABF(path) 
    pyABF = pyimport("pyabf")
    pyABF.ABF(path).launchInClampFit()
end


"""
Filter functions should be in the form (t,x) -> func(t,x)

The concatenated file, the sweeps are removed and replaced with traces. 
If the traces are different length, they are padded with 0's. 
The kwarg pad controls whether or not the padding is added to the beginning (:pre)
or the end (:post)

Prestim_time sets the amount of time (in seconds) before the END of the stimulus. This sets it so the effective time is always the prestim time

T_cutoff truncates the data to the time (in seconds)
"""
function concat(path_arr; t_cutoff = 3.5, t_eff = 0.5, filter_func = nothing, sweep_avg = true, pad = :post)
    abfs = map(p -> extract_abf(p)[1:2], path_arr)
    n_traces = length(path_arr)
    
    dt = abfs[1][1][2] - abfs[1][1][1]
    t = collect(0.0:dt:(t_cutoff+t_eff))
    concatenated_trace = zeros(n_traces, length(t), 3)
    #Average multiple traces
    for (i, (t, raw_data)) in enumerate(abfs)
        print(i)
        if sweep_avg
            data = sum(raw_data, dims = 1)/size(raw_data,1)
        else
            data = raw_data
        end
        if filter_func === nothing
            println(data |> size)
            x_ch1 = data[1,:,1] 
            x_ch2 = data[1,:,2] 
            x_stim = data[1,:,3] .> 0.2
            #x_stim = x_stim .> 0.2
        else
            x_ch1, x_ch2, x_stim = filter_func(t, data)
        end
                
        t_stim_end = findall(x -> x == true, x_stim)[end]
        t_start = t_stim_end - (t_eff/dt) |> Int64
        t_end = t_stim_end + (t_cutoff/dt) |> Int64
        concatenated_trace[i, :, 1] = x_ch1[t_start:t_end] 
        concatenated_trace[i, :, 2] = x_ch2[t_start:t_end] 
        concatenated_trace[i, :, 3] = x_stim[t_start:t_end] 
    end 
    t, concatenated_trace
end

#%% Sandbox for testing things

using NeuroPhys
using DataFrames
#We want to make a file parser that includes all data behind the recordings
df = DataFrame(
    Year = Int[], 
    Month = Int[], 
    Day = Int[]    
    )
super_folder = "D:\\Data\\ERG\\Gnat"
common_root = split(super_folder, "\\")
structure = collect(walkdir(super_folder))
[:date, :animal, :blockers, :condition]
for (root, dirs, files) in walkdir(super_folder)
    if !isempty(files)    
        reduced_root = filter(e -> e ∉ common_root, split(root, "\\"))
        if !isempty(reduced_root)
            date, animal, blockers, condition = reduced_root
            #println(reduced_root)
            year, month, day = map(x -> extract_numbers(x)[1], split(date, "_"))
            animal_n, age, genotype = split(animal, "_")
            drugs_added = blockers == "Drugs"
            wavelengh, color = condition |> extract_numbers
            for file in files
                intensity_info = split(file, "_")
                if length(intensity_info) == 2
                    println("This file has not yet been renamed")
                elseif length(intensity_info) == 3 || length(intensity_info) == 4
                    #This is the case for files that have been converted to 
                    #println(intensity_info)
                    println(year[1])
                    #push!(df, (year, month, day))
                else 
                end
            end
            #Reduced root should be made of 
        end
    end
end

#%%
a = "100f"
a |> extract_numbers