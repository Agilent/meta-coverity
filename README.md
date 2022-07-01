This layer is designed to make it easy to add Coverity static analysis to your Yocto builds. It supports committing defects to a Coverity Connect server, as well as viewing them locally.

**Current supported version**: 2022.6.0

Prerequisites
============

Coverity is a paid commerical product. You must have the appropriate license(s).

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




Limitations and TODOs
=====================

Feel free to submit PRs!

* Kernel recipes are not tested
* Doesn't yet support native and nativesdk recipes (do_coverity_configure will probably fail)
* Encryption when commiting defects is currently disabled (due a bug in a previous version of Coverity that I haven't re-tested yet to see if fixed)
* Port for committing defects is hardcoded to 9090
* 

Features
============

* Automatic integration with CMake-based recipes.


License
========

This layer is licensed under the MIT license.

Disclaimer
========
This is not an official Agilent or Synopsys product. No support is implied.
