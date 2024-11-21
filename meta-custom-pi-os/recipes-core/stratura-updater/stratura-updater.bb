SUMMARY = "straturaOS Update System"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://update-client \
    file://update-client.service \
    file://update-hooks.sh \
"

inherit systemd

SYSTEMD_SERVICE_${PN} = "update-client.service"

RDEPENDS_${PN} += "rauc curl jq"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/update-client ${D}${bindir}/update-client
    install -m 0755 ${WORKDIR}/update-hooks.sh ${D}${bindir}/update-hooks

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/update-client.service ${D}${systemd_system_unitdir}
} 