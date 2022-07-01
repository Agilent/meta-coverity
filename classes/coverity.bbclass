# Author: Chris Laplante <chris.laplante@agilent.com>

COVERITY_ENABLE ??= ""
COVERITY_ENABLE[doc] = "If non-empty, enable Coverity. Defaults to enabled."

COVERITY_ENABLE_COMMIT ??= ""
COVERITY_ENABLE_COMMIT[doc] = "Set to non-empty to enable the coverity-commit-defects task. Disabled by default to prevent accidental pushes."

COVERITY_STRATEGY ??= "auto"
COVERITY_STRATEGY[doc] = "Integration mode - supported values: auto, cmake, path-hijack, fs-capture-js, analyze-only. The only reason to use analyze-only \
                          is for images or other 'aggregate' recipes that themselves do not have any source code to analyze."

COVERITY_ANALYSIS_LIC ??= ""
COVERITY_ANALYSIS_LIC[doc] = "Full path to the analysis license file. Needed to run analysis or commit/export defects. Passed to coverity commands using the --security-file flag."

COVERITY_AUTH_KEY_FILE ??= ""
COVERITY_AUTH_KEY_FILE[doc] = "Full path to your authentication key. Needed to commit defects. To get a key, log in to Coverity Connect, click your name in the top-right corner, and click 'Authentication Keys'. \
                               Corresponds to the --auth-key-file option for cov-commit-defects."

COVERITY_SERVER_HOST ??= ""
COVERITY_SERVER_HOST[doc] = "Address of the Coverity Connect server to which defects will be committed."

COVERITY_SERVER_STREAM ??= ""
COVERITY_SERVER_STREAM[doc] = "Stream on the Coverity Connect server to which defects will be committed."

COVERITY_FS_CAPTURE_ARGS ?= " \
    --fs-capture-search ${S} \
"
COVERITY_FS_CAPTURE_ARGS[doc] = "Arguments to pass to cov-build during fs capture; defaults to --fs-capture-search ${S}"

def default_parallel_build(d):
    """
    If PARALLEL_MAKE is set, return it but with a space in between -j and the number (e.g. -j4 => -j 4).
    Otherwise, default to the number of logical cores.
    """
    import re
    parallel_make = (d.getVar("PARALLEL_MAKE") or "").strip()
    pattern = re.compile(r"-j\s*(\d+)")
    m = pattern.match(parallel_make)
    j = int(m.group(1)) if m else oe.utils.cpu_count()
    return "-j {0}".format(j)

COVERITY_PARALLEL_BUILD ??= "${@default_parallel_build(d)}"
COVERITY_PARALLEL_BUILD[doc] = "The -j argument to pass to cov-build, e.g. '-j 4'. Defaults to ${PARALLEL_MAKE}. Don't forget the space between -j and the number."

COVERITY_ANALYZE_OPTIONS ?= " \
    --enable-constraint-fpp \
    --enable-exceptions \
    --enable-virtual \
    --concurrency \
    --security \
    --enable-fnptr \
    --webapp-security \
    --checker-option DEADCODE:no_dead_default:true \
    --disable PASS_BY_VALUE \
    ${COVERITY_ANALYZE_RECURSIVE_OPTIONS} \
"
COVERITY_ANALYZE_OPTIONS[doc] = "Options to pass to cov-analyze."

COVERITY_ANALYZE_RECURSIVE_OPTIONS ?= ""

COVERITY_CONFIGURE_COMPILERS ?= " \
    ${HOST_PREFIX}gcc \
"
COVERITY_CONFIGURE_COMPILERS:toolchain-clang ?= " \
    ${HOST_PREFIX}clang \
"

COVERITY_TRAMPOLINES ?= " \
    ${COVERITY_CONFIGURE_COMPILERS} \
    ${HOST_PREFIX}g++ \
"
COVERITY_TRAMPOLINES:toolchain-clang ?= " \
    ${COVERITY_CONFIGURE_COMPILERS} \
    ${HOST_PREFIX}clang++ \
"
COVERITY_TRAMPOLINES[doc] = "Compilers whose invocations will be intercepted. Doesn't normally needed to be changed."

COVERITY_COMPTYPE ?= "gcc"
COVERITY_COMPTYPE:toolchain-clang ?= "clangcc"

