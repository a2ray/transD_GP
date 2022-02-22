using Distributed, DistributedArrays,
     PyPlot, LinearAlgebra, Formatting, Dates

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
    Chains(workers(), Tmax=Tmax, nchainsatone=nchainsatone)
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

function accept(current_misfit, new_misfit, stat, Temp, movetype) 
    logalpha = (current_misfit[1] - new_misfit)/Temp
    accepted = true
    if log(rand()) < logalpha
        current_misfit[1] = new_misfit
        stat.accepted_moves[movetype] += 1
    else
        accepted = false
    end
    accepted
end

function mh_step!(m::ModelStat, mn::ModelNuisance,
    F::Operator, opt::OptionsStat, stat::Stats,
    Temp::Float64, movetype::Int, current_misfit::Array{Float64, 1})
    # for purely stat move and nuisance
    new_misfit = get_misfit(m, mn, opt, F)
    accepted = accept(current_misfit, new_misfit, stat, Temp, movetype)
    !accepted && undo_move!(movetype, m, opt)
end

function mh_step!(mns::ModelNonstat, m::ModelStat, mn::ModelNuisance,
    F::Operator, optns::OptionsNonstat, stat::Stats,
    Temp::Float64, movetype::Int, current_misfit::Array{Float64, 1})
    # for nonstat move and nuisance
    new_misfit = get_misfit(mns, mn, optns, F)
    accepted = accept(current_misfit, new_misfit, stat, Temp, movetype)
    !accepted && undo_move!(movetype, mns, optns, m)
end

function mh_step!(m::ModelStat, mns::ModelNonstat, mn::ModelNuisance,
    F::Operator, opt::OptionsStat, optns::OptionsNonstat,
    stat::Stats, Temp::Float64, movetype::Int, current_misfit::Array{Float64, 1})
    # for stat move updating nonstat and nuisance
    new_misfit = get_misfit(mns, mn, opt, F)
    accepted = accept(current_misfit, new_misfit, stat, Temp, movetype)
    !accepted && undo_move!(movetype, m, opt, mns, optns)
end

function mh_step!(mn::ModelNuisance, m::Model, F::Operator,
    optn::OptionsNuisance, statn::Stats,
    Temp::Float64, movetype::Int, current_misfit::Array{Float64,1})
    # this only gets called for moves on the nuisance chain
    # can be either nonstat or stat
    new_misfit = get_misfit(m, mn, optn, F)
    accepted = accept(current_misfit, new_misfit, statn, Temp, movetype)
    !accepted && undo_move!(mn)
end

function mh_step!(m::ModelStat, F::Operator, opt::OptionsStat, stat::Stats,
    Temp::Float64, movetype::Int, current_misfit::Array{Float64, 1})
    # for purely stat move
    new_misfit = get_misfit(m, opt, F)
    accepted = accept(current_misfit, new_misfit, stat, Temp, movetype)
    !accepted && undo_move!(movetype, m, opt)
end

function mh_step!(mns::ModelNonstat, m::ModelStat, 
    F::Operator, optns::OptionsNonstat, statns::Stats,
    Temp::Float64, movetype::Int, current_misfit::Array{Float64, 1})
    # for purely nonstat move 
    new_misfit = get_misfit(mns, optns, F)
    accepted = accept(current_misfit, new_misfit, statns, Temp, movetype)
    !accepted && undo_move!(movetype, mns, optns, m)
end

function mh_step!(m::ModelStat, mns::ModelNonstat,
    F::Operator, opt::OptionsStat, optns::OptionsNonstat,
    stat::Stats, Temp::Float64, movetype::Int, current_misfit::Array{Float64, 1})
    # for stat move updating nonstat
    new_misfit = get_misfit(mns, optns, F)
    accepted = accept(current_misfit, new_misfit, stat, Temp, movetype)
    !accepted && undo_move!(movetype, m, opt, mns, optns)
end

function do_mcmc_step(m::ModelStat, mns::ModelNonstat, mn::ModelNuisance,
    opt::OptionsStat, optns::OptionsNonstat, stat::Stats,
    current_misfit::Array{Float64, 1}, F::Operator,
    Temp::Float64, isample::Int, wp::Writepointers)
    # Stationary GP changes which update nonstationary GP + nuisance
    movetype, priorviolate = do_move!(m, opt, stat, mns, optns)
    if !priorviolate
        mh_step!(m, mns, mn, F, opt, optns, stat, Temp, movetype, current_misfit)
    end
    get_acceptance_stats!(isample, opt, stat)
    writemodel = false
    abs(Temp-1.0) < 1e-12 && (writemodel = true)
    write_history(isample, opt, m, current_misfit[1], stat, wp, Temp, writemodel)
    return current_misfit[1]
