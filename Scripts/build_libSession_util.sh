#!/bin/bash

# Need to set the path or we won't find cmake
PATH=${PATH}:/usr/local/bin:/opt/local/bin:/opt/homebrew/bin:/opt/homebrew/opt/m4/bin:/sbin/md5
required_packages=("cmake" "m4" "pkg-config")
DERIVED_DATA_PATH=$(echo "${BUILD_DIR}" | sed -n 's/\(.*DerivedData\/[^\/]*\).*/\1/p')
PRE_BUILT_FRAMEWORK_DIR="${DERIVED_DATA_PATH}/SourcePackages/artifacts/libsession-util/SessionUtil"
FRAMEWORK_DIR="libsession-util.xcframework"

exec 3>&1 # Save original stdout

# Determine whether we want to build from source
TARGET_ARCH_DIR=""

if [ -z $PLATFORM_NAME ] || [ $PLATFORM_NAME = "iphonesimulator" ]; then
  TARGET_ARCH_DIR="ios-arm64_x86_64-simulator"
elif [ $PLATFORM_NAME = "iphoneos" ]; then
  TARGET_ARCH_DIR="ios-arm64"
else
  echo "error: Unable to find pre-packaged library for the current platform ($PLATFORM_NAME)."
  exit 1
fi

if [ "${COMPILE_LIB_SESSION}" != "YES" ]; then
  STATIC_LIB_PATH="${PRE_BUILT_FRAMEWORK_DIR}/${FRAMEWORK_DIR}/${TARGET_ARCH_DIR}/libsession-util.a"
  
  if [ ! -f "${STATIC_LIB_PATH}" ]; then
    echo "error: Pre-packaged library doesn't exist in the expected location: ${STATIC_LIB_PATH}."
    exit 1
  fi
  
  # If we'd replaced the framework with our compiled version then change it back
  if [ -d "${PRE_BUILT_FRAMEWORK_DIR}/${FRAMEWORK_DIR}_Old" ]; then
      rm -rf "${PRE_BUILT_FRAMEWORK_DIR}/${FRAMEWORK_DIR}"
      mv "${PRE_BUILT_FRAMEWORK_DIR}/${FRAMEWORK_DIR}_Old" "${PRE_BUILT_FRAMEWORK_DIR}/${FRAMEWORK_DIR}"
  fi

  # If we previously built from source then we should copy the pre-built package across
  # just to make sure we don't unintentionally use the wrong build
  if [ -d "${TARGET_BUILD_DIR}/LibSessionUtil" ]; then
    echo "Removing old compiled build data"

    if [ -d "${TARGET_BUILD_DIR}/include" ]; then
      rm -r "${TARGET_BUILD_DIR}/include"
    fi
    
    if [ -f "${TARGET_BUILD_DIR}/libsession-util.a" ]; then
      rm -r "${TARGET_BUILD_DIR}/libsession-util.a"
    fi

    cp "${PRE_BUILT_FRAMEWORK_DIR}/${FRAMEWORK_DIR}/${TARGET_ARCH_DIR}/libsession-util.a" "${TARGET_BUILD_DIR}/libsession-util.a"
    cp -r "${PRE_BUILT_FRAMEWORK_DIR}/${FRAMEWORK_DIR}/${TARGET_ARCH_DIR}/Headers" "${TARGET_BUILD_DIR}"
  fi
  
  echo "Using pre-packaged SessionUtil"
  exit 0
fi

# Ensure the machine has the build dependencies installed
echo "Validating build requirements"
missing_packages=()

for package in "${required_packages[@]}"; do
  if ! which "$package" > /dev/null; then
    missing_packages+=("$package")
  fi
done

