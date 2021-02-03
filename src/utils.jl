
mutable struct StimulusProtocol{T}
    type::Symbol
    sweep::Int64
    index_range::Tuple{Int64,Int64}
    timestamps::Tuple{T,T}
end

StimulusProtocol(type::Symbol) = StimulusProtocol(type, 1, (1, 1), (0.0, 0.0))

"""
This file contains the ABF data traces. It is a generic experiment which doesn't include any other specifics. 

To see all fields of the pyABF data: 
>> PyCall.inspect[:getmembers](trace_file)

Fields: 
    t: the time points contained within the traces
    tUnits: the measurement of time
    dt: the interval of the timepoints
    data: The trace data organized by [Sweep, Datapoints, Channels]
    chNames: The names for each of the channels
    chUnits: The units of measurment for the channels
    labels: The labels for [X (Time), Y (Membrane Voltage), Command, DigitalOut]
    stimulus_ch: If there is a channel to set as the stimulus, this will remember that channel, otherwise, this is set to -1
"""
mutable struct Experiment{T}
    ID::String
    protocol::String
    t::Array{T, 1}
    data_array::Array{T, 3}
    date_collected::DateTime
    tUnits::String
    dt::T
    chNames::Array{String, 1}
    chUnits::Array{String, 1}
    labels::Array{String, 1}
    stim_protocol::Array{StimulusProtocol}
    filename::Array{String,1}
end

