srcdir = dirname(dirname(dirname(pwd())))*"/src"
any(srcdir .== LOAD_PATH) || push!(LOAD_PATH, srcdir)
using PyPlot, Revise, AEM_VMD_HMD, Random, Statistics
## model 1
zbot = 15
z1   = [-1e5,   0,    zbot,   70,  100]
ρ1   = [1e12,   0.3,   1,     10,   10]
## model 2
z2   = [-1e5,   0,    zbot,   70, 100]
ρ2   = [1e12,   0.3,   3,     10,  10]
## model 3
z3   = [-1e5,   0,    zbot,   zbot+10,  70, 100]
ρ3   = [1e12,    0.3,   1,     4,       10,  10]
##
#z , ρ = [z1, z2], [ρ1, ρ2]
#z , ρ = [z1, z3], [ρ1, ρ3]
#z , ρ = [z2, z3], [ρ2, ρ3]
z , ρ = [z1, z2, z3], [ρ1, ρ2, ρ3]
nmax = 100
##  geometry and modeling parameters
const μ₀ = 4*pi*1e-7
rRx = 17.
zRx = -32.0
zTx = -30.0
rTx = 12.607
lowpassfcs = [300000, 450000.0]
ntimesperdecade = 10
nfreqsperdecade = 5
# Note that the receiver depth needs to be in same model layer as transmitter.
## LM times and ramp
LM_times = [
1.539e-5  1.939e-5  2.439e-5  3.139e-5  3.939e-5  4.939e-5  6.239e-5  7.839e-5  9.939e-5  0.00012539  0.00015739  0.00019939  0.00025039  0.00031539  0.00039739  0.00050039  0.00063039  0.00079339
 1.9e-5    2.4e-5    3.1e-5    3.9e-5    4.9e-5    6.2e-5    7.8e-5    9.9e-5    0.000125  0.000157    0.000199    0.00025     0.000315    0.000397    0.0005      0.00063     0.000793    0.000999]'
LM_times = exp.(mean(log.(LM_times),dims=2))[:]
LM_ramp =[
-0.001  -0.0009146  -0.0007879  -0.0005964  0.0  4.629e-7  8.751e-7  1.354e-6  2.54e-6  3.972e-6  5.404e-6  5.721e-6  6.113e-6  6.663e-6   8.068e-6  0.00125
 0.0     0.6264      0.9132      0.9905     1.0  0.9891    0.9426    0.8545    0.6053   0.303     0.04077   0.01632   0.004419  0.0006323  0.0       0.0]'
## HM times and ramp
HM_times = [
7.539e-5  9.639e-5  0.00012239  0.00015439  0.00019639  0.00024739  0.00031239  0.00039439  0.00049739  0.00062739  0.00079039  0.00099639  0.00125539  0.00158139  0.00199139  0.00250839  0.00315839  0.00397739  0.00500839  0.00630639  0.00793939
9.6e-5    0.000122  0.000154    0.000196    0.000247    0.000312    0.000394    0.000497    0.000627    0.00079     0.000996    0.001255    0.001581    0.001991    0.002508    0.003158    0.003977    0.005008    0.006306    0.007939    0.009739]'
HM_times = exp.(mean(log.(HM_times),dims=2))[:]
HM_ramp = [
-0.01  -0.008386  -0.00638  -0.003783  0.0  3.96e-7  7.782e-7  1.212e-6  3.44e-6  1.981e-5  3.619e-5  3.664e-5  3.719e-5   3.798e-5  3.997e-5  0.01
  0.0    0.4568     0.7526    0.9204    1.0  0.9984   0.9914    0.9799    0.9175   0.4587    0.007675  0.003072  0.0008319  0.000119  0.0       0.0]'
## LM operator
Flm = AEM_VMD_HMD.HFieldDHT(
                      ntimesperdecade = ntimesperdecade,
                      nfreqsperdecade = nfreqsperdecade,
                      lowpassfcs = lowpassfcs,
                      times  = LM_times,
                      ramp   = LM_ramp,
                      nmax   = nmax,
                      zTx    = zTx,
                      rRx    = rRx,
                      rTx    = rTx,
                      zRx    = zRx)
## HM operator
Fhm = AEM_VMD_HMD.HFieldDHT(
                      ntimesperdecade = ntimesperdecade,
                      nfreqsperdecade = nfreqsperdecade,
                      lowpassfcs = lowpassfcs,
                      times  = HM_times,
                      ramp   = HM_ramp,
                      nmax   = nmax,
                      zTx    = zTx,
                      rRx    = rRx,
                      rTx    = rTx,
                      zRx    = zRx)
## get the fields in place
@assert length(z) == length(ρ)
f, ax = plt.subplots(1, 2, figsize=(10,5))
ax[1].set_xlabel("log₁₀ ρ")
ax[1].set_ylabel("depth m")
for i = 1:length(z)
    ax[1].step(log10.(ρ[i][2:end]), z[i][2:end])
    AEM_VMD_HMD.getfieldTD!(Flm, z[i], ρ[i])
    AEM_VMD_HMD.getfieldTD!(Fhm, z[i], ρ[i])
    ax[2].loglog(Flm.times,μ₀*abs.(Flm.dBzdt))
    ax[2].loglog(Fhm.times,μ₀*abs.(Fhm.dBzdt), color=ax[2].lines[end].get_color())
end
ax[1].grid()
ax[2].grid()
ax[1].invert_yaxis()
ax[2].set_ylabel("dBzdt")
ax[2].set_xlabel("time (s)")
plt.tight_layout()