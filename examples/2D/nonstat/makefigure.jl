## get nonstat stuff first
cd("../nonstat")
include("01_make_model.jl")
include("02_make_options.jl")
close("all")
using Statistics
M = GeophysOperator.assembleTat1(opt, :fstar, temperaturenum=1)
mns = reshape(mean(M), length(img.y), length(img.x))
stdns = reshape(std(M), length(img.y), length(img.x))
GeophysOperator.plot_image_posterior(opt, optlog10λ, img, burninfrac=0.5, rownum=168, colnum=60, nbins=100)
figure(1)
savefig("post_rows_ns.png", dpi=300)
figure(2)
savefig("post_col_ns.png", dpi=300)
## change to stat directory
cd("../stat")
include("../stat/02_make_options.jl")
close("all")
M = GeophysOperator.assembleTat1(opt, :fstar, temperaturenum=1)
m = reshape(mean(M), length(img.y), length(img.x))
stds = reshape(std(M), length(img.y), length(img.x))
## plot comparisons
f, ax = plt.subplots(2, 2, sharex=true, sharey=true, figsize=(6.91, 6.94))
ax[1].imshow(mns, extent=[img.x[1],img.x[end],img.y[end],img.y[1]])
# ax[1].set_title("Trans-D GP")
ax[1].text(100, 170, "Variable λ", color="w", fontsize=12, alpha=0.8)
# ax[3].set_title("Image")
ax[2].imshow(m, extent=[img.x[1],img.x[end],img.y[end],img.y[1]])
ax[2].text(100, 170, "Fixed λ", color="w", fontsize=12, alpha=0.8)
ax[3].imshow(img.f, extent=[img.x[1],img.x[end],img.y[end],img.y[1]])
ax[3].text(100, 170, "True", color="w", fontsize=12, alpha=0.8)
# ax[4].imshow(log10.(stdns), extent=[img.x[1],img.x[end],img.y[end],img.y[1]])
# ax[5].imshow(log10.(stds), extent=[img.x[1],img.x[end],img.y[end],img.y[1]])
ax[4].imshow(img.f, extent=[img.x[1],img.x[end],img.y[end],img.y[1]])
ax[4].text(100, 170, "True", color="w", fontsize=12, alpha=0.8)
for a in ax
   a.axis("off")
end
# f.tight_layout()
f.subplots_adjust(wspace=0, hspace=0)
savefig("compare_ns_s.png", dpi=300)
##
