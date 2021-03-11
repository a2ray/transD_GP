using MPIClusterManagers, Distributed, DistributedArrays,
     PyPlot, LinearAlgebra, Formatting

struct Tpointer
    fp   :: IOStream
    fstr :: String
end

mutable struct Chain
    pid           :: Int
    npidsperchain :: Int
    T             :: Float64
    misfit        :: Float64
end

function Chain(nchains::Int;
               Tmax          = 2.5,
               nchainsatone  = 1,
              )

    @assert nchains > 1
    @assert Tmax > 1
    @assert mod(nworkers(), nchains) == 0

    npidsperchain = floor(Int, nworkers()/nchains)
    @info "npidsperchain = $npidsperchain"
    T = 10.0.^range(0, stop = log10(Tmax), length = nchains-nchainsatone+1)
    append!(T, ones(nchainsatone-1))
    chains = Array{Chain, 1}(undef, nchains)

    pid_end = 0
    for ichain in 1:nchains
        pid_start      = pid_end + 1
        pid_end        = pid_start + npidsperchain - 1
        pids           = workers()[pid_start:pid_end]

        chains[ichain] = Chain(pids[1], npidsperchain, T[ichain], 0.0)
    end
    chains
end

function Chain(chainprocs::Array{Int, 1};
               Tmax          = 2.5,
               nchainsatone  = 1)

    @assert Tmax > 1
    nchains = length(chainprocs)
    npidsperchain = floor(Int, length(chainprocs)/nchains)
    @info "npidsperchain = $npidsperchain"
    T = 10.0.^range(0, stop = log10(Tmax), length = nchains-nchainsatone+1)
    append!(T, ones(nchainsatone-1))
    chains = Array{Chain, 1}(undef, nchains)

    pid_end = 0
    for ichain in 1:nchains
        pid_start      = pid_end + 1
        pid_end        = pid_start + npidsperchain - 1
        pids           = chainprocs[pid_start:pid_end]

        chains[ichain] = Chain(pids[1], npidsperchain, T[ichain], 0.0)
    end
    chains
end

function mh_step!(mns::ModelNonstat, m::ModelStat,
    F::Operator, optns::OptionsNonstat, stat::Stats,
    Temp::Float64, movetype::Int, current_misfit::Array{Float64, 1})

    if optns.quasimultid
        new_misfit = get_misfit(mns, optns, movetype, F)
    else
        new_misfit = get_misfit(mns, optns, F)
    end
    logalpha = (current_misfit[1] - new_misfit)/Temp
    if log(rand()) < logalpha
        current_misfit[1] = new_misfit
        stat.accepted_moves[movetype] += 1
    else
        undo_move!(movetype, mns, optns, m)
    end
end

function mh_step!(m::ModelStat, mns::ModelNonstat, F::Operator,
    opt::OptionsStat, optns::OptionsNonstat,
    stat::Stats, Temp::Float64, movetype::Int, current_misfit::Array{Float64, 1})

    if opt.quasimultid
        if opt.updatenonstat
            new_misfit = get_misfit(mns, opt, movetype, F)
        else
            new_misfit = get_misfit(m, opt, movetype, F)
        end
    else
        if opt.updatenonstat
            new_misfit = get_misfit(mns, opt, F)
        else
            new_misfit = get_misfit(m, opt, F)
        end
    end
    logalpha = (current_misfit[1] - new_misfit)/Temp
    if log(rand()) < logalpha
        current_misfit[1] = new_misfit
        stat.accepted_moves[movetype] += 1
    else
        undo_move!(movetype, m, opt, mns, optns)
    end
end

function do_mcmc_step(m::ModelStat, mns::ModelNonstat,
    opt::OptionsStat, optns::OptionsNonstat,
    stat::Stats,
    current_misfit::Array{Float64, 1}, F::Operator,
    Temp::Float64, isample::Int, wp::Writepointers)

    # select move and do it
    movetype, priorviolate = do_move!(m, opt, stat, mns, optns)

    if !priorviolate
        mh_step!(m, mns, F, opt, optns, stat, Temp, movetype, current_misfit)
    end

    # acceptance stats
    get_acceptance_stats!(isample, opt, stat)

    # write models
    writemodel = false
    abs(Temp-1.0) < 1e-12 && (writemodel = true)
    write_history(isample, opt, m, current_misfit[1], stat, wp, Temp, writemodel)

    return current_misfit[1]
