#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
version="${UVR_DEB_VERSION:-5.6.0-2}"
python_version="${UVR_PYTHON_VERSION:-3.14.6}"
package_name=ultimate-vocal-remover
build_dir="${repo_dir}/build/debian"
staging_dir="${build_dir}/root"
dist_dir="${repo_dir}/dist"
python_install_dir="${UVR_PYTHON_INSTALL_DIR:-${repo_dir}/.cache/python}"
uv_cache_dir="${UVR_UV_CACHE_DIR:-${repo_dir}/.cache/uv}"

if [[ -x "${repo_dir}/.cache/build-tools/bin/uv" ]]; then
    uv_bin="${repo_dir}/.cache/build-tools/bin/uv"
else
    uv_bin="${UVR_UV_BIN:-$(command -v uv)}"
fi

if [[ "${build_dir}" != "${repo_dir}/build/debian" ]]; then
    echo "Refusing to use an unexpected build directory: ${build_dir}" >&2
    exit 1
fi

cd "${repo_dir}"
mkdir -p "${python_install_dir}" "${uv_cache_dir}" "${dist_dir}"

if [[ -n "${UVR_PYTHON_RUNTIME:-}" ]]; then
    runtime_source="${UVR_PYTHON_RUNTIME}"
else
    UV_CACHE_DIR="${uv_cache_dir}" UV_PYTHON_INSTALL_DIR="${python_install_dir}" \
        "${uv_bin}" python install "${python_version}"
    python_bin="$(
        UV_CACHE_DIR="${uv_cache_dir}" UV_PYTHON_INSTALL_DIR="${python_install_dir}" \
            "${uv_bin}" python find --python-preference only-managed "${python_version}"
    )"
    runtime_source="$(dirname -- "$(dirname -- "${python_bin}")")"
fi

runtime_python="${runtime_source}/bin/python3.14"
if [[ ! -x "${runtime_python}" ]]; then
    echo "Python 3.14 runtime not found at ${runtime_python}" >&2
    exit 1
fi

actual_python_version="$("${runtime_python}" -c 'import platform; print(platform.python_version())')"
if [[ "${actual_python_version}" != "${python_version}" ]]; then
    echo "Expected Python ${python_version}, found ${actual_python_version}" >&2
    exit 1
fi

UV_CACHE_DIR="${uv_cache_dir}" "${uv_bin}" pip sync requirements/linux-cpu.txt \
    --python "${runtime_python}" \
    --system \
    --break-system-packages \
    --index-strategy unsafe-best-match \
    --link-mode copy

"${runtime_python}" -c \
    "import torch; assert torch.__version__.endswith('+cpu'); assert not torch.cuda.is_available()"

rm -rf "${build_dir}"
install -d \
    "${staging_dir}/DEBIAN" \
    "${staging_dir}/usr/bin" \
    "${staging_dir}/usr/lib/${package_name}/app" \
    "${staging_dir}/usr/lib/${package_name}/runtime" \
    "${staging_dir}/usr/share/applications" \
    "${staging_dir}/usr/share/doc/${package_name}" \
    "${staging_dir}/usr/share/icons/hicolor" \
    "${staging_dir}/usr/share/man/man1"

rsync -a "${runtime_source}/" "${staging_dir}/usr/lib/${package_name}/runtime/"

