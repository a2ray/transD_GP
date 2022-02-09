#!/bin/bash
#PBS -P cr78
#PBS -q normal
#PBS -l ncpus=240
#PBS -l mem=960GB
#PBS -l walltime=1:00:00
#PBS -l wd
#PBS -N juliaSkyTEM
#PBS -e grid.err
#PBS -l storage=gdata/z67+scratch/z67
/g/data/z67/ar0754/ompi-4.1.0/bin/mpiexec -np 240 /home/547/ar0754/bin/julia-1.6.0 03_parallel_run.jl >& outfile