end

function do_mcmc_step(m::DArray{ModelStat}, mns::DArray{ModelNonstat},
    mn::DArray{ModelNuisance}, opt::DArray{OptionsStat}, 
    optns::DArray{OptionsNonstat}, stat::DArray{Stats}, 
    current_misfit::DArray{Array{Float64, 1}}, F::DArray{x}, Temp::Float64, 
    isample::Int, wp::DArray{Writepointers}) where x<:Operator
    misfit = do_mcmc_step(localpart(m)[1], localpart(mns)[1], localpart(mn)[1],
        localpart(opt)[1], localpart(optns)[1], localpart(stat)[1], 
        localpart(current_misfit)[1], localpart(F)[1],
        Temp, isample, localpart(wp)[1])
end

function do_mcmc_step(mns::ModelNonstat, m::ModelStat, mn::ModelNuisance,
    optns::OptionsNonstat, statns::Stats, current_misfit::Array{Float64, 1},
    F::Operator, Temp::Float64, isample::Int, wp::Writepointers)
    # purely nonstationary GP moves + nuisance
    movetype, priorviolate = do_move!(mns, m, optns, statns)
    if !priorviolate
        mh_step!(mns, m, mn, F, optns, statns, Temp, movetype, current_misfit)
    end
    get_acceptance_stats!(isample, optns, statns)
    writemodel = false
    abs(Temp-1.0) < 1e-12 && (writemodel = true)
    write_history(isample, optns, mns, current_misfit[1], statns, wp, Temp, writemodel)
    return current_misfit[1]
end

function do_mcmc_step(mns::DArray{ModelNonstat}, m::DArray{ModelStat},
    mn::DArray{ModelNuisance}, optns::DArray{OptionsNonstat}, statns::DArray{Stats},
    current_misfit::DArray{Array{Float64, 1}}, F::DArray{x}, Temp::Float64, 
    isample::Int, wpns::DArray{Writepointers}) where x<:Operator
    misfit = do_mcmc_step(localpart(mns)[1], localpart(m)[1], localpart(mn)[1],
        localpart(optns)[1], localpart(statns)[1],localpart(current_misfit)[1], 
        localpart(F)[1], Temp, isample, localpart(wpns)[1])
end

function do_mcmc_step(m::ModelStat, mn::ModelNuisance,
    opt::OptionsStat, stat::Stats, current_misfit::Array{Float64, 1},
    F::Operator, Temp::Float64, isample::Int, wp::Writepointers)
    # purely stationary GP moves + nuisance
    movetype, priorviolate = do_move!(m, opt, stat)
    if !priorviolate
        mh_step!(m, mn, F, opt, stat, Temp, movetype, current_misfit)
    end
    get_acceptance_stats!(isample, optns, statns)
    writemodel = false
    abs(Temp-1.0) < 1e-12 && (writemodel = true)
    write_history(isample, opt, m, current_misfit[1], stat, wp, Temp, writemodel)
    return current_misfit[1]
end

function do_mcmc_step(m::DArray{ModelStat}, mn::DArray{ModelNuisance}, 
    opt::DArray{OptionsStat}, stat::DArray{Stats},
    current_misfit::DArray{Array{Float64, 1}}, F::DArray{x}, Temp::Float64, 
    isample::Int, wp::DArray{Writepointers}) where x<:Operator
    misfit = do_mcmc_step(localpart(m)[1], localpart(mn)[1],
        localpart(opt)[1], localpart(stat)[1],localpart(current_misfit)[1], 
        localpart(F)[1], Temp, isample, localpart(wp)[1])
end

function do_mcmc_step(mn::ModelNuisance, m::Model,
    optn::OptionsNuisance, statn::Stats, current_misfit::Array{Float64,1},
    F::Operator, Temp::Float64, isample::Int, wpn::Writepointers_nuisance)
    # this only gets called for moves on the nuisance chain
    # can be either nonstat or stat model
    movetype = do_move!(mn, optn, statn)
    mh_step!(mn, m, F, optn, statn, Temp, movetype, current_misfit)
    get_acceptance_stats!(isample, optn, statn)
    writemodel = false
    abs(Temp - 1.0) < 1e-12 && (writemodel = true)
    write_history(isample, optn, mn, current_misfit[1], statn, wpn, Temp, writemodel)
    return current_misfit[1]
end

