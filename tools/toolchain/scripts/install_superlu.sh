#!/bin/bash -e
[ "${BASH_SOURCE[0]}" ] && SCRIPT_NAME="${BASH_SOURCE[0]}" || SCRIPT_NAME=$0
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_NAME")" && pwd -P)"

superlu_ver="5.1.2"
superlu_sha256="91032b9a4d23bd14272607b8fc9b6cbb936c385902ca4d3d0ba2d1014fbcd99d"
source "${SCRIPT_DIR}"/common_vars.sh
source "${SCRIPT_DIR}"/tool_kit.sh
source "${SCRIPT_DIR}"/signal_trap.sh
source "${INSTALLDIR}"/toolchain.conf
source "${INSTALLDIR}"/toolchain.env

[ -f "${BUILDDIR}/setup_superlu" ] && rm "${BUILDDIR}/setup_superlu"

SUPERLU_CFLAGS=''
SUPERLU_LDFLAGS=''
SUPERLU_LIBS=''
! [ -d "${BUILDDIR}" ] && mkdir -p "${BUILDDIR}"
cd "${BUILDDIR}"

case "$with_superlu" in
    __INSTALL__)
        echo "==================== Installing SuperLU_DIST ===================="
        require_env PARMETIS_LDFLAGS
        require_env PARMETIS_LIBS
        require_env METIS_LDFLAGS
        require_env METIS_LIBS
        require_env MATH_LIBS
        pkg_install_dir="${INSTALLDIR}/superlu_dist-${superlu_ver}"
        install_lock_file="$pkg_install_dir/install_successful"
        if verify_checksums "${install_lock_file}" ; then
            echo "superlu_dist-${superlu_ver} is already installed, skipping it."
        else
            if [ -f superlu_dist_${superlu_ver}.tar.gz ] ; then
                echo "superlu_dist_${superlu_ver}.tar.gz is found"
            else
                download_pkg ${DOWNLOADER_FLAGS} ${superlu_sha256} \
                             https://www.cp2k.org/static/downloads/superlu_dist_${superlu_ver}.tar.gz
            fi
            echo "Installing from scratch into ${pkg_install_dir}"
            [ -d SuperLU_DIST_${superlu_ver} ] && rm -rf SuperLU_DIST_${superlu_ver}
            tar -xzf superlu_dist_${superlu_ver}.tar.gz
            cd SuperLU_DIST_${superlu_ver}
            mv make.inc make.inc.orig
            # using the OMP-based math libraries here (if available) for the executables since PARMETS/METIS also use OMP if available
            cat <<EOF >> make.inc
PLAT=_${OPENBLAS_ARCH}
DSUPERLULIB= ${PWD}/lib/libsuperlu_dist.a
LIBS=\$(DSUPERLULIB) ${PARMETIS_LDFLAGS} ${METIS_LDFLAGS} ${MATH_LDFLAGS} ${PARMETIS_LIBS} ${METIS_LIBS} $(resolve_string "${MATH_LIBS}" OMP)
ARCH=ar
ARCHFLAGS=cr
RANLIB=ranlib
CC=${MPICC}
CFLAGS=${CFLAGS} -std=c99 -fPIC ${PARMETIS_CFLAGS} ${METIS_CFLAGS} ${MATH_CFLAGS}
NOOPTS=-O0
FORTRAN=${MPIFC}
F90FLAGS=${FFLAGS}
LOADER=\$(CC)
LOADOPTS=${CFLAGS}
CDEFS=-DAdd_
EOF
            make > make.log 2>&1 #-j $nprocs will crash
            # no make install, so need to this manually
            chmod a+r lib/* SRC/*.h
            ! [ -d "${pkg_install_dir}/lib" ] && mkdir -p "${pkg_install_dir}/lib"
            cp lib/libsuperlu_dist.a "${pkg_install_dir}/lib"
            ! [ -d "${pkg_install_dir}/include" ] && mkdir -p "${pkg_install_dir}/include"
            cp SRC/*.h "${pkg_install_dir}/include"
            cd ..
            write_checksums "${install_lock_file}" "${SCRIPT_DIR}/$(basename ${SCRIPT_NAME})"
        fi
        SUPERLU_CFLAGS="-I'${pkg_install_dir}/include'"
        SUPERLU_LDFLAGS="-L'${pkg_install_dir}/lib' -Wl,-rpath='${pkg_install_dir}/lib'"
        ;;
    __SYSTEM__)
        echo "==================== Finding SuperLU_DIST from system paths ===================="
        check_lib -lsuperlu_dist "SuperLU_DIST"
        add_include_from_paths SUPERLU_CFLAGS "superlu*" $INCLUDE_PATHS
        add_lib_from_paths SUPERLU_LDFLAGS "libsuperlu*" $LIB_PATHS
        ;;
    __DONTUSE__)
        ;;
    *)
        echo "==================== Linking Superlu_Dist to user paths ===================="
        pkg_install_dir="$with_superlu"
        check_dir "${pkg_install_dir}/lib"
        check_dir "${pkg_install_dir}/include"
        SUPERLU_CFLAGS="-I'${pkg_install_dir}/include'"
        SUPERLU_LDFLAGS="-L'${pkg_install_dir}/lib' -Wl,-rpath='${pkg_install_dir}/lib'"
        ;;
esac
if [ "$with_superlu" != "__DONTUSE__" ] ; then
    SUPERLU_LIBS="-lsuperlu_dist"
    if [ "$with_superlu" != "__SYSTEM__" ] ; then
        cat <<EOF > "${BUILDDIR}/setup_superlu"
prepend_path LD_LIBRARY_PATH "$pkg_install_dir/lib"
prepend_path LD_RUN_PATH "$pkg_install_dir/lib"
prepend_path LIBRARY_PATH "$pkg_install_dir/lib"
prepend_path CPATH "$pkg_install_dir/include"
EOF
        cat "${BUILDDIR}/setup_superlu" >> $SETUPFILE
    fi
    cat <<EOF >> "${BUILDDIR}/setup_superlu"
export SUPERLU_CFLAGS="${SUPERLU_CFLAGS}"
export SUPERLU_LDFLAGS="${SUPERLU_LDFLAGS}"
export SUPERLU_LIBS="${SUPERLU_LIBS}"
export CP_CFLAGS="\${CP_CFLAGS} IF_MPI(${SUPERLU_CFLAGS}|)"
export CP_LDFLAGS="\${CP_LDFLAGS} IF_MPI(${SUPERLU_LDFLAGS}|)"
export CP_LIBS="IF_MPI(${SUPERLU_LIBS}|) \${CP_LIBS}"
EOF
fi

# update toolchain environment
load "${BUILDDIR}/setup_superlu"
export -p > "${INSTALLDIR}"/toolchain.env

cd "${ROOTDIR}"
report_timing "superlu"