end

function do_mcmc_step(m::DArray{ModelStat}, mns::DArray{ModelNonstat},
    opt::DArray{OptionsStat}, optns::DArray{OptionsNonstat},
    stat::DArray{Stats}, current_misfit::DArray{Array{Float64, 1}},
    F::DArray{x}, Temp::Float64, isample::Int,
    wp::DArray{Writepointers}) where x<:Operator

    misfit = do_mcmc_step(localpart(m)[1], localpart(mns)[1], localpart(opt)[1],
                        localpart(optns)[1], localpart(stat)[1],
                          localpart(current_misfit)[1], localpart(F)[1],
                            Temp, isample, localpart(wp)[1])

end

function do_mcmc_step(mns::ModelNonstat, m::ModelStat,
    optns::OptionsNonstat, statns::Stats,
    current_misfit::Array{Float64, 1}, F::Operator,
    Temp::Float64, isample::Int, wp::Writepointers)

    # select move and do it
    movetype, priorviolate = do_move!(mns, m, optns, statns)

    if !priorviolate
        mh_step!(mns, m, F, optns, statns, Temp, movetype, current_misfit)
    end

    # acceptance stats
    get_acceptance_stats!(isample, optns, statns)

    # write models
    writemodel = false
    abs(Temp-1.0) < 1e-12 && (writemodel = true)
    write_history(isample, optns, mns, current_misfit[1], statns, wp, Temp, writemodel)

    return current_misfit[1]
end

function do_mcmc_step(mns::DArray{ModelNonstat}, m::DArray{ModelStat},
    optns::DArray{OptionsNonstat}, statns::DArray{Stats},
    current_misfit::DArray{Array{Float64, 1}},
    F::DArray{x}, Temp::Float64, isample::Int,
    wpns::DArray{Writepointers}) where x<:Operator

    misfit = do_mcmc_step(localpart(mns)[1], localpart(m)[1], localpart(optns)[1],
                         localpart(statns)[1],
                          localpart(current_misfit)[1], localpart(F)[1],
                            Temp, isample, localpart(wpns)[1])

end

function close_history(wp::DArray)
    @sync for (idx, pid) in enumerate(procs(wp))
        @spawnat pid close_history(wp[idx])
    end
end

function open_temperature_file(opt_in::Options, nchains::Int)
    fdataname = opt_in.costs_filename[9:end-4]
    fp_temps  = open(fdataname*"_temps.txt", opt_in.history_mode)
    fmt = "{:d} "
    for i = 1:nchains-1
        fmt = fmt*"{:f} "
    end
    fmt = fmt*"{:f}"
    tpointer = Tpointer(fp_temps, fmt)
end

function write_temperatures(iter::Int, chains::Array{Chain, 1}, tpointer::Tpointer, opt_in::Options)
    if (mod(iter-1, opt_in.save_freq) == 0 || iter == 1)
        printfmtln(tpointer.fp, tpointer.fstr, iter, (getproperty.(chains,:T))...)
        flush(tpointer.fp)
    end
end

function close_temperature_file(fp::IOStream)
    close(fp)
end