function do_mcmc_step(mn::DArray{ModelNuisance}, m::DArray{S}, 
    optn::DArray{OptionsNuisance}, statn::DArray{Stats},
    current_misfit::DArray{Array{Float64, 1}},
    F::DArray{x}, Temp::Float64, isample::Int,
    wpn::DArray{Writepointers_nuisance}) where {x<:Operator, S<:Model}
    misfit = do_mcmc_step(localpart(mn)[1], localpart(m)[1], 
            localpart(optn)[1], localpart(statn)[1], localpart(current_misfit)[1],
            localpart(F)[1], localpart(Temp)[1], localpart(isample)[1], localpart(wpn)[1])
end

function do_mcmc_step(m::ModelStat, mns::ModelNonstat, 
    opt::OptionsStat, optns::OptionsNonstat, stat::Stats,
    current_misfit::Array{Float64, 1}, F::Operator,
    Temp::Float64, isample::Int, wp::Writepointers)
    # Stationary GP changes which update nonstationary GP
    movetype, priorviolate = do_move!(m, opt, stat, mns, optns)
    if !priorviolate
        mh_step!(m, mns, F, opt, optns, stat, Temp, movetype, current_misfit)
    end
    get_acceptance_stats!(isample, opt, stat)
    writemodel = false
    abs(Temp-1.0) < 1e-12 && (writemodel = true)
    write_history(isample, opt, m, current_misfit[1], stat, wp, Temp, writemodel)
    return current_misfit[1]
end

function do_mcmc_step(m::DArray{ModelStat}, mn::DArray{ModelNuisance}, opt::DArray{OptionsStat}, 
    optns::DArray{OptionsNonstat}, stat::DArray{Stats}, 
    current_misfit::DArray{Array{Float64, 1}}, F::DArray{x}, Temp::Float64, 
    isample::Int, wp::DArray{Writepointers}) where x<:Operator
    misfit = do_mcmc_step(localpart(m)[1], localpart(mn)[1],
        localpart(opt)[1], localpart(optns)[1], localpart(stat)[1], 
        localpart(current_misfit)[1], localpart(F)[1],
        Temp, isample, localpart(wp)[1])
end

function do_mcmc_step(mns::ModelNonstat, m::ModelStat, 
    optns::OptionsNonstat, statns::Stats, current_misfit::Array{Float64, 1},
    F::Operator, Temp::Float64, isample::Int, wpns::Writepointers)
    # purely nonstationary GP moves 
    movetype, priorviolate = do_move!(mns, m, optns, statns)
    if !priorviolate
        mh_step!(mns, m, F, optns, statns, Temp, movetype, current_misfit)
    end
    get_acceptance_stats!(isample, optns, statns)
    writemodel = false
    abs(Temp-1.0) < 1e-12 && (writemodel = true)
    write_history(isample, optns, mns, current_misfit[1], statns, wpns, Temp, writemodel)
    return current_misfit[1]
end

function do_mcmc_step(mns::DArray{ModelNonstat}, m::DArray{ModelStat},
    optns::DArray{OptionsNonstat}, statns::DArray{Stats},
    current_misfit::DArray{Array{Float64, 1}}, F::DArray{x}, Temp::Float64, 
    isample::Int, wpns::DArray{Writepointers}) where x<:Operator
    misfit = do_mcmc_step(localpart(mns)[1], localpart(m)[1], 
        localpart(optns)[1], localpart(statns)[1],localpart(current_misfit)[1], 
        localpart(F)[1], Temp, isample, localpart(wpns)[1])
end

function do_mcmc_step(m::ModelStat, opt::OptionsStat, stat::Stats, current_misfit::Array{Float64, 1},
    F::Operator, Temp::Float64, isample::Int, wp::Writepointers)
    # purely stationary GP moves
    movetype, priorviolate = do_move!(m, opt, stat)
    if !priorviolate
        mh_step!(m, F, opt, stat, Temp, movetype, current_misfit)
    end
    get_acceptance_stats!(isample, opt, stat)
    writemodel = false
    abs(Temp-1.0) < 1e-12 && (writemodel = true)
    write_history(isample, opt, m, current_misfit[1], stat, wp, Temp, writemodel)
    return current_misfit[1]
end

function do_mcmc_step(m::DArray{ModelStat}, opt::DArray{OptionsStat}, stat::DArray{Stats},
    current_misfit::DArray{Array{Float64, 1}}, F::DArray{x}, Temp::Float64, 
    isample::Int, wp::DArray{Writepointers}) where x<:Operator
    misfit = do_mcmc_step(localpart(m)[1], localpart(opt)[1], 
        localpart(stat)[1],localpart(current_misfit)[1], 
        localpart(F)[1], Temp, isample, localpart(wp)[1])
end

function close_history(wp::DArray)
    for (idx, pid) in enumerate(procs(wp))
        @sync @spawnat pid close_history(wp[idx])
    end
end

