// Intentionally doing a depth of 2 as libSession-util has it's own submodules (and libLokinet likely will as well)
local clone_submodules = {
  name: 'Clone Submodules',
  commands: ['git fetch --tags', 'git submodule update --init --recursive --depth=2']
};

// cmake options for static deps mirror
local ci_dep_mirror(want_mirror) = (if want_mirror then ' -DLOCAL_MIRROR=https://oxen.rocks/deps ' else '');

// Cocoapods
// 
// Unfortunately Cocoapods has a dumb restriction which requires you to use UTF-8 for the
// 'LANG' env var so we need to work around the with https://github.com/CocoaPods/CocoaPods/issues/6333
local install_cocoapods = {
  name: 'Install CocoaPods',
  commands: ['LANG=en_US.UTF-8 pod install']
};

// Load from the cached CocoaPods directory (to speed up the build)
local load_cocoapods_cache = {
  name: 'Load CocoaPods Cache',
  commands: [
    |||
      while test -e /Users/drone/.cocoapods_cache.lock; do
          sleep 1
      done
    |||,
    'touch /Users/drone/.cocoapods_cache.lock'
    |||
      if [[ -d /Users/drone/.cocoapods_cache ]]; then
        cp -r /Users/drone/.cocoapods_cache ./Pods
      fi
    |||,
    'rm /Users/drone/.cocoapods_cache.lock'
  ]
};

// Override the cached CocoaPods directory (to speed up the next build)
local update_cocoapods_cache = {
  name: 'Update CocoaPods Cache',
  commands: [
    |||
      while test -e /Users/drone/.cocoapods_cache.lock; do
          sleep 1
      done
    |||,
    'touch /Users/drone/.cocoapods_cache.lock'
    |||
      if [[ -d ./Pods ]]; then
        rm -rf /Users/drone/.cocoapods_cache
        cp -r ./Pods /Users/drone/.cocoapods_cache
      fi
    |||,
    'rm /Users/drone/.cocoapods_cache.lock'
  ]
};


[
  // Unit tests
  {
    kind: 'pipeline',
    type: 'exec',
    name: 'Unit Tests',
    platform: { os: 'darwin', arch: 'amd64' },
    steps: [
      clone_submodules,
      load_cocoapods_cache,
      install_cocoapods,
      {
        name: 'Run Unit Tests',
        commands: [
          'mkdir build',
          |||
            if command -v xcpretty >/dev/null 2>&1; then
              xcodebuild test -workspace Session.xcworkspace -scheme Session -destination "platform=iOS Simulator,name=iPhone 14 Pro" | xcpretty
            else
              xcodebuild test -workspace Session.xcworkspace -scheme Session -destination "platform=iOS Simulator,name=iPhone 14 Pro"
            fi
          |||
        ],
      },
      update_cocoapods_cache
    ],
  },
  // Simulator build
  {
    kind: 'pipeline',
    type: 'exec',
    name: 'Simulator Build',
    platform: { os: 'darwin', arch: 'amd64' },
    steps: [
      clone_submodules,
      load_cocoapods_cache,
      install_cocoapods,
      {
        name: 'Build',
        commands: [
          'mkdir build',
          |||
            if command -v xcpretty >/dev/null 2>&1; then
              xcodebuild archive -workspace Session.xcworkspace -scheme Session -configuration 'App Store Release' -sdk iphonesimulator -archivePath ./build/Session_sim.xcarchive -destination "generic/platform=iOS Simulator" | xcpretty
            else
              xcodebuild archive -workspace Session.xcworkspace -scheme Session -configuration 'App Store Release' -sdk iphonesimulator -archivePath ./build/Session_sim.xcarchive -destination "generic/platform=iOS Simulator"
            fi
          |||
        ],
      },
      update_cocoapods_cache,
      {
        name: 'Upload artifacts',
        commands: [
          './Scripts/drone-static-upload.sh'
        ]
      },
    ],
  },
  // AppStore build (generate an archive to be signed later)
  {
    kind: 'pipeline',
    type: 'exec',
    name: 'AppStore Build',
    platform: { os: 'darwin', arch: 'amd64' },
    steps: [
      clone_submodules,
      load_cocoapods_cache,
      install_cocoapods,
      {
        name: 'Build',
        commands: [
          'mkdir build',
          |||
            if command -v xcpretty >/dev/null 2>&1; then
              xcodebuild archive -workspace Session.xcworkspace -scheme Session -configuration 'App Store Release' -sdk iphoneos -archivePath ./build/Session.xcarchive -destination "generic/platform=iOS" -allowProvisioningUpdates | xcpretty
            else
              xcodebuild archive -workspace Session.xcworkspace -scheme Session -configuration 'App Store Release' -sdk iphoneos -archivePath ./build/Session.xcarchive -destination "generic/platform=iOS" -allowProvisioningUpdates
            fi
          |||
        ],
      },
      update_cocoapods_cache,
      {
        name: 'Upload artifacts',
        commands: [
          './Scripts/drone-static-upload.sh'
        ]
      },
    ],
  },
]