function init_chain_darrays(opt_in::OptionsStat,
                            optns_in::OptionsNonstat,
                            F_in::Operator, chains::Array{Chain, 1})
    m_, mns_, opt_, optns_, F_in_, stat_, statns_, d_in_,
    current_misfit_, wp_, wpns_  = map(x -> Array{Future, 1}(undef, length(chains)), 1:11)

    costs_filename = "misfits_"*opt_in.fdataname
    fstar_filename = "models_"*opt_in.fdataname
    x_ftrain_filename = "points_"*opt_in.fdataname

    iterlast = 0
    @sync for(idx, chain) in enumerate(chains)

        opt_in.costs_filename      = costs_filename*"s_$idx.bin"
        optns_in.costs_filename    = costs_filename*"ns_$idx.bin"
        opt_in.fstar_filename      = fstar_filename*"s_$idx.bin"
        optns_in.fstar_filename    = fstar_filename*"ns_$idx.bin"
        opt_in.x_ftrain_filename   = x_ftrain_filename*"s_$idx.bin"
        optns_in.x_ftrain_filename = x_ftrain_filename*"ns_$idx.bin"

        opt_[idx]            = @spawnat chain.pid [opt_in]
        optns_[idx]          = @spawnat chain.pid [optns_in]

        m_[idx]                = @spawnat chain.pid [init(opt_in)]
        mns_[idx]              = @spawnat chain.pid [init(optns_in,
                                                            fetch(m_[idx])[1])]

        @sync wp_[idx]             = @spawnat chain.pid [open_history(opt_in)]
        #@info "sending $(optns_in.costs_filename)"
        @sync wpns_[idx]           = @spawnat chain.pid [open_history(optns_in)]

        stat_[idx]           = @spawnat chain.pid [Stats()]
        statns_[idx]         = @spawnat chain.pid [Stats()]

        F_in_[idx]           = @spawnat chain.pid [F_in]
        if opt_in.updatenonstat
            current_misfit_[idx] = @spawnat chain.pid [[ get_misfit(fetch(mns_[idx])[1],
                                               fetch(optns_[idx])[1],
                                               fetch(F_in_[idx])[1]) ]]
        else
            current_misfit_[idx] = @spawnat chain.pid [[ get_misfit(fetch(m_[idx])[1],
                                               fetch(opt_[idx])[1],
                                               fetch(F_in_[idx])[1]) ]]
        end
        if opt_in.history_mode=="a"
            if idx == length(chains)
                iterlast = history(opt_in, stat=:iter)[end]
            end
            chains[idx].T = history(opt_in, stat=:T)[end]
        end
    end
    m, mns, opt, optns, stat, statns, F,
    current_misfit, wp, wpns = map(x -> DArray(x), (m_, mns_, opt_, optns_,
                                    stat_, statns_, F_in_, current_misfit_,
                                    wp_, wpns_))

    return m, mns, opt, optns, stat, statns, F, current_misfit,
            wp, wpns, iterlast
end

function init_chain_darrays(opt_in::OptionsStat,
                            optns_in::OptionsNonstat,
                            F_in::Operator, chains::Array{Chain, 1},
                            manager::MPIManager)
    m_, mns_, opt_, optns_, F_in_, stat_, statns_, d_in_,
    current_misfit_, wp_, wpns_  = map(x -> Array{Future, 1}(undef, length(chains)), 1:11)

    costs_filename = "misfits_"*opt_in.fdataname
    fstar_filename = "models_"*opt_in.fdataname
    x_ftrain_filename = "points_"*opt_in.fdataname

    iterlast = 0
    @sync for(idx, chain) in enumerate(chains)

        opt_in.costs_filename      = costs_filename*"s_$idx.bin"
        optns_in.costs_filename    = costs_filename*"ns_$idx.bin"
        opt_in.fstar_filename      = fstar_filename*"s_$idx.bin"
        optns_in.fstar_filename    = fstar_filename*"ns_$idx.bin"
        opt_in.x_ftrain_filename   = x_ftrain_filename*"s_$idx.bin"
        optns_in.x_ftrain_filename = x_ftrain_filename*"ns_$idx.bin"

        opt_[idx]            = @spawnat chain.pid [opt_in]
        optns_[idx]          = @spawnat chain.pid [optns_in]

        m_[idx]                = @spawnat chain.pid [init(opt_in)]
        mns_[idx]              = @spawnat chain.pid [init(optns_in,
                                                            fetch(m_[idx])[1])]

        @sync wp_[idx]             = @spawnat chain.pid [open_history(opt_in)]
        #@info "sending $(optns_in.costs_filename)"
        @sync wpns_[idx]           = @spawnat chain.pid [open_history(optns_in)]

        stat_[idx]           = @spawnat chain.pid [Stats()]
        statns_[idx]         = @spawnat chain.pid [Stats()]

        F_in_[idx]           = @spawnat chain.pid [F_in]
        if opt_in.updatenonstat
            println("before forward call...")
            @mpi_do manager begin
                response, current_misfit_[idx] = m2d_fwd(nprocperchain,M2d)
            end
            println("after forward call!")
        else
            println("before forward call...")
            @mpi_do manager begin
                response, current_misfit_[idx] = m2d_fwd(nprocsperchain,M2d)
            end
            println("after forward call!")
        end
        if opt_in.history_mode=="a"
            if idx == length(chains)
                iterlast = history(opt_in, stat=:iter)[end]
            end
            chains[idx].T = history(opt_in, stat=:T)[end]
        end
    end
    m, mns, opt, optns, stat, statns, F,
    current_misfit, wp, wpns = map(x -> DArray(x), (m_, mns_, opt_, optns_,
                                    stat_, statns_, F_in_, current_misfit_,
                                    wp_, wpns_))

    return m, mns, opt, optns, stat, statns, F, current_misfit,
            wp, wpns, iterlast