function close_temperature_file(fp::IOStream)
    close(fp)
end

function makewritefilenames(opt_in)
    costs_filename = "misfits_"*opt_in.fdataname
    fstar_filename = "models_"*opt_in.fdataname
    x_ftrain_filename = "points_"*opt_in.fdataname
    nu_filename = "values_nuisance_"*opt_in.fdataname
    costs_filename, fstar_filename, x_ftrain_filename, nu_filename
end

function makestatfilenames(opt_in::OptionsStat)
    costs_filename, fstar_filename, x_ftrain_filename, = makewritefilenames(opt)
    opt_in.costs_filename      = costs_filename*"s_$idx.bin"
    opt_in.fstar_filename      = fstar_filename*"s_$idx.bin"
    opt_in.x_ftrain_filename   = x_ftrain_filename*"s_$idx.bin"
end    

function makenonstatfilenames(optns_in::OptionsNonstat)
    costs_filename, fstar_filename, x_ftrain_filename, = makewritefilenames(opt)
    optns_in.costs_filename    = costs_filename*"ns_$idx.bin"
    optns_in.fstar_filename    = fstar_filename*"ns_$idx.bin"
    optns_in.x_ftrain_filename = x_ftrain_filename*"ns_$idx.bin"
end

function makenuisancefilenames(optn_in::OptionsNuisance)
    costs_filename, fstar_filename, x_ftrain_filename, nu_filename = makewritefilenames(opt)
    optn_in.costs_filename     = costs_filename*"nuisance_$idx.bin"
    optn_in.vals_filename      = nu_filename*"$idx.bin"
end

function init_chain_darrays(opt_in::OptionsStat,
                            optns_in::OptionsNonstat,
                            optn_in::OptionsNuisance,
                            F_in::Operator, chains::Array{Chain, 1})
    # for nonstat, stat, and nuisances all together                        
    
    m_, mns_, mn_, opt_, optns_, optn_, F_in_, stat_, statns_, statn_,
    current_misfit_, wp_, wpns_, wpn_  = map(x -> Array{Future, 1}(undef, length(chains)), 1:14)
    
    opt_in.history_mode == "a" && setrestartflag.([opt_in, optns_in, optn_in])
    
    iterlast = 0
    @sync for(idx, chain) in enumerate(chains)

        makestatfilenames(opt_in)
        makenonstatfilenames(optns_in)
        makenuisancefilenames(optn_in)

        opt_[idx]            = @spawnat chain.pid [opt_in]
        optns_[idx]          = @spawnat chain.pid [optns_in]
        optn_[idx]           = @spawnat chain.pid [optn_in]

        m_[idx]              = @spawnat chain.pid [init(opt_in)]
        mns_[idx]            = @spawnat chain.pid [init(optns_in, fetch(m_[idx])[1])]
        mn_[idx]             = @spawnat chain.pid [init(optn_in)]

        @sync wp_[idx]       = @spawnat chain.pid [open_history(opt_in)]
        @sync wpns_[idx]     = @spawnat chain.pid [open_history(optns_in)]
        @sync wpn_[idx]      = @spawnat chain.pid [open_history(optn_in)]

        stat_[idx]           = @spawnat chain.pid [Stats()]
        statns_[idx]         = @spawnat chain.pid [Stats()]
        statn_[idx]          = @spawnat chain.pid [Stats(nmoves=optn_in.nnu)]

        F_in_[idx]           = @spawnat chain.pid [F_in]

        current_misfit_[idx] = @spawnat chain.pid [[ get_misfit(fetch(mns_[idx])[1],
                                fetch(mn_[idx])[1],
                                fetch(optns_[idx])[1],
                                fetch(F_in_[idx])[1]) ]]

    m, mns, mn, opt, optns, optn, stat, statns, statn, F,
    current_misfit, wp, wpns, wpn = map(x -> DArray(x), (m_, mns_, mn_, opt_, optns_, optn_,
                                    stat_, statns_, statn_, F_in_, current_misfit_,
                                    wp_, wpns_, wpn_))
    @info "initialisation complete"
    return m, mns, mn, opt, optns, optn, stat, statns, statn, F, current_misfit,
            wp, wpns, wpn, iterlast
end