"""
TODO: I need to do a massive restructure. 
1) ERG files need to be a seperate object. This will allow for more extensive stimulus protocols
2) I need to do something different with stimulus files
This function extracts an ABF file from a path
    - It creates a Experiment object which 
"""
function extract_abf(::Type{T}, abf_path::String; 
        stim_ch::Union{Array{Int64}, Int64, String, Array{String}} = "IN 7", 
        stim_name::Union{Array{String}, Array{Symbol}, String, Symbol} = :test,
        stimulus_threshold::Float64 = 0.2,
        swps = -1, 
        chs = ["Vm_prime","Vm_prime4", "IN 7"], 
        verbose = false, 
        time_adjusted = true
    ) where T <: Real

    #We need to make sure the stimulus names provided match the stimulus channels
    
    if length(abf_path |> splitpath) > 1
        full_path = abf_path
    else
        full_path = joinpath(pwd(), abf_path)   
    end
    
    #extract the abf file by using pyABF
    pyABF = pyimport("pyabf")
    trace_file = pyABF.ABF(full_path)
    #println("Made it here")
    #First extract the date collected 
    date_collected = trace_file.abfDateTime
    n_data_sweeps = n_sweeps = length(trace_file.sweepList)
    n_data_channels = n_channels = length(trace_file.channelList)
    n_data_points = n_points = length(trace_file.sweepX)
    
    if isa(swps, Int) && swps != -1 #Pick a sweep by index
        data_sweeps = [swps-1]
        n_data_sweeps = 1
    elseif isa(swps, AbstractArray) #pick a sweep by multiple indexes
        data_sweeps = swps.-1
        n_data_sweeps = length(swps)
    else #choose all channels to extract
        data_sweeps = trace_file.sweepList
    end
    

    if isa(chs, Int) && chs != -1 #Pick a channel by index
        data_channels = [chs-1]
        n_data_channels = 1
    elseif isa(chs, Array{Int64,1}) #Pick a channel by multiple indexes
        data_channels = chs.-1
        n_data_channels = length(chs)
    elseif isa(chs, Array{String, 1}) #Pick a channel by multiple names
        data_channels = map(ch_name -> findall(x -> x == ch_name, trace_file.adcNames)[1], chs) .- 1
        n_data_channels = length(chs)
    else #Choose all channels
        data_channels = trace_file.channelList
    end 
        #Identify channel names
    chNames = trace_file.adcNames[(data_channels.+1)]
    chUnits = trace_file.adcUnits[(data_channels.+1)]

    #Set up the data array
    t = T.(trace_file.sweepX);
    #We won't include the stimulus channels in the data analysis
    data_array = zeros(T, n_data_sweeps, n_data_points, n_data_channels)
    labels = [trace_file.sweepLabelX, trace_file.sweepLabelY, trace_file.sweepLabelC, trace_file.sweepLabelD]
    if verbose 
        print("Data output size will be:")
        println(size(data_array))
        println("$n_sweeps Sweeps available: $(trace_file.sweepList)")
        println("$n_channels Channels available: $(trace_file.channelList)")
    end
    
    #convert the stimulus channel into an array to make this part easier

    for (swp_idx, swp) in enumerate(data_sweeps), (ch_idx, ch) in enumerate(data_channels)
        trace_file.setSweep(sweepNumber = swp, channel = ch);
        data = Float64.(trace_file.sweepY);
        t = Float64.(trace_file.sweepX);
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
    #set up the stimulus protocol
    if isa(stim_ch, String)
        stim_ch = findall(x -> x == stim_ch, chNames)
        if isempty(stim_ch)
            println("No stimulus exists")
            stim_name = [:none]
        else
            stim_name = [stim_name]
        end
    elseif isa(stim_ch, Array{String})
        stim_chs = Int64[]
        stim_names = Symbol[]
        for (idx, ch) in enumerate(stim_ch)
            stim_ch_i = findall(x -> x == ch, chNames)
            if !isempty(stim_ch_i)
                push!(stim_chs, stim_ch_i[1])
                push!(stim_names, stim_name[idx])
            end
        end
        stim_ch = stim_chs
        stim_name = stim_names      
    elseif isa(stim_ch, Real)
        stim_ch = [stim_ch]
        stim_name = [stim_name]
    elseif stim_ch == -1
        #This is if there is no stimulus channel
    end

    stim_protocol = Array{StimulusProtocol}([])
    for (idx, ch) in enumerate(stim_ch), swp in 1:size(data_array,1)
        #println(swp)
        #we need to get the stimulus channel and extract the data
        stimulus_idxs = findall(data_array[swp,:,ch] .> stimulus_threshold)
        stim_begin = stimulus_idxs[1]
        stim_end = stimulus_idxs[end]
        stim_time_start = stim_begin*(t[2]-t[1])
        stim_time_end = stim_end*(t[2]-t[1])
        if time_adjusted 
            #This section automatically adjusts the time based on the stimulus start
            #t .-= stim_time_end
            #println(stim_time_end)
            #stim_time_start -= stim_time_end
            #stim_time_end = 0.0
        end
        stim = StimulusProtocol(
            stim_name[idx], swp, 
            (stim_begin, stim_end), 
            (stim_time_start, stim_time_end)    
        )
        push!(stim_protocol, stim)
    end

    Experiment{T}(
        trace_file.abfID, 
        trace_file.protocol,
        t, 
        data_array, 
        date_collected, 
        trace_file.sweepUnitsX, 
        trace_file.dataSecPerPoint, 
        chNames, 
        chUnits, 
        labels, 
        stim_protocol,
        [full_path]
        )
end

extract_abf(abf_path::String ; kwargs...) = extract_abf(Float64, abf_path ; kwargs...)

import Base: size, length, getindex, setindex, sum, copy, maximum, minimum, push!

#Extending for Experiment
size(trace::Experiment) = size(trace.data_array)
size(trace::Experiment, dim::Int64) = size(trace.data_array, dim)

length(trace::Experiment) = size(trace,2)
 
#Extending get index for Experiment
getindex(trace::Experiment, I...) = trace.data_array[I...]
setindex!(trace::Experiment, v, I...) = trace.data_array[I...] = v

import Base: +, -, *, / #Import these basic functions to help 
+(trace::Experiment, val::Real) = trace.data_array = trace.data_array .+ val
-(trace::Experiment, val::Real) = trace.data_array = trace.data_array .- val
*(trace::Experiment, val::Real) = trace.data_array = trace.data_array .* val
/(trace::Experiment, val::Real) = trace.data_array = trace.data_array ./ val

