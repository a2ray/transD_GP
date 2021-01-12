module LineRegression
import AbstractOperator.get_misfit
using AbstractOperator, CommonToAll
using TransD_GP, PyPlot, LinearAlgebra, StatsBase

export Line, makehist

mutable struct Line<:Operator1D
    d     :: Array{Float64}
    useML :: Bool
    σ     :: Float64
end

function Line(d::Array{Float64, 1} ;useML=false, σ=1.0)
    Line(d, useML, σ)
end

function get_misfit(m::TransD_GP.Model, opt::TransD_GP.Options, line::Line)
    chi2by2 = 0.0
    if !opt.debug
        d = line.d
        select = .!isnan.(d[:])
        r = m.fstar[:][select] - d[select]
        if line.useML
            N = sum(select)
            chi2by2 = 0.5*N*log(norm(r)^2)
        else
            chi2by2 = r'*r/(2line.σ^2)
        end
    end
    return chi2by2
end

function makehist(line::Line, opt::TransD_GP.Options;
    nbins=100, burninfrac=0.5, temperaturenum=1)
    linidx = findall(.!isnan.(line.d))
    M = assembleTat1(opt, :fstar,
        temperaturenum=temperaturenum, burninfrac=burninfrac)
    resids = similar(M)
    for (im, m) in enumerate(M)
        resids[im] = (m[sort(linidx)] - line.d[sort(linidx)])/line.σ
    end
    resids = permutedims(hcat(resids...))
    mmin, mmax = extrema(resids)
    edges = LinRange(mmin, mmax, nbins+1)
    himage = zeros(Float64, nbins,length(linidx))
    for ilayer=1:length(linidx)
        himage[:,ilayer] = fit(Histogram, resids[:,ilayer], edges).weights
        himage[:,ilayer] = himage[:,ilayer]/sum(himage[:,ilayer])/(diff(edges)[1])
    end
    himage, edges
end

end