function domcmciters(iterlast, nsamples, chains, mns::ModelNonStat, m::ModelStat, 
            mn::ModelNuisance, optns::OptionsNonStat, opt::OptionsStat,
            optn::OptionsNuisance, statns, stat, statn, current_misfit, F, wpns, wp, wpn)
    # for nonstat, stat, and nuisances all together         
    
    t2 = time()
    for isample = iterlast+1:iterlast+nsamples
        # we do need each remotecall to finish before 
        # moving on to the next kind of move
        swap_temps(chains)
        @sync for chain in chains
            # purely nonstationary GP moves + nuisance
            @async chain.misfit = remotecall_fetch(do_mcmc_step, chain.pid,
                                            mns, m, mn, optns, statns,
                                            current_misfit, F,
                                            chain.T, isample, wpns)
        end
        @sync for chain in chains
            # purely nuisance move
            @async chain.misfit = remotecall_fetch(do_mcmc_step, chain.pid,
                                            mn, m, optn, statn,
                                            current_misfit, F,
                                            chain.T, isample, wpn)
        end
        @sync for chain in chains
            # Stationary GP changes which update nonstationary GP + nuisance
            @async chain.misfit = remotecall_fetch(do_mcmc_step, chain.pid,
                                            m, mns, mn, opt, optns, stat,
                                            current_misfit, F,
                                            chain.T, isample, wp)
        end
        disptime(isample, t2, iterlast, nsamples)
    end
end

function main(opt_in     ::OptionsStat,
            optns_in     ::OptionsNonstat,
            optn_in      ::OptionsNuisance,
            F_in         ::Operator,
            chainprocs   ::Array{Int, 1};
            nsamples     = 4001,
            nchainsatone = 1,
            Tmax         = 2.5)
    # for nonstat, stat, and nuisances all together 

    chains = Chain(chainprocs, nchainsatone=nchainsatone, Tmax=Tmax)

    m, mns, mn, opt, optns, optn, stat, 
    statns, statn, F, current_misfit, wp, wpns, wpn, 
    iterlast = init_chain_darrays(opt_in, optns_in, optn_in, F_in, chains)

    domcmciters(iterlast, nsamples, chains, mns, m, mn, optns, opt,
        optn, statns, stat, statn, current_misfit, F, wpns, wp, wpn)

    close_history.([wp, wpns, wpn])
    nothing
end

function init_chain_darrays(opt_in::OptionsStat,
                            optns_in::OptionsNonstat,
                            F_in::Operator, chains::Array{Chain, 1})
    # for nonstat and stat together                    
    
    m_, mns_, opt_, optns_, F_in_, stat_, statns_, 
    current_misfit_, wp_, wpns_,  = map(x -> Array{Future, 1}(undef, length(chains)), 1:10)
    
    opt_in.history_mode == "a" && setrestartflag.([opt_in, optns_in])
    
    iterlast = 0
    @sync for(idx, chain) in enumerate(chains)

        makestatfilenames(opt_in)
        makenonstatfilenames(optns_in)

        opt_[idx]            = @spawnat chain.pid [opt_in]
        optns_[idx]          = @spawnat chain.pid [optns_in]

        m_[idx]              = @spawnat chain.pid [init(opt_in)]
        mns_[idx]            = @spawnat chain.pid [init(optns_in, fetch(m_[idx])[1])]

        @sync wp_[idx]       = @spawnat chain.pid [open_history(opt_in)]
        @sync wpns_[idx]     = @spawnat chain.pid [open_history(optns_in)]

        stat_[idx]           = @spawnat chain.pid [Stats()]
        statns_[idx]         = @spawnat chain.pid [Stats()]

        F_in_[idx]           = @spawnat chain.pid [F_in]

        current_misfit_[idx] = @spawnat chain.pid [[ get_misfit(fetch(mns_[idx])[1],
                                fetch(optns_[idx])[1],
                                fetch(F_in_[idx])[1]) ]]

    m, mns, opt, optns, stat, statns, F,
    current_misfit, wp, wpns = map(x -> DArray(x), (m_, mns_, opt_, optns_, 
                                    stat_, statns_, F_in_, current_misfit_,
                                    wp_, wpns_))
    @info "initialisation complete"
    return m, mns, opt, optns, stat, statns, F, current_misfit,
            wp, wpns, iterlast
end

function domcmciters(iterlast, nsamples, chains, mns::ModelNonStat, m::ModelStat, 
            optns::OptionsNonStat, opt::OptionsStat, 
            statns, stat, current_misfit, F, wpns, wp)
    # for nonstat and stat together        
    
    t2 = time()
    for isample = iterlast+1:iterlast+nsamples
        # we do need each remotecall to finish before 
        # moving on to the next kind of move
        swap_temps(chains)
        @sync for chain in chains
            # purely nonstationary GP moves
            @async chain.misfit = remotecall_fetch(do_mcmc_step, chain.pid,
                                            mns, m, optns, statns,
                                            current_misfit, F,
                                            chain.T, isample, wpns)
        end
        @sync for chain in chains
            # Stationary GP changes which update nonstationary GP
            @async chain.misfit = remotecall_fetch(do_mcmc_step, chain.pid,
                                            m, mns, opt, optns, stat,
                                            current_misfit, F,
                                            chain.T, isample, wp)
        end
        disptime(isample, t2, iterlast, nsamples)
    end