COVERITY_REAL_COMPILER_DIR ??= "${STAGING_BINDIR_TOOLCHAIN}"
COVERITY_REAL_COMPILER_DIR[doc] = "Location of the actual compiler binaries. Doesn't normally needed to be changed."

COVERITY_EXTRA_REAL_TOOLS ?= ""
COVERITY_EXTRA_REAL_TOOLS[doc] = "Additional tools to symlink to in the trampoline directory. Doesn't normally need to be set."

COVERITY_EXPORT_DEFECTS_XREF ??= ""
COVERITY_EXPORT_DEFECTS_XREF[doc] = "If set (and if COVERITY_STRATEGY is not analyze-only), then run cross-referencing during coverity_export_[all_]defects. Makes the export process take much longer."


# What follows shouldn't need to be changed by users
COVERITY_WORKDIR = "${WORKDIR}/coverity"

COVERITY_NATIVE_PATH = "${STAGING_DATADIR_NATIVE}/coverity"

COVERITY_IDIR = "${COVERITY_WORKDIR}/idir"
COVERITY_CONFIG_DIR = "${COVERITY_WORKDIR}/config"
COVERITY_CONFIG_FILE = "${COVERITY_CONFIG_DIR}/coverity_config.xml"
COVERITY_TRAMPOLINE_DIR = "${COVERITY_WORKDIR}/bin"
COVERITY_TMP_DIR = "${COVERITY_WORKDIR}/tmp"

COVERITY_COMMON_DIRS = "${COVERITY_IDIR} ${COVERITY_CONFIG_DIR} ${COVERITY_TRAMPOLINE_DIR} ${COVERITY_TMP_DIR}"

COVERITY_ANALYSIS_DIR = "${COVERITY_WORKDIR}/analysis"
COVERITY_ANALYSIS_COMPONENT_IDIRS = "${COVERITY_ANALYSIS_DIR}/components"
COVERITY_ANALYSIS_IDIR = "${COVERITY_ANALYSIS_DIR}/idir"

COVERITY_EMIT_DEPLOY = "${DEPLOY_DIR}/coverity/emit_dbs/"
SSTATE_ALLOW_OVERLAP_FILES += "${COVERITY_EMIT_DEPLOY}"

BB_SIGNATURE_EXCLUDE_FLAGS += "covprogress-triggerword covprogress-indeterminate covprogress-commitsubstatus"

PATH:prepend ="${COVERITY_NATIVE_PATH}/bin:"

coverity_configure_impl() {
    cp -r ${COVERITY_NATIVE_PATH}/dtd ${COVERITY_WORKDIR}

    cov-configure --ident

    if [ "${COVERITY_STRATEGY}" = "fs-capture-js" ]; then
        cov-configure \
            --javascript \
            --config ${COVERITY_CONFIG_FILE} \
            --tmpdir ${COVERITY_TMP_DIR}
    else
        compilers="${@" ".join([compiler for compiler in (d.getVar("COVERITY_CONFIGURE_COMPILERS") or "").split()])}"
        for compiler in ${compilers}; do
            cov-configure \
                --template \
                --compiler "${compiler}" \
                --config "${COVERITY_CONFIG_FILE}" \
                --comptype "${COVERITY_COMPTYPE}" \
                --tmpdir "${COVERITY_TMP_DIR}"
        done

        for realtool in ${@" ".join((d.getVar("COVERITY_EXTRA_REAL_TOOLS") or "").split())}; do
            ln -s ${COVERITY_REAL_COMPILER_DIR}/${realtool} -t ${COVERITY_TRAMPOLINE_DIR}
        done
    fi
}

python do_coverity_configure() {
    trampolines = (d.getVar("COVERITY_TRAMPOLINES", True) or "").split()
    create_trampolines(trampolines, bb, d)

    bb.build.exec_func("coverity_configure_impl", d)
}

do_coverity_configure[dirs] =+ "${COVERITY_COMMON_DIRS}"
do_coverity_configure[cleandirs] += "${COVERITY_COMMON_DIRS}"
do_coverity_configure[umask] = "022"

def coverity_is_kernel(bb, d):
    return bb.data.inherits_class("kernel", d);