runtime_root="${staging_dir}/usr/lib/${package_name}/runtime"
runtime_site="${runtime_root}/lib/python3.14/site-packages"
torch_dir="${runtime_site}/torch"
if [[ ! -d "${torch_dir}" || "${torch_dir}" != "${staging_dir}"/* ]]; then
    echo "Refusing to prune an unexpected PyTorch directory: ${torch_dir}" >&2
    exit 1
fi

# Wheels include test programs and C++ development files that UVR never uses at
# runtime. Prune them only from the disposable package staging tree. Keep the
# shared-memory manager and all shared libraries required for CPU inference.
rm -rf \
    "${torch_dir}/test" \
    "${torch_dir}/include" \
    "${torch_dir}/share/cmake"
find "${torch_dir}/bin" -mindepth 1 -maxdepth 1 -type f \
    ! -name torch_shm_manager -delete
test -x "${torch_dir}/bin/torch_shm_manager"

find "${runtime_site}" -type d \( -name test -o -name tests \) \
    -prune -exec rm -rf {} +

staged_python="${runtime_root}/bin/python3.14"
PYTHONNOUSERSITE=1 "${staged_python}" -c \
    "import librosa, onnxruntime, PIL, torch, torchvision; assert torch.__version__.endswith('+cpu'); assert not torch.cuda.is_available()"

rm -rf "${runtime_root}/lib/python3.14/config-3.14-x86_64-linux-gnu"

# Console scripts from dependencies point at the temporary build interpreter
# and are not used by UVR. The launcher calls the embedded interpreter directly.
find "${runtime_root}/bin" -mindepth 1 -maxdepth 1 ! -name python3.14 -delete
find "${runtime_site}" -mindepth 1 -maxdepth 1 \
    \( -name pip -o -name 'pip-*.dist-info' \) -exec rm -rf {} +
find "${runtime_root}" -type f -iname '*.exe' -delete

for source_path in UVR.py separate.py __version__.py demucs gui_data lib_v5 models; do
    rsync -a "${repo_dir}/${source_path}" "${staging_dir}/usr/lib/${package_name}/app/"
done

# The managed Python runtime ships Tk 9. The bundled theme works with it, but
# its historical Tcl file unnecessarily requires the incompatible 8.6 major.
sed -i 's/package require Tk 8\.6/package require Tk/' \
    "${staging_dir}/usr/lib/${package_name}/app/gui_data/sv_ttk/theme/dark.tcl"

find "${staging_dir}/usr/lib/${package_name}/app/gui_data/tkinterdnd2/tkdnd" \
    -mindepth 1 -maxdepth 1 -type d ! -name linux64 -exec rm -rf {} +

find "${staging_dir}/usr/lib/${package_name}" \
    -type d -name __pycache__ -prune -exec rm -rf {} +
find "${staging_dir}/usr/lib/${package_name}" \
    -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete

# Users cannot write bytecode below /usr/lib. Precompile deterministic caches so
# startup does not recompile the standard library and every dependency.
SOURCE_DATE_EPOCH=0 PYTHONHASHSEED=0 PYTHONWARNINGS=ignore::SyntaxWarning \
    "${staged_python}" -m compileall \
    --invalidation-mode checked-hash \
    -j 2 \
    -q \
    "${runtime_root}/lib/python3.14" \
    "${staging_dir}/usr/lib/${package_name}/app"
PYTHONNOUSERSITE=1 "${staged_python}" -c \
    "import librosa, onnxruntime, PIL, torch, torchvision; assert torch.__version__.endswith('+cpu'); assert not torch.cuda.is_available()"

install -m 0755 packaging/linux/ultimate-vocal-remover \
    "${staging_dir}/usr/bin/ultimate-vocal-remover"
ln -s ultimate-vocal-remover "${staging_dir}/usr/bin/uvr"
install -m 0644 packaging/linux/ultimate-vocal-remover.desktop \
    "${staging_dir}/usr/share/applications/ultimate-vocal-remover.desktop"
"${staged_python}" scripts/generate-linux-icons.py \
    gui_data/img/GUI-Icon.png \
    "${staging_dir}/usr/share/icons/hicolor"
install -m 0644 README.md LICENSE \
    "${staging_dir}/usr/share/doc/${package_name}/"
install -m 0644 packaging/debian/copyright \
    "${staging_dir}/usr/share/doc/${package_name}/copyright"
gzip -n -9 -c packaging/debian/changelog > \
    "${staging_dir}/usr/share/doc/${package_name}/changelog.Debian.gz"
gzip -n -9 -c packaging/linux/ultimate-vocal-remover.1 > \
    "${staging_dir}/usr/share/man/man1/ultimate-vocal-remover.1.gz"
ln -s ultimate-vocal-remover.1.gz "${staging_dir}/usr/share/man/man1/uvr.1.gz"

installed_size="$(du -sk "${staging_dir}" | cut -f1)"
sed \
    -e "s/@VERSION@/${version}/g" \
    -e "s/@INSTALLED_SIZE@/${installed_size}/g" \
    packaging/debian/control.in > "${staging_dir}/DEBIAN/control"

desktop-file-validate \
    "${staging_dir}/usr/share/applications/ultimate-vocal-remover.desktop"

find "${staging_dir}" -type d -exec chmod 0755 {} +
find "${staging_dir}" -type f -exec chmod 0644 {} +
chmod 0755 \
    "${staged_python}" \
    "${torch_dir}/bin/torch_shm_manager" \
    "${staging_dir}/usr/bin/ultimate-vocal-remover"

deb_path="${dist_dir}/${package_name}_${version}_amd64.deb"
dpkg-deb --root-owner-group -Zzstd -z10 --build "${staging_dir}" "${deb_path}"
(
    cd "${dist_dir}"
    sha256sum "$(basename -- "${deb_path}")" > "$(basename -- "${deb_path}").sha256"
)

echo "Built ${deb_path}"
echo "SHA-256: ${deb_path}.sha256"