end

function main(opt_in     ::OptionsStat,
            optns_in     ::OptionsNonstat,
            F_in         ::Operator,
            chainprocs   ::Array{Int, 1};
            nsamples     = 4001,
            nchainsatone = 1,
            Tmax         = 2.5)
    # for nonstat and stat together 

    chains = Chain(chainprocs, nchainsatone=nchainsatone, Tmax=Tmax)

    m, mns, opt, optns, stat, 
    statns, F, current_misfit, wp, wpns,  
    iterlast = init_chain_darrays(opt_in, optns_in, F_in, chains)

    domcmciters(iterlast, nsamples, chains, mns, m, optns, opt,
        statns, stat, current_misfit, F, wpns, wp)

    close_history.([wp, wpns])
    nothing
end

function init_chain_darrays(opt_in::OptionsStat, optn_in::OptionsNuisance,
                            F_in::Operator, chains::Array{Chain, 1})
    # purely stationary GP moves + nuisance                    
    
    m_, mn_, opt_, optn_, F_in_, stat_, statn_,
    current_misfit_, wp_, wpn_  = map(x -> Array{Future, 1}(undef, length(chains)), 1:10)
    
    opt_in.history_mode == "a" && setrestartflag.([opt_in, optn_in])
    
    iterlast = 0
    @sync for(idx, chain) in enumerate(chains)

        makestatfilenames(opt_in)
        makenuisancefilenames(optn_in)

        opt_[idx]            = @spawnat chain.pid [opt_in]
        optn_[idx]           = @spawnat chain.pid [optn_in]

        m_[idx]              = @spawnat chain.pid [init(opt_in)]
        mn_[idx]             = @spawnat chain.pid [init(optn_in)]

        @sync wp_[idx]       = @spawnat chain.pid [open_history(opt_in)]
        @sync wpn_[idx]      = @spawnat chain.pid [open_history(optn_in)]

        stat_[idx]           = @spawnat chain.pid [Stats()]
        statn_[idx]          = @spawnat chain.pid [Stats(nmoves=optn_in.nnu)]

        F_in_[idx]           = @spawnat chain.pid [F_in]    

        current_misfit_[idx] = @spawnat chain.pid [[ get_misfit(fetch(m_[idx])[1],
                                fetch(mn_[idx])[1],
                                fetch(opt_[idx])[1],
                                fetch(F_in_[idx])[1]) ]]

    m, mn, opt, optn, stat, statn, F,
    current_misfit, wp, wpn = map(x -> DArray(x), (m_, mn_, opt_, optn_,
                                    stat_, statn_, F_in_, current_misfit_,
                                    wp_, wpn_))
    @info "initialisation complete"
    return m, mn, opt, optn, stat, statn, F, current_misfit,
        wp, wpn, iterlast
end

function domcmciters(iterlast, nsamples, chains, m::ModelStat, mn::ModelNuisance, 
            opt::OptionsStat, optn::OptionsNuisance, stat, statn, 
            current_misfit, F, wp, wpn)
    # purely stationary GP moves + nuisance        
    
    t2 = time()
    for isample = iterlast+1:iterlast+nsamples
        # we do need each remotecall to finish before 
        # moving on to the next kind of move
        swap_temps(chains)
        @sync for chain in chains
            # purely nuisance move
            @async chain.misfit = remotecall_fetch(do_mcmc_step, chain.pid,
                                            mn, m, optn, statn,
                                            current_misfit, F,
                                            chain.T, isample, wpn)
        end
        @sync for chain in chains
            # purely stationary GP moves + nuisance
            @async chain.misfit = remotecall_fetch(do_mcmc_step, chain.pid,
                                            m, mn, opt, stat,
                                            current_misfit, F,
                                            chain.T, isample, wp)
        end
        disptime(isample, t2, iterlast, nsamples)
    end
end

function main(opt_in       ::OptionsStat,
        optn_in      ::OptionsNuisance,
        F_in         ::Operator,
        chainprocs   ::Array{Int, 1};
        nsamples     = 4001,
        nchainsatone = 1,
        Tmax         = 2.5)
    # purely stationary GP moves + nuisance   

    chains = Chain(chainprocs, nchainsatone=nchainsatone, Tmax=Tmax)

    m, mn, opt, optn, stat, 
    statn, F, current_misfit, wp, wpn, 
    iterlast = init_chain_darrays(opt_in, optn_in, F_in, chains)

    domcmciters(iterlast, nsamples, chains, m, mn, opt,
        optn, stat, statn, current_misfit, F, wp, wpn)

    close_history.([wp, wpn])
    nothing
