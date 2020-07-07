module AEM_VMD_HMD
include("DigFilters.jl")
include("TDcossin.jl")
using LinearAlgebra, SpecialFunctions, FastGaussQuadrature, DataInterpolations

abstract type HField end

mutable struct HFieldDHT <: HField
    thickness       :: Array{Float64, 1}
    pz              :: Array{Complex{Float64}, 1}
    epsc            :: Array{ComplexF64, 1}
    zintfc          :: Array{Float64, 1}
    rTE             :: Array{ComplexF64, 1}
    rTM             :: Array{ComplexF64, 1}
    zRx             :: Float64
    zTx             :: Float64
    rTx             :: Union{Float64, Nothing}
    rRx             :: Float64
    freqs           :: Array{Float64, 1}
    times           :: Array{Float64, 1}
    ramp            :: Array{Float64, 2}
    log10ω          :: Array{Float64, 1}
    interptimes     :: Array{Float64, 1}
    HFD             :: Array{ComplexF64, 1}
    HFDinterp       :: Array{ComplexF64, 1}
    HTDinterp       :: Array{Float64, 1}
    dBzdt           :: Array{Float64, 1}
    J0_kernel_h     :: Array{ComplexF64, 2}
    J1_kernel_h     :: Array{ComplexF64, 2}
    J0_kernel_v     :: Array{ComplexF64, 2}
    J1_kernel_v     :: Array{ComplexF64, 2}
    lowpassfcs      :: Array{Float64, 1}
    quadnodes       :: Array{Float64, 1}
    quadweights     :: Array{Float64, 1}
    interplog10ω    :: Array{Float64, 2}
    ω               :: Array{Float64, 2}
    Hsc             :: Array{ComplexF64, 2}
    rxwithinloop    :: Bool
    provideddt      :: Bool
end

function HFieldDHT(;
      nmax      = 200,
      rTx       = nothing,
      rRx       = 17.0,
      freqs     = [],
      zTx       = -35.0,
      zRx       = -37.5,
      times     = 10 .^LinRange(-6, -1, 50),
      ramp      = ones(10, 10),
      nfreqsperdecade = 7,
      ntimesperdecade = 7,
      glegintegorder = 5,
      lowpassfcs = [],
      provideddt = true
  )
    @assert all(freqs .> 0.)
    @assert all(diff(times) .> 0)
    thickness = zeros(nmax)
    zintfc    = zeros(nmax)
    pz        = zeros(Complex{Float64}, nmax)
    epsc      = similar(pz)
    rTE       = zeros(length(pz)-1)
    rTM       = similar(rTE)
    freqlow, freqhigh = 1e-3, 1e6
    if freqhigh < 3/minimum(times)
       freqhigh = 3/minimum(times)
    end
    if freqlow > 3/maximum(times)
       freqlow = 3/maximum(times)
    end
    if isempty(freqs)
        freqs = 10 .^(log10(freqlow):1/nfreqsperdecade:log10(freqhigh))
    end
    J0_kernel_h, J1_kernel_h, J0_kernel_v, J1_kernel_v = map(x->zeros(ComplexF64, length(Filter_base), length(freqs)), 1:4)
    log10freqs = log10.(freqs)
    log10ω = log10.(2*pi*freqs)
    interptimes = 10 .^(minimum(log10.(times))-1:1/ntimesperdecade:maximum(log10.(times))+1)
    HFD       = zeros(ComplexF64, length(freqs)) # space domain fields in freq
    dBzdt     = zeros(Float64, length(times)) # time derivative of space domain fields convolved with ramp
    HFDinterp = zeros(ComplexF64, length(Filter_t_base))
    HTDinterp = zeros(Float64, length(interptimes))
    lowpassfcs = float.([lowpassfcs..., 1e7])
    quadnodes, quadweights = gausslegendre(glegintegorder)
    rxwithinloop = false
    if rTx != nothing
        if rTx>=rRx
            rxwithinloop = true
        end
    end
    HFieldDHT(thickness, pz, epsc, zintfc, rTE, rTM, zRx, zTx, rTx, rRx, freqs, times, ramp, log10ω, interptimes,
            HFD, HFDinterp, HTDinterp, dBzdt, J0_kernel_h, J1_kernel_h, J0_kernel_v, J1_kernel_v, lowpassfcs,
            quadnodes, quadweights, preallocate_ω_Hsc(interptimes, lowpassfcs)..., rxwithinloop, provideddt)
end

function preallocate_ω_Hsc(interptimes, lowpassfcs)
    ω   = zeros(length(Filter_t_base), length(interptimes))
    Hsc = zeros(ComplexF64, length(Filter_t_base), length(interptimes))
    for itime = 1:length(interptimes)
        t = interptimes[itime]
        ω[:,itime] = log10.(Filter_t_base/t)
        Hsc[:,itime] = ones(ComplexF64, length(Filter_t_base))
        s = 1im*10 .^ω[:,itime]
        for fc in lowpassfcs
             Hs = 1 ./( 1 .+s./(2*pi*fc))
             Hsc[:,itime] .= Hsc[:,itime].*Hs
        end
    end
    ω, 10 .^ω, Hsc
