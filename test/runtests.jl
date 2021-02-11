#%% Test to see if the importing works
println("Beginning testing")
using Revise
using NeuroPhys
using Distributions, StatsBase, StatsPlots, Polynomials
println("Exporting succeeded")

#%% Test the exporting and filtering of .abf files
target_path1 = "test\\to_filter.abf"
target_path2 = "test\\to_analyze.abf"
data1 = extract_abf(target_path1); #Extract the data for filtering
data2 = extract_abf(target_path2; swps = -1, chs = [1,3,5]); #Extract the data for concatenation analysis
println("File extraction works")
#%% Test inline filtering functions
truncate_data!(data1);
truncate_data!(data2);
baseline_cancel!(data1; mode = :slope, region = :prestim) #Cancel drift
baseline_cancel!(data2; mode = :slope, region = :prestim) #Cancel drift for concatenation
baseline_cancel!(data1; mode = :mean, region = :prestim) #Baseline data
baseline_cancel!(data2; mode = :mean, region = :prestim) #Baseline data for concatenation
#lowpass_filter!(data1)
#lowpass_filter!(data2)
#notch_filter!(data1)
#notch_filter!(data2)
#cwt_filter!(data1)
#cwt_filter!(data2)
#average_sweeps!(data2)
println("All inline filtering functions work")

#%% Test filtering functions that are not inline
trunc_data1 = truncate_data(data1)
trunc_data2 = truncate_data(data2)
filter_data1 = lowpass_filter(data1) #Lowpass filter using a 40hz 8-pole filter
filter_data2 = lowpass_filter(data2) #Lowpass filter using a 40hz 8-pole filter
# Use this data for time to peak
cwt_data1 = cwt_filter(data1)
cwt_data2 = cwt_filter(data2)
drift_data1 = baseline_cancel(data1; mode = :slope) #Cancel drift
baseline_data1 = baseline_cancel(drift_data1; mode = :mean) #Baseline data
avg_data1 = average_sweeps(baseline_data1)
norm_data1 = normalize(baseline_data1)
println("All filtering functions work")

#%% Test the analysis
mins, maxes, means, stds = calculate_basic_stats(data1);
#These functions will only work on the data from the multi sweep data
rmaxes2 = saturated_response(filter_data2)
rdims2, dim_idx2 = dim_response(filter_data2, rmaxes2)
t_peak2 = time_to_peak(data2, dim_idx2)
t_dom2 = pepperburg_analysis(data2, rmaxes2)
ppbg_thresh2 = rmaxes2 .* 0.60;
#This function will be helpful for plotting the intensity response curves
responses2 = get_response(data2, rmaxes2)
t_Int = integration_time(filter_data2, dim_idx2)
tau_rec = recovery_tau(filter_data2, dim_idx2)
Amp_val = amplification(filter_data2, rmaxes2)
#%% Move this to a plotting function eventually
lb = [-1.0, 0.0]
ub = [Inf, Inf]
p = plot(filter_data2, c = :black, xlims = (0.0, 0.25))
for swp in 1:size(filter_data2,1), ch in 1:size(filter_data2,3)
    model(x, p) = map(t -> AMP(t, p[1], p[2], rmaxes2[ch]), x)
    xdata = filter_data2.t
    ydata = filter_data2[swp,:,ch]
    p0 = [200.0, 0.01]
    fit = curve_fit(model, xdata, ydata, p0, lower = lb, upper = ub)
    SSE = sum(fit.resid.^2)
    ȳ = sum(model(xdata, fit.param))/length(xdata)
    SST = sum((ydata .- ȳ).^2)
    GOF = 1- SSE/SST
    #println("Goodness of fit: $()")
    if GOF >= 0.50
        println("A -> $(fit.param[1])")
        println("t_eff -> $(fit.param[2])")
        plot!(p[ch], xdata, x -> model(x, fit.param), c = :red)
    end
end
p
#%%
#%%
println("Data analysis works")

#%% Test the plotting of the trace file
fig1 = plot(data1, stim_plot = :include)
savefig(fig1, "test\\test_figure1.png")
println("Plotting for single traces works")

#%% Testing file concatenation
#Concatenate two files
concat_data = concat([target_path2, target_path1])
concat!(concat_data, data1; mode = :pad)
concat!(concat_data, data2; mode = :pad)
concat!(concat_data, data2; mode = :pad, avg_swps = false)
println("Concatenation works")

#%% Useful code for demonstrating the pepperburg analysis
fig2 = plot(data2, labels = "", c = :black, lw = 2.0)
hline!(fig2[1], [rmaxes2[1]], c = :green, lw = 2.0, label = "Rmax")
hline!(fig2[2], [rmaxes2[2]], c = :green, lw = 2.0, label = "Rmax")
hline!(fig2[1], [rdims2[1]], c = :red, lw = 2.0, label = "Rdim")
hline!(fig2[2], [rdims2[2]], c = :red, lw = 2.0, label = "Rdim")
vline!(fig2[1], [t_peak2[1]], c = :blue, lw = 2.0, label = "Time to peak")
vline!(fig2[2], [t_peak2[2]], c = :blue, lw = 2.0, label = "Time to peak")
plot!(fig2[1], t_dom2[:,1], repeat([ppbg_thresh2[1]], size(data2,1)), marker = :square, c = :grey, label = "Pepperburg", lw = 2.0)
plot!(fig2[2], t_dom2[:,2], repeat([ppbg_thresh2[2]], size(data2,1)), marker = :square, c = :grey, label = "Pepperburg", lw = 2.0)
savefig(fig2, "test\\test_figure2.png")

#%% Useful code for demonstrating the rmax and rdim
p1 = plot(filter_data1, label = "", ylims = (-Inf, 0.0))
#plot!(filter_data1.t, filter_data1[dim_idx1[1]], c = :red)
hline!(p1[1], [rmaxes1[1]], c = :green, label = "Rmax")
hline!(p1[2], [rmaxes1[2]], c = :green, label = "Rmax")
hspan!(p1[1], [rmaxes1[1]*0.10, rmaxes1[1]*0.40], c = :green, alpha = 0.2)
hspan!(p1[2], [rmaxes1[2]*0.10, rmaxes1[2]*0.40], c = :green, alpha = 0.2)

hline!(p1[1], [rdims1[1]], c = :red)
hline!(p1[2], [rdims1[2]], c = :red)

p2 = plot(filter_data2, label = "", ylims = (-Inf, 0.0))
hline!(p2[1], [rmaxes2[1]], c = :green, label = "Rmax")
hline!(p2[2], [rmaxes2[2]], c = :green, label = "Rmax")
hspan!(p2[1], [rmaxes2[1]*0.10, rmaxes2[1]*0.40], c = :green, alpha = 0.2)
hspan!(p2[2], [rmaxes2[2]*0.10, rmaxes2[2]*0.40], c = :green, alpha = 0.2)

hline!(p2[1], [rdims2[1]], c = :red)
hline!(p2[2], [rdims2[2]], c = :red)

plot(p1, p2, layout = grid(1,2))

#%% Sandbox area
# TODO: Build the equation for the Ih curve fitting
# TODO: Build the equation for Recovery time constant
# TODO: Build the equation fot Amplification
