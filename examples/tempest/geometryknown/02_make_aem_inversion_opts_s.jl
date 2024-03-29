using transD_GP, Distributed
## make options for the stationary GP
nmin, nmax = 2, 40
pnorm = 2.
K = transD_GP.GP.OrstUhn()
demean = true
fbounds = [-0.5 2.5]
sdev_pos = [0.05abs(diff([extrema(znall)...])[1])]
sdev_prop = 0.05diff(fbounds, dims=2)[:]
xall = permutedims(collect(znall))
xbounds = permutedims([extrema(znall)...])
λ, δ = [2], 0.1

## Initialize a stationary GP using these options
Random.seed!(12)
opt = transD_GP.OptionsStat(nmin = nmin,
                        nmax = nmax,
                        xbounds = xbounds,
                        fbounds = fbounds,
                        xall = xall,
                        λ = λ,
                        δ = δ,
                        demean = demean,
                        sdev_prop = sdev_prop,
                        sdev_pos = sdev_pos,
                        pnorm = pnorm,
                        save_freq = 25,
                        quasimultid = false,
                        K = K,
                        )
