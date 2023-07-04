# FAROS: A Framework for Benchmarking and Analysis of Compiler Optimization

FAROS is an extensible framework to automate and structure the analysis 
of compiler optimizations of OpenMP programs. FAROS provides a generic 
configuration interface to profile and analyze OpenMP applications with 
their native build configurations.

## Description and usage

This repo contains a benchmark harness to fetch, build, and run programs
with different compilation options for analyzing the impact of
compilation on performance. The use case is contrasting OpenMP compilation
with its serial elision to understand performance differences due to
different compilations.


### Harness script

The harness script in Python, named benchmark.py, takes as input a YAML
configuration file and a set of options to build and run programs
described in that configuration. You can see below the help
output describing possible options. The configuration file input is set
with the `-i, --input` argument. There are three different actions the
harness performs:

1. fetch sources, with the option `-f, --fetch`,
fetches the program sources from the specified repositories;

For example, to fetch source files of SRAD of the Rodinia benchmark suite:
```
python faros-config.py -i config.yaml -f -p srad
```

2. build programs, with
the option `-b, --build`, builds the selected program using the specified
compilation options in the configuration, also fetching if needed;
3. generate reports, with the option `-g, --generate`, generates compilation reports
by combining optimization remarks for different compilation
configurations, creating remark diff files between them, from all the
sources of an application to a single file;
4. run tests, with the option `-r,--run` and a following argument on how many repetitions to perform, that
runs the executable with the specified input, repeating up to the number
of repetitions set. In our IWOMP paper, we used 30 repetitions for each program.

The flags can be individually set by doing multiple runs of the harness, or
combined to perform multiple actions in a single run -- fetching takes
precedence over building, building over generating reports, and running.
The user selects the list of programs to operate using `-p,--programs`
followed by individual program names or the keyword `all` for all the
programs specified in the configuration input.  Alternatively, the user
may select the list of programs by providing a tag list with `-t,--tags`
that matches tags for each program specified in the configuration.
Also, the harness has a dry run option, `-d,--dry-run`, that prints what
actions would be performed without actually performing them.

Below is the output when running help, `-h, --help` on the harness
script:
```
Benchmark and analyze programs compiled with different compilation options.

optional arguments:
  -h, --help            show this help message and exit
  -i INPUT, --input INPUT
                        configuration YAML input file for programs
  -f, --fetch           fetch program repos (without building)
  -b, --build           build programs (will fetch too)
  -r RUN, --run RUN     run <repetitions>
  -g, --generate        generate compilation reports
  -p PROGRAMS [PROGRAMS ...], --programs PROGRAMS [PROGRAMS ...]
                        programs to run from the config
  -t TAGS [TAGS ...], --tags TAGS [TAGS ...]
                        tagged program to use from the config
  -s, --stats           show run statistics
  -d, --dry-run         enable dry run
```
The harness creates four extra directories for its
operation when building and running:
1. the directory `repos` to download the benchmark application
    specified in the configuration;
2. the directory `bin` to store the generated executable from
    building to run them;
3. the directory `reports`, which stores compilation
    reports, including optimization remarks;
4. the directory `results` to store profiling results, which
    contain execution times from running different built configurations and
    inputs.

### YAML configuration input

Configuring YAML creates a hierarchy of keys for each program to
include that prescribe actions for the harness script. We describe those
keys here. For a working example please see `config.yaml` in the repo,
which includes configuration for 39 HPC programs including proxy/mini
applications, NAS and Rodinia kernels, and the open-source large
application GROMACS.  The root of the hierarchy is a user-chosen,
descriptive name per program configuration.  The harness creates a
sub-directory matching the name of this root key under `bin` to store
executables

The key `fetch` contains the shell command to fetch the
application code, for example, cloning from a GitHub repo. Note that the
fetching command can include also a patching file if needed, provided
by the user. In this repo, we provide patch files for programs in
`config.yaml` undr the directory `patches`.  For example, for some
programs, we apply a patch to guard calls to OpenMP runtime functions
using the standard approach of enabling those calls within `#ifdef OPENMP
... endif` preprocessor directives.

The key `tags` sets a list of user-defined tags which can be used by the
harness to include programs when performing its operation.

The key `build_dir` specifies the directory to build the application, so
harness changes to this directory to execute the build commands
specified under the key build. There is a different sub-key for each
different compilation specification, denoted by a user-provided
identifier.  The harness creates different sub-directories under
`bin/<program>`for each different compilation configuration.