end

function swap_temps(chains::Array{Chain, 1})
    for ichain in length(chains):-1:2
        jchain = rand(1:ichain)
        if ichain != jchain
            logalpha = (chains[ichain].misfit - chains[jchain].misfit) *
                            (1.0/chains[ichain].T - 1.0/chains[jchain].T)
            if log(rand()) < logalpha
                chains[ichain].T, chains[jchain].T = chains[jchain].T, chains[ichain].T
            end
        end
    end

end

function main(opt_in       ::OptionsStat,
              optns_in     ::OptionsNonstat,
              F_in         ::Operator;
              nsamples     = 4001,
              nchains      = 1,
              nchainsatone = 1,
              Tmax         = 2.5)

    chains = Chain(nchains, Tmax=Tmax, nchainsatone=nchainsatone)
    m, mns, opt, optns, stat, statns,
    F, current_misfit, wp, wpns, iterlast = init_chain_darrays(opt_in,
                                                optns_in, F_in, chains)

    domcmciters(iterlast, nsamples, chains, opt_in, mns, m, optns, opt,
                statns, stat, current_misfit, F, wpns, wp)

    close_history(wp)
    close_history(wpns)
    nothing
end

function main(opt_in       ::OptionsStat,
              optns_in     ::OptionsNonstat,
              F_in         ::Operator;
              nsamples     = 4001,
              nchains      = 1,
              nchainsatone = 1,
              Tmax         = 2.5,
              m2d_flag     = true,
              manager      ::MPIManager)

    println("it's true! m2d_flag is $(m2d_flag)! We're in the right 'main'! :)")
    println("type of manager: $(typeof(manager))")

    @mpi_do manager println("Hi there!")

    chains = Chain(nchains, Tmax=Tmax, nchainsatone=nchainsatone)
    m, mns, opt, optns, stat, statns,
    F, current_misfit, wp, wpns, iterlast = init_chain_darrays(opt_in,
                                                optns_in, F_in, chains, manager)

    domcmciters(iterlast, nsamples, chains, opt_in, mns, m, optns, opt,
                statns, stat, current_misfit, F, wpns, wp)

    close_history(wp)
    close_history(wpns)
    nothing
end

function main(opt_in       ::OptionsStat,
              optns_in     ::OptionsNonstat,
              F_in         ::Operator,
              chainprocs   ::Array{Int, 1};
              nsamples     = 4001,
              nchainsatone = 1,
              Tmax         = 2.5)

    chains = Chain(chainprocs, Tmax=Tmax)
    m, mns, opt, optns, stat, statns,
    F, current_misfit, wp, wpns, iterlast = init_chain_darrays(opt_in,
                                                optns_in, F_in, chains)

    domcmciters(iterlast, nsamples, chains, opt_in, mns, m, optns, opt,
                statns, stat, current_misfit, F, wpns, wp)

    close_history(wp)
    close_history(wpns)
    nothing
end

function domcmciters(iterlast, nsamples, chains, opt_in, mns, m, optns, opt,
            statns, stat, current_misfit, F, wpns, wp)
    t2 = time()
    for isample = iterlast+1:iterlast+nsamples

        swap_temps(chains)
        if opt_in.updatenonstat
            @sync for(ichain, chain) in enumerate(chains)
                @async chain.misfit = remotecall_fetch(do_mcmc_step, chain.pid,
                                                mns, m, optns, statns,
                                                current_misfit, F,
                                                chain.T, isample, wpns)
            end
        end
        @sync for(ichain, chain) in enumerate(chains)
            @async chain.misfit = remotecall_fetch(do_mcmc_step, chain.pid,
                                            m, mns, opt, optns, stat,
                                            current_misfit, F,
                                            chain.T, isample, wp)
        end
        if mod(isample-1, 1000) == 0
            dt = time() - t2 #seconds
            t2 = time()
            @info("*****$dt**sec*****")
        end
    end
end
