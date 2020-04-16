#!/bin/bash -e
[ "${BASH_SOURCE[0]}" ] && SCRIPT_NAME="${BASH_SOURCE[0]}" || SCRIPT_NAME=$0
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_NAME")" && pwd -P)"

plumed_ver="2.5.2"
plumed_pkg="plumed-${plumed_ver}.tgz"
plumed_sha256="873b694ad3c480f7855cd4c02fe5fbee4759679db1604ef4056e0571c61b9979"

source "${SCRIPT_DIR}"/common_vars.sh
source "${SCRIPT_DIR}"/tool_kit.sh
source "${SCRIPT_DIR}"/signal_trap.sh
source "${INSTALLDIR}"/toolchain.conf
source "${INSTALLDIR}"/toolchain.env

[ -f "${BUILDDIR}/setup_plumed" ] && rm "${BUILDDIR}/setup_plumed"

PLUMED_LDFLAGS=''
PLUMED_LIBS=''

! [ -d "${BUILDDIR}" ] && mkdir -p "${BUILDDIR}"
cd "${BUILDDIR}"

case "$with_plumed" in
    __INSTALL__)
        echo "==================== Installing PLUMED ===================="
        pkg_install_dir="${INSTALLDIR}/plumed-${plumed_ver}"
        install_lock_file="$pkg_install_dir/install_successful"
        if verify_checksums "${install_lock_file}" ; then
            echo "plumed-${plumed_ver} is already installed, skipping it."
        else
            if [ -f ${plumed_pkg} ] ; then
                echo "${plumed_pkg} is found"
            else
                download_pkg ${DOWNLOADER_FLAGS} ${plumed_sha256} \
                             https://www.cp2k.org/static/downloads/${plumed_pkg}
            fi

            [ -d plumed-${plumed_ver} ] && rm -rf plumed-${plumed_ver}
            tar -xzf ${plumed_pkg}

            echo "Installing from scratch into ${pkg_install_dir}"
            cd plumed-${plumed_ver}
            ./configure CXX="${MPICXX}" --prefix=${pkg_install_dir} --libdir="${pkg_install_dir}/lib" CXXFLAGS="-I${GSLROOT}/include" LIBS="-L${GSLROOT}/lib -L${MKLROOT}/lib/intel64 -Wl,--no-as-needed -lmkl_intel_lp64 -lmkl_sequential -lmkl_core -lpthread -lm -ldl" > configure.log 2>&1
            make -j $NPROCS > make.log 2>&1
            make install > install.log 2>&1
            write_checksums "${install_lock_file}" "${SCRIPT_DIR}/$(basename ${SCRIPT_NAME})"
        fi
        PLUMED_LDFLAGS="-L'${pkg_install_dir}/lib' -Wl,-rpath='${pkg_install_dir}/lib'"
        ;;
    __SYSTEM__)
        echo "==================== Finding PLUMED from system paths ===================="
        check_lib -lplumed "PLUMED"
        add_lib_from_paths PLUMED_LDFLAGS "libplumed*" $LIB_PATHS
        ;;
    __DONTUSE__)
        ;;
    *)
        echo "==================== Linking PLUMED to user paths ===================="
        pkg_install_dir="$with_plumed"
        check_dir "${pkg_install_dir}/lib"
        PLUMED_LDFLAGS="-L'${pkg_install_dir}/lib' -Wl,-rpath='${pkg_install_dir}/lib'"
        ;;
esac

if [ "$with_plumed" != "__DONTUSE__" ] ; then
    PLUMED_LIBS='-lplumedKernel -lplumed -ldl -lstdc++ -lz -ldl'
    if [ "$with_plumed" != "__SYSTEM__" ] ; then
        cat <<EOF > "${BUILDDIR}/setup_plumed"
prepend_path LD_LIBRARY_PATH "$pkg_install_dir/lib"
prepend_path LD_RUN_PATH "$pkg_install_dir/lib"
prepend_path LIBRARY_PATH "$pkg_install_dir/lib"
EOF
        cat "${BUILDDIR}/setup_plumed" >> $SETUPFILE
    fi

    cat <<EOF >> "${BUILDDIR}/setup_plumed"
export PLUMED_LDFLAGS="${PLUMED_LDFLAGS}"
export PLUMED_LIBS="${PLUMED_LIBS}"
export CP_DFLAGS="\${CP_DFLAGS} -D__PLUMED2"
export CP_LDFLAGS="\${CP_LDFLAGS} ${PLUMED_LDFLAGS}"
export CP_LIBS="${PLUMED_LIBS} \${CP_LIBS}"
EOF
fi

# update toolchain environment
load "${BUILDDIR}/setup_plumed"
export -p > "${INSTALLDIR}/toolchain.env"

cd "${ROOTDIR}"
report_timing "plumed"