#This function allows you to enter in a timestamp and get the data value relating to it
function getindex(trace::Experiment, timestamp::Float64) 
    if timestamp > trace.t[end]
        trace[:, end, :]
    else
        return trace[:, round(Int, timestamp/trace.dt)+1, :]
    end
end

function getindex(trace::Experiment, timestamp_rng::StepRangeLen{Float64}) 
    println(timestamp_rng)
    if timestamp_rng[1] == 0.0
        start_idx = 1
    else
        start_idx = round(Int, timestamp_rng[1]/trace.dt) + 1
    end
    
    println(trace.t[end])
    if timestamp_rng[2] > trace.t[end]
        end_idx = length(trace.t)
    else
        end_idx = round(Int, timestamp_rng[2]/trace.dt) + 1
    end
    println(start_idx)
    println(end_idx)

    return trace[:, start_idx:end_idx, :]
end

"""
This function pushes traces to the datafile
    -It initiates in a sweepwise function and if the item dims match the data dims, 
    the data will be added in as new sweeps
    - Sweeps are 

"""
function push!(nt::Experiment{T}, item::AbstractArray{T}; new_name = "Unnamed") where T<:Real
    
    #All of these options assume the new data point length matches the old one
    if size(item, 2) == size(nt,2) && size(item,3) == size(nt,3)
        #item = (new_sweep, datapoints, channels)
        nt.data_array = cat(nt.data_array, item, dims = 1)

    elseif size(item, 1) == size(nt,2) && size(item, 2) == size(nt,3)
        #item = (datapoints, channels) aka a single sweep
        item = reshape(item, 1, size(item,1), size(item,2))
        nt.data_array = cat(nt.data_array, item, dims = 1)

    elseif size(item, 1) == size(nt,1) && size(item, 2) == size(nt, 2)
        #item = (sweeps, datapoints, new_channels) 
        nt.data_array = cat(nt.data_array, item, dims = 3)
        #Because we are adding in a new channel, add the channel name
        push!(nt.chNames, new_name)

    else
        throw(error("File size incompatible with push!"))
    end
end

function push!(nt_push_to::Experiment, nt_added::Experiment) 
    push!(nt_push_to.filename, nt_added.filename...)
    push!(nt_push_to, nt_added.data_array)
end

function pad(trace::Experiment{T}, n_add::Int64; position::Symbol = :post, dims::Int64 = 2, val::T = 0.0) where T
    data = deepcopy(trace)    
    addon_size = collect(size(trace))
    addon_size[dims] = n_add
    addon = zeros(addon_size...)
    if position == :post
        data.data_array = [trace.data_array addon]
    elseif position == :pre
        data.data_array = [addon trace.data_array]
    end
    return data
end

function pad!(trace::Experiment{T}, n_add::Int64; position::Symbol = :post, dims::Int64 = 2, val::T = 0.0) where T
    addon_size = collect(size(trace))
    addon_size[dims] = n_add
    addon = fill(val, addon_size...)
    if position == :post
        trace.data_array = [trace.data_array addon]
    elseif position == :pre
        trace.data_array = [addon trace.data_array]
    end
end

function chop(trace::Experiment, n_chop::Int64; position::Symbol = :post, dims::Int64 = 2) 
    data = copy(trace)
    resize_size = collect(size(trace))
    resize_size[dims] = (size(trace, dims)-n_chop)
    resize_size = map(x -> 1:x, resize_size)
    data.data_array = data.data_array[resize_size...]
    return data
end

function chop!(trace::Experiment, n_chop::Int64; position::Symbol = :post, dims::Int64 = 2) 
    resize_size = collect(size(trace))
    resize_size[dims] = (size(trace, dims)-n_chop)
    resize_size = map(x -> 1:x, resize_size)
    trace.data_array = trace.data_array[resize_size...]
end

minimum(trace::Experiment; kwargs...) = minimum(trace.data_array; kwargs...)

maximum(trace::Experiment; kwargs...) = maximum(trace.data_array; kwargs...)

sum(trace::Experiment; kwargs...) = sum(trace.data_array; kwargs...)