def create_trampolines(compilers, bb, d):
    import textwrap

    staging = d.expand("${COVERITY_TRAMPOLINE_DIR}")
    if coverity_is_kernel(bb, d):
        # TODO: Handle kernel
        staging += "-kernel"

    for compiler in compilers:
        trampoline_script = """
            #!/bin/bash
            if [ "{test}" = "1" ]; then
                ${COVERITY_REAL_COMPILER_DIR}/{compiler} "$@"
            else
                ${COVERITY_NATIVE_PATH}/bin/cov-translate \\
                    --run-compile \\
                    --record-with-source \\
                    --force \\
                    --dir ${COVERITY_IDIR} \\
                    --emulate-string ^-dump.* \\
                    --emulate-string ^-E.* \\
                    --emulate-string ^--help.* \\
                    --emulate-string ^-print.* \\
                    --emulate-string ^--target-help.* \\
                    --emulate-string ^--version.* \\
                    --config ${COVERITY_CONFIG_FILE} \\
                    --tmpdir ${COVERITY_TMP_DIR} \\
                    ${COVERITY_REAL_COMPILER_DIR}/{compiler} \\
                    "$@"
            fi
        """

        # Cleanup leading whitespace
        trampoline_script = textwrap.dedent(trampoline_script).strip()

        # Perform substitutions
        trampoline_script = d.expand(trampoline_script).format( \
            compiler=compiler, \
            test="${DISABLE_COVERITY_TRAMPOLINE}")

        p = os.path.join(staging, compiler)
        with open(p, 'w') as f:
            f.write(trampoline_script)

        # Make executable
        s = os.stat(p)
        os.chmod(p, s.st_mode | 0o111)

create_trampolines[vardeps] += "COVERITY_TRAMPOLINE_DIR COVERITY_REAL_COMPILER_DIR COVERITY_NATIVE_PATH COVERITY_IDIR COVERITY_CONFIG_FILE COVERITY_TMP_DIR COVERITY_REAL_COMPILER_DIR"

do_compile[dirs] =+ "${COVERITY_COMMON_DIRS}"

# Exporting handled in main anonymous Python function at bottom
# TODO: document and move to top
COVERITY_SUPPRESS_ASSERT ?= ""

do_coverity_build() {
    set -x

    if [ "${COVERITY_STRATEGY}" = "fs-capture-js" ]; then
        cov-build \
            --no-command \
            --config ${COVERITY_CONFIG_FILE} \
            --dir ${COVERITY_IDIR} \
            ${COVERITY_FS_CAPTURE_ARGS}
    else
        ret=0
        cov-build \
            ${COVERITY_PARALLEL_BUILD} \
            --add-arg '--ticker-mode no-spin' \
            --force \
            --return-emit-failures \
            --config ${COVERITY_CONFIG_FILE} \
            --replay-from-emit \
            --dir ${COVERITY_IDIR} \
            --tmpdir ${COVERITY_TMP_DIR} \
            || ret=$?

        logfile="${WORKDIR}/temp/log.${@d.getVar("BB_RUNTASK")}"
        fail_count=$(grep -B2 "\[ERROR\] Replay failed" $logfile | sed -nr 's/Failed to compile ([[:digit:]]+) files./\1/p')
        if [ -n "$fail_count" ]; then
            bbwarn "cov-build failed to compile $fail_count translation unit(s) - they will be excluded from analysis."
        fi

        cov-build \
            ${COVERITY_PARALLEL_BUILD} \
            --add-arg '--ticker-mode no-spin' \
            --config ${COVERITY_CONFIG_FILE} \
            --dir ${COVERITY_IDIR} \
            --tmpdir ${COVERITY_TMP_DIR} \
            --finalize
    fi

    # Coverity collects SCM information from files during the analysis stage (i.e.
    # do_coverity_analyze) in order to do automatic owner assignment. But because of
    # Yocto setscene optimizations, there is no guarantee that do_coverity_build will
    # be run locally for all dependencies. If a do_coverity_build task is setscene'd away,
    # then the referent source files might not be present locally at the same path
    # in which they were when do_coverity_build was actually run.
    #
    # For example, a typical source file path on a build agent will look something like this:
    # /tmp/ramdisk/build-ramdisk/work/cortexa9hf-neon-linux-gnueabi/my-recipe/1.0+gitAUTOINC+aa4d7e7488-r0/git/src/main.cpp
    #
    # Suppose we re-use do_coverity_build task output from that agent which includes
    # data derived from that file. When do_coverity_analyze runs, it will attempt to
    # gather SCM information from that file, which will fail unless the file is
    # present at that exact location.
    #
    # The solution is to force collection of SCM information during do_coverity_build.
    cov-import-scm \
        --dir ${COVERITY_IDIR} \
        --scm git
}

