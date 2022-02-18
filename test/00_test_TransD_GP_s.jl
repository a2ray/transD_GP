## make options for the multichannel lengthscale GP
nminlog10λ, nmaxlog10λ = 2, 200
pnorm = 2.
Klog10λ = transD_GP.GP.Mat32()
λx,λy = 1, 1
x = 0:(0.005λx):λx
y = 0:(0.005λy):0.5λy
λlog10λ = [0.05maximum(x), 0.05maximum(y)]
demean = false
sdev_poslog10λ = [0.01maximum(y), 0.01maximum(x)]
log10bounds = [-1 -0.69; -1 -0.69]
δlog10λ = 0.1
##
sdev_proplog10λ = [0.1, 0.1]
xall = zeros(2,length(x)*length(y))
for i in 1:size(xall,2)
    xid, yid = Tuple(CartesianIndices((length(x),length(y)))[i])
    xall[:,i] = [x[xid]; y[yid]]
end
xbounds = zeros(Float64,size(xall, 1), 2)
for dim in 1:size(xall, 1)
    xbounds[dim,:] = [minimum(xall[dim,:]), maximum(xall[dim,:])]
end
## Initialize a model using these options
Random.seed!(12)
optlog10λ = transD_GP.OptionsStat(nmin = nminlog10λ,
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
                        timesλ = 3,
                        )
@time  log10λ = transD_GP.init(optlog10λ)
## make options for the nonstationary GP
nmin, nmax = 2, 200
fbounds = [-2. 2]
δ = 0.1
sdev_prop = [0.1]
sdev_pos = [0.05, 0.05]
K = transD_GP.GP.Mat32()
demean_ns = true
## Initialize model for the nonstationary GP - but we won't be using it
Random.seed!(13)
opt = transD_GP.OptionsNonstat(optlog10λ,
                        nmin = nmin,
                        nmax = nmax,
                        fbounds = fbounds,
                        δ = δ,
                        demean = demean_ns,
                        sdev_prop = sdev_prop,
                        sdev_pos = sdev_pos,
                        pnorm = pnorm,
                        K = K
                        )