copy(nt::Experiment) = Experiment([getfield(nt, fn) for fn in fieldnames(nt |> typeof)]...)

"""
This gets the channel based on either the name or the index of the channel
"""
getchannel(trace::Experiment, idx::Int64) = trace.data_array[:,:,idx] |> vec
getchannel(trace::Experiment, idx_arr::Array{Int64}) = trace.data_array[:,:,idx_arr]
getchannel(trace::Experiment, name::String) = getchannel(trace, findall(x -> x==name, trace.chNames)[1])

"""
This iterates through all of the channels
"""
function eachchannel(trace::Experiment; include_stim = false) 
    if include_stim == true
        return Iterators.map(idx -> getchannel(trace, idx), 1:size(trace,3))
    else
        idxs = findall(x -> x != trace.stim_ch, 1:size(trace,3))
        return Iterators.map(idx -> getchannel(trace, idx), idxs)
    end
end

"""
This gets the sweep from the data based on the sweep index
"""
getsweep(trace::Experiment, idx::Int64) = trace.data_array[idx, :, :] |> vec
getsweep(trace::Experiment, idx_arr::Array{Int64}) = trace.data_array[idx_arr, :, :]

"""
This iterates through all sweeps
"""
eachsweep(trace::Experiment) = Iterators.map(idx -> getsweep(trace, idx), 1:size(trace,1))

"""
This function truncates the data based on the amount of time.
    In most cases we want to truncate this data by the start of the stimulus. 
    This is because the start of the stimulus should be the same response in all experiments. (0.0) 
"""
function truncate_data(trace::Experiment; t_pre = 0.2, t_post = 1.0)
    dt = trace.dt
    data = deepcopy(trace)
    data.data_array = zeros(size(trace,1), Int(t_post/dt)+Int(t_pre/dt)+1, size(trace,3)) #readjust the size of the data
    #Search for the stimulus. if there is no stimulus, then just set the stim to 0.0
    for swp in 1:size(trace, 1)

        stim_protocol = trace.stim_protocol[swp]
        #We are going to iterate through each sweep and truncate it
        if truncate_based_on == :stimulus_beginning
            #This will set the beginning of the stimulus as the truncation location
            truncate_loc = stim_protocol.index_range[1]
        elseif truncate_based_on == :stimulus_end
            #This will set the beginning of the simulus as the truncation 
            truncate_loc = stim_protocol.index_range[2]
        end
        t_start = round(Int, truncate_loc - (t_pre/dt)) #Index of truncated start point
        t_start = t_start >= 0 ? t_start : 1 #If the bounds are negative indexes then reset the bounds to index 1

        t_end = round(Int, truncate_loc + (t_post/dt)) #Index of truncated end point
        t_end = t_end < size(trace,2) ? t_end : size(trace,2) #If the indexes are greater than the number of datapoints then reset the indexes to n
        data.data_array[swp, :, :] = trace.data_array[swp, t_start:t_end, :]
    end
    return data
end

function truncate_data!(trace::Experiment; t_pre = 0.2, t_post = 1.0, truncate_based_on = :stimulus_beginning)
    dt = trace.dt
    temp_data = zeros(size(trace,1), Int(t_post/dt)+Int(t_pre/dt)+1, size(trace,3))
    for swp in 1:size(trace, 1)
        stim_protocol = trace.stim_protocol[swp]
        #We are going to iterate through each sweep and truncate it
        if truncate_based_on == :stimulus_beginning
            #This will set the beginning of the stimulus as the truncation location
            truncate_loc = stim_protocol.index_range[1]
        elseif truncate_based_on == :stimulus_end
            #This will set the beginning of the simulus as the truncation 
            truncate_loc = stim_protocol.index_range[2]
        end
        stim_begin_adjust = stim_protocol.index_range[1] - truncate_loc
        stim_end_adjust = stim_protocol.index_range[2] - truncate_loc
        trace.stim_protocol[swp].index_range = (stim_begin_adjust, stim_end_adjust)
        
        t_start = round(Int, truncate_loc - (t_pre/dt)) #Index of truncated start point
        t_start = t_start >= 0 ? t_start : 1 #If the bounds are negative indexes then reset the bounds to index 1
        
        t_end = round(Int, truncate_loc + (t_post/dt)) #Index of truncated end point
        t_end = t_end < size(trace,2) ? t_end : size(trace,2) #If the indexes are greater than the number of datapoints then reset the indexes to n
        temp_data[swp, :, :] = trace.data_array[swp, t_start:t_end, :]
    end
    #println(truncate_locs)
    #change the time 
    trace.t = range(-t_pre, t_post, length = length(trace.t))
	trace.data_array = temp_data