do_coverity_build[postfuncs] += "record_coverity_build_info"

python record_coverity_build_info() {
    from pathlib import Path
    import json

    basedir = Path(d.expand("${COVERITY_IDIR}/emit"))

    marker = basedir / "externalsrc"
    if bb.data.inherits_class("externalsrc", d):
        marker.touch()
    elif marker.exists():
        marker.unlink()

    infofile = basedir / "yocto-vars.json"
    with infofile.open("w") as f:
        data = {}
        # There isn't an actual variable that represents this. It's the first part of WORKDIR.
        # It's what will be used as the argument to --strip-path.
        data["workdir_prefix"] = d.expand("${BASE_WORKDIR}/${MULTIMACH_TARGET_SYS}")
        data["recursive_analyze_options"] = d.getVar("COVERITY_ANALYZE_RECURSIVE_OPTIONS")
        f.write(json.dumps(data, indent=4, sort_keys=True))
}

do_coverity_build[dirs] =+ "${COVERITY_COMMON_DIRS}"
do_coverity_build[sstate-inputdirs] = "${COVERITY_IDIR}/emit"
do_coverity_build[sstate-outputdirs] = "${COVERITY_EMIT_DEPLOY}/${PN}/emit"
do_coverity_build[umask] = "022"
do_coverity_build[progress] = "custom:CovBuildProgressHandler"
do_coverity_build[vardepsexclude] += "COVERITY_PARALLEL_BUILD BB_RUNTASK"

SSTATETASKS += "${@"do_coverity_build" if (d.getVar("COVERITY_ENABLE") and d.getVar("COVERITY_STRATEGY") != "analyze-only") else ""}"

python do_coverity_build_setscene() {
    sstate_setscene(d)
}

def determine_components(d, check_externalsrc=False):
    """
    Returns a sorted list of recipes for which do_coverity_build was run as part of
    the current BitBake task graph.

    If check_externalsrc is True, then bail if any of the recipes are under externalsrc/devtool.
    """
    # This only works in task context
    if d.getVar("BB_TASKDEPDATA") is None:
        return []

    import os.path
    pn_list = set()
    this_pn = d.getVar("PN")
    base_dir = d.getVar("COVERITY_EMIT_DEPLOY")

    def check_for_emit_dir(pn):
        emit_dir = os.path.join(base_dir, pn, "emit")
        if not os.path.isdir(emit_dir):
           return False
        # Emit directory could be empty - ensure there's at least one directory inside it
        if not [e for e in os.scandir(emit_dir) if e.is_dir()]:
           return False
        if check_externalsrc:
            # Check for marker files indicating components that are under externalsrc/devtool and bail if any found
            marker_file = os.path.join(emit_dir, "externalsrc")
            if os.path.isfile(marker_file):
                bb.fatal("Refusing to commit defects while externalsrc/devtool is in use for recipe: {0}".format(pn))
        return True

    for task_data in d.getVar("BB_TASKDEPDATA").values():
        if task_data[1] == "do_coverity_build":
            for dep in task_data[4]:
                if check_for_emit_dir(dep):
                    pn_list.add(dep)

    if check_for_emit_dir(this_pn):
        pn_list.add(this_pn)

    # The sorting is just a precaution to improve reproducibility
    return sorted(list(pn_list))

determine_components[vardepsexclude] += "BB_TASKDEPDATA"

