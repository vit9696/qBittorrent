#!/bin/bash -e -u -x
# -e / set -e / set -o errexit - exit immediately if a command exits with a non-zero status
# -u / set -u / set -o nounset - treat unset variables as an error when substituting
# -x / set -x / set -o xtrace  - print commands and their arguments as they are executed
set -o pipefail     # the return value of a pipeline is the status of the last command to exit with a non-zero status

MIN_MACOS_VER=12
LIBTORRENT_COMMIT="2ab8fedabb7716947edc77958da6d0b5e1040df9"
QBITTORRENT_COMMIT="a23f45cc70e7bb32924ef01f080f73dd1c83d2be"
OPENSSL_ROOT_DIR=/usr/local/opt/openssl
OPENSSL_LIBRARIES=/usr/local/opt/openssl/lib
QT_ROOT="$(brew --prefix qt)"

SELFDIR=$(dirname $0)
cd $SELFDIR
SELFDIR=$(pwd)
cd -
WORKDIR=${SELFDIR}/build
echo "Current working directory: ${WORKDIR}"
DEPSDIR="${WORKDIR%/}/ext"      # all dependencies will be placed here
rm -rf ${WORKDIR} ${SELFDIR}/dist
mkdir -p ${WORKDIR}/ext
cd ${WORKDIR}

git_shallow_clone() {
  mkdir -p $1
  cd $1
  git init
  git remote add origin $2
  git fetch --depth 1 origin $3
  git checkout FETCH_HEAD
  git submodule update --init --recommend-shallow
  cd -
}

# download and build libtorrent
git_shallow_clone libtorrent https://github.com/arvidn/libtorrent $LIBTORRENT_COMMIT
cd libtorrent

cmake -Wno-dev -B build -G Ninja -DCMAKE_PREFIX_PATH=${DEPSDIR} -DCMAKE_CXX_STANDARD=17 \
  -DCMAKE_CXX_EXTENSIONS=OFF -DCMAKE_OSX_DEPLOYMENT_TARGET=${MIN_MACOS_VER} \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -Ddeprecated-functions=OFF \
  -DCMAKE_INSTALL_PREFIX=${DEPSDIR} -DOPENSSL_ROOT_DIR=${OPENSSL_ROOT_DIR} \
  -DOPENSSL_LIBRARIES=${OPENSSL_ROOT_DIR}
cmake --build build
cmake --install build

cd -

# Download and build qBittorrent
git_shallow_clone qBittorrent https://github.com/qBittorrent/qBittorrent $QBITTORRENT_COMMIT
cd qBittorrent
cp -r ${SELFDIR}/graphics/* .
git apply ${SELFDIR}/patches/qBittorrent-colours.diff
git apply ${SELFDIR}/patches/qBittorrent-sequential.diff
git apply ${SELFDIR}/patches/qBittorrent-dbus.diff
#git apply ${SELFDIR}/patches/qBittorrent-light.diff
git apply ${SELFDIR}/patches/qBittorrent-version.diff
git apply ${SELFDIR}/patches/qBittorrent-release.diff

mkdir build && cd build
cmake -DCMAKE_PREFIX_PATH="${DEPSDIR}" -DCMAKE_CXX_STANDARD=17 \
  -DCMAKE_CXX_EXTENSIONS=OFF -DCMAKE_OSX_DEPLOYMENT_TARGET=${MIN_MACOS_VER} \
  -DCMAKE_BUILD_TYPE=Release -DOPENSSL_ROOT_DIR=${OPENSSL_ROOT_DIR} \
  -DOPENSSL_LIBRARIES=${OPENSSL_ROOT_DIR} -DQT6=ON -DQt6_DIR=${QT_ROOT}/lib/cmake/Qt6 ..
make -j$(sysctl -n hw.ncpu)

${QT_ROOT}/bin/macdeployqt "qbittorrent.app"
# FIXME: This is some weird macdeployqt bug.
${QT_ROOT}/bin/macdeployqt "qbittorrent.app"
if [ -f "/usr/local/lib/libbrotlicommon.1.dylib" ]; then
  cp "/usr/local/lib/libbrotlicommon.1.dylib" "qbittorrent.app/Contents/Frameworks"
fi

mkdir "${SELFDIR}/dist"
if [ -z ${DEPLOY_SCRIPT-} ]; then
  zip -qry qbittorrent.zip qbittorrent.app
  mv qbittorrent.zip "${SELFDIR}/dist"
else
  version=$(defaults read $(pwd)/qbittorrent.app/Contents/Info CFBundleShortVersionString)
  revision="r${QBITTORRENT_EDITION}"
  mime="application/octet-stream"
  name="qBittorrent-${version}-${revision}-$(uname -m).dmg"

  if [ ! -z ${GITHUB_ENV-} ]; then
    echo "VERSION=${version}" >> "$GITHUB_ENV"
    echo "REVISION=${revision}" >> "$GITHUB_ENV"
    echo "FILENAME=${name}" >> "$GITHUB_ENV"
    echo "CONTENT_TYPE=${mime}" >> "$GITHUB_ENV"
  fi

  "$DEPLOY_SCRIPT" "$(pwd)/qbittorrent.app" "${SELFDIR}/dist/${name}"
fi
