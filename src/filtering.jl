####################These functions are for filtering and adjusting the traces################
"""
This function adjusts the baseline, similar to how it is done in clampfit. 
    To change the mode of the function use the keyword argument mode
        it can cancel baseline based on: 
    - :mean -> the average voltage of a region
    - :slope -> the linear slope of a region
    To choose a region use the keyword region
    - :prestim -> measures all time before the stimulus
    - :whole -> measures the entire trace
    - (start, end) -> a custom region
It catches the baseline if the stimulus is at the beginning of the 
    """
function baseline_cancel(trace::Experiment; mode::Symbol = :mean, region = :prestim)
    data = deepcopy(trace)
    if isempty(trace.stim_protocol)
        #println("No Stim protocol exists")
        return data
    else
        for swp in 1:size(trace,1)
            if isa(region, Tuple{Float64, Float64})
                rng_begin = round(Int, region[1]/trace.dt)+1
                if region[2] > trace.t[end]
                    rng_end = length(trace.t)
                else
                    rng_end = round(Int, region[2]/trace.dt)+1
                end
            elseif isa(region, Tuple{Int64, Int64})
                rng_begin, rng_end = region
            elseif region == :whole
                rng_begin = 1
                rng_end = length(trace)
            elseif region == :prestim
                rng_begin = 1
                rng_end = trace.stim_protocol[swp].index_range[1] #Get the first stimulus index
            end
            for ch in 1:size(trace,3)
                if mode == :mean
                    if (rng_end - rng_begin) != 0
                        baseline_adjust = sum(trace.data_array[swp, rng_begin:rng_end, ch])/(rng_end-rng_begin)
                        #Now subtract the baseline scaling value
                        data.data_array[swp,:, ch] .= trace.data_array[swp,:,ch] .- baseline_adjust
                    else
                        if verbose
                            #println("no pre-stimulus range exists")
                        end
                    end
                elseif mode == :slope
                    if (rng_end - rng_begin) != 0
                        pfit = Polynomials.fit(trace.t[rng_begin:rng_end], trace[swp, rng_begin:rng_end , ch], 1)
                        #Now offset the array by the linear range
                        data.data_array[swp, :, ch] .= trace[swp, :, ch] - pfit.(trace.t)
                    else
                        #println("no pre-stimulus range exists")
                    end
                end
            end
        end
        return data
    end
end

function baseline_cancel!(trace::Experiment; mode::Symbol = :mean, region = :prestim)
    if isempty(trace.stim_protocol)
        #println("No stim protocol exists")
    else
        for swp in 1:size(trace,1)
            if isa(region, Tuple{Float64, Float64})
                rng_begin = round(Int, region[1]/trace.dt)+1
                if region[2] > trace.t[end]
                    rng_end = length(trace.t)
                else
                    rng_end = round(Int, region[2]/trace.dt)+1
                end
            elseif isa(region, Tuple{Int64, Int64})
                rng_begin, rng_end = region
            elseif region == :whole
                rng_begin = 1
                rng_end = length(trace)
            elseif region == :prestim
                rng_begin = 1
                rng_end = trace.stim_protocol[swp].index_range[1] #Get the first stimulus index
            end
            for ch in 1:size(trace,3)
                if mode == :mean
                    if (rng_end - rng_begin) != 0
                        baseline_adjust = sum(trace.data_array[swp, rng_begin:rng_end, ch])/(rng_end-rng_begin)
                        #Now subtract the baseline scaling value
                        trace.data_array[swp,:, ch] .= trace.data_array[swp,:,ch] .- baseline_adjust
                    else
                        #println("no pre-stimulus range exists")
                    end
                elseif mode == :slope
                    #println(rng_begin)
                    if (rng_end - rng_begin) != 0 # && rng_begin != 1
                        pfit = Polynomials.fit(trace.t[rng_begin:rng_end], trace[swp, rng_begin:rng_end , ch], 1)
                        #Now offset the array by the linear range
                        trace.data_array[swp, :, ch] .= trace[swp, :, ch] - pfit.(trace.t)
                    else
                        #trace.data_array[swp, :, ch] .= trace[swp, :, ch] 
                        #println("no pre-stimulus range exists")
                    end
                end
            end
        end
    end
end

