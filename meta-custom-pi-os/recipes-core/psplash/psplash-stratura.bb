SUMMARY = "Custom splash screen for straturaOS"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS += "psplash"

SRC_URI = "file://psplash-stratura.png"

inherit base

do_install() {
    install -d ${D}${datadir}/psplash
    install -m 0644 ${WORKDIR}/psplash-stratura.png ${D}${datadir}/psplash/psplash-stratura.png
}

FILES_${PN} += "${datadir}/psplash/psplash-stratura.png" 