end

const mu       = 4*pi*1e-7
const eps0     = 8.854e-12
const iTxLayer = 1
const iRxLayer = 1

function stacks!(F::HField, iTxLayer::Int, nlayers::Int, omega::Float64)

    rTE              = F.rTE
    rTM              = F.rTM
    pz               = view(F.pz, 1:nlayers)
    #The last and first layer thicknesses are infinite
    d                = view(F.thickness, 1:nlayers)
    d[1]             = 1e60
    d[nlayers]       = 1e60

    # Capital R is for a stack
    # Starting from the bottom up, for Rs_down
    Rlowerstack_TE, Rlowerstack_TM = 0. *im, 0. *im
    for k = (nlayers-1):-1:iTxLayer
      Rlowerstack_TE = lowerstack(Rlowerstack_TE, pz, rTE, d, k, omega)
      #Rlowerstack_TM = lowerstack(Rlowerstack_TM, pz, rTM, d, k, omega)
    end

return Rlowerstack_TE, Rlowerstack_TM
end

function lowerstack(Rlowerstack::ComplexF64, pz::SubArray{ComplexF64, 1},
                    r::Array{ComplexF64, 1}, d::SubArray{Float64, 1}, k::Int, omega::Float64)
    e_to_the_2iwpznext_dnext = exp(2im*omega*pz[k+1]*d[k+1])
    Rs_d = (r[k] + Rlowerstack * e_to_the_2iwpznext_dnext) /
        (1. + r[k]*Rlowerstack * e_to_the_2iwpznext_dnext)
end

function getCurlyR(Rs_d::ComplexF64, pz::ComplexF64,
                  zR::Float64, z::SubArray{Float64, 1}, iTxLayer::Int, omega::Float64)

    if (zR>=0)
        e_to_the_iwpzzr               = exp( im*omega*pz*zR)
        e_to_the_iwpz_2znext_minus_zr = exp( im*omega*pz*(2*z[iTxLayer+1] - zR))

        finRA = e_to_the_iwpzzr + e_to_the_iwpz_2znext_minus_zr*Rs_d
        # Will need these for other components
        # finRB = e_to_the_iwpzzr + e_to_the_iwpz_2znext_minus_zr*Rs_d
        #
        # finRC = e_to_the_iwpzzr + e_to_the_iwpz_2znext_minus_zr*(-Rs_d)
        #
        # finRD = e_to_the_iwpzzr + e_to_the_iwpz_2znext_minus_zr*(-Rs_d)
    else
        e_to_the_iwpz2znext              = exp(im*omega*pz*2*z[iTxLayer+1])
        e_to_the_minus_iwpzzr            = exp(-im*omega*pz*zR)

        finRA = (1. + e_to_the_iwpz2znext*Rs_d) * e_to_the_minus_iwpzzr
        # Will need these for other components
        # finRB = (-1. + e_to_the_iwpz2znext*Rs_d) * e_to_the_minus_iwpzzr
        #
        # finRC = (1. + e_to_the_iwpz2znext*(-Rs_d)) * e_to_the_minus_iwpzzr
        #
        # finRD = (-1. + e_to_the_iwpz2znext*(-Rs_d)) * e_to_the_minus_iwpzzr
    end

    return finRA #, finRB, finRC, finRD
end
# FT convention in this function means will have to conjugate for compatibility with FT = exp(-iωt)
getepsc(rho, omega)      = eps0 + 1im/(rho*omega) # corresponds to FT = exp(+iωt)
getpz(epsc, krho, omega) = sqrt(mu*epsc - (krho/omega)^2) # corresponds k² = iωμσ
ztxorignify(z, zTx)      = z - zTx
makesane(pz::Complex)    = imag(pz)  < 0.0 ? ( pz*=-1.) : pz # Sommerfeld radiation condition for fields 0 at ∞

