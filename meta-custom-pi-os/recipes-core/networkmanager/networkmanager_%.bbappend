FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI += " \
    file://networkmanager.conf \
    file://00-stratura-network.conf \
"

do_install_append() {
    install -d ${D}${sysconfdir}/NetworkManager/conf.d
    install -m 0644 ${WORKDIR}/networkmanager.conf ${D}${sysconfdir}/NetworkManager/conf.d/
    install -m 0644 ${WORKDIR}/00-stratura-network.conf ${D}${sysconfdir}/NetworkManager/conf.d/
} 