end

"""
The files in path array or super folder are concatenated into a single Experiment file
- There are a few modes
    - pre_pad will add zeros at the beginning of a data array that is too short
    - post_pad will add zeros at the end of a data array that is too short
    - pre_chop will remove beginning datapoints of a data array that is too long
    - post_chop will remove end datapoints of a data array that is too long
    - auto mode will will select a mode for you
        - If a majority of arrays are longer, it will pad the shorter ones
        - If a majority of arrays are shorter, it will chop the longer ones
"""

function concat(data::Experiment{T}, data_add::Experiment{T}; mode = :pad, position = :post, avg_swps = true, kwargs...) where T
    new_data = deepcopy(data)
    if size(data,2) > size(data_add,2)
        #println("Original data larger $(size(data,2)) > $(size(data_add,2))")
        n_vals = abs(size(data,2) - size(data_add,2))
        if mode == :pad
            pad!(data_add, n_vals; position = position)
        elseif mode == :chop
            chop!(data, n_vals; position = position)
        end
    elseif size(data,2) < size(data_add,2)
        #println("Original data smaller $(size(data,2)) < $(size(data_add,2))")
        n_vals = abs(size(data,2) - size(data_add,2))
        if mode == :pad
            pad!(data, n_vals; position = position)
        elseif mode == :chop
            chop!(data_add, n_vals; position = position)
        end
    end

    if avg_swps == true && size(data_add,1) > 1
        avg_data_added = average_sweeps(data_add)
        push!(new_data, avg_data_add)
    else
        push!(new_data, data_add)
    end

    return new_data
end

function concat!(data::Experiment{T}, data_add::Experiment{T}; mode = :pad, position = :post, avg_swps = true, kwargs...) where T
    if size(data,2) > size(data_add,2)
        #println("Original data larger $(size(data,2)) > $(size(data_add,2))")
        n_vals = abs(size(data,2) - size(data_add,2))
        if mode == :pad
            pad!(data_add, n_vals; position = position)
        elseif mode == :chop
            chop!(data, n_vals; position = position)
        end
    elseif size(data,2) < size(data_add,2)
        #println("Original data smaller $(size(data,2)) < $(size(data_add,2))")
        n_vals = abs(size(data,2) - size(data_add,2))
        if mode == :pad
            pad!(data, n_vals; position = position)
        elseif mode == :chop
            chop!(data_add, n_vals; position = position)
        end
    end

    if avg_swps == true && size(data_add,1) > 1
        avg_data_add = average_sweeps(data_add)
        push!(data, avg_data_add)
    else
        #If you one or more sweeps to add in the second trace, this adds all of them
        push!(data, data_add)
    end
end

function concat(path_arr::Array{String,1}; kwargs...)
    data = extract_abf(path_arr[1]; kwargs...)
    for path in path_arr[2:end]
        println(path)
        data_add = extract_abf(path; kwargs...)
        println(findstimRng(data_add))
        concat!(data, data_add; kwargs...)
    end
    return data
end

concat(superfolder::String; kwargs...) = concat(parse_abf(superfolder); kwargs ...)

exclude(A, exclusions) = A[filter(x -> !(x ∈ exclusions), eachindex(A))]
"""
This function opens the .abf file in clampfit if it is installed
"""
function openABF(trace::Experiment)
    pyABF = pyimport("pyabf")
    pyABF.ABF(trace.filename).launchInClampFit()
end