function getAEM1DKernelsH!(F::HField, krho::Float64, f::Float64, zz::Array{Float64, 1}, rho::Array{Float64, 1})
    nlayers = length(rho)
    z       = view(F.zintfc, 1:nlayers)
    zRx     = ztxorignify(F.zRx, F.zTx)
    omega   = 2. *pi*f
    epsc    = F.epsc
    pz      = F.pz
    # reflection coefficients (downward) for an intfc: pz vertical slowness
    rTE, rTM = F.rTE, F.rTM

    l = 1
    z[l]       = ztxorignify(zz[l], F.zTx)
    epsc[l]    = getepsc(rho[l], omega)
    pz[l]      = makesane(getpz(epsc[l], krho, omega))
    for intfc in 1:nlayers-1
        l = intfc+1
        z[l]       = ztxorignify(zz[l], F.zTx)
        epsc[l]    = getepsc(rho[l], omega)
        pz[l]      = makesane(getpz(epsc[l], krho, omega))
        rTE[intfc] = (pz[intfc] - pz[intfc+1])/(pz[intfc] + pz[intfc+1])
        # commented out as we aren't yet using TM modes
        # rTM[intfc] = (epsc[intfc]*pz[intfc+1] - epsc[intfc+1]*pz[intfc]) /
        #              (epsc[intfc]*pz[intfc+1] + epsc[intfc+1]*pz[intfc])
        F.thickness[intfc] = z[intfc+1] - z[intfc]
    end

    # TE and TM modes
    Rs_dTE, Rs_dTM   = stacks!(F, iTxLayer, nlayers, omega)
    curlyRA,         = getCurlyR(Rs_dTE, pz[iTxLayer], zRx, z, iTxLayer, omega)
    lf = 1.0
    if F.rxwithinloop
        lf *= loopfactor(F.rTx, krho, F.rRx)
    else
        lf *= loopfactor(F.rTx, krho)
    end
    gA_TE            = mu/pz[iTxLayer]*curlyRA*lf

    # Kernels according to Loseth, without the bessel functions multiplied
    J0v              = gA_TE*1im/(omega*mu)

    return J0v
end

loopfactor(rTx::Nothing, krho::Float64)               = krho^3/(4*pi)
loopfactor(rTx::Float64, krho::Float64)               = krho^2*besselj1(krho*rTx)/(2*pi*rTx)
loopfactor(rTx::Float64, krho::Float64, rRx::Float64) = krho^2*besselj0(krho*rRx)/(2*pi*rTx)

function getfieldFD!(F::HFieldDHT, z::Array{Float64, 1}, ρ::Array{Float64, 1})
    for (ifreq, freq) in enumerate(F.freqs)
        for (ikr, kr) in enumerate(Filter_base)
            if F.rxwithinloop
                F.J1_kernel_v[ikr,ifreq] = getAEM1DKernelsH!(F, kr/F.rTx, freq, z, ρ)
            else
                F.J0_kernel_v[ikr,ifreq] = getAEM1DKernelsH!(F, kr/F.rRx, freq, z, ρ)
            end
        end # kr loop
        if F.rxwithinloop
            J1_kernel_v = @view F.J1_kernel_v[:,ifreq]
            F.HFD[ifreq] = dot(J1_kernel_v, Filter_J1)/F.rTx
        else
            J0_kernel_v = @view F.J0_kernel_v[:,ifreq]
            F.HFD[ifreq] = dot(J0_kernel_v, Filter_J0)/F.rRx
        end
    end # freq loop
end

function getfieldTD!(F::HFieldDHT, z::Array{Float64, 1}, ρ::Array{Float64, 1})
    getfieldFD!(F, z, ρ)
    splreal = CubicSpline(real(F.HFD), F.log10ω) # TODO preallocate
    splimag = CubicSpline(imag(F.HFD), F.log10ω) # TODO preallocate
    @views begin
        for itime = 1:length(F.interptimes)
            l10w, H = F.interplog10ω[:,itime], F.Hsc[:,itime]
            t = F.interptimes[itime]
            # Conjugate for my sign convention, apply Butterworth and inverse transform
            if F.provideddt
                F.HFDinterp[:] = imag(conj((splreal.(l10w) .+ 1im*splimag.(l10w)).*H))*2/pi
                F.HTDinterp[itime] = dot(F.HFDinterp, Filter_t_sin)/t
            else
                w = F.ω[:,itime]
                F.HFDinterp[:] = -imag(conj((splreal.(l10w) .+ 1im*splimag.(l10w)).*H)./w)*2/pi
            end
        end
    end
    spl = CubicSpline(F.HTDinterp, log10.(F.interptimes)) # TODO preallocate
    convramp!(F, spl)
end

function convramp!(F::HFieldDHT, spl::CubicSpline)
    fill!(F.dBzdt, 0.)
    for itime = 1:length(F.times)
        for iramp = 1:size(F.ramp,1)-1
            rta, rtb  = F.ramp[iramp,1], F.ramp[iramp+1,1]
            dt   = rtb - rta
            dI   = F.ramp[iramp+1,2] - F.ramp[iramp,2]
            dIdt = dI/dt

            if rta > F.times[itime]
                break
            end
            if rtb > F.times[itime] # end in this interval
                rtb = F.times[itime]
            end

            ta = F.times[itime]-rta
            tb = max(F.times[itime]-rtb, 1e-8) # rtb > rta, so make sure this is not zero...
            a, b = log10(ta), log10(tb)
            x, w = F.quadnodes, F.quadweights
            F.dBzdt[itime] += (b-a)/2*dot(getrampresponse((b-a)/2*x .+ (a+b)/2, spl), w)*dIdt
        end
    end
end

function getrampresponse(t::Array{Float64, 1}, spl::CubicSpline)
    spl.(t).*(10 .^t)*log(10)
end

end # module
