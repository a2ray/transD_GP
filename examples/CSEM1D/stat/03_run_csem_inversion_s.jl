## set up McMC
nsamples, nchains, nchainsatone = 200001, 8, 1
Tmax = 2.50
addprocs(nchains)
@info "workers are $(workers())"
@everywhere any($srcdir .== LOAD_PATH) || push!(LOAD_PATH, $srcdir)
@everywhere any(pwd() .== LOAD_PATH) || push!(LOAD_PATH, pwd())
@everywhere using Distributed
@everywhere import MCMC_Driver
## run McMC
@time MCMC_Driver.main(opt, optdummy, csem, Tmax=Tmax, nsamples=nsamples, nchains=nchains, nchainsatone=nchainsatone)
rmprocs(workers())