coverity_prepare_analysis_impl() {
    # Initialize an empty intermediate directory
    cov-build \
        --dir "${COVERITY_ANALYSIS_IDIR}" \
        --config "${COVERITY_CONFIG_FILE}" \
        --initialize

    components="${COVERITY_INTERNAL_COMPONENTS_LIST}"

    # Add translation units from ourself and all dependencies
    i=1
    for pn in $components; do
        echo "Processing component $pn ($i of ${COVERITY_INTERNAL_COMPONENTS_COUNT})"
        # bitbake doesn't support shell arithmetic...
        i=`echo "$i+1" | bc`
        cp -r ${COVERITY_EMIT_DEPLOY}/${pn} ${COVERITY_ANALYSIS_COMPONENT_IDIRS}

        cov-manage-emit \
            --dir ${COVERITY_ANALYSIS_COMPONENT_IDIRS}/${pn} \
            --config ${COVERITY_CONFIG_FILE} \
            reset-host-name

        cov-manage-emit \
            --dir ${COVERITY_ANALYSIS_IDIR} \
            --config ${COVERITY_CONFIG_FILE} \
            add ${COVERITY_ANALYSIS_COMPONENT_IDIRS}/${pn}

        # For debug purposes - list the source files in the component's idir for which Coverity has SCM information.
        cov-manage-emit \
           --dir ${COVERITY_ANALYSIS_COMPONENT_IDIRS}/${pn} \
           --config ${COVERITY_CONFIG_FILE} \
           list-scm-known

        # Transfer the components SCM information into the shared analysis idir.
		cov-manage-emit \
           --dir ${COVERITY_ANALYSIS_COMPONENT_IDIRS}/${pn} \
           --config ${COVERITY_CONFIG_FILE} \
           dump-scm-annotations --output - \
        | cov-manage-emit \
           --dir ${COVERITY_ANALYSIS_IDIR} \
           --config ${COVERITY_CONFIG_FILE} \
           add-scm-annotations --input -
    done
}

coverity_prepare_analysis_impl[progress] = "outof:\((\d+) of (\d+)\)"

python do_coverity_prepare_analysis() {
    localdata = bb.data.createCopy(d)
    components = determine_components(d)
    localdata.setVar("COVERITY_INTERNAL_COMPONENTS_LIST", " ".join(components))
    localdata.setVar("COVERITY_INTERNAL_COMPONENTS_COUNT", str(len(components)))
    bb.build.exec_func("coverity_prepare_analysis_impl", localdata)
}

do_coverity_prepare_analysis[dirs] =+ "${COVERITY_COMMON_DIRS} ${COVERITY_ANALYSIS_IDIR} ${COVERITY_ANALYSIS_COMPONENT_IDIRS}"
do_coverity_prepare_analysis[cleandirs] += "${COVERITY_ANALYSIS_IDIR} ${COVERITY_ANALYSIS_COMPONENT_IDIRS}"
do_coverity_prepare_analysis[umask] = "022"
do_coverity_prepare_analysis[recrdeptask] = "do_coverity_build"
do_coverity_prepare_analysis[recideptask] = "do_${BB_DEFAULT_TASK}"
do_coverity_prepare_analysis[depends] += "bc-native:do_populate_sysroot"

coverity_analyze_impl() {
    cov-analyze \
        ${COVERITY_INTERNAL_ANALYZE_STRIP_PATH_FLAGS} \
        --ticker-mode no-spin \
        --config "${COVERITY_CONFIG_FILE}" \
        --security-file "${COVERITY_ANALYSIS_LIC}" \
        --dir "${COVERITY_ANALYSIS_IDIR}" \
        --tmpdir "${COVERITY_TMP_DIR}" \
        --force \
        --enable-callgraph-metrics \
        ${COVERITY_ANALYZE_OPTIONS}
}

coverity_analyze_impl[progress] = "custom:CovBuildProgressHandler"
coverity_analyze_impl[vardepsexclude] += "COVERITY_ANALYSIS_LIC"

python do_coverity_analyze() {
    import json
    from pathlib import Path
    components = determine_components(d)

    strip_paths = set()
    extra_analyze_options = set()

    for com in components:
        infofile = Path(d.getVar("COVERITY_EMIT_DEPLOY")) / com / "emit" / "yocto-vars.json"
        assert infofile.exists()
        with infofile.open() as f:
            data = json.loads(f.read())
        strip_paths.add(data["workdir_prefix"])
        extra_analyze_options.add(data["recursive_analyze_options"])

    strip_path_flags = " ".join(["--strip-path {0}".format(p) for p in sorted(strip_paths)])

    localdata = bb.data.createCopy(d)
    localdata.setVar("COVERITY_INTERNAL_ANALYZE_STRIP_PATH_FLAGS", strip_path_flags)
    localdata.appendVar("COVERITY_ANALYZE_RECURSIVE_OPTIONS", " ".join(extra_analyze_options))
    bb.build.exec_func("coverity_analyze_impl", localdata)
}