end

function init_chain_darrays(opt_in::OptionsStat, F_in::Operator, 
    chains::Array{Chain, 1})
    # purely stationary GP moves
    
    m_, opt_, F_in_, stat_, current_misfit_, 
    wp_  = map(x -> Array{Future, 1}(undef, length(chains)), 1:6)
    
    opt_in.history_mode == "a" && setrestartflag(opt_in)
    
    iterlast = 0
    @sync for(idx, chain) in enumerate(chains)

        makestatfilenames(opt_in)

        opt_[idx]            = @spawnat chain.pid [opt_in]
        m_[idx]              = @spawnat chain.pid [init(opt_in)]
        @sync wp_[idx]       = @spawnat chain.pid [open_history(opt_in)]
        stat_[idx]           = @spawnat chain.pid [Stats()]
        F_in_[idx]           = @spawnat chain.pid [F_in]    
        current_misfit_[idx] = @spawnat chain.pid [[ get_misfit(fetch(m_[idx])[1],
                                fetch(opt_[idx])[1],
                                fetch(F_in_[idx])[1]) ]]

    m, opt, stat, F,
    current_misfit, wp = map(x -> DArray(x), (m_, opt_, 
                                    stat_, F_in_, current_misfit_,
                                    wp_))
    @info "initialisation complete"
    return m, opt, stat, F, current_misfit,
        wp, iterlast
end

function domcmciters(iterlast, nsamples, chains, m::ModelStat, 
            opt::OptionsStat, stat, 
            current_misfit, F, wp)
    # purely stationary GP moves     
    
    t2 = time()
    for isample = iterlast+1:iterlast+nsamples
        swap_temps(chains)
        @sync for chain in chains
            # purely stationary GP moves 
            @async chain.misfit = remotecall_fetch(do_mcmc_step, chain.pid,
                                            m, opt, stat,
                                            current_misfit, F,
                                            chain.T, isample, wp)
        end
        disptime(isample, t2, iterlast, nsamples)
    end
end

function main(opt_in ::OptionsStat,
        F_in         ::Operator,
        chainprocs   ::Array{Int, 1};
        nsamples     = 4001,
        nchainsatone = 1,
        Tmax         = 2.5)
    # purely stationary GP moves    

    chains = Chain(chainprocs, nchainsatone=nchainsatone, Tmax=Tmax)

    m, opt, stat, 
    F, current_misfit, wp, 
    iterlast = init_chain_darrays(opt_in, F_in, chains)

    domcmciters(iterlast, nsamples, chains, m, opt,
        stat, current_misfit, F, wp)

    close_history(wp)
    nothing
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

function disptime(isample, t2, iterlast, nsamples)
    if mod(isample-1, 1000) == 0
        dt = time() - t2 #seconds
        t2 = time()
        @info("**$dt**sec** $isample out of $(iterlast+nsamples)")
    end
end

# maybe split this off into a different include file
# no nuisances e.g., SkyTEM
function loopacrosssoundings(soundings::Array{S, 1}, opt_in::Options;
                            nsequentialiters   =-1,
                            nparallelsoundings =-1,
                            zfixed             = [-1e5],
                            ρfixed             = [1e12],
                            useML              = false,
                            zstart             = 0.0,
                            extendfrac         = 1.06,
                            dz                 = 2.,
                            ρbg                = 10,
                            nlayers            = 50,
                            ntimesperdecade    = 10,
                            nfreqsperdecade    = 5,
                            Tmax               = -1,
                            nsamples           = -1,
                            nchainsatone       = -1,
                            modelprimary       = false,
                            nchainspersounding = -1) where S<:Sounding

    @assert nsequentialiters  != -1
    @assert nparallelsoundings != -1
    @assert nchainspersounding != -1
    @assert nsamples != - 1
    @assert nchainsatone != -1
    @assert Tmax != -1

    nsoundings = length(soundings)
    opt= deepcopy(opt_in)

    for iter = 1:nsequentialiters
        if iter<nsequentialiters
            ss = (iter-1)*nparallelsoundings+1:iter*nparallelsoundings
        else
            ss = (iter-1)*nparallelsoundings+1:nsoundings
        end
        @info "soundings in loop $iter of $nsequentialiters", ss
        r_nothing = Array{Nothing, 1}(undef, length(ss))
        @sync for (i, s) in Iterators.reverse(enumerate(ss))
            pids = (i-1)*nchainspersounding+i:i*(nchainspersounding+1)
            @info "pids in sounding $s:", pids

            aem, = makeoperator(    soundings[s],
                                    zfixed = zfixed,
                                    ρfixed = ρfixed,
                                    zstart = zstart,
                                    extendfrac = extendfrac,
                                    dz = dz,
                                    ρbg = ρbg,
                                    useML = useML,
                                    nlayers = nlayers,
                                    modelprimary = modelprimary,
                                    ntimesperdecade = ntimesperdecade,
                                    nfreqsperdecade = nfreqsperdecade)

            opt = deepcopy(opt_in)
            opt.fdataname = soundings[s].sounding_string*"_"

            @async r_nothing[i] = remotecall_fetch(main, pids[1], opt, aem, collect(pids[2:end]),
                                    Tmax         = Tmax,
                                    nsamples     = nsamples,
                                    nchainsatone = nchainsatone)

        end # @sync
        @info "done $iter out of $nsequentialiters at $(Dates.now())"
    end
