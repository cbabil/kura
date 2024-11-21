SUMMARY = "straturaOS Core Components"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://__init__.py \
    file://network.py \
    file://containers.py \
    file://state.py \
    file://api.py \
    file://update.py \
"

inherit setuptools3

RDEPENDS:${PN} += " \
    python3-docker \
    python3-requests \
    python3-dbus \
    python3-cryptography \
    python3-psutil \
    python3-prometheus-client \
"

do_install:append() {
    install -d ${D}${libdir}/python3/dist-packages/stratura
    install -m 0644 ${WORKDIR}/*.py ${D}${libdir}/python3/dist-packages/stratura/
}

FILES:${PN} += "${libdir}/python3/dist-packages/stratura/*" 