# Copyright 1999-2017 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=5
PYTHON_COMPAT=( python2_7 )

if [[ $PV = *9999* ]]; then
	scm_eclass=git-r3
	EGIT_REPO_URI="https://github.com/ceph/ceph.git"
	SRC_URI=""
else
	[[ -n ${UPSTREAM_VER} ]] && \
		UPSTREAM_PATCHSET_URI="https://dev.gentoo.org/~dlan/distfiles/${P}-upstream-patches-${UPSTREAM_VER}.tar.xz"

	SRC_URI="https://download.ceph.com/tarballs/${P}.tar.gz
		${UPSTREAM_PATCHSET_URI}"
fi
KEYWORDS="~amd64 ~arm ~ppc ~ppc64 ~x86"

inherit check-reqs autotools eutils multilib python-single-r1 udev readme.gentoo-r1 systemd ${scm_eclass}

DESCRIPTION="Ceph distributed filesystem"
HOMEPAGE="https://ceph.com/"

LICENSE="LGPL-2.1"
SLOT="0"
IUSE="babeltrace cryptopp debug fuse gtk libatomic +libaio lttng +nss radosgw static-libs jemalloc python tcmalloc xfs zfs"

COMMON_DEPEND="
	app-arch/snappy
	dev-libs/boost:=[threads]
	dev-libs/fcgi
	dev-libs/libaio
	dev-libs/libedit
	dev-libs/leveldb[snappy]
	nss? ( dev-libs/nss )
	cryptopp? ( dev-libs/crypto++ )
	sys-apps/keyutils
	sys-apps/util-linux
	dev-libs/libxml2
	babeltrace? ( dev-util/babeltrace )
	fuse? ( sys-fs/fuse:0 )
	libatomic? ( dev-libs/libatomic_ops )
	xfs? ( sys-fs/xfsprogs )
	zfs? ( sys-fs/zfs )
	gtk? (
		x11-libs/gtk+:2
		dev-cpp/gtkmm:2.4
		gnome-base/librsvg
	)
	radosgw? (
		dev-libs/fcgi
		dev-libs/expat
		net-misc/curl
	)
	jemalloc? ( dev-libs/jemalloc )
	!jemalloc? ( dev-util/google-perftools )
	lttng? ( dev-util/lttng-ust )
	${PYTHON_DEPS}
	"
DEPEND="${COMMON_DEPEND}
	virtual/pkgconfig"
RDEPEND="${COMMON_DEPEND}
	sys-apps/hdparm
	dev-python/flask[${PYTHON_USEDEP}]
	dev-python/requests[${PYTHON_USEDEP}]
	"
REQUIRED_USE="
	${PYTHON_REQUIRED_USE}
	^^ ( nss cryptopp )
	?? ( jemalloc tcmalloc )
	"

STRIP_MASK="/usr/lib*/rados-classes/*"

PATCHES=(
	"${FILESDIR}"/${PN}-0.79-libzfs.patch
)
CHECKREQS_DISK_BUILD="1400M"

pkg_setup() {
	python_setup
}

src_prepare() {
	# Upstream's patchset
	if [[ -n ${UPSTREAM_VER} ]]; then
		einfo "Try to apply Ceph Upstream patch set"
		EPATCH_SUFFIX="patch" \
		EPATCH_FORCE="yes" \
		EPATCH_OPTS="-p1" \
			epatch "${WORKDIR}"/patches-upstream
	fi

	[[ ${PATCHES[@]} ]] && epatch "${PATCHES[@]}"

	epatch_user
	eautoreconf
}

src_configure() {
	local myeconfargs=(
		--without-hadoop
		--docdir="${EPREFIX}/usr/share/doc/${PF}"
		--includedir=/usr/include
		$(use_with debug)
		$(use_with fuse)
		$(use_with libaio)
		$(use_with libatomic libatomic-ops)
		$(use_with nss)
		$(use_with cryptopp)
		$(use_with radosgw)
		$(use_with gtk gtk2)
		$(use_enable static-libs static)
		$(use_with jemalloc)
		$(use_with xfs libxfs)
		$(use_with zfs libzfs)
		$(use_with lttng )
		$(use_with babeltrace)
		--without-kinetic
		--without-librocksdb
	)

	use jemalloc || \
		myeconfargs+=( $(usex tcmalloc " --with-tcmalloc" " --with-tcmalloc-minimal") )

	PYTHON="${EPYTHON}" \
		econf "${myeconfargs[@]}"
}

src_install() {
	default

	prune_libtool_files --all

	exeinto /usr/$(get_libdir)/ceph
	newexe src/init-ceph ceph_init.sh

	insinto /etc/logrotate.d/
	newins "${FILESDIR}"/ceph.logrotate ${PN}

	chmod 644 "${ED}"/usr/share/doc/${PF}/sample.*

	keepdir /var/lib/${PN}
	keepdir /var/lib/${PN}/tmp
	keepdir /var/log/${PN}/stat

	newinitd "${FILESDIR}/rbdmap.initd" rbdmap
	newinitd "${FILESDIR}/${PN}.initd-r1.1" ${PN}
	newconfd "${FILESDIR}/${PN}.confd-r1" ${PN}

	systemd_dounit           "${FILESDIR}/ceph.target"
	systemd_newunit          "${FILESDIR}/ceph-mds_at.service"      "ceph-mds@.service"
	systemd_install_serviced "${FILESDIR}/ceph-mds_at.service.conf" "ceph-mds@.service"
	systemd_newunit          "${FILESDIR}/ceph-osd_at.service"      "ceph-osd@.service"
	systemd_install_serviced "${FILESDIR}/ceph-osd_at.service.conf" "ceph-osd@.service"
	systemd_newunit          "${FILESDIR}/ceph-mon_at.service"      "ceph-mon@.service"

	python_fix_shebang \
		"${ED}"/usr/sbin/{ceph-disk,ceph-create-keys} \
		"${ED}"/usr/bin/{ceph,ceph-rest-api,ceph-brag}

	#install udev rules
	udev_dorules udev/50-rbd.rules
	udev_dorules udev/95-ceph-osd.rules

	readme.gentoo_create_doc
}

pkg_postinst() {
	readme.gentoo_print_elog
}