end

# there are definitely nuisances, e.g. TEMPEST
function loopacrosssoundings(soundings::Array{S, 1};
                                nsequentialiters   = -1,
                                nparallelsoundings = -1,
                                zfixed             = [-1e5],
                                ρfixed             = [1e12],
                                zstart             = 0.0,
                                extendfrac         = 1.06,
                                dz                 = 2.,
                                ρbg                = 10,
                                nlayers            = 50,
                                ntimesperdecade    = 10,
                                nfreqsperdecade    = 5,
                                Tmax               = -1,
                                nsamples           = -1,
                                nchainsatone       = -1,
                                nchainspersounding = -1,
                                nmin               = 2,
                                nmax               = 40,
                                K                  = GP.Mat32(),
                                demean             = true,
                                sampledc           = true,
                                sddc               = 0.01,
                                sdpos              = 0.05,
                                sdprop             = 0.05,
                                fbounds            = [-0.5 2.5],
                                λ                  = [2],
                                δ                  = 0.1,
                                pnorm              = 2,
                                save_freq          = 50,
                                nuisance_sdev      = [0.],
                                nuisance_bounds    = [0. 0.],
                                updatenuisances    = true,
                                dispstatstoscreen  = false,
                                useML              = false,
                                restart            = false,
                                C                  = nothing,
                                vectorsum          = false) where S<:Sounding

    @assert nsequentialiters  != -1
    @assert nparallelsoundings != -1
    @assert nchainspersounding != -1
    @assert nsamples != - 1
    @assert nchainsatone != -1
    @assert Tmax != -1

    nsoundings = length(soundings)

    for iter = 1:nsequentialiters
        if iter<nsequentialiters
            ss = (iter-1)*nparallelsoundings+1:iter*nparallelsoundings
        else
            ss = (iter-1)*nparallelsoundings+1:nsoundings
        end
        @info "soundings in loop $iter of $nsequentialiters", ss
        r_nothing = Array{Nothing, 1}(undef, length(ss))
        @sync for (i, s) in Iterators.reverse(enumerate(ss))
            pids = (i-1)*nchainspersounding+i:i*(nchainspersounding+1)
            @info "pids in sounding $s:", pids

            aem, znall = makeoperator(    soundings[s],
                                    zfixed = zfixed,
                                    ρfixed = ρfixed,
                                    zstart = zstart,
                                    extendfrac = extendfrac,
                                    dz = dz,
                                    ρbg = ρbg,
                                    useML = useML,
                                    nlayers = nlayers,
                                    ntimesperdecade = ntimesperdecade,
                                    nfreqsperdecade = nfreqsperdecade,
                                    vectorsum = vectorsum)

            opt, optn = transD_GP.make_tdgp_opt(soundings[s],
                                znall = znall,
                                fileprefix = soundings[s].sounding_string,
                                nmin = nmin,
                                nmax = nmax,
                                K = K,
                                demean = demean,
                                sampledc = sampledc,
                                sddc = sddc,
                                sdpos = sdpos,
                                sdprop = sdprop,
                                fbounds = fbounds,
                                save_freq = save_freq,
                                λ = λ,
                                δ = δ,
                                nuisance_bounds = nuisance_bounds,
                                nuisance_sdev = nuisance_sdev,
                                updatenuisances = updatenuisances,
                                C = C,
                                restart = restart,
                                dispstatstoscreen = dispstatstoscreen
                                )

            @async r_nothing[i] = remotecall_fetch(main, pids[1], opt, optn, aem, collect(pids[2:end]),
                                    Tmax         = Tmax,
                                    nsamples     = nsamples,
                                    nchainsatone = nchainsatone)

        end # @sync
        @info "done $iter out of $nsequentialiters at $(Dates.now())"
    end
end
