This layer is designed to make it easy to add Coverity static analysis to your Yocto builds. It supports committing defects to a Coverity Connect server, as well as viewing them locally.

**Current supported version**: 2022.6.0

This layer uses the new BitBake override syntax and poky variable names, so it only supports the Kirkstone and Langdale releases of Yocto.

Prerequisites
============

Coverity is a paid commerical product. You must have the appropriate license(s).

Features
============

* Automatic integration with several kinds of recipes (CMake, qmake5, and image)
* Supports gcc and clang
* Automatically aggregates translation units across the entire BitBake task graph (i.e. if you are analyzing recipe A, which depends on B, C, and D, then assuming all four are setup to use Coverity, translation units from all four are factored into the analysis).
* Build capture is setscene optimized
* Easy export of defects to local .html files
* Supports comitting defects to Coverity Connect server
* Customizable stream name
* Detailed progress capture for `cov-analyze`

Build system instructions 
=========================

These instructions configure your Yocto build system to enable Coverity integration.

* To run analyses, you need the analysis license (it's typically a .dat file). Edit local.conf to indicate where your analysis license is:

```
COVERITY_ANALYSIS_LIC = "/home/user/licenses/coverity-analysis.dat"
```

* You must download the analysis tarball (from https://community.synopsys.com/s/downloads) yourself and host it somewhere that is accessible to your Yocto build. (Obviously, it should only be accessible inside your corporate intranet to users who are licensed to use it). The easiest place to host it is on the Coverity Connect server itself in the **$SERVER_INSTALL_LOCATION\server\base\webapps\downloads** directory.

  Currently, version 2022.6.0 is the supported version. So, you need to download **cov-analysis-linux64-2022.6.0.tar.gz**

  Then, in your local.conf (or in a layer/distro .conf if you choose), set `SRC_URI:pn-coverity-native` to the location of the tarball. For example:

```
# This example assumes you are hosting the tarball on the Coverity Connect server in "Downloads" as described above
SRC_URI:pn-coverity-native = "https://MY-COVERITY-CONNECT-SERVER.company.com:8443/downloads/cov-analysis-linux64-${PV}.tar.gz"
```

* You will also need to explicitly enable Coverity integration in local.conf (or in a layer/distro .conf if you choose):

```
COVERITY_ENABLE = "1"
```

* (OPTIONAL) If you want to commit defects to a Coverity Connect server then you also need to set the following variables in local.conf:

```
# NB: Commits only happen when you explicitly run the do_coverity_commit_defects task. This variable is an extra failsafe so end-users (who may just be interested in local analyses) don't accidentally commit to streams.
COVERITY_ENABLE_COMMIT = "1"
# You can generate an authentication key using the Coverity Connect interface. Click your name in the top-right corner, then click "Authentication Keys" in the dropdown
COVERITY_AUTH_KEY_FILE = "/home/user/path/to/key.txt"
COVERITY_SERVER_HOST = "MY-COVERITY-CONNECT-SERVER.company.com"
COVERITY_SERVER_STREAM = "my-stream-name"
```

  Recommendation: set `COVERITY_SERVER_HOST` and `COVERITY_SERVER_STREAM` in a layer or distro conf. Set the other two variables in local.conf as necessary (e.g. on your build machine). 
  
  You might consider using separate streams for different projects. In this case, you can set `COVERITY_SERVER_STREAM` conditionally. For example:
  
```
# Here, product-1 and product-2 are assumed to be the name of different MACHINEs. 
COVERITY_SERVER_STREAM:product-1 = "product-1"
COVERITY_SERVER_STREAM:product-2 = "product-2"
```


Recipe setup instructions
=========================

At a bare minimum each recipe that you want to be analyzed needs to have this line added:

```
inherit coverity
```

Try adding that line and then running `bitbake my-recipe -c coverity_export_defects`. If it works then you're probably good to go. Otherwise, consult the sections below for variables you can set to change how coverity.bbclass works. The first thing to check is whether you need a different integration strategy.

Integration strategies: `COVERITY_STRATEGY`
=============================================

The variable `COVERITY_STRATEGY` configures how coverity.bbclass attempts to integrate Coverity with your build. The available options are:

* `auto` - default, explained below
* `cmake` - overrides `OECMAKE_C_COMPILER` and `OECMAKE_CXX_COMPILER`  
* `fs-capture-js` - runs Coverity in filesystem capture mode looking for .js files
* `path-hijack` - manipulates the `PATH` environment variable so that our special trampoline compiler scripts are used instead of the actual compiler (explained more below)
* `analyze-only` - only useful for image recipes (or other "aggregates") that don't actually build any source code themselves

When `auto` is used the strategy is calculated as follows:
* If the recipe uses CMake (i.e. `inherit cmake`), use `cmake`
* If the recipe uses qmake from Qt5 (i.e. `inherit qmake5`), use `path-hijack`)
* If the recipe is an image recipe, use `analyze-only`
* Otherwise, error

Makefile-based recipes are mostly untested, but should use the `path-hijack` strategy.

Useful variables
================

Here are some variables you may want to tweak (either on a per-recipe basis, or local.conf/distro/layer wide):

| Variable      | Description | Default |
| ----------- | ----------- | ---- |
| `COVERITY_ANALYZE_OPTIONS`      | Arguments passed to `cov-analyze`       | See coverity.bbclass |
| `COVERITY_FS_CAPTURE_ARGS`      | Arguments passed to `cov-build` during filesystem capture       | `--fs-capture-search ${S}` |
| `COVERITY_PARALLEL_BUILD` | The -j argument to pass to cov-build, e.g. '-j 4' | `${PARALLEL_MAKE}`, but reformatted to add the space in between -j and the number |
| `COVERITY_CONFIGURE_COMPILERS` | Compilers to run `cov-configure` on. | `${HOST_PREFIX}gcc` if gcc, `${HOST_PREFIX}clang` if clang |
| `COVERITY_TRAMPOLINES` | Compilers for which to generate trampoline scripts that interpose compilation. | `${COVERITY_CONFIGURE_COMPILERS} ${HOST_PREFIX}g++` if gcc, `${COVERITY_CONFIGURE_COMPILERS} ${HOST_PREFIX}clang++` if clang  |
| `COVERITY_ANALYZE_RECURSIVE_OPTIONS`   | TODO explain | *empty* |
| `COVERITY_EXPORT_DEFECTS_XREF` | When set to `"1"`, run cross-referencing during `do_coverity_export_defects` and `do_coverity_export_defects_all`. This passes `-x` to `cov-format-errors`. | `""` (off) | 

Internals
=========

## Basic principles

While Coverity documentation generally suggests using `cov-build` in "Build capture" mode, that is not feasible for BitBake/Yocto. BitBake spawns worker processes in a way that `cov-build` cannot follow. Even if it could follow, the analysis results would likely not be complete due to BitBake's optimizations such as setscene. Moreover, we are probably not interested in the analysis of every single dependency of the system anyway.

coverity.bbclass takes a more surgical approach. It uses `cov-translate` as described in section 3.3.3 of the "Coverity Analysis 2020.06 User and Administrator
Guide". 

## Compiler trampolines

At a high level, coverity.bbclass works by manipulating the build environment in such a way that instead of the actual compiler getting called, a special trampoline script is called. This trampoline script is a thin wrapper around `cov-translate`. `cov-translate`, behind the scenes, invokes the real compiler. It also records the arguments that were passed to the compiler. 

Later on, during the `do_coverity_build` task, Coverity goes over what `cov-translate` emitted and produces its intermediate data that will later be fed into `cov-analyze`.

## Tasks

coverity.bbclass adds the following BitBake tasks to recipes:

| Task      | Description | Notes |
| ----------- | ----------- | ---- |
| `do_coverity_configure` | Runs `cov-configure` on compilers and generates trampoline scripts |  |
| `do_coverity_build` | Consumes information emitted during the `do_compile` and produces intermediate data. Filesystem capture is done here as well for JavaScript. |  |
| `do_coverity_prepare_analysis` | Assembles the analysis intermediate directory | This works by using the BitBake `[recrdeptask]` varflag set to `do_coverity_build`. |
| `do_coverity_analyze` | Runs `cov-analyze` | |
| `do_coverity_export_defects` | Produces a local .html version of detected defects (using `cov-emit-defects`) for just the current recipe | Filtering is applied to exclude any results that fall under the recipe's sysroot. Note that the filtering is imperfect, so defects may be erroneously included/excluded. |
| `do_coverity_export_defects_all` | Produces a local .html version of detected defects (using `cov-emit-defects`) across current recipe and all dependencies | |
| `do_coverity_commit_defects` | Commits defects to the Coverity Connect server | |

The only tasks you should need to run manually are the last three.

Limitations and TODOs
=====================

Feel free to submit PRs!

If you encounter issues, submit them and I'll do my best to look at the failure (though I don't have unlimited time to troubleshoot integrations).

* Kernel recipes are not tested
* Doesn't yet support native and nativesdk recipes (do_coverity_configure will probably fail)
* Encryption when commiting defects is currently disabled (due a bug in a previous version of Coverity that I haven't re-tested yet to see if fixed)
* Port for committing defects is hardcoded to 9090

License
========

Copyright 2022 Agilent Technologies, Inc.

This layer is licensed under the MIT license.

Disclaimer
========
This is not an official Agilent or Synopsys product. No support is implied.