@time m = transD_GP.init(opt, log10λ)
## run tests for the different McMC moves
@testset "GP and MCMC move do and undo state tests" begin
    @testset "init test" begin
        ftest = transD_GP.testupdate(optlog10λ, log10λ)
        @test norm(mean(ftest' - log10λ.fstar)) < 1e-12
    end
    @testset "birth tests" begin
        for i = 1:50
            transD_GP.birth!(log10λ, optlog10λ, m, opt)
        end
        ftest = transD_GP.testupdate(optlog10λ, log10λ)
        @test norm(mean(ftest' - log10λ.fstar)) < 1e-12
    end
    @testset "death tests" begin
        for i = 1:20
            transD_GP.death!(log10λ, optlog10λ, m, opt)
        end
        ftest = transD_GP.testupdate(optlog10λ, log10λ)
        @test norm(mean(ftest' - log10λ.fstar)) < 1e-12
    end
    # birth and death hold correct states if tests above passed
    @testset "undo birth" begin
        log10λold = deepcopy(log10λ)
        transD_GP.birth!(log10λ, optlog10λ, m, opt)
        transD_GP.undo_birth!(log10λ, m)
        transD_GP.sync_model!(log10λ, optlog10λ)
        ftest = transD_GP.testupdate(optlog10λ, log10λ)
        @test norm(mean(log10λold.fstar - log10λ.fstar)) < 1e-12
    end
    # undo_birth holds state if gotten till here
    @testset "undo multiple birth" begin
        transD_GP.birth!(log10λ, optlog10λ, m, opt)
        transD_GP.birth!(log10λ, optlog10λ, m, opt)
        log10λold = deepcopy(log10λ)
        transD_GP.birth!(log10λ, optlog10λ, m, opt)
        transD_GP.undo_birth!(log10λ, m)
        transD_GP.sync_model!(log10λ, optlog10λ)
        ftest = transD_GP.testupdate(optlog10λ, log10λ)
        @test norm(mean(ftest' - log10λ.fstar)) < 1e-12
        @test norm(mean(log10λold.fstar - log10λ.fstar)) < 1e-12
    end
    # undo_birth holds state as well for multiple births and deaths till here
    @testset "undo death" begin
        log10λold = deepcopy(log10λ)
        transD_GP.death!(log10λ, optlog10λ, m, opt)
        transD_GP.undo_death!(log10λ, optlog10λ, m)
        transD_GP.sync_model!(log10λ, optlog10λ)
        ftest = transD_GP.testupdate(optlog10λ, log10λ)
        @test norm(mean(ftest' - log10λ.fstar)) < 1e-12
        @test norm(mean(log10λold.fstar - log10λ.fstar)) < 1e-12
    end
    # undo death holds state if here
    @testset "undo multiple death" begin
        transD_GP.birth!(log10λ, optlog10λ, m, opt)
        transD_GP.birth!(log10λ, optlog10λ, m, opt)
        transD_GP.birth!(log10λ, optlog10λ, m, opt)
        log10λold = deepcopy(log10λ)
        transD_GP.death!(log10λ, optlog10λ, m, opt)
        transD_GP.undo_death!(log10λ, optlog10λ, m)
        transD_GP.sync_model!(log10λ, optlog10λ)
        ftest = transD_GP.testupdate(optlog10λ, log10λ)
        @test norm(mean(ftest' - log10λ.fstar)) < 1e-12
        @test norm(mean(log10λold.fstar - log10λ.fstar)) < 1e-12
    end
    # undo_death holds state as well for multiple births and deaths till here
    @testset "property change" begin
        transD_GP.property_change!(log10λ, optlog10λ, m, opt)
        ftest = transD_GP.testupdate(optlog10λ, log10λ)
        @test norm(mean(ftest' - log10λ.fstar)) < 1e-12
    end
    # property change works if here
    @testset "undo property change" begin
        log10λold = deepcopy(log10λ)
        transD_GP.property_change!(log10λ, optlog10λ, m, opt)
        transD_GP.undo_property_change!(log10λ, optlog10λ, m)
        transD_GP.sync_model!(log10λ, optlog10λ)
        ftest = transD_GP.testupdate(optlog10λ, log10λ)
        @test norm(mean(ftest' - log10λ.fstar)) < 1e-12
        @test norm(mean(log10λold.fstar - log10λ.fstar)) < 1e-12
    end
    # undo property change works if here
    @testset "position change" begin
        transD_GP.position_change!(log10λ, optlog10λ, m, opt)
        ftest = transD_GP.testupdate(optlog10λ, log10λ)
        @test norm(mean(ftest' - log10λ.fstar)) < 1e-12
    end
    # position change works if here
    @testset "undo position change" begin
        log10λold = deepcopy(log10λ)
        transD_GP.position_change!(log10λ, optlog10λ, m, opt)
        transD_GP.undo_position_change!(log10λ, optlog10λ, m)
        transD_GP.sync_model!(log10λ, optlog10λ)
        ftest = transD_GP.testupdate(optlog10λ, log10λ)
        @test norm(mean(ftest' - log10λ.fstar)) < 1e-12
        @test norm(mean(log10λold.fstar - log10λ.fstar)) < 1e-12
    end
    # undo position change works if here
end
# ## timing for birth
# m = transD_GP.init(opt, log10λ)
# log10λ = transD_GP.init(optlog10λ)
# @time for i = 1:148
#           transD_GP.birth!(log10λ, optlog10λ, m, opt)
# end
# ## timing for many births
# NTIMES = 20
# ntimes = 150
# T = zeros(NTIMES)
# for I = 1:NTIMES
#     T[I] = time()
#     for i = 1:ntimes
#         transD_GP.death!(log10λ, optlog10λ, m, opt)
#         transD_GP.birth!(log10λ, optlog10λ, m, opt)
#     end
#     T[I] = (time() - T[I])/2ntimes
# end
# @info "time for $ntimes birth/death is $(mean(T)) +- $(std(T)/sqrt(NTIMES))"
# ## plot
# l = log10λ.fstar
# fig,ax = plt.subplots(1,2, sharex=true, sharey=true)
# vmin, vmax = minimum(l[1,:]), maximum(l[1,:])
# im1 = ax[1].imshow(reshape(l[1,:],length(x), length(y)), extent=[y[1],y[end],x[end],x[1]],
#     vmin=vmin, vmax=vmax)
# colorbar(im1, ax=ax[1])
# ax[1].scatter(log10λ.xtrain[2,1:log10λ.n], log10λ.xtrain[1,1:log10λ.n], marker="+",c="r")
# ax[1].scatter(log10λ.xtrain[2,1:log10λ.n], log10λ.xtrain[1,1:log10λ.n], c=log10λ.ftrain[1,1:log10λ.n], alpha=0.8)
# vmin, vmax = minimum(l[2,:]), maximum(l[2,:])
# im2 = ax[2].imshow(reshape(l[2,:],length(x), length(y)), extent=[y[1],y[end],x[end],x[1]],
#     vmin=vmin, vmax=vmax)
# colorbar(im2, ax=ax[2])
# ax[2].scatter(log10λ.xtrain[2,1:log10λ.n], log10λ.xtrain[1,1:log10λ.n], marker="+",c="r")
# ax[2].scatter(log10λ.xtrain[2,1:log10λ.n], log10λ.xtrain[1,1:log10λ.n], c=log10λ.ftrain[2,1:log10λ.n], alpha=0.8,
#     vmin=vmin, vmax=vmax)
# vmin, vmax = minimum(m.fstar), maximum(m.fstar)