if [ ${#missing_packages[@]} -ne 0 ]; then
  packages=$(echo "${missing_packages[@]}")
  echo "error: Some build dependencies are not installed, please install them ('brew install ${packages}'):"
  exit 1
fi

# Ensure the build directory exists (in case we need it before XCode creates it)
COMPILE_DIR="${TARGET_BUILD_DIR}/LibSessionUtil"
mkdir -p "${COMPILE_DIR}"

if [ ! -d "${LIB_SESSION_SOURCE_DIR}" ] || [ ! -d "${LIB_SESSION_SOURCE_DIR}/src" ]; then
  echo "error: Could not find LibSession source in 'LIB_SESSION_SOURCE_DIR' directory: ${LIB_SESSION_SOURCE_DIR}."
  exit 1
fi

# Validate the submodules in 'LIB_SESSION_SOURCE_DIR'
are_submodules_valid() {
  local PARENT_PATH=$1

  # Change into the path to check for it's submodules
  cd "${PARENT_PATH}"
  local SUB_MODULE_PATHS=($(git config --file .gitmodules --get-regexp path | awk '{ print $2 }'))

  # If there are no submodules then return success based on whether the folder has any content
  if [ ${#SUB_MODULE_PATHS[@]} -eq 0 ]; then
    if [[ ! -z "$(ls -A "${PARENT_PATH}")" ]]; then
      return 0
    else
      return 1
    fi
  fi

  # Loop through the child submodules and check if they are valid
  for i in "${!SUB_MODULE_PATHS[@]}"; do
    local CHILD_PATH="${SUB_MODULE_PATHS[$i]}"
  
    # If the child path doesn't exist then it's invalid
    if [ ! -d "${PARENT_PATH}/${CHILD_PATH}" ]; then
      echo "Submodule '${CHILD_PATH}' doesn't exist."
      return 1
    fi

    are_submodules_valid "${PARENT_PATH}/${CHILD_PATH}"
    local RESULT=$?

    if [ "${RESULT}" -eq 1 ]; then
      echo "Submodule '${CHILD_PATH}' is in an invalid state."
      return 1
    fi
  done

  return 0
}

# Validate the state of the submodules
are_submodules_valid "${LIB_SESSION_SOURCE_DIR}" "LibSession-Util"

HAS_INVALID_SUBMODULE=$?

if [ "${HAS_INVALID_SUBMODULE}" -eq 1 ]; then
  echo "error: Submodules are in an invalid state, please run 'git submodule update --init --recursive' in ${LIB_SESSION_SOURCE_DIR}."
  exit 1
fi

# Generate a hash of the libSession-util source files and check if they differ from the last hash
echo "Checking for changes to source"

NEW_SOURCE_HASH=$(find "${LIB_SESSION_SOURCE_DIR}/src" -type f -exec md5 {} + | awk '{print $NF}' | sort | md5 | awk '{print $NF}')
NEW_HEADER_HASH=$(find "${LIB_SESSION_SOURCE_DIR}/include" -type f -exec md5 {} + | awk '{print $NF}' | sort | md5 | awk '{print $NF}')
NEW_EXTERNAL_HASH=$(find "${LIB_SESSION_SOURCE_DIR}/external" -type f -exec md5 {} + | awk '{print $NF}' | sort | md5 | awk '{print $NF}')

if [ -f "${COMPILE_DIR}/libsession_util_source_dir.log" ]; then
  read -r OLD_SOURCE_DIR < "${COMPILE_DIR}/libsession_util_source_dir.log"
fi

if [ -f "${COMPILE_DIR}/libsession_util_source_hash.log" ]; then
  read -r OLD_SOURCE_HASH < "${COMPILE_DIR}/libsession_util_source_hash.log"
fi

if [ -f "${COMPILE_DIR}/libsession_util_header_hash.log" ]; then
  read -r OLD_HEADER_HASH < "${COMPILE_DIR}/libsession_util_header_hash.log"
fi

if [ -f "${COMPILE_DIR}/libsession_util_external_hash.log" ]; then
  read -r OLD_EXTERNAL_HASH < "${COMPILE_DIR}/libsession_util_external_hash.log"
fi

if [ -f "${COMPILE_DIR}/libsession_util_archs.log" ]; then
  read -r OLD_ARCHS < "${COMPILE_DIR}/libsession_util_archs.log"
fi

# Check the current state of the build (comparing hashes to determine if there was a source change)
REQUIRES_BUILD=0

if [ "${LIB_SESSION_SOURCE_DIR}" != "${OLD_SOURCE_DIR}" ]; then
  echo "Build is not up-to-date (source dir change) - removing old build and rebuilding"
  rm -rf "${COMPILE_DIR}"
  REQUIRES_BUILD=1
elif [ "${NEW_SOURCE_HASH}" != "${OLD_SOURCE_HASH}" ]; then
  echo "Build is not up-to-date (source change) - creating new build"
  REQUIRES_BUILD=1
elif [ "${NEW_HEADER_HASH}" != "${OLD_HEADER_HASH}" ]; then
  echo "Build is not up-to-date (header change) - creating new build"
  REQUIRES_BUILD=1
elif [ "${NEW_EXTERNAL_HASH}" != "${OLD_EXTERNAL_HASH}" ]; then
  echo "Build is not up-to-date (external lib change) - creating new build"
  REQUIRES_BUILD=1
elif [ "${ARCHS[*]}" != "${OLD_ARCHS}" ]; then
  echo "Build is not up-to-date (build architectures changed) - creating new build"
  REQUIRES_BUILD=1
elif [ ! -f "${COMPILE_DIR}/libsession-util.a" ]; then
  echo "Build is not up-to-date (no static lib) - creating new build"
  REQUIRES_BUILD=1
else
  echo "Build is up-to-date"
fi

if [ "${REQUIRES_BUILD}" == 1 ]; then
  # Import settings from XCode (defaulting values if not present)
  VALID_SIM_ARCHS=(arm64 x86_64)
  VALID_DEVICE_ARCHS=(arm64)
  VALID_SIM_ARCH_PLATFORMS=(SIMULATORARM64 SIMULATOR64)
  VALID_DEVICE_ARCH_PLATFORMS=(OS64)

  OUTPUT_DIR="${TARGET_BUILD_DIR}"
  IPHONEOS_DEPLOYMENT_TARGET=${IPHONEOS_DEPLOYMENT_TARGET}
  ENABLE_BITCODE=${ENABLE_BITCODE}

  # Generate the target architectures we want to build for
  TARGET_ARCHS=()
  TARGET_PLATFORMS=()
  TARGET_SIM_ARCHS=()
  TARGET_DEVICE_ARCHS=()

  if [ -z $PLATFORM_NAME ] || [ $PLATFORM_NAME = "iphonesimulator" ]; then
    for i in "${!VALID_SIM_ARCHS[@]}"; do
      ARCH="${VALID_SIM_ARCHS[$i]}"
      ARCH_PLATFORM="${VALID_SIM_ARCH_PLATFORMS[$i]}"

      if [[ " ${ARCHS[*]} " =~ " ${ARCH} " ]]; then
        TARGET_ARCHS+=("sim-${ARCH}")
        TARGET_PLATFORMS+=("${ARCH_PLATFORM}")
        TARGET_SIM_ARCHS+=("sim-${ARCH}")
      fi
    done
  fi

  if [ -z $PLATFORM_NAME ] || [ $PLATFORM_NAME = "iphoneos" ]; then
    for i in "${!VALID_DEVICE_ARCHS[@]}"; do
      ARCH="${VALID_DEVICE_ARCHS[$i]}"
      ARCH_PLATFORM="${VALID_DEVICE_ARCH_PLATFORMS[$i]}"

      if [[ " ${ARCHS[*]} " =~ " ${ARCH} " ]]; then
        TARGET_ARCHS+=("ios-${ARCH}")
        TARGET_PLATFORMS+=("${ARCH_PLATFORM}")
        TARGET_DEVICE_ARCHS+=("ios-${ARCH}")
      fi
    done
  fi

  # Remove any old build logs (since we are doing a new build)
  rm -rf "${COMPILE_DIR}/libsession_util_output.log"
  touch "${COMPILE_DIR}/libsession_util_output.log"
  echo "CMake build logs: ${COMPILE_DIR}/libsession_util_output.log"

  submodule_check=ON
  build_type="Release"

  if [ "$CONFIGURATION" == "Debug" ]; then
    submodule_check=OFF
    build_type="Debug"
  fi

  # Build the individual architectures
  for i in "${!TARGET_ARCHS[@]}"; do
    build="${COMPILE_DIR}/${TARGET_ARCHS[$i]}"
    platform="${TARGET_PLATFORMS[$i]}"
    log_file="${COMPILE_DIR}/libsession_util_output.log"
    echo "Building ${TARGET_ARCHS[$i]} for $platform in $build"
    
    # Redirect the build output to a log file and only include the progress lines in the XCode output
    exec > >(tee "$log_file" | grep --line-buffered '^\[.*%\]') 2>&1

    cd "${LIB_SESSION_SOURCE_DIR}"
    env -i PATH="$PATH" SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" \
      ./utils/static-bundle.sh "$build" "" \
      -DCMAKE_TOOLCHAIN_FILE="${LIB_SESSION_SOURCE_DIR}/external/ios-cmake/ios.toolchain.cmake" \
      -DPLATFORM=$platform \
      -DDEPLOYMENT_TARGET=$IPHONEOS_DEPLOYMENT_TARGET \
      -DENABLE_BITCODE=$ENABLE_BITCODE \
      -DBUILD_TESTS=OFF \
      -DBUILD_STATIC_DEPS=ON \
      -DENABLE_VISIBILITY=ON \
      -DSUBMODULE_CHECK=$submodule_check \
      -DCMAKE_BUILD_TYPE=$build_type \
      -DLOCAL_MIRROR=https://oxen.rocks/deps

    # Capture the exit status of the ./utils/static-bundle.sh command
    EXIT_STATUS=$?
        
    # Flush the tee buffer (ensure any errors have been properly written to the log before continuing) and
    # restore stdout
    echo ""
    exec 1>&3

    # Retrieve and log any submodule errors/warnings
    ALL_CMAKE_ERROR_LINES=($(grep -nE "CMake Error" "$log_file" | cut -d ":" -f 1))
    ALL_SUBMODULE_ISSUE_LINES=($(grep -nE "\s*Submodule '([^']+)' is not up-to-date" "$log_file" | cut -d ":" -f 1))
    ALL_CMAKE_ERROR_LINES_STR=" ${ALL_CMAKE_ERROR_LINES[*]} "
    ALL_SUBMODULE_ISSUE_LINES_STR=" ${ALL_SUBMODULE_ISSUE_LINES[*]} "

    for i in "${!ALL_SUBMODULE_ISSUE_LINES[@]}"; do
      line="${ALL_SUBMODULE_ISSUE_LINES[$i]}"
      prev_line=$((line - 1))
      value=$(sed "${line}q;d" "$log_file" | sed -E "s/.*Submodule '([^']+)'.*/Submodule '\1' is not up-to-date./")
      
      if [[ "$ALL_CMAKE_ERROR_LINES_STR" == *" $prev_line "* ]]; then
        echo "error: $value"
      else
        echo "warning: $value"
      fi
    done

    if [ $EXIT_STATUS -ne 0 ]; then
      ALL_ERROR_LINES=($(grep -n "error:" "$log_file" | cut -d ":" -f 1))

      # Log any other errors
      for e in "${!ALL_ERROR_LINES[@]}"; do
        error_line="${ALL_ERROR_LINES[$e]}"
        error=$(sed "${error_line}q;d" "$log_file")

        # If it was a CMake Error then the actual error will be on the next line so we want to append that info
        if [[ $error == *'CMake Error'* ]]; then
            actual_error_line=$((error_line + 1))
            error="${error}$(sed "${actual_error_line}q;d" "$log_file")"
        fi

        # Exclude the 'ALL_ERROR_LINES' line and the 'grep' line
        if [[ ! $error == *'grep -n "error'* ]] && [[ ! $error == *'grep -n error'* ]]; then
            echo "error: $error"
        fi
      done
      exit 1
    fi
  done

  # Remove the old static library file
  rm -rf "${COMPILE_DIR}/libsession-util.a"
  rm -rf "${COMPILE_DIR}/Headers"

  # If needed combine simulator builds into a multi-arch lib
  if [ "${#TARGET_SIM_ARCHS[@]}" -eq "1" ]; then
    # Single device build
    cp "${COMPILE_DIR}/${TARGET_SIM_ARCHS[0]}/libsession-util.a" "${COMPILE_DIR}/libsession-util.a"
  elif [ "${#TARGET_SIM_ARCHS[@]}" -gt "1" ]; then
    # Combine multiple device builds into a multi-arch lib
    echo "Built multiple architectures, merging into single static library"
    lipo -create "${COMPILE_DIR}"/sim-*/libsession-util.a -output "${COMPILE_DIR}/libsession-util.a"
  fi

  # If needed combine device builds into a multi-arch lib
  if [ "${#TARGET_DEVICE_ARCHS[@]}" -eq "1" ]; then
    cp "${COMPILE_DIR}/${TARGET_DEVICE_ARCHS[0]}/libsession-util.a" "${COMPILE_DIR}/libsession-util.a"
  elif [ "${#TARGET_DEVICE_ARCHS[@]}" -gt "1" ]; then
    # Combine multiple device builds into a multi-arch lib
    echo "Built multiple architectures, merging into single static library"
    lipo -create "${COMPILE_DIR}"/ios-*/libsession-util.a -output "${COMPILE_DIR}/libsession-util.a"
  fi

  # Save the updated build info to disk to prevent rebuilds when there were no changes
  echo "${LIB_SESSION_SOURCE_DIR}" > "${COMPILE_DIR}/libsession_util_source_dir.log"
  echo "${NEW_SOURCE_HASH}" > "${COMPILE_DIR}/libsession_util_source_hash.log"
  echo "${NEW_HEADER_HASH}" > "${COMPILE_DIR}/libsession_util_header_hash.log"
  echo "${NEW_EXTERNAL_HASH}" > "${COMPILE_DIR}/libsession_util_external_hash.log"
  echo "${ARCHS[*]}" > "${COMPILE_DIR}/libsession_util_archs.log"
  
  # Copy the headers across
  echo "Copy headers"
  mkdir -p "${COMPILE_DIR}/Headers"
  cp -r "${LIB_SESSION_SOURCE_DIR}/include/session" "${COMPILE_DIR}/Headers"

  echo "Build complete"
fi

# Remove any previous versions (in case there is a discrepancy anywhere
rm -rf "${BUILT_PRODUCTS_DIR}/include"
rm -rf "${BUILT_PRODUCTS_DIR}/libsession-util.a"

cp -r "${COMPILE_DIR}/Headers" "${BUILT_PRODUCTS_DIR}/include"
cp "${COMPILE_DIR}/libsession-util.a" "${BUILT_PRODUCTS_DIR}"

# Generate the 'module.modulemap' (needed for XCode to be able to find the headers)
#
# Note: We do this last and don't include the `COMPILE_DIR` because, if we do, Xcode
# sees both files and considers the module redefined
echo "Generate modulemap"
modmap="${BUILT_PRODUCTS_DIR}/include/module.modulemap"
echo "module SessionUtil {" >"$modmap"
echo "  module capi {" >>"$modmap"
for x in $(cd "${COMPILE_DIR}/Headers" && find session -name '*.h'); do
echo "    header \"$x\"" >>"$modmap"
done
echo -e "    export *\n  }" >>"$modmap"
echo "}" >>"$modmap"

# Output to XCode just so the output is good
echo "LibSession is Ready"
