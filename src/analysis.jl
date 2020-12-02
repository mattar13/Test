"""
This function is for computing the R-squared of a polynomial
"""
function RSQ(poly::Polynomial, x, y)
	ŷ = poly.(x)
	ȳ = sum(ŷ)/length(ŷ)
	SSE = sum((y-ŷ).^2)
	SST = sum((y.-ȳ).^2)
	1-SSE/SST
end

function rolling_mean(x::AbstractArray; window = 10)
    data_array = Float64[]
    for i = 1:length(x)-window
        push!(data_array, sum(x[i:i+window])/window)
    end
    data_array
end

function peak_finder(x::AbstractArray; change_thresh = 10)
    peak = Bool[]
    for i = 1:length(x)
        if i == 1
            push!(peak, false)
        elseif i == length(x)
            push!(peak, false)
        else
            if (x[i-1]-x[i]) < -change_thresh && (x[i+1]-x[i]) > change_thresh
                #This indicates a peak
                push!(peak, true)
            else
                push!(peak, false)
            end
        end
    end
    peak
end

"""
This function uses a histogram method to find the Rmax. 
"""
function rmax_no_nose(nt::NeuroTrace; precision = 500)
    rmaxs = zeros(size(nt,1), size(nt,3))
    for swp in 1:size(nt, 1)
        for ch in 1:size(nt,3)
            trace = nt[swp, :, ch]
            #We can assume the mean will be between the two peaks, therefore this is a good cutoff
            means = sum(trace)/length(trace)
            bins = LinRange(minimum(trace), means, precision)
            h = Distributions.fit(Histogram, trace, bins)
            edges = collect(h.edges...)
			weights = h.weights
			peaks = edges[argmax(weights)]
            #return edges, weights, peaks, means
            rmaxs[swp, ch] = peaks
        end
    end
    rmaxs
end

"""
This function calculates the min, max, mean, and std of each trace
"""
function calculate_basic_stats(data::NeuroTrace)
    stim_begin, stim_end = findstimRng(data)
    ch_idxs = findall(x -> x!=data.stim_ch, 1:size(data,3))
    pre_stim = data[:, 1:stim_end, ch_idxs]
    post_stim = data[:, stim_end:size(data,2), ch_idxs]
    mins = minimum(data.data_array, dims = 2)[:,1,1:2]
    maxes = maximum(data.data_array, dims = 2)[:,1,1:2]
    means = zeros(size(data,1), size(data,3))
    stds = zeros(size(data,1), size(data,3))
    for i_swp in 1:size(data,1)
        for i_ch in ch_idxs
            means[i_swp, i_ch] = sum(pre_stim[i_swp, :, i_ch])/size(pre_stim,2)
            stds[i_swp, i_ch] = std(pre_stim[i_swp, :, i_ch])
        end
    end
    return mins, maxes, means, stds
end


