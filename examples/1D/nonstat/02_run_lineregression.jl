## make options for the multichannel lengthscale GP
log10bounds = [-1.2 -0.8]
δlog10λ = 0.05
nminlog10λ, nmaxlog10λ = 2, 30
pnorm = 2.
Klog10λ = GP.Mat32()
λlog10λ = [0.02abs(diff([extrema(x)...])[1])]
demean = false
sdev_poslog10λ = [0.05abs(diff([extrema(x)...])[1])]
sdev_proplog10λ = 0.05*diff(log10bounds, dims=2)[:]
xall = permutedims(collect(x))
xbounds = permutedims([extrema(x)...])
## Initialize a lengthscale model using these options
Random.seed!(12)
optlog10λ = TransD_GP.OptionsStat(nmin = nminlog10λ,
                        nmax = nmaxlog10λ,
                        xbounds = xbounds,
                        fbounds = log10bounds,
                        xall = xall,
                        λ = λlog10λ,
                        δ = δlog10λ,
                        demean = demean,
                        sdev_prop = sdev_proplog10λ,
                        sdev_pos = sdev_poslog10λ,
                        pnorm = pnorm,
                        quasimultid = false,
                        K = Klog10λ,
                        save_freq = 20,
                        timesλ = 3.6,
                        peskycholesky = true
                        )
## make options for the nonstationary actual properties GP
nmin, nmax = 2, 30
fbounds = permutedims([extrema(ynoisy[.!isnan.(ynoisy)])...])
ymin, ymax = extrema(y)
fbounds[1] > ymin && (fbounds[1] = ymin)
fbounds[2] < ymax && (fbounds[2] = ymax)
sdev_prop = 0.05*diff(fbounds, dims=2)[:]
sdev_pos = [0.05abs(diff([extrema(x)...])[1])]
demean_ns = true
K = GP.Mat32()
δ = 0.05
## Initialize model for the nonstationary properties GP
Random.seed!(13)
opt = TransD_GP.OptionsNonstat(optlog10λ,
                        nmin = nmin,
                        nmax = nmax,
                        fbounds = fbounds,
                        δ = δ,
                        demean = demean_ns,
                        sdev_prop = sdev_prop,
                        sdev_pos = sdev_pos,
                        pnorm = pnorm,
                        K = K,
                        )
## set up McMC
nsamples, nchains, nchainsatone = 400001, 4, 1
Tmax = 2.50
addprocs(nchains)
@info "workers are $(workers())"
@everywhere any($srcdir .== LOAD_PATH) || push!(LOAD_PATH, $srcdir)
@everywhere any(pwd() .== LOAD_PATH) || push!(LOAD_PATH, pwd())
@everywhere using Distributed
@everywhere import MCMC_Driver
## run McMC
@time MCMC_Driver.main(optlog10λ, opt, line, Tmax=Tmax, nsamples=nsamples, nchains=nchains, nchainsatone=nchainsatone)
rmprocs(workers())
## plot
GeophysOperator.getchi2forall(opt, fsize=8, alpha=1)
gcf().text(0.02, 0.9, "a.", fontsize=14, color="red")
figure(1)
ax = gcf().axes;
r = ynoisy[linidx] - y[linidx]
χ² = length(r)#r'*r/σ^2
ax[2].set_ylim(χ²/2 - 20, χ²/2 + 40)
ax[2].plot(xlim(), [χ²/2 , χ²/2], "--", color="gray")
figure(2)
ax = gcf().axes;
ax[2].set_ylim(χ²/2 - 20, χ²/2 + 40)
ax[2].plot(xlim(), [χ²/2 , χ²/2], "--", color="gray")
savefig("line_conv_ns_1.png", dpi=300)
close("all")
GeophysOperator.getchi2forall(optlog10λ, fsize=8, alpha=1)
gcf().text(0.02, 0.9, "b.", fontsize=14, color="red")
figure(1)
ax = gcf().axes;
r = ynoisy[linidx] - y[linidx]
χ² = length(r)#r'*r/σ^2
ax[2].set_ylim(χ²/2 - 20, χ²/2 + 40)
ax[2].plot(xlim(), [χ²/2 , χ²/2], "--", color="gray")
figure(2)
ax = gcf().axes;
ax[2].set_ylim(χ²/2 - 20, χ²/2 + 40)
ax[2].plot(xlim(), [χ²/2 , χ²/2], "--", color="gray")
savefig("line_conv_ns_2.png", dpi=300)
GeophysOperator.plot_posterior(line, opt, optlog10λ,
    burninfrac=0.25, figsize=(7.5,4), fsize=8, nbins=100)
ax=gcf().axes
p = ax[1].scatter(ynoisy, x, c="w", alpha=0.2, s=25)
ax[1].plot(y, x, "--w", alpha=0.5)
del = fbounds[2]-fbounds[1]
ax[1].set_xlim(fbounds[1]-0.05del, fbounds[2]+0.05del)
savefig("jump1D_ns.png", dpi=300)
# zoom in
GeophysOperator.plot_posterior(line, opt, optlog10λ,
    burninfrac=0.25, figsize=(7.5,4), fsize=8, nbins=100, vmaxpc=0.6)
ax=gcf().axes
p = ax[1].scatter(ynoisy, x, c="w", alpha=0.2, s=25)
ax[1].plot(y, x, "--w", alpha=0.5)
del = fbounds[2]-fbounds[1]
ax[1].set_xlim(fbounds[1]-0.05del, fbounds[2]+0.05del,)
ax[1].set_ylim(0.37,0.42)
p.set_alpha(0.6)
p.set_sizes([60])
gcf().text(0.02, 0.9, "b.", fontsize=14, color="red")
ax[1].invert_yaxis()
ax[2].set_xlim(-1.6, -0.7)
savefig("jump1D_ns_zoom.png", dpi=300)
# PSNR calculation
M = GeophysOperator.assembleTat1(opt, :fstar, temperaturenum=1, burninfrac=0.25)
m = mean(M)
@info "Nonstationary PSNR is " GeophysOperator.CommonToAll.psnr(y,m)
## correlated residuals (hacky, uncomment and run after running the stationary script first)
h, edges = GeophysOperator.makehist(line, opt)
ax[2].pcolormesh(x[sort(linidx)], edges, h)
GeophysOperator.nicenup(f, fsize=8)
savefig("residual_comparison.png", dpi=300)