The key `copy` specifies a list of files or directories that the harness
copies out to those sub-directories. The list contains the executable
file and possibly any input files needed for execution, if the user
desires to have self-contained execution in `bin` by avoiding referring to
input files in the directory repos -- this is useful for
relocating the directory bins without needing to copy over
repos.

Further, the key `run` specifies the command to
execute, which is typically the executable binary of the application,
prepended with any environment variables to set.

Moreover, the key `input` specifies the input arguments
for the application in the run command.

The key `measure`
specifies a regular expression to match the application's executable
output to capture the desired measure of performance, such as execution
time or some other Figure of Merit (FoM). If the value of the key
measure is empty, the harness measures end-to-end, wall clock  execution
time from launching the application to its end, using python's
time module.

Lastly, the key `clean` specifies the commands the harness executes to
clean the repo for building a different compilation configuration.

## An Example Session

We will use the SRAD benchmark from Rodinia as an example to show how to use FAROS, including
- how to fetch and build the benchmark
- how to generate performance measurements of two versions (sequential vs. OpenMP single thread) and their corresponding compiler remarks. 
- how to look into results

Before we dive into the example, we need to understand the background of LLVM remarks
https://llvm.org/docs/Remarks.html


LLVM is able to emit diagnostics from passes describing whether an optimization has been performed or missed for a particular reason, which should give more insight to users about what the compiler did during the compilation pipeline.

There are three main remark types:
- Passed: Remarks that describe a successful optimization performed by the compiler.
- Missed: Remarks that describe an attempt to an optimization by the compiler that could not be performed.
- Analysis: Remarks that describe the result of an analysis, that can bring more information to the user regarding the generated code.

To do a comparative performance analysis of sequential vs OpenMP versions, the Passed and Analysis Remarks are particularly useful to investigate the differences among enabled optimizations of two versions and why. 

Now, let's see the example session. 

First, view and edit config.yaml to prepare programs supported. 
Some programs may have stale URL links so you may want to update them. 
The compiler used may also have new flags needed. 

For example, srad has the following configuration settings:
```
srad:
    fetch: 'wget -nc http://www.cs.virginia.edu/~skadron/lava/Rodinia/Packages/rodinia_3.1.tar.bz2;
            [ ! -d "./rodinia_3.1" ] && tar xfk rodinia_3.1.tar.bz2;
            cd rodinia_3.1 && patch -N -r /dev/null -p1 < ../../patches/rodinia_3.1/openmp/srad.patch'
    tags: ['rodinia']
    build_dir: 'rodinia_3.1/openmp/srad/srad_v2'
    build: {
        seq: [ 'make -j CC="clang++"
                CC_FLAGS="-g -O3 -march=native -fsave-optimization-record -save-stats"'],
        omp: [ 'make -j CC="clang++"
                CC_FLAGS="-DOPEN -fopenmp -g -O3 -march=native -fsave-optimization-record -save-stats -fopenmp"
                '],
    }
    copy: [ 'srad' ]
    bin: 'srad'
    run: 'env OMP_NUM_THREADS=1 OMP_PROC_BIND=true ./srad'
    input: '2048 2048 0 127 0 127 1 0.5 100'
    measure: ''
    clean: [ 'make -j clean' ]
```

If things look good. Do the following
```
# Fetch if needed, then build the srad program
 python faros-config.py -i config.yaml -b -p srad

# Run the program 10 times
 python faros-config.py -i config.yaml -r 10  -p srad

# Generate compiler optimization remarks
 python faros-config.py -i config.yaml -g  -p srad

# Show statistics

 python faros-config.py -i config.yaml -s  -p srad
# apps:  38  selected  ['srad']
=======
srad # runs {'seq': 10, 'omp': 10} 

# Results

## Ranked by speed
seq :    4.349 s, slowdown/seq:    1.000
omp :    9.702 s, slowdown/seq:    2.231
=======
```

There are two folders storing useful information for performance investigation
* results: this folder stores the performance measurements of the benchmark into .yaml files
* reports: this folder stores compiler remarks of two versions and their differences in HTML format 

For example, results/results-srad.yaml may have the following content:
```
srad:
  omp:
  - 9.652787942439318
  - 9.73018952831626
  - 9.641681296750903
  - 9.761115090921521
  - 9.619307561777532
  - 9.583568077534437
  - 9.738149240612984
  - 9.75324924569577
  - 9.636020811274648
  - 9.904356695711613
  seq:
  - 4.374754965305328
  - 4.363104037940502
  - 4.353898557834327
  - 4.349130207672715
  - 4.332207940518856
  - 4.338168643414974
  - 4.344235148280859
  - 4.3434492610394955
  - 4.338591802865267
  - 4.3562699453905225

```