do_coverity_analyze[covprogress-triggerword] = "Running analysis"
do_coverity_analyze[dirs] =+ "${COVERITY_COMMON_DIRS} ${COVERITY_ANALYSIS_IDIR} ${COVERITY_ANALYSIS_COMPONENT_IDIRS}"
do_coverity_analyze[umask] = "022"
# cov-analyze is very heavyweight so there is no point in running them concurrently (e.g. across multiconfigs)
do_coverity_analyze[lockfiles] += "${PERSISTENT_DIR}/coverity-analysis.lock"
do_coverity_analyze[network] = "1"

export_defects_impl() {
    cov-format-errors \
        --dir "${COVERITY_ANALYSIS_IDIR}" \
        --html-output ${WORKDIR}/coverity-defects \
        --security-file "${COVERITY_ANALYSIS_LIC}" \
        --tmpdir "${COVERITY_TMP_DIR}" \
        ${COVERITY_INTERNAL_FORMAT_ERRORS_ARGS}

    bbplain "coverity.bbclass: To view defects for ${PN}, visit this URL: file://${WORKDIR}/coverity-defects/index.html"
}

export_defects_impl[progress] = "custom:CovBuildProgressHandler"

def call_export_defects(d, is_all):
    localdata = bb.data.createCopy(d)
    if not is_all:
        import re
        pattern = re.escape(d.expand("/${PN}/${EXTENDPE}${PV}-${PR}")) + "|${S}"
        args = "--include-files '{}' --exclude-files '/recipe-sysroot'".format(pattern)
        localdata.appendVar("COVERITY_INTERNAL_FORMAT_ERRORS_ARGS", args)

    if d.getVar("COVERITY_STRATEGY") != "analyze-only" and d.getVar("COVERITY_EXPORT_DEFECTS_XREF"):
        localdata.appendVar("COVERITY_INTERNAL_FORMAT_ERRORS_ARGS", "-x")

    bb.build.exec_func("export_defects_impl", localdata)

python do_coverity_export_defects() {
    call_export_defects(d, is_all=False)
}

do_coverity_export_defects[dirs] =+ "${WORKDIR}/coverity-defects ${COVERITY_COMMON_DIRS} ${COVERITY_ANALYSIS_IDIR}"
do_coverity_export_defects[cleandirs] += "${WORKDIR}/coverity-defects"
do_coverity_export_defects[umask] = "022"

python do_coverity_export_all_defects() {
    call_export_defects(d, is_all=True)
}

do_coverity_export_all_defects[dirs] =+ "${WORKDIR}/coverity-defects ${COVERITY_ANALYSIS_IDIR}"
do_coverity_export_all_defects[cleandirs] += "${WORKDIR}/coverity-defects"
do_coverity_export_all_defects[umask] = "022"

do_coverity_commit_defects() {
    cov-commit-defects \
        --dir "${COVERITY_ANALYSIS_IDIR}" \
        --security-file "${COVERITY_ANALYSIS_LIC}" \
        --tmpdir "${COVERITY_TMP_DIR}" \
        --auth-key-file "${COVERITY_AUTH_KEY_FILE}" \
        --encryption none \
        --dataport 9090 \
        -g \
        --host "${COVERITY_SERVER_HOST}" \
        --stream "${COVERITY_SERVER_STREAM}"

    # TODO:    --version "${BUILD_NUMBER}"
}

do_coverity_commit_defects[prefuncs] =+ "pre_commit_defects"
do_coverity_commit_defects[dirs] += "${COVERITY_ANALYSIS_IDIR} ${COVERITY_COMMON_DIRS}"
do_coverity_commit_defects[progress] = "custom:CovBuildProgressHandler"
do_coverity_commit_defects[covprogress-indeterminate] = "1"
do_coverity_commit_defects[covprogress-commitsubstatus] = "1"
do_coverity_commit_defects[nostamp] = "1"
do_coverity_commit_defects[network] = "1"

python pre_commit_defects() {
    # Bail if any components are under externalsrc
    determine_components(d, check_externalsrc=True)
}

