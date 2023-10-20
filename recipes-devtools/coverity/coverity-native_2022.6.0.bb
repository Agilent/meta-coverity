LICENSE = "Proprietary"
LIC_FILES_CHKSUM = " "

# Coverity is a commerical product that you must pay for and license in order to
# use. You need to deploy the cov-analysis-linux64-${PN}.tar.gz tarball to a
# place accessible on your network and point this recipe at it.
#
# The suggested place to host the tarball is on the Coverity server itself, under 'Downloads'. Then
# you'll set SRC_URI to something like: https://[Coverity server]/downloads/cov-analysis-linux64-${PV}.tar.gz
SRC_URI ?= ""

python() {
    if not d.getVar("COVERITY_ENABLE"):
        raise bb.parse.SkipRecipe("COVERITY_ENABLE is disabled; set to non-empty string to enable. See meta-coverity README for more instructions.")
    if not d.getVar("SRC_URI"):
        bb.fatal("You need to set SRC_URI:pn-coverity-native; see meta-coverity README for more instructions.")
}

SRC_URI[md5sum] = "c8aa4dc121d0df7623242aa79f4bf76d"
SRC_URI[sha256sum] = "5bee489534bb81e66f0f58e17edd1335633bfd884179e0260af9e2270abe07cd"
SRC_URI[sha1sum] = "a93dea8a882cd72946724957f607816223ef0e14"
SRC_URI[sha384sum] = "04763e3cb066e66723f7af64cc45ea569deb6b7be8af51e72b7e65af4e1aa8b4b64ca61679ff266cd57ffade2ae7444b"
SRC_URI[sha512sum] = "efdc183e5b8bcc887c4a7d0aa20a0b165508836e80411747b4f3bbf00d471b1ce5106ff3d3f2e1b8b0644345326b40a9b16babd88b75a91054541ee668531028"

do_compile[noexec] = "1"
do_configure[noexec] = "1"

INHIBIT_DEFAULT_DEPS = "1"

S = "${WORKDIR}/cov-analysis-linux64-${PV}"

# This will be large (~2 GB), but thankfully every recipe that uses it will hard link the stuff in.
do_install () {
    mkdir -p ${D}${datadir}/coverity
    for path in bin config certs dtd framework-analyzer jshint lib library node python3.7 sdk support-angularjs xsl VERSION VERSION.xml .install4j; do
        cp -r --no-preserve=ownership ${S}/${path} ${D}${datadir}/coverity/
    done

    mkdir -p ${D}${datadir}/coverity/doc/
    for docpath in en examples zh-cn; do
        cp -r --no-preserve=ownership ${S}/doc/${docpath} ${D}${datadir}/coverity/doc/
    done

    # This is some kind of IA-64 shared library. Yocto won't be able to run 'strip' on it and will throw an error.
    # We don't need it anyway, so just delete it.
    rm ${D}${datadir}/coverity/bin/libjnidispatch.so
}

INSANE_SKIP_${PN} = "already-stripped"
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"

inherit native