Seeing the big difference (slowing down of the OpenMP version compared to the sequential version),
the next step is to investigate the diff information of the two versions for compiler remarks for Passed optimizations. 

Within reports/srad/html-seq-omp-passed, there are
* index.html  : index of all compiler remarks for passed optimizations
* srad.cpp.html  : each source file has annotated remarks

Opening srad.cpp.html, we should focus on OpenMP annotated regions to find compiler remarks. 

The relevant loop is the following:
```
127			
#ifdef OPEN
128			
		omp_set_num_threads(nthreads);
129			
		#pragma omp parallel for shared(J, dN, dS, dW, dE, c, rows, cols, iN, iS, jW, jE) private(i, j, k, Jc, G2, L, num, den, qsqr)
+asm-printer	181 instructions in function 	.omp_outlined.
+prologepilog	104 stack bytes in function 	.omp_outlined.
130			
#endif

131			
		for (int i = 0 ; i < rows ; i++) {
-loop-delete	   Loop deleted because it is invariant 	main
-licm	                		    hoisting and 	main
-licm	                		    hoisting icmp 	main
132			
            for (int j = 0; j < cols; j++) { 
-licm	             hoisting and 	main
-licm	                               hoisting and 	main
-licm	             hoisting shufflevector 	main
-loop-vectorize	             vectorized loop (vectorization width: 8, interleaved count: 1) 	main
-licm	             hoisting insertelement 	main
-licm	             hoisting sub 	main
+licm	                               hoisting zext 	.omp_outlined._debug__
-licm	             hoisting icmp 	main
+licm	                                 hoisting load 

```

The loop at line 132 does not have loop-vectorize enabled compared to its sequential counterpart. 
So it has the remark of "-loop-vectorze         vectorized loop (vectorization width: 8, interleaved count: 1) 	main". 

To understand the Passed remark more, we should investigate the compiler's Analysis Remark for the same loop. 

Open reports/srad/html-seq-omp-analysis/srad.cpp.html

We can see the following content:
```
131			
		for (int i = 0 ; i < rows ; i++) {
132			
            for (int j = 0; j < cols; j++) { 
-loop-vectorize	             the cost-model indicates that interleaving is not beneficial 	main
+loop-vectorize	             loop not vectorized: cannot identify array bounds 
```

The compiler analysis remark difference shows that for the omp version, 
"loop not vectorized: cannot identify array bounds ". 

Now we know that the LLVM compiler cannot vectorize the loop in question since it cannot
identify array bounds when it compiles the loop in OpenMP mode. 

We can now analyze the code and try different options to enable vectorization in the OpenMP mode. 


## Contributing
To contribute to this repo please send a [pull
request](https://help.github.com/articles/using-pull-requests/) on the
develop branch of this repo.

## Authors

This code was created by Giorgis Georgakoudis (LLNL),
georgakoudis1@llnl.gov, assisted with technical design input from
Ignacio Laguna (LLNL), Tom Scogland, and Johannes Doerfert (ANL).

### Citing FAROS

Please cite the following paper: 

* Georgakoudis G., Doerfert J., Laguna I., Scogland T.R.W. (2020) [FAROS: A
  Framework to Analyze OpenMP Compilation Through Benchmarking and Compiler
  Optimization
  Analysis](https://link.springer.com/chapter/10.1007/978-3-030-58144-2_1). In: Milfeld K., de Supinski B., Koesterke L.,
  Klinkenberg J. (eds) OpenMP: Portable Multi-Level Parallelism on Modern
  Systems. IWOMP 2020. Lecture Notes in Computer Science, vol 12295. Springer,
  Cham. https://doi.org/10.1007/978-3-030-58144-2_1

## License

This repo is distributed under the terms of the Apache License (Version
2.0) with LLVM exceptions. Other software that is part of this
repository may be under a different license, documented by the file
LICENSE in its sub-directory.

All new contributions to this repo must be under the Apache License (Version 2.0) with LLVM exceptions.

See files [LICENSE](LICENSE) and [NOTICE](NOTICE) for more information.

SPDX License Identifier: "Apache-2.0 WITH LLVM-exception"

LLNL-CODE-813267