python __anonymous() {
    if d.getVar("BBCLASSEXTEND"):
        bb.fatal("coverity: incompatible with recipes utilizing BBCLASSEXTEND")

    if not d.getVar("COVERITY_ENABLE"):
        return

    d.appendVar("DEPENDS", " coverity-native")

    strategy = d.getVar("COVERITY_STRATEGY")
    supported_strategies = ["auto", "fs-capture-js", "cmake", "path-hijack"]
    if strategy not in supported_strategies:
        bb.fatal("coverity: unsupported strategy {0}; supported choices are: {1}".format(strategy, ", ".join(supported_strategies)))
        return

    # Handle 'auto' strategy
    if strategy == "auto":
        computed_strategy = None
        if bb.data.inherits_class("cmake", d):
            computed_strategy = "cmake"
        elif bb.data.inherits_class("qmake5", d):
            computed_strategy = "path-hijack"
        elif bb.data.inherits_class("image", d):
            computed_strategy = "analyze-only"
        if not computed_strategy:
            bb.fatal("coverity: unable to automatically determine integration strategy; please set COVERITY_STRATEGY manually. Choices: {0}".format(", ".join(supported_strategies)))
            return
        strategy = computed_strategy
        d.setVar("COVERITY_STRATEGY", strategy)

    if strategy in ["fs-capture-js", "path-hijack"]:
        bb.build.addtask("do_coverity_configure", "do_configure", "do_prepare_recipe_sysroot", d)
        if strategy == "path-hijack":
            d.prependVarFlag("do_compile", "dirs", d.getVar("COVERITY_TRAMPOLINE_DIR"))
            # Modify do_compile to hijack PATH
            if d.getVarFlag("do_configure", "python", False):
                bb.fatal("coverity: 'path-hijack' strategy was chosen, but do_compile is a Python task?")
            else:
                d.prependVar("do_compile", "export PATH=\"${COVERITY_TRAMPOLINE_DIR}:${PATH}\"\n")
    elif strategy == "cmake":
        bb.build.addtask("do_coverity_configure", "do_generate_toolchain_file", "do_prepare_recipe_sysroot", d)
        d.appendVar("EXTRA_OECMAKE", " --debug-output")
        d.setVar("OECMAKE_C_COMPILER", "${COVERITY_TRAMPOLINE_DIR}/${HOST_PREFIX}gcc")
        d.setVar("OECMAKE_C_COMPILER:toolchain-clang", "${COVERITY_TRAMPOLINE_DIR}/${HOST_PREFIX}clang")
        d.setVar("OECMAKE_CXX_COMPILER", "${COVERITY_TRAMPOLINE_DIR}/${HOST_PREFIX}g++")
        d.setVar("OECMAKE_CXX_COMPILER:toolchain-clang", "${COVERITY_TRAMPOLINE_DIR}/${HOST_PREFIX}clang++")

        # Modify do_configure to inject the DISABLE_COVERITY_TRAMPOLINE env variable
        if d.getVarFlag("do_configure", "python", False):
            bb.fatal("coverity: 'cmake' strategy was chosen, but do_configure is a Python task?")
        else:
            d.prependVar("do_configure", "export DISABLE_COVERITY_TRAMPOLINE=1\n")

    if strategy == "analyze-only":
        bb.build.addtask("do_coverity_configure", None, "do_prepare_recipe_sysroot", d)
        bb.build.addtask("do_coverity_prepare_analysis", None, "do_coverity_configure", d)
    else:
        bb.build.addtask("do_coverity_build", None, "do_compile", d)
        bb.build.addtask("do_coverity_build_setscene", None, None, d)

        bb.build.addtask("do_coverity_prepare_analysis", None, "do_coverity_build do_coverity_configure", d)

    d.setVarFlag("COVERITY_SUPPRESS_ASSERT", "export", "1")

    bb.build.addtask("do_coverity_analyze", None, "do_coverity_prepare_analysis", d)

    if strategy != "analyze-only":
        bb.build.addtask("do_coverity_export_defects", None, "do_coverity_analyze", d)
    bb.build.addtask("do_coverity_export_all_defects", None, "do_coverity_analyze", d)

    if d.getVar("COVERITY_ENABLE_COMMIT") and (strategy == "analyze-only"):
        bb.build.addtask("do_coverity_commit_defects", None, "do_coverity_analyze", d)

    for task in (d.getVar("__BBTASKS") or []):
        if task.startswith("do_coverity_"):
            d.appendVarFlag(task, "depends", " coverity-native:do_populate_sysroot")
}

def install_progress_handler():
    from coverity.progress import CovBuildProgressHandler

    # Inject progress handlers into global namespace so build.py can find them
    __builtins__["CovBuildProgressHandler"] = CovBuildProgressHandler

    return "OK"


# Trigger installation
__COV_INSTALL_PROGRESS_HANDLERS := "${@install_progress_handler()}"