"""
This function applies a n-pole lowpass filter
"""
function lowpass_filter(trace::Experiment; freq = 40.0, pole = 8)
    
    responsetype = Lowpass(freq; fs =  1/trace.dt)
    designmethod = Butterworth(8)
    digital_filter = digitalfilter(responsetype, designmethod)
    data = deepcopy(trace)
    for swp in 1:size(trace,1)
        for ch in 1:size(trace,3)
        #never adjust the stim
            data.data_array[swp,:,ch] .= filt(digital_filter, trace[swp, :, ch])
        end
    end
    return data
end

function lowpass_filter!(trace::Experiment; freq = 40.0, pole = 8)
    
    responsetype = Lowpass(freq; fs =  1/trace.dt)
    designmethod = Butterworth(8)
    digital_filter = digitalfilter(responsetype, designmethod)
    for swp in 1:size(trace,1)
        for ch in 1:size(trace,3)
            trace.data_array[swp,:,ch] .= filt(digital_filter, trace[swp, :, ch])
        end
    end
end

lowpass_filter(trace::Experiment, freq; pole = 8) = lowpass_filter(trace; freq = freq, pole = pole)

function notch_filter(trace::Experiment; pole = 8, center = 60.0, std = 0.1)
    
    responsetype = Bandstop(center-std, center+std; fs = 1/trace.dt)
	designmethod = Butterworth(8)
	digital_filter = digitalfilter(responsetype, designmethod)
    data = deepcopy(trace)
    for swp in 1:size(trace,1)
        for ch in 1:size(trace,3)
            #never adjust the stim
            data.data_array[swp,:,ch] .= filt(digital_filter, trace[swp, :, ch])
        end
    end
    return data
end

function notch_filter!(trace::Experiment; pole = 8, center = 60.0, std = 0.1)
    
    responsetype = Bandstop(center-std, center+std; fs = 1/trace.dt)
	designmethod = Butterworth(8)
	digital_filter = digitalfilter(responsetype, designmethod)
    for swp in 1:size(trace,1)
        for ch in 1:size(trace,3)
            trace.data_array[swp,:,ch] .= filt(digital_filter, trace[swp, :, ch])
        end
    end
end

function cwt_filter(trace::Experiment; wave = WT.dog2, periods = 1:7, return_cwt = true)
    data = deepcopy(trace)
    for swp in 1:size(trace,1)
        for ch in 1:size(trace,3)
            y = cwt(trace[swp, :, ch], wavelet(wave))
            data.data_array[swp,:,ch] .= -sum(real.(y[:,periods]), dims = 2) |> vec;
        end
    end
    data
end

function cwt_filter!(trace::Experiment; wave = WT.dog2, periods = 1:9)
    
    for swp in 1:size(trace,1)
        for ch in 1:size(trace,3)
            y = cwt(trace[swp, :, ch], wavelet(wave))
            trace.data_array[swp,:,ch] .= -sum(real.(y[:,periods]), dims = 2) |> vec;
        end
    end
end

"""
If the traces contain multiple runs, then this file averages the data
"""
function average_sweeps(trace::Experiment)
    
    data = deepcopy(trace)
    for ch in 1:size(trace,3)
        data[:,:,ch] .= sum(trace.data_array[:,:,ch], dims = 1)/size(trace,1)
    end
    return data
end

average_sweeps!(trace::Experiment) = trace.data_array = sum(trace, dims = 1)/size(trace,1) 

function normalize(trace::Experiment; rng = (-1,0))
    data = deepcopy(trace)
    for swp in 1:size(trace,1)
        for ch in 1:size(trace,3)
            data[swp,:,ch] .= (trace[swp,:,ch] ./ minimum(trace[swp,:,ch], dims = 2))
        end
    end
    return data
end

function normalize!(trace::Experiment; rng = (-1,0))
    for swp in 1:size(trace,1)
        for ch in 1:size(trace,3)
            if rng[1] < 0
                trace.data_array[swp,:,ch] .= (trace[swp,:,ch] ./ minimum(trace[swp,:,ch], dims = 2))
            else
                trace.data_array[swp,:,ch] .= (trace[swp,:,ch] ./ maximum(trace[swp,:,ch], dims = 2))
            end
        end
    end
end


################## Check these functions because they might be deprecated #####################################
function fft_spectrum(t, data::Array{T, 1}) where T <: Real
    #FFTW filtering
    x_fft = fft(data) |> fftshift
    dt = t[2] - t[1]
    freqs = FFTW.fftfreq(length(t), 1.0/dt) |> fftshift
    over_0 = findall(freqs .> 0);
    return freqs[over_0], x_fft[over_0] 
end