SUMMARY = "straturaOS Configuration System"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://config.json \
    file://stratura-config.service \
"

inherit systemd

SYSTEMD_SERVICE_${PN} = "stratura-config.service"

do_install() {
    install -d ${D}${sysconfdir}/stratura
    install -m 0644 ${WORKDIR}/config.json ${D}${sysconfdir}/stratura/

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/stratura-config.service ${D}${systemd_system_unitdir}
}

FILES_${PN} += " \
    ${sysconfdir}/stratura \
    ${systemd_system_unitdir} \
" 